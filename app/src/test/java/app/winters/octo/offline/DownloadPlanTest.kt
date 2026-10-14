package app.winters.octo.offline

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class DownloadPlanTest {
    private fun done(format: String?, sizeBytes: Long, fileSize: Long?, serverSize: Long?, serverType: String? = "audio/flac") =
        DownloadedFile("server:a", "tr-1", format, sizeBytes, fileSize, serverSize, serverType)

    @Test
    fun aDownloadOfASwappedFileDownloadsAgain() {
        assertEquals(KeptCopyCheck.Keep, checkDownload(done("audio/flac", 31_000_000, 31_000_000, 31_000_000)))
        assertEquals(KeptCopyCheck.Refetch, checkDownload(done("audio/flac", 31_000_000, 31_000_000, 28_500_000)))
        assertEquals(KeptCopyCheck.Refetch, checkDownload(done("audio/mpeg", 7_000_000, 31_000_000, 28_500_000)))
    }

    @Test
    fun anOlderDownloadIsCheckedByItsSizeWhenItIsTheFileAsItIs() {
        assertEquals(KeptCopyCheck.Note, checkDownload(done("audio/flac", 31_000_000, null, 31_000_000)))
        assertEquals(KeptCopyCheck.Refetch, checkDownload(done("audio/flac", 31_000_000, null, 28_500_000)))
        // An MP3 may be the file as it is or a smaller copy: nothing tells.
        assertEquals(KeptCopyCheck.Note, checkDownload(done("audio/mpeg", 7_000_000, null, 9_000_000, serverType = "audio/mpeg")))
        assertEquals(KeptCopyCheck.Note, checkDownload(done("audio/mpeg", 7_000_000, null, 31_000_000)))
        // A server song with no size keeps its download.
        assertEquals(KeptCopyCheck.Keep, checkDownload(done("audio/flac", 31_000_000, null, null)))
    }

    private val manual = Reasons.MANUAL
    private val liked = Reasons.LIKED
    private val gym = Reasons.playlist("gym")
    private val road = Reasons.playlist("road")

    @Test
    fun theRulesWantLikedSongsOnlyWhileLikedSongsAreKept() {
        val members = listOf(PlaylistMember("gym", "a"), PlaylistMember("gym", "b"), PlaylistMember("road", "b"))
        assertEquals(
            mapOf("a" to setOf(liked, gym), "b" to setOf(gym, road), "c" to setOf(liked)),
            wantedByRules(keepLiked = true, liked = listOf("a", "c"), playlistSongs = members),
        )
        assertEquals(
            mapOf("a" to setOf(gym), "b" to setOf(gym, road)),
            wantedByRules(keepLiked = false, liked = listOf("a", "c"), playlistSongs = members),
        )
    }

    @Test
    fun newSongsDownloadOnlyWhenTheyCanBe() {
        val plan = planDownloads(
            held = emptyMap(),
            wanted = mapOf("a" to setOf(liked), "b" to setOf(liked), "find:x" to setOf(gym)),
            downloadable = setOf("a"),
        )
        assertEquals(mapOf("a" to setOf(liked)), plan.add)
        assertTrue(plan.change.isEmpty() && plan.remove.isEmpty())
    }

    @Test
    fun aDownloadAskedForByHandStaysWhenNoRuleWantsIt() {
        val plan = planDownloads(held = mapOf("a" to setOf(manual)), wanted = emptyMap(), downloadable = setOf("a"))
        assertTrue(plan.isEmpty)
    }

    @Test
    fun switchingARuleOffLetsGoOfWhatOnlyItHeld() {
        val held = mapOf("a" to setOf(liked), "b" to setOf(liked, manual), "c" to setOf(liked, gym))
        val plan = planDownloads(held, wanted = mapOf("c" to setOf(gym)), downloadable = emptySet())
        assertEquals(setOf("a"), plan.remove)
        assertEquals(mapOf("b" to setOf(manual), "c" to setOf(gym)), plan.change)
        assertTrue(plan.add.isEmpty())
    }

    @Test
    fun aSongTakenOutOfAPlaylistGoesUnlessSomethingElseHoldsIt() {
        val held = mapOf("a" to setOf(gym), "b" to setOf(gym, road))
        val plan = planDownloads(held, wanted = mapOf("b" to setOf(road)), downloadable = setOf("a", "b"))
        assertEquals(setOf("a"), plan.remove)
        assertEquals(mapOf("b" to setOf(road)), plan.change)
    }

    @Test
    fun aSongMissingFromTheLibraryForAMomentIsNotDeleted() {
        // During a sync the song is briefly not downloadable, but the playlist still has it.
        val plan = planDownloads(held = mapOf("a" to setOf(gym)), wanted = mapOf("a" to setOf(gym)), downloadable = emptySet())
        assertTrue(plan.isEmpty)
    }

    @Test
    fun aHeldSongGainsANewRuleWithoutDownloadingAgain() {
        val plan = planDownloads(held = mapOf("a" to setOf(manual)), wanted = mapOf("a" to setOf(liked)), downloadable = setOf("a"))
        assertEquals(mapOf("a" to setOf(manual, liked)), plan.change)
        assertTrue(plan.add.isEmpty() && plan.remove.isEmpty())
    }

    @Test
    fun reasonsSurviveTheirColumn() {
        val reasons = setOf(manual, liked, gym)
        assertEquals(reasons, Reasons.parse(Reasons.join(reasons)))
        assertEquals(emptySet<String>(), Reasons.parse(""))
        assertEquals("gym", Reasons.playlistOf(gym))
        assertEquals(null, Reasons.playlistOf(liked))
    }
}
