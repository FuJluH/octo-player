package app.winters.octo.desktop.library

import app.winters.octo.catalog.DRAWN_COVER_VERSION
import app.winters.octo.covers.coverBucket
import app.winters.octo.catalog.naturalSortKey
import app.winters.octo.server.serverTime
import app.winters.octo.sort.SongSort
import app.winters.octo.sort.SortList
import app.winters.octo.sort.SortOrder
import app.winters.octo.sort.sortedByKey
import app.winters.octo.subsonic.Album
import app.winters.octo.subsonic.Artist
import app.winters.octo.subsonic.Song
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.random.Random

class SongSortingTest {
    private val songs = listOf(
        Song("1", "Yesterday", artist = "The Beatles", album = "Help!", albumId = "h", track = 13, year = 1965, duration = 125, created = "2024-01-02T00:00:00Z", playCount = 3, played = "2026-09-01T10:00:00Z"),
        Song("2", "Airbag", artist = "Radiohead", album = "OK Computer", albumId = "ok", track = 1, year = 1997, duration = 284, created = "2025-05-05T00:00:00Z", playCount = 10, played = "2026-08-01T10:00:00Z"),
        Song("3", "Help!", artist = "The Beatles", album = "Help!", albumId = "h", track = 1, year = 1965, duration = 138, created = "2024-01-02T00:00:00Z"),
        Song("4", "An Untitled Demo", artist = "Abba", album = "Demos", albumId = "d", duration = 0),
    )

    private fun ids(list: List<Song>) = list.map { it.id }

    @Test
    fun everySortableColumnIsASharedSongOrder() {
        SongColumn.entries.filter { it.sort != null }.forEach { column ->
            assertTrue("${column.title} is offered for songs", SortList.Songs.options.contains(column.sort!!))
            assertEquals(column, SongColumn.of(column.sort!!))
        }
        assertNull(SongColumn.Number.sort)
    }

    @Test
    fun aNewColumnStartsItsUsualWayAndAClickTurnsItRound() {
        val start = SortList.Songs.default
        assertEquals(SortOrder(SongSort.Title, false), start)
        val byYear = start.clicking(SongColumn.Year)
        assertEquals(SortOrder(SongSort.Year, true), byYear)
        assertEquals(SortOrder(SongSort.Year, false), byYear.clicking(SongColumn.Year))
        assertEquals(SortOrder(SongSort.Artist, false), byYear.clicking(SongColumn.Artist))
        assertEquals("the number column does not sort", start, start.clicking(SongColumn.Number))
    }

    @Test
    fun titlesFileWithoutTheirArticle() {
        assertEquals(listOf("2", "3", "4", "1"), ids(sortSongs(songs, SortOrder(SongSort.Title, false))))
    }

    @Test
    fun anArtistsSongsStayInAlbumOrder() {
        // "Abba", then "The Beatles" filed under B with Help! before Yesterday, then Radiohead.
        assertEquals(listOf("4", "3", "1", "2"), ids(sortSongs(songs, SortOrder(SongSort.Artist, false))))
    }

    @Test
    fun missingValuesGoLastWhicheverWay() {
        assertEquals("4", sortSongs(songs, SortOrder(SongSort.Year, true)).last().id)
        assertEquals("4", sortSongs(songs, SortOrder(SongSort.Year, false)).last().id)
        assertEquals("4", sortSongs(songs, SortOrder(SongSort.Length, false)).last().id)
    }

    @Test
    fun playsUseTheSharedListeningOrder() {
        assertEquals(listOf("2", "1", "3", "4"), ids(sortSongs(songs, SortOrder(SongSort.MostPlayed, true))))
        // Ascending, the never-played come first, then the least played.
        assertEquals(listOf("3", "4", "1", "2"), ids(sortSongs(songs, SortOrder(SongSort.MostPlayed, false))))
    }

    @Test
    fun newestAddedFirst() {
        assertEquals("2", sortSongs(songs, SortOrder(SongSort.RecentlyAdded, true)).first().id)
    }

    // The orders as they were first written, with every key worked out on
    // every comparison, to hold the quicker ones to the same results.
    private val slowInAlbum: Comparator<Song> = compareBy<Song>({ naturalSortKey(it.album.orEmpty()) }, { it.albumId.orEmpty() }, { it.discNumber ?: 0 }, { it.track ?: 0 }, { naturalSortKey(it.title) }, { it.id })
    private val slowByTitle: Comparator<Song> = compareBy({ naturalSortKey(it.title) }, { naturalSortKey(it.artist.orEmpty()) }, { it.id })

