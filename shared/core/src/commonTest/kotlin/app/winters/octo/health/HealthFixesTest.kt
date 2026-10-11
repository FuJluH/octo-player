package app.winters.octo.health

import app.winters.octo.subsonic.ArtistRef
import app.winters.octo.subsonic.LibraryActionResult
import app.winters.octo.subsonic.Song
import app.winters.octo.subsonic.SongLookup
import app.winters.octo.subsonic.SongTag
import app.winters.octo.subsonic.TrashedSong
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

// Library health's fixes, planned from the songs and run through a stand-in
// for the server.
class HealthFixesTest {
    private fun song(
        id: String,
        title: String = "Teardrop",
        artist: String = "Massive Attack",
        album: String? = "Mezzanine",
        albumId: String = "al-${album.orEmpty()}",
        suffix: String = "flac",
        bitDepth: Int? = 16,
        bitRate: Int? = 900,
        year: Int? = null,
        genre: String? = null,
        track: Int? = null,
        albumArtist: String? = null,
        isrc: List<String> = emptyList(),
        seconds: Int = 330,
    ) = Song(
        id = id, title = title, artist = artist, album = album, albumId = albumId, duration = seconds,
        suffix = suffix, bitDepth = bitDepth, samplingRate = 44_100, bitRate = bitRate, isrc = isrc,
        year = year, genre = genre, track = track, displayAlbumArtist = albumArtist,
        albumArtists = listOfNotNull(albumArtist?.let { ArtistRef(name = it) }), coverArt = "mf-$id",
    )

    private fun group(vararg songs: Song) = findDuplicates(songs.toList(), SubsonicHealth).single()

    // Copies

    @Test
    fun theBestCopyIsKept_TheOthersGo_AndItsBlankTagsAreFilledFromThem() {
        val flac = song("flac")
        val mp3 = song("mp3", suffix = "mp3", bitDepth = null, bitRate = 320, year = 1998, genre = "Trip Hop", track = 3, albumArtist = "Massive Attack", isrc = listOf("GBAAA9800003"))

        val fix = duplicateFix(group(mp3, flac), SubsonicHealth)

        assertEquals("flac", fix.keep.id)
        assertEquals(listOf("mp3"), fix.remove.map { it.id })
        assertEquals("Keeps the FLAC, 16-bit, 44.1 kHz copy, because it sounds best.", fix.why)
        assertEquals(
            mapOf(SongTag.ALBUM_ARTIST to "Massive Attack", SongTag.TRACK to "3", SongTag.YEAR to "1998", SongTag.GENRE to "Trip Hop", SongTag.ISRC to "GBAAA9800003"),
            fix.fills.associate { it.tag to it.value },
        )
        assertTrue(fix.fills.all { it.from == "mp3" && it.now == null })
        assertNull(fix.note)
        val steps = fix.steps(SubsonicHealth)
        // The tags first, while the copy they come from is still there.
        assertTrue(steps[0] is FixStep.Retag && steps[0].id == "flac")
        assertEquals(FixStep.Remove("mp3", "Teardrop", copy = true), steps[1])
        // Only that copy is unwanted, so the server is told.
        assertEquals(mapOf("copy" to "true"), steps[1].with)
        assertEquals(emptyMap<String, String>(), FixStep.Remove("mp3", "Teardrop").with)
    }

    @Test
    fun aTrackNumberIsNotTakenFromACopyOnAnotherAlbum_ButTheGenreIs() {
        val keep = song("keep")
        val single = song("single", album = "Teardrop (Single)", suffix = "mp3", bitDepth = null, bitRate = 320, track = 1, year = 1998, genre = "Trip Hop")

        val fix = duplicateFix(group(single, keep), SubsonicHealth)

        assertEquals(mapOf(SongTag.GENRE to "Trip Hop"), fix.fills.associate { it.tag to it.value })
        assertEquals("Teardrop (MP3, 320 kbps) is on Teardrop (Single), so that album will no longer have this song.", fix.note)
    }

    @Test
    fun aCopyWithNoAlbumTakesAWholeAlbumFromOneCopy() {
        val loose = song("loose", album = null, albumId = "")
        val tagged = song("tagged", suffix = "mp3", bitDepth = null, bitRate = 320, track = 3, albumArtist = "Massive Attack")

        val fix = duplicateFix(group(tagged, loose), SubsonicHealth)

        assertEquals("loose", fix.keep.id)
        assertEquals(
            mapOf(SongTag.ALBUM to "Mezzanine", SongTag.ALBUM_ARTIST to "Massive Attack", SongTag.TRACK to "3"),
            fix.fills.associate { it.tag to it.value },
        )
    }

