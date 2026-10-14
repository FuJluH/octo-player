package app.winters.octo.player

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

// How the upright player shares its height, at a tall phone and a short
// one, with large text, and the same for a song and a station.
class PlayerRhythmTest {
    // The blocks under the artwork, as they measure at normal text: the
    // song's name with its rating line, the bar with its times, the play
    // controls, the volume and the switches.
    private val blocks = listOf(74f, 72f, 72f, 48f, 44f)
    private val header = 40f

    private fun total(r: PlayerRhythm, blocks: List<Float>): Float =
        header + r.art + r.gaps.sum() + blocks.filterIndexed { i, _ -> r.volume || i != 3 }.sum()

    @Test
    fun aTallPhoneGivesTheArtworkTheFullWidthNearTheTopAndSpreadsTheRest() {
        // 1440x3168 at 3.5: 411 x 905 dp, less the bars and the side margins.
        val r = playerRhythm(height = 833f, width = 363f, header = header, blocks = blocks)
        assertEquals(363f, r.art, 0.01f)
        assertTrue(r.volume)
        // The artwork sits the same short way under the album line.
        assertEquals(RHYTHM_TOP_GAP, r.gaps[0], 0.01f)
        // Everything fills the height exactly; nothing piles at the bottom.
        assertEquals(833f, total(r, blocks), 0.5f)
        assertEquals(7, r.gaps.size)
        assertTrue(r.gaps.last() < r.gaps[1])
        // The room left is shared out, each gap past its least.
        assertTrue(r.gaps.drop(1).zip(listOf(20f, 4f, 4f, 4f, 8f, 16f)).all { (gap, least) -> gap > least })
    }

    @Test
    fun aShortPhoneShrinksTheArtworkFirstAndLeavesOutTheVolume() {
        // 360x640 dp, less the bars and the side margins.
        val r = playerRhythm(height = 568f, width = 312f, header = header, blocks = blocks)
        assertFalse(r.volume)
        assertTrue(r.art in 150f..312f)
        assertEquals(568f, total(r, blocks), 0.5f)
        // Every gap at its least: nothing to spare.
        assertEquals(listOf(8f, 20f, 4f, 4f, 4f, 16f), r.gaps.map { Math.round(it).toFloat() })
    }

    @Test
    fun largeTextStillFitsOnAShortPhone() {
        val large = listOf(110f, 80f, 72f, 48f, 60f)
        val r = playerRhythm(height = 568f, width = 312f, header = 52f, blocks = large)
        assertFalse(r.volume)
        assertTrue(r.art > 0f)
        assertEquals(568f, 52f + r.art + r.gaps.sum() + large.filterIndexed { i, _ -> i != 3 }.sum(), 0.5f)
        // With no room at all the artwork goes before anything overlaps.
        val tiny = playerRhythm(height = 300f, width = 312f, header = 52f, blocks = large)
        assertEquals(0f, tiny.art, 0.01f)
    }

    @Test
    fun aRoomyPhoneKeepsTheVolume() {
        val r = playerRhythm(height = 700f, width = 340f, header = header, blocks = blocks)
        assertTrue(r.volume)
        assertTrue(r.art >= 340f * 0.62f)
        assertEquals(700f, total(r, blocks), 0.5f)
    }

    @Test
    fun aSongAndAStationPutTheArtworkInTheSamePlace() {
        // The live bar takes the scrub bar's room, and a station keeps the
        // rating line, so their blocks measure the same.
        val song = playerRhythm(833f, 363f, header, blocks)
        val station = playerRhythm(833f, 363f, header, blocks.toList())
        assertEquals(song, station)
        // A song with no rating keeps its line too: the same heights again.
        assertEquals(BarRoom.value + TimesRoom.value, 72f, 0.01f)
    }

    @Test
    fun aWideUprightScreenStopsTheArtworkAtTheHeightItHas() {
        val r = playerRhythm(height = 900f, width = 760f, header = header, blocks = blocks)
        assertEquals(900f, total(r, blocks), 0.5f)
        assertTrue(r.art < 760f)
        assertEquals(listOf(8f, 20f, 4f, 4f, 4f, 8f, 16f), r.gaps.map { Math.round(it).toFloat() })
    }
}
