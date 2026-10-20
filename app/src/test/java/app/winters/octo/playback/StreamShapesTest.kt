package app.winters.octo.playback

import android.net.TestUri
import android.net.Uri
import androidx.annotation.OptIn
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DataSource
import androidx.media3.datasource.DataSpec
import androidx.media3.datasource.TransferListener
import app.winters.octo.output.DEVICE_MP3_KBPS
import app.winters.octo.output.deviceMediaFor
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

// A server can send a song as another file than it listed (a whole FLAC
// for a listed preview): what is held or saved of one file is never
// continued with another's bytes, and the player, the request and a cast
// device go by what the server sends.
@OptIn(UnstableApi::class)
class StreamShapesTest {
    private val song = "octo-stream://song/abc"

    private fun spec(position: Long = 0, key: String? = null): DataSpec =
        DataSpec.Builder().setUri(TestUri(song)).setPosition(position).setKey(key).build()

    // The server: answers each open with the next headers given.
    private class Server(vararg val answers: Map<String, List<String>>) : DataSource {
        var opened = 0
        var closed = 0
        private var now: Map<String, List<String>> = emptyMap()

        override fun addTransferListener(transferListener: TransferListener) = Unit

        override fun open(dataSpec: DataSpec): Long {
            now = answers[minOf(opened, answers.lastIndex)]
            opened++
            return 100
        }

        override fun read(buffer: ByteArray, offset: Int, length: Int): Int = -1

        override fun getUri(): Uri? = null

        override fun getResponseHeaders(): Map<String, List<String>> = now

        override fun close() {
            closed++
        }
    }

    // Saved copies by name, as the phone's store keeps them.
    private class Store : StreamShapes {
        val kept = HashMap<String, StreamShape>()
        val dropped = mutableListOf<String>()

        override fun shape(key: String): StreamShape? = kept[key]

        override fun note(key: String, shape: StreamShape) {
            kept.putIfAbsent(key, shape)
        }

        override fun drop(key: String) {
            kept.remove(key)
            dropped += key
        }
    }

    private val preview = mapOf("content-type" to listOf("audio/mp4"), "content-length" to listOf("4000000"))
    private val previewPart = mapOf("Content-Type" to listOf("audio/mp4"), "Content-Range" to listOf("bytes 1000000-3999999/4000000"))
    private val flacPart = mapOf("Content-Type" to listOf("audio/flac"), "Content-Range" to listOf("bytes 1000000-30999999/31000000"))

    @Test
    fun anAnswerSaysItsTypeAndWholeLength() {
        assertEquals(StreamShape("audio/mp4", 4_000_000), streamShapeOf(preview))
        assertEquals(StreamShape("audio/flac", 31_000_000), streamShapeOf(flacPart))
        // A stream made on the way names no length, and plain bytes name no file.
        assertEquals(StreamShape(null, null), streamShapeOf(mapOf("Content-Type" to listOf("application/octet-stream"))))
        assertNull(streamShapeOf(mapOf("Content-Range" to listOf("bytes 0-99/*"))).total)
    }

    @Test
    fun anotherTypeOrLengthIsAnotherFile() {
        val mp4 = StreamShape("audio/mp4", 4_000_000)
        assertTrue(mp4.differsFrom(StreamShape("audio/flac", 31_000_000)))
        assertTrue(mp4.differsFrom(StreamShape("audio/mp4", 4_100_000)))
        assertFalse(mp4.differsFrom(StreamShape("AUDIO/MP4; charset=binary", 4_000_000)))
        // What one side leaves out is no difference.
        assertFalse(mp4.differsFrom(StreamShape("audio/mp4", null)))
        assertFalse(StreamShape(null, null).differsFrom(StreamShape("audio/flac", 31_000_000)))
    }

    @Test
    fun aSavedPreviewIsNeverContinuedWithAFlac() {
        val store = Store().apply { kept["k"] = StreamShape("audio/mp4", 4_000_000) }
        // The saved copy is the preview; the rest of it now comes as a FLAC.
        val guard = ShapeGuardDataSource(Server(flacPart), { it.scheme == STREAM_SCHEME }, store)
        try {
            guard.open(spec(position = 1_000_000, key = "k"))
            fail("another file must not be read on")
        } catch (e: StreamChanged) {
            assertEquals(listOf("k"), store.dropped)
        }
        // The same file again carries on.
        val same = Store().apply { kept["k"] = StreamShape("audio/mp4", 4_000_000) }
        ShapeGuardDataSource(Server(previewPart), { it.scheme == STREAM_SCHEME }, same).open(spec(position = 1_000_000, key = "k"))
        assertTrue(same.dropped.isEmpty())
    }

    @Test
    fun aReaderNoticesAnotherFileWithNothingSaved() {
        // No saved copies: the reader remembers its first answer.
        val guard = ShapeGuardDataSource(Server(preview, flacPart), { it.scheme == STREAM_SCHEME }, null)
        guard.open(spec())
        guard.close()
        try {
            guard.open(spec(position = 1_000_000))
            fail("another file must not be read on")
        } catch (e: StreamChanged) {
            assertTrue(streamChangedIn(RuntimeException("load failed", e)))
        }
        assertFalse(streamChangedIn(RuntimeException("load failed")))
    }

    @Test
    fun aFirstAnswerIsNotedForTheSavedCopy() {
        val store = Store()
        ShapeGuardDataSource(Server(preview), { it.scheme == STREAM_SCHEME }, store).open(spec(key = "k"))
        assertEquals(StreamShape("audio/mp4", 4_000_000), store.kept["k"])
    }

    @Test
    fun aFindsPlayerItemGoesByTheBytes() {
        assertNull(playerMimeType("audio/mp4", sniffed = true))
        assertEquals("audio/flac", playerMimeType("audio/flac", sniffed = false))
    }

    @Test
    fun aFindAsksWithTheCapLikeALosslessSong() {
        // A find carries no listed bitrate: the preview's 128 kbps would
        // have asked for the file as it is, and a whole FLAC could come.
        val find = StreamRef(sourceId = "server:a", serverId = "x1", mimeType = "audio/mp4", bitrate = null)
        assertEquals(StreamRequest(192), find.request(StreamQuality.Kbps192))
        assertEquals(StreamRequest(null), find.request(StreamQuality.Original))
        assertEquals(StreamRequest(null), find.copy(bitrate = 128_000).request(StreamQuality.Kbps192))
    }

    @Test
    fun aDeviceGetsTheTypeTheServerSends() {
        val playsFlac = { type: String -> type == "audio/flac" || type == "audio/mpeg" || type == "audio/mp4" }
        val playsNoFlac = { type: String -> type != "audio/flac" }
        // Listed as the preview, sent as a FLAC.
        assertEquals(StreamRequest(null) to "audio/flac", deviceMediaFor(StreamRequest(null), "audio/mp4", "audio/flac", playsFlac))
        // A device that does not play FLAC gets an MP3 made on the way.
        assertEquals(StreamRequest(DEVICE_MP3_KBPS) to "audio/mpeg", deviceMediaFor(StreamRequest(null), "audio/mp4", "audio/flac", playsNoFlac))
        // No answer: the listed type. A made MP3 is what it is.
        assertEquals(StreamRequest(null) to "audio/mp4", deviceMediaFor(StreamRequest(null), "audio/mp4", null, playsFlac))
        assertEquals(StreamRequest(320) to "audio/mpeg", deviceMediaFor(StreamRequest(320), "audio/flac", null, playsFlac))
    }
}