    @Test
    fun aPersonCanKeepAnotherCopy_AndTagsTheCopiesSayDifferentlyAreForThemToPick() {
        val flac = song("flac", year = 1998)
        val mp3 = song("mp3", suffix = "mp3", bitDepth = null, bitRate = 320, year = 1997)

        val fix = duplicateFix(group(mp3, flac), SubsonicHealth, keep = mp3)

        assertEquals("mp3", fix.keep.id)
        assertEquals(listOf("flac"), fix.remove.map { it.id })
        assertEquals("You picked this copy (MP3, 320 kbps) to keep.", fix.why)
        assertEquals(listOf(TagChoice(SongTag.YEAR, mapOf("mp3" to "1997", "flac" to "1998"))), fix.differs)
        assertTrue(fix.fills.isEmpty())
    }

    // Albums

    @Test
    fun aSplitAlbumMovesTheSmallerPartsOntoTheLargest() {
        val songs = listOf(
            song("a1", "Angel", album = "Mezzanine", albumId = "big", albumArtist = "Massive Attack", year = 1998),
            song("a2", "Risingson", album = "Mezzanine", albumId = "big", albumArtist = "Massive Attack", year = 1998),
            song("b1", "Teardrop", album = "Mezzanine ", albumId = "small", albumArtist = "Massive Attack", year = 1998),
        )
        val split = findSplitAlbums(songs, SubsonicHealth).single()

        val join = albumJoin(split)

        assertEquals(listOf("b1"), join.moving.map { it.id })
        assertEquals(listOf(FixStep.JoinAlbum("b1", "Teardrop", like = join.lead.id)), join.steps(SubsonicHealth))
        assertTrue(join.lead.id == "a1" || join.lead.id == "a2")
        assertEquals("Moves 1 song onto Mezzanine, the part with 2 songs.", join.words)
    }

    // Missing tags

    @Test
    fun aYearTheRestOfTheAlbumAgreesOnIsFilledIn_ButNotWhenItDisagrees() {
        val all = listOf(
            song("a1", "One", year = 1998), song("a2", "Two", year = 1998), song("a3", "Three", year = null),
            song("b1", "Four", album = "Other", year = 2001), song("b2", "Five", album = "Other", year = 2003), song("b3", "Six", album = "Other", year = null),
        )
        val missing = all.filter { it.year == null }

        val fills = fillsFromAlbum(missing, all, HealthTag.Year, SubsonicHealth)

        assertEquals(listOf("a3" to "1998"), fills.map { (song, change) -> song.id to change.value })
    }

    @Test
    fun anAlbumArtistComesFromTheArtistWhenEverySongIsByOne() {
        val all = listOf(song("a1", "One"), song("a2", "Two"))

        val fills = fillsFromAlbum(all, all, HealthTag.AlbumArtist, SubsonicHealth)

        assertEquals(listOf("Massive Attack", "Massive Attack"), fills.map { it.second.value })
        assertEquals(SongTag.ALBUM_ARTIST, fills[0].second.tag)
    }

    // Lookups

    @Test
    fun aLookupPicksBlanks_AndOverwritesOnlyWhenSure_NeverTheSongsName() {
        val lookup = SongLookup(
            state = "found", confidence = "Strong", source = "Fingerprint",
            current = mapOf("title" to "teardrop", "year" to null, "genre" to "Electronic", "track" to "3"),
            suggested = mapOf("title" to "Teardrop", "year" to "1998", "genre" to "Trip Hop", "track" to "3"),
        )

        val picked = lookup.changes().associate { (change, pick) -> change.tag to pick }

        assertEquals(mapOf("title" to false, "year" to true, "genre" to true), picked)
        val doubtful = lookup.copy(confidence = "Low").changes().associate { (change, pick) -> change.tag to pick }
        assertEquals(mapOf("title" to false, "year" to true, "genre" to false), doubtful)
        assertEquals("A sure match from the song's fingerprint.", lookup.origin())
    }

    // Running

    @Test
    fun aRunSaysWhatWasDone_WhatWasNot_AndHowToPutItBack() = runTest {
        val steps = listOf(
            FixStep.Retag("flac", "Teardrop", mapOf("year" to "1998")),
            FixStep.Remove("mp3", "Teardrop"),
            FixStep.Remove("ogg", "Teardrop"),
            FixStep.AddCover("c", "Angel"),
        )
        val seen = ArrayList<Pair<Int, Int>>()

        val outcome = runFix(steps, { step ->
            when (step.id) {
                "ogg" -> LibraryActionResult(step.id, step.action, "failed", "Could not work out which file this is, so nothing was touched.")
                "c" -> LibraryActionResult(step.id, step.action, "skipped", "The song has a picture of its own already, so it was left alone.")
                else -> LibraryActionResult(step.id, step.action, "applied")
            }
        }, progress = { done, total -> seen += done to total })

        assertEquals(setOf("mp3"), outcome.removed)
        assertEquals(listOf(FixStep.Restore("mp3", "Teardrop"), FixStep.Undo("flac", "Teardrop")), outcome.undo)
        assertEquals(listOf("c"), outcome.unchanged.map { it.id })
        assertEquals(
            "Removed 1 song, changed the tags of 1 song. Teardrop: Could not work out which file this is, so nothing was touched.",
            outcome.summary(),
        )
        assertEquals(0 to 4, seen.first())
        assertEquals(4 to 4, seen.last())
    }

