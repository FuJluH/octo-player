package app.winters.octo.desktop.discord

import app.winters.octo.catalog.SongIdentity
import app.winters.octo.desktop.system.NowPlaying
import app.winters.octo.discovery.sameArtist
import app.winters.octo.subsonic.Song
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.OkHttpClient
import okhttp3.Request
import java.net.URLEncoder
import java.util.Collections
import java.util.concurrent.TimeUnit

// The cover and artist photo found for the Discord status, when found.
data class DiscordArtwork(val cover: String? = null, val artist: String? = null)

// What a song's pictures are looked up by: only the names Discord shows anyway.
data class ArtQuery(val title: String, val artist: String, val album: String, val albumArtist: String)

// A live station's album is the station, which no catalog has.
fun artQueryOf(now: NowPlaying) = if (now.live) ArtQuery(now.title, now.artist, "", "") else ArtQuery(now.title, now.artist, now.album, now.albumArtist)

// The same names nowPlayingOf takes from a song, for a song still to come.
fun artQueryOf(song: Song) = ArtQuery(
    title = song.title,
    artist = (song.displayArtist ?: song.artist).orEmpty(),
    album = song.album.orEmpty(),
    albumArtist = (song.displayAlbumArtist ?: song.albumArtists.joinToString(", ") { it.name }.ifBlank { null }).orEmpty(),
)

// Finds pictures for the Discord status on public catalogues, by name, so no
// address of the listener's server and nothing signed ever leaves this
// computer: the album cover from Deezer (iTunes when Deezer has none), by
// the album, or by the song itself when the album is unknown or not in the
// catalogue; and the artist's photo from Deezer. The cover and the photo
// are looked for at once, and the next song's ahead of time, so a song
// usually has its pictures the moment it starts.
// Every answer, found or not, is kept for the session. A lookup that could
// not reach the catalogue is not an answer: it rests a while, then is tried
// again, so a moment offline does not cost the pictures for good.
class DiscordArt(
    // The body of a GET, or null on any failure.
    private val fetch: (String) -> String? = ::httpGet,
    private val keep: Int = 512,
    private val clock: () -> Long = System::currentTimeMillis,
) {
    private val found: MutableMap<String, String?> = Collections.synchronizedMap(
        object : LinkedHashMap<String, String?>(16, 0.75f, true) {
            override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, String?>) = size > keep
        },
    )
    private val looking: MutableSet<String> = Collections.synchronizedSet(HashSet())
    private val failedAt: MutableMap<String, Long> = Collections.synchronizedMap(HashMap())

    fun known(now: NowPlaying): DiscordArtwork = known(artQueryOf(now))

    fun known(song: ArtQuery): DiscordArtwork = DiscordArtwork(cover = found[coverKey(song)], artist = found[artistKey(song)])

    fun wants(now: NowPlaying, prefs: DiscordPrefs): Boolean = wants(artQueryOf(now), prefs)

    // Whether a picture the settings ask for has not been looked for yet.
    fun wants(song: ArtQuery, prefs: DiscordPrefs): Boolean =
        keysFor(song, prefs).any { it !in found && it !in looking && !resting(it) }

    // Whether a picture the settings ask for is still to come: not looked
    // for yet, or being looked for now.
    fun pending(song: ArtQuery, prefs: DiscordPrefs): Boolean =
        keysFor(song, prefs).any { it !in found && !resting(it) }

    suspend fun look(now: NowPlaying, prefs: DiscordPrefs) = look(artQueryOf(now), prefs)

    suspend fun look(song: ArtQuery, prefs: DiscordPrefs) = withContext(Dispatchers.IO) {
        coroutineScope {
            keysFor(song, prefs).map { key ->
                async {
                    if (key in found || resting(key) || !looking.add(key)) return@async
                    try {
                        found[key] = if (key == coverKey(song)) findCover(song) else findArtist(songArtist(song))
                        failedAt.remove(key)
                    } catch (e: Unreachable) {
                        failedAt[key] = clock()
                    } finally {
                        looking.remove(key)
                    }
                }
            }.awaitAll()
        }
    }

    private fun resting(key: String): Boolean = failedAt[key]?.let { clock() - it < RETRY_AFTER_MS } == true

    // The body of a GET, or Unreachable when there was no answer to read.
    private fun get(url: String): String = fetch(url) ?: throw Unreachable()

    private fun keysFor(song: ArtQuery, prefs: DiscordPrefs): List<String> = buildList {
        if (prefs.picture == DiscordPicture.Cover && (knownAlbum(song) != null || song.title.isNotBlank())) add(coverKey(song))
        if (prefs.badge == DiscordBadge.Artist && songArtist(song).isNotBlank()) add(artistKey(song))
    }

    // By the album when there is a real one, then by the song: a library of
    // singles often has no album, or one the catalogues file differently.
    private fun findCover(song: ArtQuery): String? {
        val credit = albumCredit(song)
        val album = knownAlbum(song)
        if (album != null) {
            val term = enc("${SongIdentity.primaryArtist(credit)} $album")
            (deezerCover(get(DEEZER_ALBUM + term), credit, album) ?: itunesCover(get(ITUNES_ALBUM + term), credit, album))
                ?.let { return it }
        }
        if (song.title.isBlank()) return null
        val term = enc("${songArtist(song)} ${SongIdentity.stripFeatures(song.title)}")
        return deezerTrackCover(get(DEEZER_TRACK + term), song.artist, song.title)
            ?: itunesSongCover(get(ITUNES_SONG + term), song.artist, song.title)
    }

    private fun findArtist(artist: String): String? =
        deezerArtistPhoto(get(DEEZER_ARTIST + enc(artist)), artist)

    private fun coverKey(song: ArtQuery): String {
        val album = knownAlbum(song)
        return if (album != null) "cover:${SongIdentity.key(SongIdentity.primaryArtist(albumCredit(song)))}|${SongIdentity.key(album)}"
        else "cover:${SongIdentity.key(songArtist(song))}|song:${SongIdentity.key(SongIdentity.stripFeatures(song.title))}"
    }

    private fun artistKey(song: ArtQuery) = "artist:${SongIdentity.key(songArtist(song))}"
}

