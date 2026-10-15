package app.winters.octo.cast

import app.winters.octo.output.RemoteMedia
import app.winters.octo.output.RemoteState
import com.google.android.gms.cast.MediaQueueItem
import com.google.android.gms.cast.MediaStatus

// What the receiver's media status says about its player and its queue.
internal data class CastQueueStatus(
    val playerState: Int,
    val idleReason: Int,
    val currentItemId: Int,
    val loadingItemId: Int,
    val itemIds: List<Int>,
) {
    // Going on by itself to the item it is loading: the item before ended or
    // was skipped on the receiver, and it still names that one as current
    // until the new one starts.
    val movingOn: Boolean
        get() = playerState == MediaStatus.PLAYER_STATE_IDLE &&
            loadingItemId != MediaQueueItem.INVALID_ITEM_ID &&
            (idleReason == MediaStatus.IDLE_REASON_FINISHED || idleReason == MediaStatus.IDLE_REASON_INTERRUPTED)

    // The item the receiver is on: the one it is loading while it goes on to
    // it, otherwise the current one.
    val onItemId: Int
        get() = loadingItemId.takeIf { it != MediaQueueItem.INVALID_ITEM_ID } ?: currentItemId

    // The items queued after the one it is on.
    val later: List<Int>
        get() = itemIds.dropWhile { it != onItemId }.drop(1)

    // The song could not be played.
    val failed: Boolean
        get() = playerState == MediaStatus.PLAYER_STATE_IDLE && idleReason == MediaStatus.IDLE_REASON_ERROR

    // What the receiver is doing, or null when it is a failure or a state
    // nothing is done about.
    val state: RemoteState?
        get() = when (playerState) {
            MediaStatus.PLAYER_STATE_PLAYING -> RemoteState.Playing
            MediaStatus.PLAYER_STATE_PAUSED -> RemoteState.Paused
            MediaStatus.PLAYER_STATE_BUFFERING, MediaStatus.PLAYER_STATE_LOADING -> RemoteState.Loading
            MediaStatus.PLAYER_STATE_IDLE -> when {
                failed -> null
                movingOn -> RemoteState.Loading
                idleReason == MediaStatus.IDLE_REASON_FINISHED -> RemoteState.Ended
                else -> RemoteState.Idle
            }
            else -> null
        }
}

internal fun MediaStatus.forQueue() = CastQueueStatus(
    playerState = playerState,
    idleReason = idleReason,
    currentItemId = currentItemId,
    loadingItemId = loadingItemId,
    itemIds = queueItems.map { it.itemId },
)

// The part of the receiver's media client the next song is kept through.
internal interface CastQueueClient {
    val status: CastQueueStatus?

    fun removeItems(itemIds: IntArray)

    fun append(media: RemoteMedia)
}

// Replaces whatever is queued after the item the receiver is on with
// `next`. The item it is playing or loading is never removed, since that
// ends its media session.
internal fun CastQueueClient.setNext(next: RemoteMedia?) {
    val status = status ?: return
    val later = status.later
    if (later.isNotEmpty()) removeItems(later.toIntArray())
    next?.let(::append)
}
