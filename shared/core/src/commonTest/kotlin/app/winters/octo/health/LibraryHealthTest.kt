package app.winters.octo.health

import app.winters.octo.subsonic.ArtistRef
import app.winters.octo.subsonic.Song
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

// The library health checks over a server's songs.
class LibraryHealthTest {
    private var next = 0

    // A tidy song: every tag there, one of ten on its album.
    private fun song(
        title: String,
        artist: String = "Artist",
        seconds: Int = 200,
        album: String = "Album",
        albumId: String = "al-$album",
        suffix: String = "flac",
        bitDepth: Int? = 16,
        rate: Int? = 44_100,
        bitRate: Int? = 900,
        isrc: List<String> = emptyList(),
        mbid: String? = null,
        year: Int? = 2020,
        genre: String? = "Rock",
        track: Int? = ++next,
        albumArtist: String? = artist,
        cover: String? = "mf-$next",
        id: String = "s${next++}",
    ) = Song(
        id = id, title = title, artist = artist, album = album, albumId = albumId, duration = seconds,
        suffix = suffix, bitDepth = bitDepth, samplingRate = rate, bitRate = bitRate, isrc = isrc,
        musicBrainzId = mbid, year = year, genre = genre, track = track, displayAlbumArtist = albumArtist,
        albumArtists = listOfNotNull(albumArtist?.let { ArtistRef(name = it) }), coverArt = cover,
    )

    private fun report(vararg songs: Song) = checkLibrary(songs.toList(), SubsonicHealth)

    private fun titles(group: DuplicateGroup<Song>) = group.copies.map { it.id }

    // Duplicates

    @Test
    fun twoCopiesOfOneSongAreASetWithTheLosslessOneFirst() {
        val mp3 = song("Holocene", "Bon Iver", 337, suffix = "mp3", bitDepth = null, rate = 44_100, bitRate = 320, id = "mp3")
        val flac = song("Holocene", "Bon Iver", 336, id = "flac")
        val other = song("Towers", "Bon Iver", 188, id = "towers")

        val sets = report(mp3, flac, other).duplicates

        assertEquals(1, sets.size)
        assertEquals(listOf("flac", "mp3"), titles(sets[0]))
        assertEquals(DuplicateBasis.TitleAndLength, sets[0].basis)
        assertEquals(BestReason.Sound, sets[0].bestReason)
    }

    @Test
    fun lengthsMayDifferByThreeSecondsButNotFour() {
        val within = report(song("Song", seconds = 200, id = "a"), song("Song", seconds = 203, id = "b"))
        val beyond = report(song("Song", seconds = 200, id = "a"), song("Song", seconds = 204, id = "b"))

        assertEquals(1, within.duplicates.size)
        assertTrue(beyond.duplicates.isEmpty())
    }

    @Test
    fun anotherVersionIsNotACopy() {
        val found = report(
            song("Song", seconds = 200, id = "studio"),
            song("Song (Live)", seconds = 201, id = "live"),
            song("Song - Acoustic", seconds = 200, id = "acoustic"),
            song("Song (Interlude)", seconds = 200, id = "interlude"),
            song("Song", "Someone Else", seconds = 200, id = "cover"),
        )

        assertTrue(found.duplicates.isEmpty())
    }

    @Test
    fun titlesThatNameDifferentVersionsAreNeverPaired() {
        val pairs = listOf(
            "Let's Get Lost [Bear//Face Remix]" to "Let's Get Lost (Teklife Remix)",
            "Song (Remix)" to "Song",
            "Song (Live)" to "Song",
            "Song (Acoustic)" to "Song",
            "Song (Sped Up)" to "Song",
            "Song (Slowed)" to "Song",
            "Song (Instrumental)" to "Song",
            "Song (Radio Edit)" to "Song (Album Version)",
            "Song (Demo)" to "Song",
            "Song (Taylor's Version)" to "Song",
        )
        for ((one, other) in pairs) {
            val found = report(song(one, seconds = 200, id = "a"), song(other, seconds = 201, id = "b"))
            assertTrue("$one and $other", found.duplicates.isEmpty())
        }
    }

