package app.winters.octo.desktop.discord

import app.winters.octo.desktop.system.NowPlaying
import app.winters.octo.desktop.system.isOpenedFile
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.addJsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray
import kotlinx.serialization.json.putJsonObject

// Showing what plays in the listener's Discord status. Off until they turn
// it on; songs opened from a file on this computer stay out of it unless
// they say so too. The rest shapes how it looks.
@Serializable
data class DiscordPrefs(
    val on: Boolean = false,
    val openedFiles: Boolean = false,
    // The two lines under "Listening to Octo"; {title}, {artist} and {album}
    // are filled in.
    val firstLine: String = FIRST_LINE,
    val secondLine: String = SECOND_LINE,
    // What the member list names after "Listening to".
    val listName: DiscordListName = DiscordListName.Song,
    val time: DiscordTime = DiscordTime.Remaining,
    // The album's name, when someone points at the cover.
    val albumName: Boolean = true,
    val picture: DiscordPicture = DiscordPicture.Cover,
    val badge: DiscordBadge = DiscordBadge.Artist,
    // Stays on show while paused, with a pause badge and no time.
    val whilePaused: Boolean = false,
    // The song and artist open their Last.fm pages, with a button for friends.
    val lastFmLinks: Boolean = true,
)

const val FIRST_LINE = "{title}"
const val SECOND_LINE = "{artist}"

@Serializable enum class DiscordListName { Song, Artist, App }

@Serializable enum class DiscordTime { Remaining, Elapsed, Off }

@Serializable enum class DiscordPicture { Cover, Icon }

@Serializable enum class DiscordBadge { Artist, Icon, Off }

// What Octo puts in the Discord status. Discord draws the time bar from
// the start and end, so nothing needs sending while it plays on.
data class DiscordActivity(
    val details: String,
    val state: String?,
    val listName: DiscordListName = DiscordListName.Song,
    val startMs: Long?,
    val endMs: Long?,
    val largeImage: String = DISCORD_ICON,
    val largeText: String? = null,
    val smallImage: String? = null,
    val smallText: String? = null,
    val detailsUrl: String? = null,
    val stateUrl: String? = null,
    val button: DiscordButton? = null,
) {
    // Whether this shows the same as `other`: everything the same, and times
    // no further apart than a moment of drift. A seek moves them further.
    fun looksLike(other: DiscordActivity?): Boolean =
        other != null &&
            copy(startMs = null, endMs = null) == other.copy(startMs = null, endMs = null) &&
            near(startMs, other.startMs) &&
            near(endMs, other.endMs)

    private fun near(a: Long?, b: Long?): Boolean =
        (a == null) == (b == null) && kotlin.math.abs((a ?: 0) - (b ?: 0)) <= TIME_SLACK_MS
}

data class DiscordButton(val label: String, val url: String)

// How far the shown times may drift from the player's before they are sent again.
const val TIME_SLACK_MS = 2_000L

// Octo's icon, uploaded to the Discord application under this name: the
// picture when no cover is found, or by choice. Never a cover from the
// listener's server, since its address would carry the sign-in.
const val DISCORD_ICON = "octo"

// The badge shown while paused, uploaded under this name.
const val DISCORD_PAUSE = "pause"

// Discord takes words of 2 to 128 characters.
private const val TEXT_MIN = 2
private const val TEXT_MAX = 128

// Discord drops a link or picture address longer than these.
private const val URL_MAX = 256
private const val BUTTON_URL_MAX = 512

// What to show for the song in, or null to show nothing: nothing with
// nothing in, nothing while paused unless the listener keeps it on show,
// and nothing for a file opened from this computer unless they allowed it.
// The times follow the playing speed, so the bar ends when the song does.
// `art` is the cover and artist photo found so far, if any.
fun discordActivityFor(
    now: NowPlaying?,
    positionMs: Long,
    clockMs: Long,
    prefs: DiscordPrefs,
    art: DiscordArtwork = DiscordArtwork(),
): DiscordActivity? {
    if (!prefs.on || now == null) return null
    if (!now.playing && !prefs.whilePaused) return null
    if (isOpenedFile(now.songId) && !prefs.openedFiles) return null
    val album = discordAlbum(now.title, now.album)
    fun fill(template: String): String {
        val line = template.replace("{title}", now.title).replace("{artist}", now.artist).replace("{album}", album)
        return if ("{album}" in template && album.isBlank()) tidyLine(line) else line
    }
    val speed = now.speed.takeIf { it.isFinite() && it > 0f } ?: 1f
    val length = now.durationMs.takeIf { it > 0 }
    val played = positionMs.coerceIn(0, length ?: Long.MAX_VALUE)
    val start = clockMs - (played / speed).toLong()
    val timed = now.playing && prefs.time != DiscordTime.Off
    // A live station shows its song's artwork or its logo from the web.
    val cover = (now.artUrl?.takeIf { now.live } ?: art.cover)?.takeIf { prefs.picture == DiscordPicture.Cover && it.length <= URL_MAX }
    val (small, smallText) = when {
        !now.playing -> DISCORD_PAUSE to "Paused"
        prefs.badge == DiscordBadge.Artist -> art.artist?.takeIf { it.length <= URL_MAX } to discordText(now.artist)
        prefs.badge == DiscordBadge.Icon && cover != null -> DISCORD_ICON to "Octo"
        else -> null to null
    }
    // A station naming no song links nowhere.
    val linked = prefs.lastFmLinks && (!now.live || now.liveNamed)
    val track = if (linked) lastFmTrackUrl(now.artist, now.title) else null
    return DiscordActivity(
        details = discordText(fill(prefs.firstLine)) ?: discordText(now.title) ?: "Unknown song",
        state = discordText(fill(prefs.secondLine)),
        listName = prefs.listName,
        startMs = start.takeIf { timed },
        endMs = length?.let { start + (it / speed).toLong() }?.takeIf { timed && prefs.time == DiscordTime.Remaining },
        largeImage = cover ?: DISCORD_ICON,
        largeText = (if (prefs.albumName) discordText(album) else null) ?: if (cover == null) "Octo" else null,
        smallImage = small,
        smallText = smallText.takeIf { small != null },
        detailsUrl = track?.takeIf { it.length <= URL_MAX },
        stateUrl = if (linked) lastFmArtistUrl(now.artist)?.takeIf { it.length <= URL_MAX } else null,
        button = track?.takeIf { it.length <= BUTTON_URL_MAX }?.let { DiscordButton("Open on Last.fm", it) },
    )
}