    @Test
    fun aRehearsalSaysNothingChanged_AndAStopEndsBetweenSteps() = runTest {
        val rehearsed = runFix(listOf(FixStep.Remove("a", "A")), { LibraryActionResult(it.id, it.action, "rehearsed") })
        assertTrue(rehearsed.rehearsed)
        assertTrue(rehearsed.done.isEmpty())
        assertTrue("dry run" in rehearsed.summary())

        var asked = 0
        val stopped = runFix(
            listOf(FixStep.Remove("a", "A"), FixStep.Remove("b", "B")),
            { asked++; LibraryActionResult(it.id, it.action, "applied") },
            stop = { asked >= 1 },
        )
        assertEquals(1, asked)
        assertTrue(stopped.stopped)
        assertFalse(stopped.summary().isEmpty())
    }

    @Test
    fun puttingBackAReplacedCopySaysTheServersWords_AndUndoSwapsAgain() = runTest {
        val replaced = TrashedSong(id = "nd-1", title = "Holocene", kind = "replaced", was = "FLAC 16-bit 44.1 kHz", now = "MP3 320")
        assertTrue(replaced.replaced)
        assertFalse(TrashedSong(id = "x", title = "X").replaced)
        assertEquals("Replaced: was FLAC 16-bit 44.1 kHz, now MP3 320", replacedText(replaced.was, replaced.now))
        assertEquals("Replaced by another copy", replacedText(null, " "))
        val step = replaced.restoreStep()
        assertEquals(FixStep.Restore("nd-1", "Holocene", replaced = true), step)
        assertEquals(step, step.undo)

        val sent = ArrayList<String>()
        val back = runFix(listOf(step), {
            sent += "${it.action}:${it.id}"
            LibraryActionResult(it.id, it.action, "applied", "Put back your old copy. The one that replaced it is in Recently removed.")
        })
        assertEquals(listOf("restore:nd-1"), sent)
        assertEquals("Put back your old copy. The one that replaced it is in Recently removed.", back.summary())

        val notKept = runFix(listOf(step), {
            LibraryActionResult(it.id, it.action, "skipped", "Your old copy was not kept on this server, so there is nothing to put back.")
        })
        assertEquals("Your old copy was not kept on this server, so there is nothing to put back.", notKept.summary())

        // A plain removed song still reads as before.
        val plain = runFix(listOf(FixStep.Restore("x", "X")), { LibraryActionResult(it.id, it.action, "applied", "Put back.") })
        assertEquals("Put back 1 song.", plain.summary())
    }

    @Test
    fun theFixWordsHaveNoDashes() {
        val words = listOf(
            keepWhy(group(song("a"), song("b", suffix = "mp3", bitDepth = null, bitRate = 128)), song("a"), SubsonicHealth),
            TagChange(SongTag.YEAR, "1997", "1998").words(),
            SongLookup(confidence = "Medium", source = "Database", release = "'Mezzanine' 1998").origin(),
        ) + SongTag.all.map(::tagName)
        for (line in words) assertFalse(line, line.contains('—') || line.contains('–') || line.contains(" - "))
    }

    @Test
    fun deletingSaysWhereTheFileGoesAndForHowLong() {
        assertEquals("Delete this song from disk?", deleteTitle(1))
        assertEquals("Delete 3 songs from disk?", deleteTitle(3))
        val body = deleteBody("Teardrop", 30)
        assertTrue("for 30 days" in body)
        assertTrue("until someone clears it" in deleteBody("Teardrop", 0))
        val day = 86_400_000L
        assertEquals("Deleted for good in 12 days", goneText(13 * day - 1, 0))
        assertEquals("Deleted for good tomorrow", goneText(day + 5, 0))
        assertEquals("Kept until someone clears the trash", goneText(null, 0))
        for (line in listOf(body, deletedLine(2, null)) + HealthCheck.entries.flatMap { listOf(it.fixAllLabel(2), it.fixMeaning()) })
            assertFalse(line, line.contains('—') || line.contains('–') || line.contains(" - "))
    }
}