    @Test
    fun aSongTaggedPlainlyOnAnAlbumOfAnotherVersionIsNotACopy() {
        val albums = listOf(
            "Let's Get Lost Remixes",
            "Song (Remixes) - EP",
            "Song (Sped Up) - Single",
            "Slowed Down Hits",
            "Song (Acoustic)",
            "The Instrumentals",
            "Song (Radio Edit) - Single",
            "Club Hits (Extended Mixes)",
            "Song (Demo)",
        )
        for (album in albums) {
            val found = report(
                song("Song", seconds = 240, album = "Studio Album", id = "studio"),
                song("Song", seconds = 242, album = album, id = "other"),
            )
            assertTrue(album, found.duplicates.isEmpty())
        }
    }

    @Test
    fun albumsThatNameNoOtherVersionStillPairTheirCopies() {
        val albums = listOf(
            "Studio Album (Deluxe Edition)",
            "Studio Album (Extended Edition)",
            "Studio Album (Remastered)",
            "Studio Album (Explicit)",
            "Mix Tape",
        )
        for (album in albums) {
            val found = report(
                song("Song", seconds = 240, album = "Studio Album", id = "studio"),
                song("Song", seconds = 241, album = album, id = "other"),
            )
            assertEquals(album, 1, found.duplicates.size)
        }
    }

    @Test
    fun copiesOnTwoAlbumsOfTheSameVersionArePaired() {
        val bothRemixes = report(
            song("Song", seconds = 242, album = "Song Remixes", id = "ep"),
            song("Song", seconds = 242, album = "Song (Remixes)", id = "ep-again"),
        )
        val versionInTheTitle = report(
            song("Song (Remix)", seconds = 242, album = "Song (Remix) - Single", id = "single"),
            song("Song (Remix)", seconds = 242, album = "Best of 2014", id = "compilation"),
        )

        assertEquals(1, bothRemixes.duplicates.size)
        assertEquals(1, versionInTheTitle.duplicates.size)
    }

    @Test
    fun anArtistsOwnNameOnTheAlbumIsNoVersion() {
        val found = report(
            song("Song", "The Remix Kids", 240, album = "Studio Album", id = "studio"),
            song("Song", "The Remix Kids", 241, album = "The Remix Kids", id = "self-titled"),
        )

        assertEquals(1, found.duplicates.size)
    }

    @Test
    fun aRemasterGuestOrTrackNumberInTheTitleIsStillTheSameRecording() {
        val found = report(
            song("Pain 1993", "Drake", 149, id = "plain"),
            song("Pain 1993 (featuring Playboi Carti)", "Drake", 149, id = "feat"),
            song("10 - Pain 1993 - Remastered 2021", "Drake", 150, id = "remaster"),
        )

        assertEquals(1, found.duplicates.size)
        assertEquals(3, found.duplicates[0].copies.size)
    }

    @Test
    fun aSharedIsrcIsOneRecordingWhateverTheTitleSays() {
        val found = report(
            song("紅蓮華", "LiSA", 240, isrc = listOf("JPU901901234"), id = "jp"),
            song("Gurenge", "LiSA", 241, isrc = listOf("JP-U90-19-01234"), id = "en"),
        )

        assertEquals(1, found.duplicates.size)
        assertEquals(DuplicateBasis.Tags, found.duplicates[0].basis)
    }

    @Test
    fun aSharedMusicBrainzRecordingIsOneRecording() {
        val found = report(
            song("Teardrop", "Massive Attack", 330, mbid = "F200A9A9-0000-0000-0000-000000000001", id = "a"),
            song("Tear Drop (Album Version)", "Massive Attack", 331, mbid = "f200a9a9-0000-0000-0000-000000000001", id = "b"),
        )

        assertEquals(1, found.duplicates.size)
        assertEquals(DuplicateBasis.Tags, found.duplicates[0].basis)
    }

