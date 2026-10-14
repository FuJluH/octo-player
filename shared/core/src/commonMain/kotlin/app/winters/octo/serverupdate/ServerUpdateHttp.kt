package app.winters.octo.serverupdate

import app.winters.octo.subsonic.SubsonicClient
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import okhttp3.HttpUrl
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.IOException
import java.util.concurrent.TimeUnit

// Reading and starting a server update.
interface ServerUpdateCalls {
    suspend fun read(): UpdateRead

    suspend fun start(tag: String): UpdateStart
}

// Where Octo's admin pages answer, how a call to them is signed, and the
// server's own extra headers (a proxy's access token), which go only there.
class AdminPlace(
    val base: HttpUrl,
    val sign: (HttpUrl) -> HttpUrl,
    val headers: Map<String, String> = emptyMap(),
)

// The server's own addresses as the place: the one calls go to now. The
// sign-in is only ever added for the server's own addresses, never for an
// address that merely answers like it.
fun ownAddresses(client: SubsonicClient, headers: Map<String, String> = emptyMap()): AdminPlace {
    val trusted = setOf(rootOf(client.baseUrl), rootOf(client.primaryUrl))
    return AdminPlace(rootOf(client.baseUrl), { url -> if (rootOf(url) in trusted) client.signed(url) else url }, headers)
}

private fun rootOf(url: HttpUrl): HttpUrl = url.newBuilder().encodedPath("/").query(null).fragment(null).build()

// GET and POST /api/admin/update. Every call has a short limit of its own,
// so a connection left open to a server that restarted is dropped rather
// than waited on.
class ServerUpdateHttp(
    http: OkHttpClient,
    private val where: suspend () -> AdminPlace?,
) : ServerUpdateCalls {
    private val quick = http.newBuilder().callTimeout(UPDATE_CALL_TIMEOUT_MS, TimeUnit.MILLISECONDS).build()

    override suspend fun read(): UpdateRead {
        val place = runCatching { where() }.getOrNull() ?: return UpdateRead.NoAnswer
        return withContext(Dispatchers.IO) {
            try {
                quick.newCall(request(place).get().build()).execute().use { response ->
                    when {
                        response.code in NOT_OFFERED -> UpdateRead.NotOffered
                        !response.isSuccessful -> UpdateRead.NoAnswer
                        else -> parseServerUpdate(response.body.string())?.let { UpdateRead.Answered(it) } ?: UpdateRead.NoAnswer
                    }
                }
            } catch (e: IOException) {
                UpdateRead.NoAnswer
            }
        }
    }

    override suspend fun start(tag: String): UpdateStart {
        val place = runCatching { where() }.getOrNull() ?: return UpdateStart.Refused(NO_ANSWER)
        val body = JsonObject(mapOf("tag" to JsonPrimitive(tag))).toString().toRequestBody("application/json".toMediaType())
        return withContext(Dispatchers.IO) {
            try {
                quick.newCall(request(place).header("X-Octo-Admin", "1").post(body).build()).execute().use { response ->
                    val answer = parseStartAnswer(response.body.string())
                    when {
                        response.isSuccessful -> UpdateStart.Started(answer?.id, answer?.tag ?: tag)
                        response.code == 409 -> UpdateStart.Refused(answer?.error?.takeIf(String::isNotBlank) ?: "Octo would not start the update just now.")
                        response.code in NOT_OFFERED -> UpdateStart.Refused("Only a Navidrome admin can update the server.")
                        else -> UpdateStart.Refused(answer?.error?.takeIf(String::isNotBlank) ?: NO_ANSWER)
                    }
                }
            } catch (e: IOException) {
                UpdateStart.Refused(NO_ANSWER)
            }
        }
    }

    private fun request(place: AdminPlace): Request.Builder {
        val url = place.sign(place.base.newBuilder().encodedPath("/api/admin/update").query(null).build())
        return Request.Builder().url(url).apply { place.headers.forEach { (name, value) -> header(name, value) } }
    }

    private companion object {
        // A listener's account, or a server that has no such page or does
        // not take the app's sign-in there.
        val NOT_OFFERED = setOf(401, 403, 404)

        const val NO_ANSWER = "Octo did not answer. Try again in a moment."
    }
}
