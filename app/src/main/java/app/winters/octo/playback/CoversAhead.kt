package app.winters.octo.playback

import android.content.Context
import androidx.media3.common.C
import androidx.media3.common.Player
import app.winters.octo.catalog.ArtworkRef
import app.winters.octo.covers.AheadCoverBucket
import app.winters.octo.covers.COVERS_AHEAD
import app.winters.octo.covers.CoverAhead
import app.winters.octo.server.CoverTraffic
import app.winters.octo.server.serverCoverKey
import coil3.SingletonImageLoader
import coil3.request.ImageRequest
import coil3.size.Precision
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import javax.inject.Inject
import javax.inject.Singleton

// Keeps the covers of the playing song and the next ones in play order
// (shuffled or not, wrapping round with repeat all) ready, so every place
// that shows the playing song (the player, the mini bar, the lyrics bar,
// the background, the notification, the widgets) has its cover at once.
// The moment the song or the queue changes they are marked urgent, so
// they go to the server ahead of every other cover, and fetched together
// at the largest size, which answers every smaller ask for them.
@Singleton
class CoversAhead @Inject constructor(@ApplicationContext private val context: Context) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val ahead = CoverAhead(scope, CoverTraffic.lanes, urgentKey = ::laneKey) { ref -> fetch(ref) }
    private var player: Player? = null

    private val listener = object : Player.Listener {
        override fun onEvents(player: Player, events: Player.Events) {
            if (events.containsAny(
                    Player.EVENT_MEDIA_ITEM_TRANSITION,
                    Player.EVENT_TIMELINE_CHANGED,
                    Player.EVENT_SHUFFLE_MODE_ENABLED_CHANGED,
                    Player.EVENT_REPEAT_MODE_CHANGED,
                )
            ) {
                refresh()
            }
        }
    }

    // Follows this player until detached. Called on its thread.
    fun attach(player: Player) {
        this.player = player
        player.addListener(listener)
        refresh()
    }

    fun detach() {
        player?.removeListener(listener)
        player = null
        ahead.stop()
    }

    private fun refresh() {
        val player = player ?: return
        ahead.want(coversFor(player))
    }

    // The server covers of the song on and the next ones, the song on first.
    private fun coversFor(player: Player): List<String> {
        val timeline = player.currentTimeline
        if (timeline.isEmpty) return emptyList()
        val current = player.currentMediaItemIndex
        // Repeating one song still moves on to the next once it is skipped.
        val repeat = if (player.repeatMode == Player.REPEAT_MODE_ALL) Player.REPEAT_MODE_ALL else Player.REPEAT_MODE_OFF
        val shuffle = player.shuffleModeEnabled
        val next = nextInPlayOrder(current, COVERS_AHEAD) { index ->
            timeline.getNextWindowIndex(index, repeat, shuffle).takeIf { it != C.INDEX_UNSET }
        }
        return (listOf(current) + next)
            .mapNotNull { player.getMediaItemAt(it).mediaMetadata.artworkRef() }
            .filter { ArtworkRef.decode(it) is ArtworkRef.Server }
    }

    private suspend fun fetch(ref: String) {
        val art = ArtworkRef.decode(ref) as? ArtworkRef.Server ?: return
        val request = ImageRequest.Builder(context)
            .data(art)
            .size(AheadCoverBucket)
            .precision(Precision.INEXACT)
            .build()
        SingletonImageLoader.get(context).execute(request)
    }

    private companion object {
        // What the lanes know a cover by, as the artwork fetcher does.
        fun laneKey(ref: String): String = (ArtworkRef.decode(ref) as? ArtworkRef.Server)?.let { serverCoverKey(it) } ?: ref
    }
}