// The album as Discord shows it: none when it only says the song's title
// again, as a single named after its song does ("Creep" from "Creep -
// Single"). Case, punctuation and a Single or EP ending make no difference.
fun discordAlbum(title: String, album: String): String =
    if (album.isNotBlank() && plainName(album.replace(ReleaseKind, "")).let { it.isNotEmpty() && it == plainName(title) }) "" else album

// " - Single", " (EP)", " [Single]" at the end of an album's name.
private val ReleaseKind = Regex("""\s*(?:[-–:]\s*|[(\[]\s*)(?:single|ep)\s*[)\]]?\s*$""", RegexOption.IGNORE_CASE)

// Only the letters and digits of a name, in lower case.
private fun plainName(name: String): String = name.lowercase().filter(Char::isLetterOrDigit)

// A filled line without what an empty part left behind: "()" or "[]", and
// a separator at either end ("Radiohead - " from "{artist} - {album}").
fun tidyLine(line: String): String =
    line.replace(EmptyBrackets, "").replace(Spaces, " ").trim().trim(*LineSeparators).trim()

private val EmptyBrackets = Regex("""\(\s*\)|\[\s*]""")
private val Spaces = Regex("""\s{2,}""")
private val LineSeparators = charArrayOf('-', '–', '·', '|', '•', ',', ':', '/', ' ')

// The public Last.fm pages of a song and an artist. Last.fm writes a space
// as + in its addresses, as form encoding does.
fun lastFmTrackUrl(artist: String, title: String): String? =
    if (artist.isBlank() || title.isBlank()) null
    else "https://www.last.fm/music/${lastFmPart(artist)}/_/${lastFmPart(title)}"

fun lastFmArtistUrl(artist: String): String? =
    if (artist.isBlank()) null else "https://www.last.fm/music/${lastFmPart(artist)}"

private fun lastFmPart(text: String): String = java.net.URLEncoder.encode(text.trim(), Charsets.UTF_8)

// Words made fit for Discord: trimmed, cut to its limit without splitting
// a character, and a single character padded with a blank it keeps.
// Nothing for blank words.
fun discordText(text: String?): String? {
    val trimmed = text?.trim().orEmpty()
    if (trimmed.isEmpty()) return null
    if (trimmed.length > TEXT_MAX) {
        var end = TEXT_MAX - 1
        if (Character.isHighSurrogate(trimmed[end - 1])) end--
        return trimmed.substring(0, end).trimEnd() + "…"
    }
    return if (trimmed.length < TEXT_MIN) trimmed + "⠀" else trimmed
}

// The activity as Discord reads it: "Listening to", the two lines, the
// cover with the album on it, the badge, links and a button.
fun DiscordActivity.toJson(): JsonObject = buildJsonObject {
    put("type", LISTENING)
    put(
        "status_display_type",
        when (listName) {
            DiscordListName.App -> SHOW_NAME
            DiscordListName.Artist -> SHOW_STATE
            DiscordListName.Song -> SHOW_DETAILS
        },
    )
    put("details", details)
    detailsUrl?.let { put("details_url", it) }
    state?.let { put("state", it) }
    stateUrl?.let { put("state_url", it) }
    if (startMs != null) {
        putJsonObject("timestamps") {
            put("start", startMs)
            endMs?.let { put("end", it) }
        }
    }
    putJsonObject("assets") {
        put("large_image", largeImage)
        largeText?.let { put("large_text", it) }
        smallImage?.let { put("small_image", it) }
        smallText?.let { put("small_text", it) }
    }
    button?.let { b ->
        putJsonArray("buttons") {
            addJsonObject {
                put("label", b.label)
                put("url", b.url)
            }
        }
    }
}

// The command that sets the status, or clears it with no activity.
fun setActivityCommand(activity: DiscordActivity?, pid: Long, nonce: String): JsonObject = buildJsonObject {
    put("cmd", "SET_ACTIVITY")
    putJsonObject("args") {
        put("pid", pid)
        put("activity", activity?.toJson() ?: JsonNull)
    }
    put("nonce", nonce)
}

// Discord's numbers for "Listening to", and for what the member list names
// after it: the app, the second line, or the first line (the song).
private const val LISTENING = 2
private const val SHOW_NAME = 0
private const val SHOW_STATE = 1
private const val SHOW_DETAILS = 2

// How long Octo waits before trying Discord again: soon at first, then
// less often, never longer than a minute, so a Discord opened later is
// found within a minute. A working connection starts it over.
class Backoff(private val steps: List<Long> = RETRY_STEPS_MS) {
    private var tries = 0

    fun next(): Long = steps[minOf(tries, steps.lastIndex)].also { tries++ }

    fun reset() {
        tries = 0
    }
}

val RETRY_STEPS_MS = listOf(2_000L, 5_000L, 10_000L, 20_000L, 40_000L, 60_000L)
