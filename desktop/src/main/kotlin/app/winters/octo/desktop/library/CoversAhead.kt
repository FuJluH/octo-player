package app.winters.octo.desktop.library

import app.winters.octo.covers.AheadCoverBucket
import app.winters.octo.covers.COVERS_AHEAD
import app.winters.octo.covers.CoverAhead
import app.winters.octo.desktop.player.DesktopPlayer
import app.winters.octo.desktop.player.PlayerState
import app.winters.octo.desktop.player.QueueEntry
import app.winters.octo.desktop.player.RepeatMode
import app.winters.octo.playback.nextInPlayOrder
import app.winters.octo.subsonic.SubsonicClient
import coil3.ImageLoader
import coil3.PlatformContext
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map

// The covers of the song on and the next ones in play order (shuffled or
// not, wrapping round with repeat all), the song on first.
fun coversAhead(state: PlayerState, count: Int = COVERS_AHEAD): List<String> {
    val current = state.current
    val played = state.played
    val upcoming = state.upcoming
    // The whole play order, without copying a long queue.
    val order = object : AbstractList<QueueEntry>() {
        override val size: Int get() = played.size + (if (current != null) 1 else 0) + upcoming.size

        override fun get(index: Int): QueueEntry = when {
            index < played.size -> played[index]
            current != null && index == played.size -> current
            else -> upcoming[index - played.size - (if (current != null) 1 else 0)]
        }
    }
    val at = if (current != null) played.size else -1
    val next = nextInPlayOrder(order, at, state.repeat == RepeatMode.All, count)
    return (listOfNotNull(current) + next).mapNotNull { it.song.coverArt }.distinct()
}

// Keeps the covers of the song on and the next ones ready while it runs, so
// every place that shows the playing song (the player bar, the full player
// and its lyrics, the background, the mini player, the system's player)
// has its cover at once. The moment the song or the queue changes they are
// marked urgent, so they go to the server ahead of every other cover, and
// fetched together at the largest size, which answers every smaller ask.
suspend fun followCoversAhead(player: DesktopPlayer, client: () -> SubsonicClient?, loader: () -> ImageLoader) = coroutineScope {
    val ahead = CoverAhead(this, CoverTraffic.lanes) { coverId ->
        val server = client() ?: return@CoverAhead
        loader().execute(coverRequest(PlatformContext.INSTANCE, server, coverId, AheadCoverBucket).size(AheadCoverBucket).build())
    }
    try {
        player.state.map { coversAhead(it) }.distinctUntilChanged().collect { ahead.want(it) }
    } finally {
        ahead.stop()
    }
}
