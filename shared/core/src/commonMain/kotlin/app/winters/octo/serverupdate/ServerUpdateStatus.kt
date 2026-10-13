package app.winters.octo.serverupdate

import kotlinx.serialization.Serializable
import kotlinx.serialization.SerializationException
import kotlinx.serialization.json.Json

// What Octo's admin pages say about updating the server itself, as
// GET /api/admin/update answers. Only the parts the apps read; anything
// missing reads as its plain default.

// A release on Octo's repository: its tag, name, notes in markdown and page.
@Serializable
data class ServerRelease(
    val tag: String = "",
    val name: String? = null,
    val notes: String? = null,
    val url: String? = null,
    val publishedUtc: String? = null,
)

// The small service on the server's host that fetches a release and
// restarts Octo. `mode` is how it brings a release in: "image" pulls the
// published images, "git" checks the release out first, "build" builds it.
@Serializable
data class UpdateHelper(
    val installed: Boolean = false,
    val version: String? = null,
    val mode: String? = null,
    val dir: String? = null,
    val installedUtc: String? = null,
    val outdated: Boolean = false,
)

// One run of the helper: the release it brings in, where it is, and why it
// stopped when it failed.
@Serializable
data class UpdateRun(
    val id: String = "",
    val tag: String? = null,
    val from: String? = null,
    val state: String = "",
    val step: String? = null,
    val error: String? = null,
    val startedUtc: String? = null,
    val finishedUtc: String? = null,
    val log: List<String> = emptyList(),
) {
    // Still under way: neither done nor failed.
    val active: Boolean get() = state in RunState.ACTIVE
}

// The states a run moves through.
object RunState {
    const val ACCEPTED = "accepted"
    const val FETCHING = "fetching"
    const val BUILDING = "building"
    const val RESTARTING = "restarting"
    const val DONE = "done"
    const val FAILED = "failed"

    val ACTIVE = setOf(ACCEPTED, FETCHING, BUILDING, RESTARTING)
}

@Serializable
data class ServerUpdateStatus(
    val enabled: Boolean = false,
    val repo: String = "",
    // The release the server runs now.
    val running: String = "",
    val latest: ServerRelease? = null,
    // Every release newer than the one running, newest first.
    val newer: List<ServerRelease> = emptyList(),
    val updateAvailable: Boolean = false,
    // "behind", "current", "ahead" or "unknown".
    val standing: String = "unknown",
    val checkedUtc: String? = null,
    val error: String? = null,
    val helper: UpdateHelper = UpdateHelper(),
    val reinstallCommand: String = "",
    // A request written for the helper that it has not picked up yet.
    val pending: Boolean = false,
    val pendingId: String? = null,
    // The id of a request the helper never picked up.
    val unanswered: String? = null,
    val run: UpdateRun? = null,
    val command: String = "",
    val imageCommand: String = "",
) {
    // An update is waiting for the helper or under way.
    val busy: Boolean get() = pending || run?.active == true

    // Whether this app can start the update: one is out, the helper is
    // there and current, and nothing is under way.
    val canUpdate: Boolean get() = updateAvailable && latest != null && helper.installed && !helper.outdated && !busy
}

private val updateJson = Json {
    ignoreUnknownKeys = true
    coerceInputValues = true
    explicitNulls = false
}

// The admin page's answer, or null when it is not one.
fun parseServerUpdate(text: String): ServerUpdateStatus? = try {
    updateJson.decodeFromString(ServerUpdateStatus.serializer(), text)
} catch (e: SerializationException) {
    null
} catch (e: IllegalArgumentException) {
    null
}

// What POST /api/admin/update answers: the request's id and tag, or why not.
@Serializable
internal data class StartAnswer(val ok: Boolean = false, val id: String? = null, val tag: String? = null, val error: String? = null)

internal fun parseStartAnswer(text: String): StartAnswer? = try {
    updateJson.decodeFromString(StartAnswer.serializer(), text)
} catch (e: SerializationException) {
    null
} catch (e: IllegalArgumentException) {
    null
}

// Orders two of Octo's dated release tags, like 2026.10.03 and
// 2026.10.03.1: number by number, a longer tag after the shorter one it
// starts with. Parts that are not numbers compare as words.
fun compareReleaseTags(a: String, b: String): Int {
    val left = a.trim().removePrefix("v").split('.', '-')
    val right = b.trim().removePrefix("v").split('.', '-')
    for (i in 0 until maxOf(left.size, right.size)) {
        val x = left.getOrNull(i) ?: return -1
        val y = right.getOrNull(i) ?: return 1
        val nx = x.toLongOrNull()
        val ny = y.toLongOrNull()
        val order = if (nx != null && ny != null) nx.compareTo(ny) else x.compareTo(y)
        if (order != 0) return order
    }
    return 0
}
