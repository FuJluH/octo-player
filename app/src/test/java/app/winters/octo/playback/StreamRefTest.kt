package app.winters.octo.playback

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class StreamRefTest {
    private val flac = StreamRef("server:music.example", "tr-42", "audio/flac", 900_000)
    private val mp3 = StreamRef("server:music.example", "tr-7", "audio/mpeg", 256_000)

    @Test
    fun aSongReadsBackAsItWasWritten() {
        assertEquals(flac, parseStreamUri(streamUri(flac)))
        val pinned = flac.pin(StreamRequest(192))
        assertEquals(pinned, parseStreamUri(streamUri(pinned)))
        val raw = flac.pin(StreamRequest(null))
        assertEquals(raw, parseStreamUri(streamUri(raw)))
    }

    @Test
    fun theFileSizeReadsBackToo() {
        val sized = flac.copy(size = 31_000_000)
        assertEquals(sized, parseStreamUri(streamUri(sized)))
        val pinned = sized.pin(StreamRequest(192))
        assertEquals(pinned, parseStreamUri(streamUri(pinned)))
        // An address from before sizes were carried has none.
        assertNull(parseStreamUri("octo-stream://song/tr-42?source=server%3Aa&mime=audio%2Fflac")!!.size)
    }

    @Test
    fun oddIdsAndServersSurviveTheAddress() {
        val odd = StreamRef("server:host:4533", "a/b c+d&e=f", "audio/x-flac", null)
        assertEquals(odd, parseStreamUri(streamUri(odd)))
        val bare = StreamRef(null, "123", null, null)
        assertEquals(bare, parseStreamUri(streamUri(bare)))
    }

    @Test
    fun anythingElseIsNotAServerSong() {
        assertNull(parseStreamUri("content://media/external/audio/media/12"))
        assertNull(parseStreamUri("file:///storage/Music/Octo/song.flac"))
        assertNull(parseStreamUri("https://music.example/rest/stream?id=1"))
        assertNull(parseStreamUri("octo-stream://album/1"))
        assertNull(parseStreamUri("not a uri at all"))
    }

    @Test
    fun theKeyNamesTheSongNeverTheSignedAddress() {
        val key = streamCacheKey("server:music.example", flac, StreamRequest(null))
        assertEquals("server:music.example|tr-42|audio/flac|raw", key)
        assertEquals("server:music.example|tr-42|audio/flac|192", streamCacheKey("server:music.example", flac, StreamRequest(192)))
        // Nothing random goes in, so the same song always finds its saved copy.
        assertEquals(key, streamCacheKey("server:music.example", parseStreamUri(streamUri(flac))!!, StreamRequest(null)))
        assertFalse(key.contains("salt") || key.contains("token") || key.contains("http"))
    }

    @Test
    fun eachServerTypeAndRequestIsItsOwnCopy() {
        val raw = StreamRequest(null)
        val base = streamCacheKey("server:a", flac, raw)
        assertNotEquals(base, streamCacheKey("server:b", flac, raw))
        assertNotEquals(base, streamCacheKey("server:a", flac.copy(mimeType = "audio/mpeg"), raw))
        assertNotEquals(base, streamCacheKey("server:a", flac, StreamRequest(320)))
        assertNotEquals(base, streamCacheKey("server:a", flac.copy(serverId = "tr-43"), raw))
    }

    @Test
    fun aNewFileUnderTheSameIdIsItsOwnCopy() {
        val raw = StreamRequest(null)
        val live = streamCacheKey("server:a", flac.copy(size = 31_000_000), raw)
        val studio = streamCacheKey("server:a", flac.copy(size = 28_500_000), raw)
        assertEquals("server:a|tr-42|audio/flac|raw|31000000", live)
        assertNotEquals(live, studio)
        // A song with no size, such as one found online, keeps the plain name.
        assertEquals("server:a|tr-42|audio/flac|raw", streamCacheKey("server:a", flac, raw))
    }

    @Test
    fun aKeyLosesItsSizeOnlyWhenItHasOne() {
        assertEquals("server:a|tr-42|audio/flac|raw", cacheKeyWithoutSize("server:a|tr-42|audio/flac|raw|31000000"))
        assertEquals("server:a|tr-42|audio/flac|192", cacheKeyWithoutSize("server:a|tr-42|audio/flac|192|31000000"))
        assertEquals("server:a|tr-42|audio/flac|192", cacheKeyWithoutSize("server:a|tr-42|audio/flac|192"))
        assertEquals("server:a|tr-42|unknown|raw", cacheKeyWithoutSize("server:a|tr-42|unknown|raw"))
    }

    // Saved copies in memory: each name with its whole length, and any noted size.
    private class Saved(vararg copies: Pair<String, Long>) : SavedCopies {
        val lengths = mutableMapOf(*copies)
        val noted = mutableMapOf<String, Long>()
        val dropped = mutableListOf<String>()

        override fun has(key: String) = key in lengths

        override fun length(key: String) = lengths[key] ?: -1L

        override fun notedSize(key: String) = noted[key]

        override fun note(key: String, size: Long) {
            noted[key] = size
        }

        override fun drop(key: String) {
            lengths.remove(key)
            noted.remove(key)
            dropped += key
        }
    }

    @Test
    fun aCopyUnderTheFullNameIsUsed() {
        val ref = flac.copy(size = 28_500_000)
        val full = streamCacheKey("server:a", ref, StreamRequest(null))
        val saved = Saved(full to 28_500_000)
        assertEquals(full, savedCopyKey("server:a", ref, StreamRequest(null), saved))
        assertTrue(saved.dropped.isEmpty())
    }

    @Test
    fun anOlderCopyOfTheSameFileStillPlays() {
        val ref = flac.copy(size = 31_000_000)
        val older = streamCacheKey("server:a", flac, StreamRequest(null))
        val saved = Saved(older to 31_000_000)
        assertEquals(older, savedCopyKey("server:a", ref, StreamRequest(null), saved))
        assertEquals(31_000_000L, saved.noted[older])
        assertTrue(saved.dropped.isEmpty())
    }

    @Test
    fun anOlderCopyOfAnotherFileIsLetGoAndTheNewFileLoads() {
        // The live take was saved; the server now has the studio one under the same id.
        val ref = flac.copy(size = 28_500_000)
        val older = streamCacheKey("server:a", flac, StreamRequest(null))
        val saved = Saved(older to 31_000_000)
        assertEquals(streamCacheKey("server:a", ref, StreamRequest(null)), savedCopyKey("server:a", ref, StreamRequest(null), saved))
        assertEquals(listOf(older), saved.dropped)
    }

    @Test
    fun anOlderSmallerCopyIsKeptUntilItsFileChanges() {
        val small = StreamRequest(192)
        val older = streamCacheKey("server:a", flac, small)
        val saved = Saved(older to 7_000_000)
        // Nothing tells which file it came from, so it plays, and the size is noted.
        assertEquals(older, savedCopyKey("server:a", flac.copy(size = 31_000_000), small, saved))
        assertEquals(31_000_000L, saved.noted[older])
        assertEquals(older, savedCopyKey("server:a", flac.copy(size = 31_000_000), small, saved))
        // Then the file is swapped: the noted size no longer matches.
        val swapped = flac.copy(size = 28_500_000)
        assertEquals(streamCacheKey("server:a", swapped, small), savedCopyKey("server:a", swapped, small, saved))
        assertEquals(listOf(older), saved.dropped)
    }

    @Test
    fun aSongWithNoSizeUsesThePlainName() {
        val plain = streamCacheKey("server:a", flac, StreamRequest(null))
        val saved = Saved(plain to 5)
        assertEquals(plain, savedCopyKey("server:a", flac, StreamRequest(null), saved))
        assertTrue(saved.dropped.isEmpty() && saved.noted.isEmpty())
    }

    @Test
    fun choosingASizeLooksUnderTheNamesTheSavedCopiesHave() {
        // A whole copy of the file as it is, saved before names carried sizes, still wins over streaming 128.
        val ref = flac.copy(size = 31_000_000)
        val older = streamCacheKey("server:a", flac, StreamRequest(null))
        val saved = Saved(older to 31_000_000)
        val picked = chooseRequest("server:a", ref, StreamQuality.Kbps128, fullySaved = { saved.has(it) }) {
            savedCopyKey("server:a", ref, it, saved)
        }
        assertEquals(StreamRequest(null), picked)
        // Once the file is swapped, the old copy is not picked.
        val swapped = flac.copy(size = 28_500_000)
        val again = chooseRequest("server:a", swapped, StreamQuality.Kbps128, fullySaved = { saved.has(it) }) {
            savedCopyKey("server:a", swapped, it, saved)
        }
        assertEquals(StreamRequest(128), again)
    }

    @Test
    fun variantsRunFromTheFileAsItIsDownToTheSmallestMp3() {
        assertEquals(
            listOf(StreamRequest(null), StreamRequest(320), StreamRequest(256), StreamRequest(192), StreamRequest(128)),
            requestVariants(flac),
        )
        // A 256 kbps MP3 plays as it is at 256 and above.
        assertEquals(listOf(StreamRequest(null), StreamRequest(192), StreamRequest(128)), requestVariants(mp3))
    }

    @Test
    fun theConnectionsSizeIsAskedForWhenNothingIsSaved() {
        assertEquals(StreamRequest(192), chooseRequest("server:a", flac, StreamQuality.Kbps192, fullySaved = { false }))
        assertEquals(StreamRequest(null), chooseRequest("server:a", flac, StreamQuality.Original, fullySaved = { false }))
    }

    @Test
    fun aWholeSavedCopyInAnotherSizePlaysInstead() {
        val saved = setOf(streamCacheKey("server:a", flac, StreamRequest(null)))
        assertEquals(StreamRequest(null), chooseRequest("server:a", flac, StreamQuality.Kbps128, fullySaved = { it in saved }))
    }

    @Test
    fun theWantedSizeWinsWhenItIsSavedToo() {
        val saved = setOf(
            streamCacheKey("server:a", flac, StreamRequest(null)),
            streamCacheKey("server:a", flac, StreamRequest(128)),
        )
        assertEquals(StreamRequest(128), chooseRequest("server:a", flac, StreamQuality.Kbps128, fullySaved = { it in saved }))
    }

    @Test
    fun aSongStartedInOneSizeKeepsItWhenTheConnectionChanges() {
        val started = setOf(streamCacheKey("server:a", flac, StreamRequest(null)))
        val picked = chooseRequest("server:a", flac, StreamQuality.Kbps192, fullySaved = { false }, partlySaved = { it in started })
        assertEquals(StreamRequest(null), picked)
    }

    @Test
    fun aPinnedRequestIsNeverChanged() {
        val pinned = flac.pin(StreamRequest(256))
        assertEquals(StreamRequest(256), chooseRequest("server:a", pinned, StreamQuality.Original, fullySaved = { true }))
        assertEquals(StreamRequest(256), pinned.request(StreamQuality.Original))
        assertTrue(flac.request(StreamQuality.Kbps128) == StreamRequest(128))
    }
}
