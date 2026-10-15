package app.winters.octo.ui.settings

import app.winters.octo.ambient.AmbientPrefs
import app.winters.octo.ambient.AmbientStrength
import app.winters.octo.connection.Place
import app.winters.octo.device.Access
import app.winters.octo.device.MusicFolder
import app.winters.octo.listening.ListenBrainzPrefs
import app.winters.octo.offline.CacheSize
import app.winters.octo.offline.OfflinePrefs
import app.winters.octo.playback.StreamQuality
import app.winters.octo.playback.speedLabel
import app.winters.octo.player.PlayerPrefs
import app.winters.octo.player.StreamPrefs
import app.winters.octo.radio.RadioDiscovery

// The one line under each category on the front page, saying how it is set
// now. Parts are joined with a middle dot, and the most telling come first.

private const val DOT = " · "
private const val MINUTE_MS = 60_000L
private const val HOUR_MS = 60 * MINUTE_MS
private const val DAY_MS = 24 * HOUR_MS

// At most this many parts, so the line stays one line.
private const val MOST_PARTS = 3

private fun line(vararg parts: String?): String = parts.filterNotNull().take(MOST_PARTS).joinToString(DOT)

private fun count(n: Int, one: String, many: String) = if (n == 1) "1 $one" else "%,d $many".format(n)

// A streaming size as the settings show it.
internal val StreamQuality.label: String get() = kbps?.let { "$it kbps" } ?: "Original"

// A cache size as the settings show it.
internal val CacheSize.label: String get() = if (this == CacheSize.Off) "Off" else "${bytes shr 30} GB"

fun playbackSummary(prefs: PlayerPrefs): String = line(
    if (prefs.crossfade) "Crossfade ${prefs.crossfadeSeconds} s" else "Gapless",
    speedLabel(prefs.speed).takeIf { !prefs.paceIsDefault },
    "Autoplay".takeIf { prefs.autoplay },
    "Skip silence".takeIf { prefs.skipSilence },
)

// Radio's two parts, with how song radio is tuned when it is not as it came.
fun radioSummary(prefs: PlayerPrefs): String = line(
    if (prefs.libraryOnly || prefs.radioDiscovery == RadioDiscovery.LibraryOnly) "Song radio from your library" else "Song radio ${prefs.radioDiscovery.label.lowercase()}",
    "Live radio",
)

fun appearanceSummary(ambient: AmbientPrefs, liveBackground: Boolean): String = line(
    when (ambient.strength) {
        AmbientStrength.Off -> "No glow"
        AmbientStrength.Subtle -> "Subtle glow"
        AmbientStrength.Rich -> "Rich glow"
    },
    "Live background".takeIf { liveBackground },
)

fun librarySummary(access: Access, songs: Int, folders: List<MusicFolder>): String {
    if (access != Access.Granted) return "Music on this phone not allowed yet"
    val left = folders.count { !it.included }
    return line(count(songs, "song", "songs"), count(left, "folder", "folders").plus(" left out").takeIf { left > 0 })
}

// The phone's part of the account card.
fun phoneLine(access: Access, songs: Int): String =
    if (access == Access.Granted) count(songs, "song", "songs") + " on this phone" else "Allow access to the music on this phone"

// How long ago something happened, in words: "Just now", "5 min ago".
fun timeAgo(at: Long, now: Long): String {
    val gone = (now - at).coerceAtLeast(0)
    return when {
        gone < MINUTE_MS -> "Just now"
        gone < HOUR_MS -> "${gone / MINUTE_MS} min ago"
        gone < DAY_MS -> "${gone / HOUR_MS} hr ago"
        gone < 2 * DAY_MS -> "Yesterday"
        else -> "${gone / DAY_MS} days ago"
    }
}

// When the library was last copied from the server, in words.
fun syncedAgo(at: Long, now: Long): String = "Synced " + timeAgo(at, now).replaceFirstChar { it.lowercase() }

// How the server is doing, for the account card and its category: syncing,
// or where it is reached from and how fresh the copy is. Place is null when
// the server has only one address.
fun serverStatus(syncing: Boolean, place: Place?, syncedAt: Long?, now: Long): String {
    if (syncing) return "Syncing…"
    return line(
        when (place) {
            Place.Home -> "Connected at home"
            Place.Away -> "Connected away"
            null -> null
        },
        syncedAt?.let { syncedAgo(it, now) } ?: "Not synced yet",
    )
}

fun streamingSummary(stream: StreamPrefs, offline: OfflinePrefs): String = line(
    "Wi-Fi ${stream.wifi.label}",
    "mobile ${stream.mobile.label}",
    if (offline.cacheSize == CacheSize.Off) "no cache" else "${offline.cacheSize.label} cache",
)

fun lyricsSummary(online: Boolean, keepScreenOn: Boolean): String = line(
    if (online) "Found online" else "From your music only",
    "Screen stays on".takeIf { keepScreenOn },
)

fun scrobblingSummary(prefs: ListenBrainzPrefs): String = when {
    !prefs.enabled -> "Off"
    !prefs.connected -> "Not connected yet"
    prefs.needsAttention -> "Needs a new token"
    else -> "ListenBrainz as ${prefs.user}"
}

const val BACKUP_SUMMARY = "Settings, playlists, likes and favorites"

fun aboutSummary(version: String, updateReady: String? = null): String =
    if (updateReady != null) "Update ready: $updateReady" else "Version $version"
