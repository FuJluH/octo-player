package app.winters.octo.liveradio

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import okhttp3.Call
import okhttp3.Callback
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import java.io.IOException
import java.net.InetAddress
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlin.math.roundToInt

// A live radio station from the Radio Browser catalog, as an app shows,
// plays and keeps it.
@Serializable
data class LiveStation(
    val uuid: String,
    val name: String,
    val streamUrl: String,
    val favicon: String = "",
    val codec: String = "",
    val bitrate: Int = 0,
    val hls: Boolean = false,
    val country: String = "",
    val countryCode: String = "",
    val state: String = "",
    val tags: List<String> = emptyList(),
    // The station's own website, empty when the catalog has none.
    val homepage: String = "",
    // How far from the place asked about, in meters; null when the catalog
    // does not know where the station is.
    val distanceMeters: Double? = null,
    // How often listeners started it lately, the catalog's measure of how
    // popular it is.
    val clicks: Int = 0,
)

// A place to find stations around: where it is, and the names the catalog
// files stations under when it has no coordinates for them.
@Serializable
data class LivePlace(
    val latitude: Double,
    val longitude: Double,
    val label: String,
    val state: String = "",
    val countryCode: String = "",
)

// Whether the place has coordinates. One without them (a city typed where
// nothing could look it up) is searched by its state and country only.
val LivePlace.located: Boolean get() = latitude != 0.0 || longitude != 0.0

// How the stations found are ordered.
enum class LiveSort { Distance, Popular }

// The radius choices, in the listener's own units.
val LiveRadiusMiles = listOf(10, 25, 50, 100)
val LiveRadiusKm = listOf(15, 40, 80, 160)
const val LIVE_RADIUS_DEFAULT_INDEX = 1

const val MILE_METERS = 1609.344

// The station rows the catalog sends.
@Serializable
internal data class CatalogStation(
    @SerialName("stationuuid") val uuid: String = "",
    val name: String = "",
    @SerialName("url_resolved") val urlResolved: String = "",
    val url: String = "",
    val favicon: String = "",
    val codec: String = "",
    val bitrate: Int = 0,
    val hls: Int = 0,
    val country: String = "",
    @SerialName("countrycode") val countryCode: String = "",
    val state: String = "",
    val tags: String = "",
    val homepage: String = "",
    @SerialName("geo_distance") val geoDistance: Double? = null,
    @SerialName("geo_lat") val geoLat: Double? = null,
    @SerialName("geo_long") val geoLong: Double? = null,
    @SerialName("clickcount") val clickCount: Int = 0,
    @SerialName("lastcheckok") val lastCheckOk: Int = 1,
)

@Serializable
internal data class CatalogServer(val name: String = "")

internal fun CatalogStation.toLive(): LiveStation? {
    val stream = urlResolved.ifBlank { url }.trim()
    if (uuid.isBlank() || stream.isBlank() || lastCheckOk == 0) return null
    return LiveStation(
        uuid = uuid,
        name = name.trim().ifBlank { stream },
        streamUrl = stream,
        favicon = favicon.trim(),
        codec = codec.trim(),
        bitrate = bitrate,
        hls = hls == 1,
        country = country.trim(),
        countryCode = countryCode.trim().uppercase(),
        state = state.trim(),
        tags = tags.split(',').map { it.trim() }.filter { it.isNotEmpty() }.distinct().take(6),
        homepage = homepage.trim().takeIf { it.startsWith("http://", ignoreCase = true) || it.startsWith("https://", ignoreCase = true) }.orEmpty(),
        distanceMeters = geoDistance,
        clicks = clickCount,
    )
}

