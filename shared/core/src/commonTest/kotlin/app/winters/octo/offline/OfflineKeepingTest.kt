package app.winters.octo.offline

import org.junit.Assert.assertEquals
import org.junit.Test

// What to keep on a device and why, what to fetch and let go, and where
// kept files go.
class OfflineKeepingTest {
    @Test
    fun aSongIsKeptWhileAnyReasonIs() {
        val choices = KeepChoices(byHand = listOf("a"), liked = true, playlists = listOf("p1"))
        val wanted = wantedCopies(choices, liked = listOf("a", "b"), playlists = mapOf("p1" to listOf("b", "c"), "p2" to listOf("d")))
        assertEquals(setOf(KeepReason.BY_HAND, KeepReason.LIKED), wanted["a"])
        assertEquals(setOf(KeepReason.LIKED, KeepReason.playlist("p1")), wanted["b"])
        assertEquals(setOf("a", "b", "c"), wanted.keys)
        // Liked songs not kept: only the rest.
        assertEquals(setOf("a", "c", "b"), wantedCopies(choices.copy(liked = false), listOf("x"), mapOf("p1" to listOf("b", "c"))).keys)
    }

    @Test
    fun thePlanFetchesWhatIsMissingAndLetsGoTheRest() {
        val plan = keepPlan(mapOf("a" to setOf("manual"), "b" to setOf("liked")), kept = setOf("b", "z", "y"), unsure = setOf("y"))
        assertEquals(listOf("a"), plan.fetch)
        // y's playlist could not be read, so it stays.
        assertEquals(listOf("z"), plan.remove)
    }

    @Test
    fun keptFilesHaveNamesEverySystemTakes() {
        assertEquals("Massive Attack/Mezzanine/01 Angel.flac", keptPath("Massive Attack", "Mezzanine", 1, "Angel", "FLAC"))
        assertEquals("AC_DC/Back In Black_/Hells Bells.audio", keptPath("AC/DC", "Back In Black?", null, "Hells Bells", null))
        assertEquals("_con", fileSafe("con"))
        assertEquals("_", fileSafe("..."))
        assertEquals(80, fileSafe("x".repeat(200)).length)
        assertEquals("312 songs, 1.9 GB", keptLine(312, 1_900_000_000))
        assertEquals("1 song, 8 MB", keptLine(1, 8_000_000))
    }

    @Test
    fun aCopyOfTheFileTheServerHasStays() {
        assertEquals(KeptCopyCheck.Keep, checkKeptCopy(keptFor = 31_000_000, serverSize = 31_000_000, copySize = 9_000_000, asIs = false))
    }

    @Test
    fun aCopyOfAFileTheServerSwappedIsFetchedAgain() {
        // The same id, a new file: a live take swapped for the studio one.
        assertEquals(KeptCopyCheck.Refetch, checkKeptCopy(keptFor = 31_000_000, serverSize = 28_500_000, copySize = 31_000_000, asIs = true))
        assertEquals(KeptCopyCheck.Refetch, checkKeptCopy(keptFor = 31_000_000, serverSize = 28_500_000, copySize = 9_000_000, asIs = false))
    }

    @Test
    fun anOlderCopyOfTheFileAsItIsIsCheckedByItsOwnSize() {
        assertEquals(KeptCopyCheck.Note, checkKeptCopy(keptFor = null, serverSize = 31_000_000, copySize = 31_000_000, asIs = true))
        assertEquals(KeptCopyCheck.Refetch, checkKeptCopy(keptFor = null, serverSize = 28_500_000, copySize = 31_000_000, asIs = true))
        // A copy cut short never matches.
        assertEquals(KeptCopyCheck.Refetch, checkKeptCopy(keptFor = null, serverSize = 28_500_000, copySize = -1, asIs = true))
    }

    @Test
    fun anOlderSmallerCopyIsTakenAsItIs() {
        // A smaller copy's size says nothing about the file it came from.
        assertEquals(KeptCopyCheck.Note, checkKeptCopy(keptFor = null, serverSize = 31_000_000, copySize = 7_000_000, asIs = false))
    }

    @Test
    fun aSongWithNoSizeKeepsItsCopy() {
        assertEquals(KeptCopyCheck.Keep, checkKeptCopy(keptFor = 31_000_000, serverSize = null, copySize = 31_000_000, asIs = true))
        assertEquals(KeptCopyCheck.Keep, checkKeptCopy(keptFor = null, serverSize = 0, copySize = 5, asIs = true))
        // A noted size of nothing counts as none noted.
        assertEquals(KeptCopyCheck.Note, checkKeptCopy(keptFor = 0, serverSize = 31_000_000, copySize = 31_000_000, asIs = true))
    }
}