// Who the album is by: its own artist, unless that is blank or "Various
// Artists", then the song's.
private fun albumCredit(song: ArtQuery): String =
    song.albumArtist.takeUnless { it.isBlank() || SongIdentity.key(it) in Various } ?: song.artist

// The artist a song is by, first of its credits ("Scrim • $crim" is Scrim).
private fun songArtist(song: ArtQuery): String = SongIdentity.primaryArtist(song.artist)

// The album, unless there is none worth looking for.
private fun knownAlbum(song: ArtQuery): String? =
    song.album.trim().takeUnless { it.isEmpty() || UnknownAlbum.matches(it) }

private val UnknownAlbum = Regex("""\[?\s*unknown album\s*]?""", RegexOption.IGNORE_CASE)
private val Various = setOf(SongIdentity.key("Various Artists"), SongIdentity.key("Various"), SongIdentity.key("VA"))

private class Unreachable : Exception()

// How long a lookup that could not reach the catalogue rests before another try.
const val RETRY_AFTER_MS = 2 * 60_000L

// Plain searches: Deezer's own artist:"…" album:"…" form finds nothing for
// a name it spells differently, where a plain search still does.
private const val DEEZER_ALBUM = "https://api.deezer.com/search/album?limit=10&q="
private const val DEEZER_TRACK = "https://api.deezer.com/search/track?limit=10&q="
private const val DEEZER_ARTIST = "https://api.deezer.com/search/artist?limit=5&q="
private const val ITUNES_ALBUM = "https://itunes.apple.com/search?media=music&entity=album&limit=10&term="
private const val ITUNES_SONG = "https://itunes.apple.com/search?media=music&entity=song&limit=10&term="

