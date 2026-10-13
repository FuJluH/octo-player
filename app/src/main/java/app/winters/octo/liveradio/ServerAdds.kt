package app.winters.octo.liveradio

import kotlin.coroutines.cancellation.CancellationException

// How adding a live station to the server went.
sealed interface AddResult {
    data object Added : AddResult

    // Only an admin may add stations; nothing was asked.
    data object NotAdmin : AddResult

    // The server streams it already; nothing was asked.
    data object AlreadyThere : AddResult

    // No server is signed in; nothing was asked.
    data object NoServer : AddResult

    // The server said no, in its words.
    data class Failed(val why: String) : AddResult
}

// Adds live stations to the server in use, for an admin only, and never one
// it already streams. `add` asks the server and says whether a server was
// there to ask; `streams` are the server's stations' stream addresses.
class ServerAdds(
    private val admin: () -> Boolean,
    private val streams: () -> Collection<String>,
    private val add: suspend (LiveStation) -> Boolean,
    private val why: (Exception) -> String = { it.message.orEmpty() },
) {
    // Whether the server streams this address already.
    fun onServer(streamUrl: String): Boolean {
        val key = liveStreamKey(streamUrl)
        return streams().any { liveStreamKey(it) == key }
    }

    // Whether the menu offers adding this station.
    fun offers(station: LiveStation): Boolean = admin() && !onServer(station.streamUrl)

    suspend fun addToServer(station: LiveStation): AddResult {
        if (!admin()) return AddResult.NotAdmin
        if (onServer(station.streamUrl)) return AddResult.AlreadyThere
        return try {
            if (add(station)) AddResult.Added else AddResult.NoServer
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            AddResult.Failed(why(e))
        }
    }
}

// What adding a station said, in words.
fun addResultLine(result: AddResult, name: String): String = when (result) {
    AddResult.Added -> "Added $name to your server"
    AddResult.NotAdmin -> "Only an admin can add stations to this server."
    AddResult.AlreadyThere -> "$name is on your server already"
    AddResult.NoServer -> "Sign in to a server to add $name to it."
    is AddResult.Failed -> "Could not add $name: ${result.why}"
}
