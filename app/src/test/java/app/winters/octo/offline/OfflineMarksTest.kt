package app.winters.octo.offline

import app.winters.octo.catalog.TrackEntity
import app.winters.octo.playback.StreamRef
import app.winters.octo.playback.StreamRequest
import app.winters.octo.playback.streamCacheKey
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class OfflineMarksTest {
    private fun track(id: String, onPhone: Boolean, nativeId: String = id) = TrackEntity(
        id = id, sourceId = "server:music.example", nativeId = nativeId, title = "", searchKey = "", sortKey = "",
        artist = "", artistId = "", album = "", albumId = "", trackNo = null, discNo = null, year = null, durationMs = 0,
        addedAt = 0, mimeType = "audio/flac", sizeBytes = null, artwork = null, uri = null, onPhone = onPhone,
    )

    @Test
    fun aSavedKeyNamesItsSong() {
        val key = streamCacheKey("server:music.example", StreamRef(null, "tr-1", "audio/flac", null), StreamRequest(192))
        assertEquals(savedSong("server:music.example", "tr-1"), savedSongOf(key))
        val sized = StreamRef(null, "tr-1", "audio/flac", null, size = 31_000_000)
        assertEquals(savedSong("server:music.example", "tr-1"), savedSongOf(streamCacheKey("server:music.example", sized, StreamRequest(null))))
        assertEquals(savedSong("server:music.example", "tr-1"), savedSongOf(streamCacheKey("server:music.example", sized, StreamRequest(192))))
    }

    @Test
    fun withNoConnectionOnlySongsThatCannotPlayAreFaint() {
        val marks = OfflineMarks(
            downloaded = setOf("down"),
            offline = true,
            saved = setOf(savedSong("server:music.example", "cached")),
        )
        assertFalse(marks.isOutOfReach(track("phone", onPhone = true)))
        assertFalse(marks.isOutOfReach(track("down", onPhone = false)))
        assertFalse(marks.isOutOfReach(track("x", onPhone = false, nativeId = "cached")))
        assertTrue(marks.isOutOfReach(track("stream", onPhone = false)))
        // With a connection, everything can play.
        assertFalse(marks.copy(offline = false).isOutOfReach(track("stream", onPhone = false)))
    }
}