    @Test
    fun oneIsrcOnAWholeAlbumOfDifferentLengthsIsATaggingMistakeNotACopy() {
        val code = listOf("USRC17607839")
        val found = report(
            song("One", seconds = 180, isrc = code, id = "1"),
            song("Two", seconds = 240, isrc = code, id = "2"),
            song("Three", seconds = 305, isrc = code, id = "3"),
        )

        assertTrue(found.duplicates.isEmpty())
    }

    @Test
    fun differentIsrcsStillFallBackToTheTitleAndLength() {
        val found = report(
            song("Song", seconds = 200, isrc = listOf("GBAAA0100001"), id = "a"),
            song("Song (Remastered 2011)", seconds = 201, isrc = listOf("GBAAA1100002"), id = "b"),
        )

        assertEquals(1, found.duplicates.size)
        assertEquals(DuplicateBasis.TitleAndLength, found.duplicates[0].basis)
    }

    @Test
    fun copiesChainIntoOneSet() {
        val found = report(
            song("Song", seconds = 200, id = "a"),
            song("Song", seconds = 203, id = "b"),
            song("Song", seconds = 206, id = "c"),
        )

        assertEquals(1, found.duplicates.size)
        assertEquals(3, found.duplicates[0].copies.size)
    }

    @Test
    fun theBestCopyHasMoreBitsThenAHigherRate() {
        val found = report(
            song("Song", bitDepth = 16, rate = 44_100, bitRate = 1650, id = "cd"),
            song("Song", bitDepth = 24, rate = 48_000, bitRate = 1500, id = "hires48"),
            song("Song", bitDepth = 24, rate = 96_000, bitRate = 2800, id = "hires96"),
            song("Song", suffix = "mp3", bitDepth = null, rate = 44_100, bitRate = 320, id = "mp3"),
        )

        assertEquals(listOf("hires96", "hires48", "cd", "mp3"), titles(found.duplicates[0]))
    }

    @Test
    fun theBitRateSettlesLossyCopies() {
        val found = report(
            song("Song", suffix = "mp3", bitDepth = null, bitRate = 192, id = "low"),
            song("Song", suffix = "mp3", bitDepth = null, bitRate = 320, id = "high"),
        )

        assertEquals(listOf("high", "low"), titles(found.duplicates[0]))
        assertEquals(BestReason.Sound, found.duplicates[0].bestReason)
    }

    @Test
    fun copiesThatSoundAlikeKeepTheOneWithFullerTags() {
        val found = report(
            song("Song", year = null, genre = null, id = "bare"),
            song("Song", id = "tagged"),
        )

        assertEquals(listOf("tagged", "bare"), titles(found.duplicates[0]))
        assertEquals(BestReason.Tags, found.duplicates[0].bestReason)
    }

    @Test
    fun identicalCopiesSayNothingSetsThemApart() {
        val found = report(song("Song", id = "b"), song("Song", id = "a"))

        assertEquals(listOf("a", "b"), titles(found.duplicates[0]))
        assertEquals(BestReason.None, found.duplicates[0].bestReason)
    }

    @Test
    fun copiesInTwoPlacesAreNotDuplicates() {
        val phone = object : HealthFields<Song> by SubsonicHealth {
            override fun place(song: Song) = if (song.id.startsWith("p")) "phone" else "server"
        }
        val found = checkLibrary(listOf(song("Song", id = "p1"), song("Song", id = "s1")), phone)

        assertTrue(found.duplicates.isEmpty())
    }

    // Split albums

