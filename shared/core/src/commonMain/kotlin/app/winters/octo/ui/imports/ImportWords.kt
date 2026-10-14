package app.winters.octo.ui.imports

import app.winters.octo.subsonic.ImportListSummary
import app.winters.octo.subsonic.ImportOverview
import app.winters.octo.subsonic.ImportSource
import app.winters.octo.subsonic.ImportTrackState
import app.winters.octo.subsonic.TrickleState
import app.winters.octo.subsonic.TrickleStatus
import app.winters.octo.ui.upgrade.songsText
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter

// Imports as the phone and the desktop both show them: the words for each
// state and what a list's line says. The server does the reading, matching
// and fetching; the apps draw what it says and pass on what was tapped.

// How often to ask how things are going while songs are on their way, and
// otherwise while the view is open.
const val IMPORTS_BUSY_POLL_MS = 3_000L
const val IMPORTS_IDLE_POLL_MS = 20_000L

// Whether anything is moving on the server, so the view asks again soon.
fun ImportOverview.moving(): Boolean = trickle.queued > 0 || trickle.downloading > 0

const val KEEP_AS_PLAYLIST = "Keep as playlist"
const val GET_MISSING_SONGS = "Get missing songs"

// One song's state, in the words the dashboard uses too.
fun ImportTrackState.label(): String = when (this) {
    ImportTrackState.Have -> "In your library"
    ImportTrackState.Missing -> "Missing"
    ImportTrackState.Queued -> "Queued"
    ImportTrackState.Downloading -> "Fetching"
    ImportTrackState.Done -> "Fetched"
    ImportTrackState.NotFound -> "Not found"
    ImportTrackState.Skipped -> "Skipped"
    ImportTrackState.Unknown -> "Unknown"
}

// Where a list came from, who made it when someone else did, and that a
// list from a Spotify account sign-in no longer updates.
fun ImportListSummary.originLine(): String = listOfNotNull(
    when (origin) {
        ImportSource.SpotifyLiked, ImportSource.SpotifyPlaylist -> "Spotify"
        ImportSource.Link -> "Link"
        ImportSource.File -> "File"
        ImportSource.Unknown -> null
    },
    by?.let { "by $it" },
    if (origin.fromSignIn) "not updating" else null,
).joinToString(" · ")

// "6 of 10 · 2 missing · 1 coming · 1 not found".
fun ImportListSummary.countsLine(): String = listOfNotNull(
    "$have of $total",
    if (missing > 0) "$missing missing" else null,
    if (coming > 0) "$coming coming" else null,
    if (notFound > 0) "$notFound not found" else null,
).joinToString(" · ")

// Removing a list is asked first: the question, and what goes and what
// stays. The server keeps the songs it fetched and the playlist it made.
const val REMOVE_LIST = "Remove this list?"

fun ImportListSummary.removeLine(): String = buildString {
    append("Octo forgets $name")
    if (getMissing) append(" and stops getting its missing songs")
    append(". Songs already in your library stay")
    if (playlistId != null) append(", and so does its playlist")
    append(".")
}

// What the trickle is doing, as a heading.
fun TrickleStatus.title(): String = when (stage) {
    TrickleState.Idle, TrickleState.Unknown -> "Nothing to fetch"
    TrickleState.Running -> if (downloading > 0) "Fetching" else "Waiting for the next turn"
    TrickleState.Paused -> "Paused"
    TrickleState.Off -> "Off"
    TrickleState.Yielding -> "Waiting for other downloads"
    TrickleState.WaitingForSoulseek -> "Waiting for Soulseek"
}

// The trickle's line under it: the pace, when the next song starts, and the counts.
fun TrickleStatus.line(zone: ZoneId = ZoneId.systemDefault()): String {
    val parts = ArrayList<String>()
    if (stage == TrickleState.Off) parts += "Songs an hour is 0 on the server, so nothing starts."
    else parts += "Up to ${songsText(perHour)} an hour."
    if (stage == TrickleState.Running && downloading == 0) nextUtc?.let { parts += "Next song at ${time(it, zone)}." }
    if (stage == TrickleState.Yielding) parts += "Someone's own downloads come first."
    if (stage == TrickleState.WaitingForSoulseek) parts += "It goes on once Soulseek is back."
    val tally = listOf(queued to "waiting", downloading to "fetching", done to "fetched", notFound to "not found", skipped to "skipped")
        .filter { it.first > 0 }.joinToString(", ") { "${it.first} ${it.second}" }
    if (tally.isNotEmpty()) parts += "$tally."
    return parts.joinToString(" ")
}

private fun time(utc: String, zone: ZoneId): String = runCatching {
    DateTimeFormatter.ofPattern("HH:mm").format(Instant.parse(utc).atZone(zone))
}.getOrDefault(utc)
