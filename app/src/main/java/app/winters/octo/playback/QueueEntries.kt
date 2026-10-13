package app.winters.octo.playback

import android.os.Bundle
import androidx.media3.common.MediaItem

// Each song in the queue carries its own entry id, given by the player as
// it goes in. The same song queued twice is two entries, and a list can
// point at one entry even while songs around it come and go.
const val EXTRA_QUEUE_ENTRY = "app.winters.octo.queueEntry"

// A song Autoplay added once the listener's own queue ran out.
const val EXTRA_AUTOPLAY = "app.winters.octo.autoplay"

// Where a song came from (QueueSource.encoded): the listener's own pick
// or the list it was played from, for the queue's headings. A song
// playTracks asks for carries it in its request, and the service puts it
// on the song.
const val EXTRA_SOURCE = "app.winters.octo.source"

val MediaItem.entryId: String? get() = mediaMetadata.extras?.getString(EXTRA_QUEUE_ENTRY)

val MediaItem.isAutoplay: Boolean get() = mediaMetadata.extras?.getBoolean(EXTRA_AUTOPLAY, false) == true

// Where the song came from; Autoplay's own are marked apart.
val MediaItem.queueSource: QueueSource
    get() = if (isAutoplay) QueueSource.Autoplay else queueSourceOf(mediaMetadata.extras?.getString(EXTRA_SOURCE))

// The source a request from the app names, if any.
val MediaItem.requestedSource: String? get() = requestMetadata.extras?.getString(EXTRA_SOURCE)

fun MediaItem.withEntry(id: String): MediaItem = withExtras { putString(EXTRA_QUEUE_ENTRY, id) }

fun MediaItem.markedAutoplay(): MediaItem = withExtras { putBoolean(EXTRA_AUTOPLAY, true) }

fun MediaItem.withSource(source: QueueSource): MediaItem = withSource(source.encoded())

fun MediaItem.withSource(word: String): MediaItem = withExtras { putString(EXTRA_SOURCE, word) }

// A saved song with the source it was saved with; Autoplay's are marked so
// again. With no word saved, it is left as it is.
fun withSavedSource(item: MediaItem, word: String?): MediaItem = when {
    word.isNullOrEmpty() -> item
    queueSourceOf(word) == QueueSource.Autoplay -> item.markedAutoplay()
    else -> item.withSource(word)
}

// The same song with its extras changed, keeping everything else.
private fun MediaItem.withExtras(change: Bundle.() -> Unit): MediaItem {
    val extras = Bundle(mediaMetadata.extras ?: Bundle.EMPTY).apply(change)
    return buildUpon().setMediaMetadata(mediaMetadata.buildUpon().setExtras(extras).build()).build()
}
