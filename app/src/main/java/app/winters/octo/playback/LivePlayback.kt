package app.winters.octo.playback

import androidx.annotation.OptIn
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.common.Timeline
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.source.ForwardingTimeline
import app.winters.octo.liveradio.LiveLineup
import app.winters.octo.liveradio.liveLineup

// How the player behaves while a live station plays: no seeking anywhere,
// Back and Next step through the stations it was started from in their
// order and stop at the ends, and the session says the stream is live,
// with no length.

// What the commands a player offers become while a station of `lineup`
// plays: none that seek within it, and the next and previous station only
// where there is one.
fun liveCommands(commands: Set<Int>, lineup: LiveLineup): Set<Int> {
    val kept = commands - NoLiveCommands
    return kept +
        (if (lineup.hasNext) setOf(Player.COMMAND_SEEK_TO_NEXT, Player.COMMAND_SEEK_TO_NEXT_MEDIA_ITEM) else emptySet()) +
        (if (lineup.hasPrevious) setOf(Player.COMMAND_SEEK_TO_PREVIOUS, Player.COMMAND_SEEK_TO_PREVIOUS_MEDIA_ITEM) else emptySet())
}

private val NoLiveCommands = setOf(
    Player.COMMAND_SEEK_IN_CURRENT_MEDIA_ITEM,
    Player.COMMAND_SEEK_BACK,
    Player.COMMAND_SEEK_FORWARD,
    Player.COMMAND_SEEK_TO_NEXT,
    Player.COMMAND_SEEK_TO_NEXT_MEDIA_ITEM,
    Player.COMMAND_SEEK_TO_PREVIOUS,
    Player.COMMAND_SEEK_TO_PREVIOUS_MEDIA_ITEM,
)

// What a seek asks of a station that plays, as the queue index to go to;
// null for one that does nothing. Next and previous go to the station after
// or before in the lineup, never round from an end, and "previous" never
// starts the station again the way it does a song. Choosing a station in
// the queue goes to it. Nothing seeks within a station.
fun liveSeekTarget(seekCommand: Int, requestedIndex: Int, lineup: LiveLineup): Int? = when (seekCommand) {
    Player.COMMAND_SEEK_TO_NEXT, Player.COMMAND_SEEK_TO_NEXT_MEDIA_ITEM -> lineup.next
    Player.COMMAND_SEEK_TO_PREVIOUS, Player.COMMAND_SEEK_TO_PREVIOUS_MEDIA_ITEM -> lineup.previous
    Player.COMMAND_SEEK_TO_MEDIA_ITEM -> requestedIndex.takeIf { it in lineup.ids.indices && it != lineup.index }
    else -> null
}

// The lineup of what a player holds, while its current item is a station.
fun Player.liveLineupNow(): LiveLineup? {
    val current = currentMediaItem ?: return null
    if (!isRadio(current.mediaId)) return null
    return liveLineup(List(mediaItemCount) { getMediaItemAt(it).mediaId }, currentMediaItemIndex)
}

// The lineup of the items a timeline holds, at `current`.
fun liveLineupOf(timeline: Timeline, current: Int): LiveLineup? {
    if (current !in 0 until timeline.windowCount) return null
    val window = Timeline.Window()
    val ids = List(timeline.windowCount) { timeline.getWindow(it, window).mediaItem.mediaId }
    return liveLineup(ids, current)
}

// A timeline whose stations are live: no length, nowhere to seek to, and
// marked live, so the lock screen and the notification show no scrubber
// and no times.
@OptIn(UnstableApi::class)
class LiveTimeline(timeline: Timeline) : ForwardingTimeline(timeline) {
    override fun getWindow(windowIndex: Int, window: Window, defaultPositionProjectionUs: Long): Window {
        super.getWindow(windowIndex, window, defaultPositionProjectionUs)
        if (isRadio(window.mediaItem.mediaId)) {
            window.isSeekable = false
            window.isDynamic = true
            window.durationUs = C.TIME_UNSET
            if (window.liveConfiguration == null) window.liveConfiguration = MediaItem.LiveConfiguration.UNSET
        }
        return window
    }
}

// The ids a set of commands holds.
fun Player.Commands.toIds(): Set<Int> = (0 until size()).mapTo(HashSet()) { get(it) }

fun commandsOf(ids: Set<Int>): Player.Commands = Player.Commands.Builder().apply { ids.forEach(::add) }.build()