    private fun slowSort(songs: List<Song>, by: SongSort, down: Boolean): List<Song>? = when (by) {
        SongSort.Title -> sortedByKey(songs, down, { naturalSortKey(it.title) }, slowByTitle)
        SongSort.Artist -> sortedByKey(songs, down, { naturalSortKey(it.artist.orEmpty()) }, slowInAlbum)
        SongSort.Album -> sortedByKey(songs, down, { naturalSortKey(it.album.orEmpty()) }, compareBy<Song> { naturalSortKey(it.artist.orEmpty()) }.then(slowInAlbum))
        SongSort.Year -> sortedByKey(songs, down, { it.year?.takeIf { y -> y > 0 } }, slowInAlbum)
        SongSort.Length -> sortedByKey(songs, down, { it.duration.takeIf { d -> d > 0 } }, slowByTitle)
        SongSort.RecentlyAdded -> sortedByKey(songs, down, { serverTime(it.created) }, slowInAlbum)
        else -> null
    }

    // A big made-up library, with repeated names, articles, accents, numbers
    // and missing values, so ties and tie-breaks all come up.
    private fun bigLibrary(count: Int): List<Song> {
        val random = Random(7)
        val words = listOf("The Wall", "a Song", "Élan", "elan", "Vol. 2", "Vol. 10", "Track 01", "track 1", "", "Zebra", "An Hour", "99 Luftballons")
        return List(count) { i ->
            Song(
                "s$i",
                words.random(random) + if (random.nextBoolean()) " ${random.nextInt(30)}" else "",
                artist = words.random(random).takeIf { random.nextInt(8) > 0 },
                album = words.random(random).takeIf { random.nextInt(8) > 0 },
                albumId = "a${random.nextInt(40)}",
                discNumber = random.nextInt(3).takeIf { it > 0 },
                track = random.nextInt(15).takeIf { it > 0 },
                year = listOf(null, 0, 1965, 1997, 2024).random(random),
                duration = random.nextInt(0, 400),
                created = listOf(null, "2024-01-02T00:00:00Z", "2025-05-05T00:00:00Z", "not a date").random(random),
                playCount = random.nextLong(0, 5),
                played = listOf(null, "2026-09-01T10:00:00Z", "2026-08-01T10:00:00Z").random(random),
            )
        }
    }

    @Test
    fun aBigLibrarySortsExactlyAsTheSlowOrdersDid() {
        val big = bigLibrary(5_000)
        for (by in SongSort.entries) {
            for (down in listOf(false, true)) {
                val slow = slowSort(big, by, down) ?: continue
                assertEquals("$by ${if (down) "down" else "up"}", ids(slow), ids(sortSongs(big, SortOrder(by, down))))
            }
        }
        val artists = big.mapNotNull { it.artist }.distinct().map { Artist(it, it) }
        assertEquals(artists.sortedBy { naturalSortKey(it.name) }, sortedByName(artists) { it.name })
        assertEquals(ids(big.filter { serverTime(it.played) != null }.sortedByDescending { serverTime(it.played) }), ids(recentlyPlayed(big)))
    }

    @Test
    fun historyIsWhatWasPlayedNewestFirst() {
        assertEquals(listOf("1", "2"), ids(recentlyPlayed(songs)))
    }

    @Test
    fun lengthsReadPlainly() {
        assertEquals("2:05", lengthText(125))
        assertEquals("1:02:03", lengthText(3723))
        assertEquals("", lengthText(0))
        assertEquals("2 h 14 min", totalLengthText(8040))
        assertEquals("38 min", totalLengthText(2280))
    }
}

class SelectionTest {
    // Ten rows, known by keys "0" to "9".
    private val order = (0..9).map { "$it" }

    @Test
    fun aClickPicksOneRow() {
        val s = TableSelection()
        s.click("3", toggle = false, range = false, order = order)
        s.click("5", toggle = false, range = false, order = order)
        assertEquals(setOf("5"), s.picked)
    }

    @Test
    fun ctrlAddsAndTakesAway() {
        val s = TableSelection()
        s.click("1", false, false, order = order)
        s.click("4", toggle = true, range = false, order = order)
        assertEquals(setOf("1", "4"), s.picked)
        s.click("1", toggle = true, range = false, order = order)
        assertEquals(setOf("4"), s.picked)
    }

    @Test
    fun shiftPicksTheRunFromTheLastClick() {
        val s = TableSelection()
        s.click("6", false, false, order = order)
        s.click("2", toggle = false, range = true, order = order)
        assertEquals(setOf("2", "3", "4", "5", "6"), s.picked)
        // The run still starts where the plain click was.
        s.click("8", toggle = false, range = true, order = order)
        assertEquals(setOf("6", "7", "8"), s.picked)
        s.click("0", toggle = true, range = true, order = order)
        assertEquals(setOf("0", "1", "2", "3", "4", "5", "6", "7", "8"), s.picked)
    }

    @Test
    fun aRightClickOutsideTheSelectionActsOnThatRowAlone() {
        val s = TableSelection()
        s.click("1", false, false, order = order)
        s.click("3", true, false, order = order)
        s.pickForMenu("3")
        assertEquals(setOf("1", "3"), s.picked)
        s.pickForMenu("7")
        assertEquals(setOf("7"), s.picked)
    }