// The stations near a place: those the catalog places within the radius,
// and those it files under the place's state and country but cannot place,
// each once. Nearest first (the ones it cannot place after, the most played
// first), or the most played first.
internal fun mergeStations(near: List<LiveStation>, regional: List<LiveStation>, sort: LiveSort): List<LiveStation> {
    val seen = HashSet<String>()
    val all = (near + regional.filter { it.distanceMeters == null }).filter { seen.add(it.uuid) }
    return when (sort) {
        LiveSort.Distance -> all.sortedWith(
            compareBy<LiveStation> { it.distanceMeters == null }
                .thenBy { it.distanceMeters ?: 0.0 }
                .thenByDescending { it.clicks }
                .thenBy { it.name.lowercase() },
        )
        LiveSort.Popular -> all.sortedWith(compareByDescending<LiveStation> { it.clicks }.thenBy { it.name.lowercase() })
    }
}

// A place to two decimals (about a kilometer): all that is sent, and what
// answers are kept under.
internal fun rounded(value: Double): Double = (value * 100).roundToInt() / 100.0

// The Radio Browser catalog of live radio stations. It is asked through one
// of its servers (`servers`, names or full addresses), picked at random
// (`pick`), with the app's own name so its keepers know who asks; a server
// that fails is left for another one of the list, once, within the same
// ask. Answers are kept for six hours per place and radius. `userAgent` is
// like "Octo/1.7 (Android)".
class RadioBrowser(
    private val http: OkHttpClient,
    private val userAgent: String,
    private val servers: suspend () -> List<String> = ::catalogServers,
    private val now: () -> Long = System::currentTimeMillis,
    private val pick: (List<String>) -> String = { it.random() },
) {
    private val json = Json { ignoreUnknownKeys = true; coerceInputValues = true }

    // The server in use, and the list it was picked from.
    @Volatile private var chosen: String? = null
    @Volatile private var pickedFrom: List<String> = emptyList()
    private val kept = HashMap<String, Pair<Long, List<LiveStation>>>()

    // The stations around `place` within `radiusMeters`, those this app
    // can play (`playable`) only, ordered by `sort`. A place without
    // coordinates skips the radius search and gives its state's stations.
    suspend fun near(
        place: LivePlace,
        radiusMeters: Double,
        sort: LiveSort,
        playable: (LiveStation) -> Boolean = { true },
    ): List<LiveStation> = withContext(Dispatchers.IO) {
        val lat = rounded(place.latitude)
        val lon = rounded(place.longitude)
        val key = "$lat,$lon,${radiusMeters.roundToInt()},${place.state},${place.countryCode}"
        val found = keptFor(key) ?: run {
            val near = if (place.located) {
                search(
                    "geo_lat" to "$lat",
                    "geo_long" to "$lon",
                    "geo_distance" to "${radiusMeters.roundToInt()}",
                )
            } else {
                emptyList()
            }
            // From the state and country, only the stations the catalog cannot
            // place: one it can place was in the circle search if near enough.
            // The catalog matches a state by part of its name (Kansas finds
            // Arkansas), so it is asked for the exact name and checked again.
            val state = place.state.trim()
            val regional = if (place.countryCode.isNotBlank()) {
                val params = listOfNotNull(
                    "countrycode" to place.countryCode,
                    state.takeIf { it.isNotEmpty() }?.let { "state" to it },
                    ("stateExact" to "true").takeIf { state.isNotEmpty() },
                )
                rows(*params.toTypedArray())
                    .filter { state.isEmpty() || it.state.trim().equals(state, ignoreCase = true) }
                    .filter { !place.located || it.geoLat == null || it.geoLong == null }
                    .mapNotNull { it.toLive() }
            } else {
                emptyList()
            }
            val all = mergeStations(near, regional, LiveSort.Distance)
            keep(key, all)
            all
        }
        mergeStations(found.filter(playable), emptyList(), sort)
    }

    // Tells the catalog a listener started a station, as its keepers ask,
    // so popular stations rise for everyone. A failure is of no matter.
    suspend fun started(uuid: String) {
        withContext(Dispatchers.IO) {
            runCatching { asking { base -> get(base.newBuilder().addPathSegments("json/url").addPathSegment(uuid).build()) } }
        }
    }

    // An answer kept for `key` that is still fresh.
    private fun keptFor(key: String): List<LiveStation>? = synchronized(kept) {
        kept[key]?.takeIf { now() - it.first < KEEP_MS }?.second
    }

    // Keeps an answer, and lets go of the ones gone stale.
    private fun keep(key: String, stations: List<LiveStation>) = synchronized(kept) {
        val at = now()
        kept.entries.removeAll { at - it.value.first >= KEEP_MS }
        kept[key] = at to stations
    }

    // How many answers are kept, for tests.
    internal fun keptCount(): Int = synchronized(kept) { kept.size }

    private suspend fun search(vararg params: Pair<String, String>): List<LiveStation> = rows(*params).mapNotNull { it.toLive() }

    private suspend fun rows(vararg params: Pair<String, String>): List<CatalogStation> = asking { base ->
        val url = base.newBuilder().addPathSegments("json/stations/search").apply {
            params.forEach { (name, value) -> addQueryParameter(name, value) }
            addQueryParameter("hidebroken", "true")
            addQueryParameter("order", "clickcount")
            addQueryParameter("reverse", "true")
            addQueryParameter("limit", "$SEARCH_LIMIT")
        }.build()
        val body = get(url)
        try {
            json.decodeFromString<List<CatalogStation>>(body)
        } catch (e: kotlinx.serialization.SerializationException) {
            throw IOException("The radio catalog sent an answer it could not read", e)
        } catch (e: IllegalArgumentException) {
            throw IOException("The radio catalog sent an answer it could not read", e)
        }
    }

    // Runs one ask against the server in use. When it fails (no answer, an
    // error, something unreadable), another server of the same list is
    // asked once; when that fails too, the next ask picks anew.
    private suspend fun <T> asking(ask: suspend (HttpUrl) -> T): T {
        val first = server()
        try {
            return ask(address(first))
        } catch (e: IOException) {
            currentCoroutineContext().ensureActive()
            chosen = null
            val others = pickedFrom.filter { it != first }
            if (others.isEmpty()) throw e
            val other = pick(others)
            chosen = other
            try {
                return ask(address(other))
            } catch (again: IOException) {
                chosen = null
                throw again
            }
        }
    }

    // The server in use, or one picked from the list now.
    private suspend fun server(): String {
        chosen?.let { return it }
        val list = runCatching { servers() }.getOrDefault(emptyList()).filter { it.isNotBlank() }.distinct()
        pickedFrom = list
        val server = if (list.isEmpty()) FALLBACK_SERVER else pick(list)
        chosen = server
        return server
    }

    // A server's address: a name stands for its https address.
    private fun address(server: String): HttpUrl = (if ("://" in server) server else "https://$server/").toHttpUrl()

    // One request, given up on the moment the ask is cancelled.
    private suspend fun get(url: HttpUrl): String = suspendCancellableCoroutine { done ->
        val call = http.newCall(Request.Builder().url(url).header("User-Agent", userAgent).build())
        done.invokeOnCancellation { call.cancel() }
        call.enqueue(
            object : Callback {
                override fun onFailure(call: Call, e: IOException) {
                    done.resumeWithException(e)
                }

                override fun onResponse(call: Call, response: Response) {
                    try {
                        response.use {
                            if (!it.isSuccessful) throw IOException("The radio catalog answered HTTP ${it.code}")
                            done.resume(it.body.string())
                        }
                    } catch (e: IOException) {
                        done.resumeWithException(e)
                    }
                }
            },
        )
    }

    private companion object {
        const val KEEP_MS = 6 * 60 * 60 * 1000L
        const val SEARCH_LIMIT = 200
    }
}

const val FALLBACK_SERVER = "de1.api.radio-browser.info"

// The catalog's servers, by name: every address all.api.radio-browser.info
// stands for, named again by a reverse lookup, as its keepers ask apps to
// find them. None when the lookup fails, and the fallback server is used.
suspend fun catalogServers(): List<String> = withContext(Dispatchers.IO) {
    runCatching {
        InetAddress.getAllByName("all.api.radio-browser.info")
            .map { it.canonicalHostName }
            .filter { it.endsWith(".radio-browser.info") }
            .distinct()
    }.getOrDefault(emptyList())
}