// How big the pictures are: Discord fetches them itself (through its own
// proxy) and draws the cover at most a couple of hundred pixels across even
// on a sharp screen, and the badge far smaller. So the cover is asked for
// at 512 px (Deezer's nearest is 500) and the artist's photo at 250: no
// visible loss, and about a quarter of the weight of 1000 px.
private const val COVER_PX = 512

private val json = Json { ignoreUnknownKeys = true }

private fun enc(text: String) = URLEncoder.encode(text, Charsets.UTF_8)

// "Album - Single" and "Album - EP" on iTunes are the album.
private val ReleaseKind = Regex("""\s+-\s+(Single|EP)$""")

private fun albumKey(name: String) = SongIdentity.key(name.replace(ReleaseKind, ""))

private fun titleKey(name: String) = SongIdentity.key(SongIdentity.stripFeatures(name))

private fun JsonObject.text(name: String): String? = this[name]?.jsonPrimitive?.content

private fun rows(body: String, name: String): List<JsonObject> =
    json.parseToJsonElement(body).jsonObject[name]?.jsonArray.orEmpty().map { it.jsonObject }

// The first iTunes album whose artist and name agree, at COVER_PX.
fun itunesCover(body: String, artist: String, album: String): String? =
    runCatching {
        rows(body, "results").firstOrNull {
            sameArtist(it.text("artistName").orEmpty(), artist) && albumKey(it.text("collectionName").orEmpty()) == albumKey(album)
        }?.text("artworkUrl100")?.replace("100x100bb", "${COVER_PX}x${COVER_PX}bb")
    }.getOrNull()

// The first Deezer album whose artist and name agree, at 500 px.
fun deezerCover(body: String, artist: String, album: String): String? =
    runCatching {
        rows(body, "data").firstOrNull {
            sameArtist(it["artist"]?.jsonObject?.text("name").orEmpty(), artist) && albumKey(it.text("title").orEmpty()) == albumKey(album)
        }?.text("cover_big")
    }.getOrNull()

// The cover of the first Deezer track whose artist and title agree.
fun deezerTrackCover(body: String, artist: String, title: String): String? =
    runCatching {
        rows(body, "data").firstOrNull {
            sameArtist(it["artist"]?.jsonObject?.text("name").orEmpty(), artist) && titleKey(it.text("title").orEmpty()) == titleKey(title)
        }?.get("album")?.jsonObject?.text("cover_big")
    }.getOrNull()

// The cover of the first iTunes song whose artist and title agree, at COVER_PX.
fun itunesSongCover(body: String, artist: String, title: String): String? =
    runCatching {
        rows(body, "results").firstOrNull {
            sameArtist(it.text("artistName").orEmpty(), artist) && titleKey(it.text("trackName").orEmpty()) == titleKey(title)
        }?.text("artworkUrl100")?.replace("100x100bb", "${COVER_PX}x${COVER_PX}bb")
    }.getOrNull()

// The Deezer photo of the artist with this very name; Deezer's empty
// placeholder (no picture id in its address) is not a photo.
fun deezerArtistPhoto(body: String, artist: String): String? =
    runCatching {
        rows(body, "data").firstOrNull {
            SongIdentity.key(it.text("name").orEmpty()) == SongIdentity.key(artist)
        }?.text("picture_medium")?.takeUnless { "/artist//" in it }
    }.getOrNull()

private val http by lazy {
    OkHttpClient.Builder().callTimeout(4, TimeUnit.SECONDS).build()
}

private fun httpGet(url: String): String? = runCatching {
    http.newCall(Request.Builder().url(url).header("User-Agent", "Octo").build()).execute().use { response ->
        if (response.isSuccessful) response.body.string() else null
    }
}.getOrNull()
