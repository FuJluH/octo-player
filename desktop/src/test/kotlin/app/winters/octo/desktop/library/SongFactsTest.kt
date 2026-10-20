package app.winters.octo.desktop.library

import app.winters.octo.desktop.player.SongFormat
import app.winters.octo.subsonic.Song
import app.winters.octo.subsonic.SongReplayGain
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Test
import java.time.ZoneOffset
import java.util.Locale

class SongFactsTest {
    private val flac = Song(
        "s1", "Karma Police", artist = "Radiohead", album = "OK Computer", suffix = "flac", bitDepth = 24, samplingRate = 96_000,
        size = 48_000_000, playCount = 1234, bpm = 75, explicitStatus = "clean", isrc = listOf("GBAYE9700001"),
        replayGain = SongReplayGain(trackGain = -7.4f, trackPeak = 0.998f),
    )

    private fun facts(song: Song) = songFacts(song, "Your server (Octo)", ZoneOffset.UTC, Locale.UK).associate { it.label to it.value }

    @Test
    fun whatIsKnownIsListedInThePhonesWords() {
        val f = facts(flac)
        assertEquals("FLAC, lossless", f["Format"])
        assertEquals("96 kHz", f["Sample rate"])
        assertEquals("24-bit", f["Bit depth"])
        assertEquals("45.8 MB", f["File size"])
        assertEquals("1,234", f["Plays"])
        assertEquals("Clean", f["Lyrics"])
        assertEquals("-7.4 dB", f["Track gain"])
        assertEquals("GBAYE9700001", f["ISRC"])
        assertEquals("Your server (Octo)", f["Source"])
    }

    @Test
    fun whatIsNotKnownIsLeftOut() {
        val f = facts(Song("s2", "Bare"))
        assertFalse("Format" in f)
        assertFalse("Rating" in f)
        assertEquals("0", f["Plays"])
    }

    @Test
    fun aFileOnThisComputerSaysSo() {
        assertEquals("A file on this computer", facts(Song("file:abc", "Local"))["Source"])
    }

    // A song Octo found online, as it sends one: how it streams, no file.
    private val online = Song(
        "mXFKjv7oqx1HTOzoJP1nk3", "One Woman (Album Version)", artist = "Randy Rogers Band", suffix = "m4a",
        contentType = "audio/mp4", bitRate = 128, duration = 245, isrc = listOf("USUM70813712"), isExternal = true,
    )

    private fun outsideFacts(song: Song) =
        songFacts(song, "Your server (Octo)", ZoneOffset.UTC, Locale.UK, outside = true).associate { it.label to it.value }

    @Test
    fun aRadioSongSaysWhichSourceSuggestedIt_RightAfterWhereItIs() {
        val labels = songFacts(Song("s1", "Roads", octoSuggestedBy = "Sounds alike"), "Your server (Octo)", ZoneOffset.UTC, Locale.UK)
            .map { it.label }
        assertEquals(labels.indexOf("Source") + 1, labels.indexOf("Suggested by"))
        assertEquals("YouTube Music", outsideFacts(online.copy(octoSuggestedBy = "YouTube Music"))["Suggested by"])
        assertNull(facts(Song("s2", "Bare"))["Suggested by"])
    }

    @Test
    fun aSongFoundOnlineIsNotSaidToBeOnTheServer() {
        val f = outsideFacts(online)
        assertEquals("Found online", f["Source"])
        assertEquals("AAC, 128 kbps", f["Streams as"])
        assertEquals("4:05", f["Length"])
        assertEquals("USUM70813712", f["ISRC"])
        // Nothing that describes a file on the server.
        listOf("Format", "File type", "Bitrate", "Sample rate", "Bit depth", "File size", "Added", "Rating").forEach {
            assertFalse("$it should not show", it in f)
        }
        assertFalse("Plays" in f)
    }

    @Test
    fun aSongFoundOnlineCountsItsPlaysOnceItHasSome() {
        assertEquals("3", outsideFacts(online.copy(playCount = 3))["Plays"])
    }

    @Test
    fun evenFileFactsSentForASongFoundOnlineAreLeftOut() {
        val f = outsideFacts(online.copy(size = 9_000_000, created = "2026-09-28T10:00:00Z", bitDepth = 16, samplingRate = 44_100))
        listOf("File size", "Added", "Bit depth", "Sample rate").forEach { assertFalse("$it should not show", it in f) }
    }

    // A song can arrive as another file than the one listed: the song
    // playing shows the file that opened, not the listing.
    @Test
    fun theSongPlayingShowsTheFileThatOpened() {
        val mp3 = flac.copy(suffix = "mp3", contentType = "audio/mpeg", bitRate = 320, bitDepth = null, samplingRate = 44_100)
        val opened = SongFormat("flac", lossless = true, sampleRate = 48_000, bits = 24, channels = 2)
        val f = songFacts(mp3, "Your server (Octo)", ZoneOffset.UTC, Locale.UK, opened = opened).associate { it.label to it.value }
        assertEquals("FLAC, lossless", f["Format"])
        assertEquals("48 kHz", f["Sample rate"])
        assertEquals("24-bit", f["Bit depth"])
        listOf("Bitrate", "File type", "File size").forEach { assertFalse("$it should not show", it in f) }
        val streams = songFacts(online, "Your server (Octo)", ZoneOffset.UTC, Locale.UK, outside = true, opened = opened)
            .associate { it.label to it.value }
        assertEquals("FLAC, lossless", streams["Streams as"])
    }

    @Test
    fun theListingStaysWhenTheListedFileOpened() {
        val opened = SongFormat("flac", lossless = true, sampleRate = 96_000, bits = 24, channels = 2)
        assertEquals(facts(flac), songFacts(flac, "Your server (Octo)", ZoneOffset.UTC, Locale.UK, opened = opened).associate { it.label to it.value })
        // A file on this computer lists no codec: its facts stay as they are.
        val local = Song("file:abc", "Local", size = 1_000_000)
        assertEquals(facts(local), songFacts(local, "Your server (Octo)", ZoneOffset.UTC, Locale.UK, opened = opened).associate { it.label to it.value })
    }
}