    @Test
    fun anAlbumUnderTwoIdsIsSplitAndSaysWhatDiffers() {
        val found = report(
            song("One", "SueCo", album = "It Was Fun While It Lasted", albumId = "a", albumArtist = "SueCo", track = 1),
            song("Two", "SueCo", album = "It Was Fun While It Lasted", albumId = "a", albumArtist = "SueCo", track = 2),
            song("Three", "Sueco", album = "It Was Fun While It Lasted", albumId = "b", albumArtist = "Sueco", track = 3),
        ).splitAlbums

        assertEquals(1, found.size)
        assertEquals(listOf("a", "b"), found[0].parts.map { it.albumId })
        assertEquals("SueCo", found[0].artist)
        assertEquals(listOf(AlbumDifferenceValues(AlbumDifference.AlbumArtist, listOf("SueCo", "Sueco"))), found[0].differences)
    }

    @Test
    fun aMissingYearSplitsAnAlbumAndIsNamed() {
        val found = report(
            song("One", album = "Currents", albumId = "a", year = 2015),
            song("Two", album = "Currents", albumId = "b", year = null),
        ).splitAlbums

        assertEquals(1, found.size)
        assertEquals(AlbumDifference.Year, found[0].differences.single().kind)
        assertEquals(listOf("2015", ""), found[0].differences.single().values)
        assertEquals("The year differs: 2015, none.", found[0].differences.single().words())
    }

    @Test
    fun aStraySpaceIsNamedSinceItCannotBeSeen() {
        val found = report(
            song("One", "Disturbed", album = "The Sickness ", albumId = "a"),
            song("Two", "Disturbed", album = "The Sickness", albumId = "b"),
        ).splitAlbums.single()

        assertEquals("The Sickness by Disturbed, shown as 2 albums", found.heading())
        assertEquals("The album title has a stray space on some songs.", found.summary())
    }

    @Test
    fun twoAlbumsOfOneNameFromDifferentYearsAreTwoAlbums() {
        val found = report(
            song("My Name Is Jonas", "Weezer", album = "Weezer", albumId = "blue", year = 1994),
            song("Hash Pipe", "Weezer", album = "Weezer", albumId = "green", year = 2001),
        )

        assertTrue(found.splitAlbums.isEmpty())
    }

    @Test
    fun albumsOfOneNameByDifferentArtistsAreNotSplit() {
        val found = report(
            song("A", "One", album = "Greatest Hits", albumId = "x"),
            song("B", "Two", album = "Greatest Hits", albumId = "y"),
        )

        assertTrue(found.splitAlbums.isEmpty())
    }

    @Test
    fun whenNothingVisibleDiffersTheReportSaysSomethingElseDoes() {
        val found = report(song("One", album = "Album", albumId = "a"), song("Two", album = "Album", albumId = "b")).splitAlbums

        assertEquals(AlbumDifference.Other, found.single().differences.single().kind)
    }

    // Missing tags

    @Test
    fun eachMissingTagListsItsSongs() {
        val found = report(
            song("Tidy", albumId = "x"),
            song("No genre", albumId = "x", genre = null),
            song("No year", albumId = "x", year = 0),
            song("No track", albumId = "x", track = null),
            song("No album artist", albumId = "x", albumArtist = null),
            song("No cover", albumId = "x", cover = null),
        )

        assertEquals(listOf("No genre"), found.missing.getValue(HealthTag.Genre).map { it.title })
        assertEquals(listOf("No year"), found.missing.getValue(HealthTag.Year).map { it.title })
        assertEquals(listOf("No track"), found.missing.getValue(HealthTag.TrackNumber).map { it.title })
        assertEquals(listOf("No album artist"), found.missing.getValue(HealthTag.AlbumArtist).map { it.title })
        assertEquals(listOf("No cover"), found.missing.getValue(HealthTag.Cover).map { it.title })
        assertEquals(1, found.count(HealthCheck.NoGenre))
    }

    @Test
    fun aSingleNeedsNoTrackNumberOrAlbumArtist() {
        val found = report(song("Single", albumId = "one", track = null, albumArtist = null))

        assertFalse(HealthTag.TrackNumber in found.missing)
        assertFalse(HealthTag.AlbumArtist in found.missing)
    }