    @Test
    fun thePickedRowsComeOutInTableOrder() {
        val s = TableSelection()
        s.click("2", false, false, order = order)
        s.click("0", true, false, order = order)
        val rows = listOf("0", "1", "2").map { TableRow(it, app.winters.octo.subsonic.Song(it), it.toInt()) }
        assertEquals(listOf("0", "2"), s.of(rows).map { it.key })
    }
}

class LibraryIndexTest {
    private val index = LibraryIndex(
        songs = listOf(
            Song("s1", "Blue Monday", artist = "New Order", albumId = "a1", genre = "Synth-pop", duration = 448),
            Song("s2", "Ceremony", artist = "New Order", albumId = "a2", genres = listOf("Post-punk", "Synth-pop"), duration = 264),
            Song("s3", "Atmosphere", artist = "Joy Division", albumId = "a3", genre = "post-punk", duration = 250),
        ),
        albums = listOf(Album("a1"), Album("a2"), Album("a3")),
        artists = listOf(Artist("r1", "New Order")),
    )

    @Test
    fun genresAreCountedAcrossSongsWithOneNameEach() {
        assertEquals(listOf(GenreCount("Post-punk", 2, 2), GenreCount("Synth-pop", 2, 2)), index.genres)
        assertEquals(listOf("s2", "s3"), index.songsInGenre("post-punk").map { it.id })
    }

    @Test
    fun aSongIsInTheLibraryByIdOrAsTheSameSong() {
        assertTrue(index.holds(Song("s1", "Blue Monday")))
        assertTrue("a find downloaded since", index.holds(Song("other", "Blue Monday", artist = "New Order", duration = 447)))
        assertFalse("another recording", index.holds(Song("other", "Blue Monday (Live)", artist = "New Order", duration = 600)))
        assertFalse(index.holds(Song("x", "Temptation", artist = "New Order")))
    }

    @Test
    fun aSongWithTheSameIsrcIsInTheLibraryUnderAnyTitle() {
        val library = LibraryIndex(
            songs = listOf(Song("s1", "紅蓮華", artist = "LiSA", duration = 239, isrc = listOf("JPU901901234"))),
            albums = emptyList(),
            artists = emptyList(),
        )
        assertTrue("its romanised title", library.holds(Song("ext-1", "Gurenge", artist = "LiSA", duration = 239, isrc = listOf("JP-U90-19-01234"))))
        assertFalse("no code to tell by", library.holds(Song("ext-2", "Gurenge", artist = "LiSA", duration = 239)))
        assertFalse("another code", library.holds(Song("ext-3", "Gurenge", artist = "LiSA", duration = 239, isrc = listOf("JPU902003065"))))
    }

    @Test
    fun coversAreCachedByWhatTheyAreNotWhereTheyCameFrom() {
        assertEquals(300, coverBucket(160))
        assertEquals(1200, coverBucket(5000))
        assertEquals("cover:music.test:al-1:300", coverKey("music.test", "al-1", 300))
        assertEquals("online-cover:v$ONLINE_COVER_VERSION:music.test:al-1:300", coverKey("music.test", "al-1", 300, online = true))
    }

    @Test
    fun aCoverOctoPaintsIsKeptUnderItsVersionAndTheDay() {
        val day = 24L * 60 * 60 * 1000
        // 2026-09-29T12:00Z, on day 20725.
        val noon = 1_790_683_200_000L
        val station = "or3kZ9QpLmN2xY7wV1bC0a"
        val mix = "og8Hf2Kd9LzQw3Rt5Yu7Ip"
        assertEquals("drawn-cover:v$DRAWN_COVER_VERSION:20725:music.test:$station:300", coverKey("music.test", station, 300, nowMs = noon))
        assertEquals("drawn-cover:v$DRAWN_COVER_VERSION:20725:music.test:$mix:600", coverKey("music.test", mix, 600, nowMs = noon))
        // Never the key it was kept under for good before.
        assertNotEquals("cover:music.test:$station:300", coverKey("music.test", station, 300, nowMs = noon))
        // Asked for again the next day, and only then.
        assertEquals(coverKey("music.test", station, 300, nowMs = 20725 * day), coverKey("music.test", station, 300, nowMs = 20726 * day - 1))
        assertNotEquals(coverKey("music.test", station, 300, nowMs = 20725 * day), coverKey("music.test", station, 300, nowMs = 20726 * day))
        // A library cover keeps its key whatever the day.
        assertEquals("cover:music.test:al-1:300", coverKey("music.test", "al-1", 300, nowMs = noon))
    }

    @Test
    fun aSmallCoverIsFetchedAtLeastTwiceItsSize() {
        // A sidebar cover, a song row's, a card's, a page's.
        assertEquals(150, coverBucket(coverFetchPx(32)))
        assertEquals(150, coverBucket(coverFetchPx(64)))
        assertEquals(300, coverBucket(coverFetchPx(100)))
        assertEquals(300, coverBucket(coverFetchPx(240)))
        assertEquals(600, coverBucket(coverFetchPx(400)))
        for (px in 1..1200) assertTrue(coverFetchPx(px) >= minOf(px * 2, 300) && coverFetchPx(px) >= px)
    }
}
