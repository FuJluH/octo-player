package app.winters.octo.output

import androidx.annotation.OptIn
import androidx.media3.common.ForwardingSimpleBasePlayer
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import app.winters.octo.playback.EditableQueue
import app.winters.octo.playback.LiveTimeline
import app.winters.octo.playback.OctoPlayer
import app.winters.octo.playback.SleepTarget
import app.winters.octo.playback.commandsOf
import app.winters.octo.playback.entryId
import app.winters.octo.playback.liveCommands
import app.winters.octo.playback.liveLineupNow
import app.winters.octo.playback.liveLineupOf
import app.winters.octo.playback.liveSeekTarget
import app.winters.octo.playback.toIds
import com.google.common.util.concurrent.Futures
import com.google.common.util.concurrent.ListenableFuture

// The one player the media session holds: the phone's own player, or the
// one standing in while music plays on another device. Swapping between
// them goes unnoticed outside, so the notification, lock screen, widgets,
// the app and a car keep one player throughout. The sleep timer and the
// queue edits the app offers work on whichever is in use.
@OptIn(UnstableApi::class)
class OutputSwitch(private val local: OctoPlayer) : ForwardingSimpleBasePlayer(local), SleepTarget, EditableQueue {
    var remote: RemotePlayer? = null
        private set

    val isRemote: Boolean get() = remote != null

    private val active: EditableQueue get() = remote ?: local

    // Music moves to another device.
    fun useRemote(player: RemotePlayer) {
        remote = player
        player.pauseAtEndOfSong = pauseAtEnd
        setPlayer(player)
    }

    // Music comes back to the phone.
    fun useLocal() {
        remote = null
        setPlayer(local)
    }

    // The crossfade length in use: none while casting.
    val crossfadeMs: Long get() = if (isRemote) 0 else local.crossfadeMs

    // The sleep timer's fade is the phone's alone; a device keeps its volume.
    override var sleepFade: Float
        get() = local.sleepFade
        set(value) {
            local.sleepFade = value
        }

    private var pauseAtEnd = false

    override var pauseAtEndOfSong: Boolean
        get() = pauseAtEnd
        set(value) {
            pauseAtEnd = value
            local.pauseAtEndOfSong = value
            remote?.pauseAtEndOfSong = value
        }

    override val currentKey: String? get() = currentMediaItem?.entryId

    override val isBlending: Boolean get() = !isRemote && local.isBlending

    override fun hasEntry(key: String): Boolean = (0 until mediaItemCount).any { getMediaItemAt(it).entryId == key }

    override fun addNext(items: List<MediaItem>) = active.addNext(items)

    override fun setPlayOrder(order: IntArray) = active.setPlayOrder(order)

    override fun putBack(runs: List<Pair<Int, List<MediaItem>>>, order: IntArray) = active.putBack(runs, order)

    override fun removeRuns(runs: List<IntRange>) = active.removeRuns(runs)

    // While a station plays, the session hears it is live with no length,
    // offers no seeking, and offers Back and Next only toward stations of
    // its lineup that are there.
    override fun getState(): State {
        val state = super.getState()
        val lineup = liveLineupOf(state.timeline, state.currentMediaItemIndex) ?: return state
        return state.buildUpon()
            .setAvailableCommands(commandsOf(liveCommands(state.availableCommands.toIds(), lineup)))
            .setPlaylist(LiveTimeline(state.timeline), state.currentTracks, state.currentMetadata)
            .build()
    }

    // Back and Next step through a station's lineup in its order, whatever
    // the shuffle and repeat settings say for songs; nothing seeks within a
    // station.
    override fun handleSeek(mediaItemIndex: Int, positionMs: Long, seekCommand: Int): ListenableFuture<*> {
        val lineup = playing.liveLineupNow() ?: return super.handleSeek(mediaItemIndex, positionMs, seekCommand)
        if (seekCommand == Player.COMMAND_SEEK_TO_DEFAULT_POSITION) return super.handleSeek(mediaItemIndex, positionMs, seekCommand)
        liveSeekTarget(seekCommand, mediaItemIndex, lineup)?.let { playing.seekToDefaultPosition(it) }
        return Futures.immediateVoidFuture()
    }

    // The player in use, the phone's or the device's.
    private val playing: Player get() = remote ?: local

    // Both go when the service does.
    override fun handleRelease(): ListenableFuture<*> {
        remote?.release()
        remote = null
        local.release()
        return Futures.immediateVoidFuture()
    }
}