    @Test
    fun aTagTheAppNeverKeepsIsNeverMissing() {
        val phone = object : HealthFields<Song> by SubsonicHealth {
            override val seen = setOf(HealthTag.Genre)
        }
        val found = checkLibrary(listOf(song("Song", genre = null, year = null, cover = null)), phone)

        assertEquals(setOf(HealthTag.Genre), found.missing.keys)
    }

    @Test
    fun songsMissingATagComeByArtistThenAlbumOrder() {
        val found = report(
            song("B2", "Beta", album = "B", albumId = "b", genre = null, track = 2),
            song("A1", "Alpha", album = "A", albumId = "a", genre = null, track = 1),
            song("B1", "Beta", album = "B", albumId = "b", genre = null, track = 1),
        )

        assertEquals(listOf("A1", "B1", "B2"), found.songs(HealthCheck.NoGenre).map { it.title })
    }

    // The report

    @Test
    fun aSongWithNoLengthIsFound() {
        val found = report(song("Broken", seconds = 0), song("Fine", seconds = 180))

        assertEquals(listOf("Broken"), found.noLength.map { it.title })
    }

    @Test
    fun aTidyLibraryIsClean() {
        val found = report(song("One", albumId = "a"), song("Two", albumId = "a", seconds = 180))

        assertTrue(found.clean)
        assertEquals("Checked 2 songs.", found.overview())
    }

    @Test
    fun findingsComeInTheirOrderWithCounts() {
        val found = report(
            song("Song", genre = null, id = "a"),
            song("Song", genre = null, id = "b"),
            song("Other", seconds = 0),
        )

        assertEquals(listOf(HealthCheck.Duplicates, HealthCheck.NoLength, HealthCheck.NoGenre), found.findings)
        assertEquals(1, found.count(HealthCheck.Duplicates))
        assertEquals("Checked 3 songs. 3 things could be better.", found.overview())
    }

    @Test
    fun removedSongsLeaveTheReport() {
        val found = report(song("Song", genre = null, id = "a"), song("Song", genre = null, id = "b"))
        val after = found.without(setOf("b"), SubsonicHealth)

        assertTrue(after.duplicates.isEmpty())
        assertEquals(listOf("a"), after.songs(HealthCheck.NoGenre).map { it.id })
    }

    // Words

    @Test
    fun aSetOfCopiesSaysWhichToKeep() {
        val found = report(
            song("Song", "Artist", bitDepth = 24, rate = 96_000, id = "a"),
            song("Song", "Artist", suffix = "mp3", bitDepth = null, bitRate = 320, id = "b"),
        ).duplicates.single()

        assertEquals("Song by Artist", found.heading(SubsonicHealth))
        assertEquals("2 copies. Same title, artist and length. Keep the first, FLAC, 24-bit, 96 kHz.", found.summary(SubsonicHealth))
    }

    @Test
    fun qualityReadsTheWayPeopleSayIt() {
        assertEquals("FLAC, 16-bit, 44.1 kHz", qualityText("flac", true, 16, 44_100, 900))
        assertEquals("MP3, 320 kbps", qualityText("mp3", false, null, 44_100, 320))
        assertEquals("unknown quality", qualityText(null, false, null, null, null))
    }

    @Test
    fun countsReadNaturally() {
        assertEquals("1 song", HealthCheck.NoGenre.countLabel(1))
        assertEquals("2,256 songs", HealthCheck.NoGenre.countLabel(2256))
        assertEquals("64 songs with more than one copy", HealthCheck.Duplicates.countLabel(64))
    }

    @Test
    fun noWordsUseADash() {
        val words = HealthCheck.entries.flatMap { listOf(it.title(), it.meaning(), it.advice()) } +
            AlbumDifference.entries.map { AlbumDifferenceValues(it, listOf("a", "b")).words() } +
            DuplicateBasis.entries.map { it.words() } + BestReason.entries.map { it.words("FLAC") } + HEALTH_ALL_CLEAR
        words.forEach { assertFalse(it, it.contains('\u2014') || it.contains('\u2013')) }
    }
}
