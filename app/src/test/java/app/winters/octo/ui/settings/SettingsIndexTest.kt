package app.winters.octo.ui.settings

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

// The long dash, which the app's words never use.
private val EM_DASH = Char(0x2014)

class SettingsIndexTest {
    private fun titles(query: String, entries: List<SettingEntry> = SettingsIndex.all) = searchSettings(query, entries).map { it.title }

    @Test
    fun everySettingHasItsOwnIdAndATitle() {
        val ids = SettingsIndex.all.map { it.id }
        assertEquals(ids.size, ids.toSet().size)
        assertTrue(SettingsIndex.all.all { it.title.isNotBlank() })
        assertEquals(SettingsIndex.Crossfade, SettingsIndex.byId("crossfade"))
    }

    @Test
    fun everyPageHasSettings() {
        SettingsPage.entries.forEach { page -> assertTrue("$page is empty", SettingsIndex.all.any { it.page == page }) }
    }

    @Test
    fun noEmDashesInWhatPeopleRead() {
        SettingsIndex.all.forEach { entry ->
            (listOf(entry.title, entry.summary, entry.place) + entry.keywords).forEach { assertTrue(it, EM_DASH !in it) }
        }
    }

    @Test
    fun nothingTypedFindsNothing() {
        assertEquals(emptyList<String>(), titles(""))
        assertEquals(emptyList<String>(), titles("   "))
    }

    @Test
    fun theTitleComesFirst() {
        assertEquals(listOf("Crossfade", "Longest blend"), titles("crossfade").take(2))
        assertEquals("Crossfade", titles("CROSS").first())
    }

    @Test
    fun otherWordsFindASetting() {
        assertEquals("Crossfade", titles("gapless").first())
        assertEquals("Speed", titles("semitones").first())
        assertTrue("Speed" in titles("tempo"))
        assertTrue("Loudness" in titles("replaygain"))
    }

    @Test
    fun punctuationAndAccentsDoNotMatter() {
        assertTrue("Streaming on Wi-Fi" in titles("wifi"))
        assertTrue("What's new" in titles("whats new"))
        assertTrue("What's new" in titles("Whät's"))
    }

    @Test
    fun everyWordMustBeFound() {
        // Both words in the title first, then "mobile" with the page's name.
        assertEquals(
            listOf("Streaming on mobile data", "Fetch ahead on mobile data", "Download on Wi-Fi only"),
            titles("streaming mobile"),
        )
        assertEquals(emptyList<String>(), titles("crossfade bluetooth"))
    }

    @Test
    fun shortWordsOnlyMatchTheStartOfAWord() {
        // "eq" starts "equalizer" but sits inside no other word's start.
        assertEquals("Equalizer", titles("eq").first())
        assertTrue(titles("ss").isEmpty())
    }

    @Test
    fun homeSectionsAreFoundByWhatTheyDo() {
        assertEquals("Home sections", titles("rearrange").first())
        assertEquals("Home sections", titles("edit home").first())
        assertEquals("Appearance · Home", SettingsIndex.HomeSections.place)
    }

    @Test
    fun aResultSaysWhereItLives() {
        assertEquals("Appearance · Where it shows", SettingsIndex.AmbientHome.place)
        assertEquals("Lyrics", SettingsIndex.LyricsOnline.place)
    }

    @Test
    fun titlesRankAboveOtherWordsAboveTheSummary() {
        val entries = listOf(
            SettingEntry("summary", SettingsPage.Lyrics, "Other", summary = "screen stuff"),
            SettingEntry("keyword", SettingsPage.Lyrics, "Keep awake", keywords = listOf("screen")),
            SettingEntry("inside", SettingsPage.Lyrics, "Full screen mode"),
            SettingEntry("start", SettingsPage.Lyrics, "Screen"),
            SettingEntry("none", SettingsPage.Lyrics, "Nothing", summary = "at all"),
        )
        assertEquals(listOf("start", "inside", "keyword", "summary"), searchSettings("screen", entries).map { it.id })
    }

    @Test
    fun wordsCanBeSpreadOverTitleAndOtherWords() {
        val entries = listOf(
            SettingEntry("spread", SettingsPage.Playback, "Resume", keywords = listOf("bluetooth")),
            SettingEntry("title", SettingsPage.Playback, "Resume on bluetooth"),
        )
        assertEquals(listOf("title", "spread"), searchSettings("resume bluetooth", entries).map { it.id })
        // The page's name counts as another word; both rank the same, so
        // they keep the order they are written in.
        assertEquals(listOf("spread", "title"), searchSettings("playback resume", entries).map { it.id })
    }
}
