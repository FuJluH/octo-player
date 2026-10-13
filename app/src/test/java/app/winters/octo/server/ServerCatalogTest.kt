package app.winters.octo.server

import app.winters.octo.catalog.SourceAlbumEntity
import app.winters.octo.catalog.SourceArtistEntity
import app.winters.octo.catalog.SourceTrackEntity
import app.winters.octo.catalog.joinLines
import app.winters.octo.catalog.relinkKey
import app.winters.octo.subsonic.Album
import app.winters.octo.subsonic.Artist
import app.winters.octo.subsonic.ArtistRef
import app.winters.octo.subsonic.DiscTitle
import app.winters.octo.subsonic.ItemDate
import app.winters.octo.subsonic.Library
import app.winters.octo.subsonic.Song
import app.winters.octo.subsonic.SongReplayGain
import okhttp3.HttpUrl.Companion.toHttpUrl
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ServerCatalogTest {
    private val source = "server:10.0.0.5:4533"

    private val album = Album(
        id = "al1",
        name = "Nightcall",
        artist = "Kavinsky",
        artistId = "ar1",
        coverArt = "al-al1_6aafffab",
        songCount = 1,
        duration = 179,
        year = 2024,
        created = "2026-09-20T15:51:15.203420216Z",
    )

    private val song = Song(
        id = "s1",
        title = "Nightcall",
        album = "Nightcall",
        albumId = "al1",
        artist = "Kavinsky",
        artistId = "ar1",
        displayArtist = "Kavinsky feat. Angèle",
        track = 1,
        discNumber = 1,
        year = 2024,
        duration = 179,
        coverArt = "mf-s1_6aafffab",
        suffix = "flac",
        contentType = "audio/x-flac",
        bitRate = 1032,
        samplingRate = 44_100,
        bitDepth = 16,
        size = 24_740_366,
        starred = "2026-09-23T08:00:00Z",
        displayAlbumArtist = "Kavinsky",
        genre = "Electro",
        created = "2026-09-20T15:51:15.236955739Z",
        played = "2026-09-22T13:36:41.43536229Z",
        playCount = 4,
    )

    private fun song(id: String, disc: Int?, track: Int?) =
        Song(id = id, title = "Song $id", albumId = "al1", discNumber = disc, track = track, duration = 200)

    @Test
    fun aSongOutsideTheLibraryIsNotKept() {
        // Octo lists an album's missing tracks with it, marked.
        val online = song.copy(id = "s2", title = "Found online", isExternal = true, path = null, size = null, created = null)
        val catalog = buildServerCatalog(source, Library(listOf(song, online), listOf(album), emptyList()))
        assertEquals(listOf("s1"), catalog.tracks.map { it.nativeId })
    }

    @Test
    fun aSongMapsToItsRow() {
        val catalog = buildServerCatalog(source, Library(listOf(song), listOf(album), emptyList()))
        val expected = SourceTrackEntity(
            id = "$source:s1",
            sourceId = source,
            nativeId = "s1",
            title = "Nightcall",
            searchKey = "nightcall",
            sortKey = "nightcall",
            artist = "Kavinsky feat. Angèle",
            artistId = "$source:ar1",
            album = "Nightcall",
            albumId = "$source:al1",
            trackNo = 1,
            discNo = 1,
            year = 2024,
            durationMs = 179_000,
            addedAt = 1_789_919_475,
            mimeType = "audio/flac",
            sizeBytes = 24_740_366,
            // The album's cover, then the album's first song's own, for when
            // the server answers the album's with its stand-in picture.
            artwork = "server:$source|al-al1_6aafffab|mf-s1_6aafffab",
            uri = null,
            albumOrder = 0,
            relinkKey = relinkKey("Kavinsky", "Nightcall", 1, 1, "Nightcall", 179_000),
            genre = "Electro",
            bitrate = 1_032_000,
            sampleRate = 44_100,
            bitDepth = 16,
            playCount = 4,
            lastPlayedAt = 1_790_084_201_435,
            starredAt = 1_790_150_400_000,
            // A server that sends one genre still gives the list of genres.
            genres = "Electro",
        )
        assertEquals(listOf(expected), catalog.tracks)
    }

    private val rich = song.copy(
        genre = "Disco",
        genres = listOf("Disco", "Funk"),
        artists = listOf(ArtistRef("ar1", "Kavinsky"), ArtistRef("ar2", "Angèle")),
        musicBrainzId = "B1A9C0E9-D987-4042-AE91-78D6A3267D69",
        bpm = 116,
        comment = " Single edit ",
        displayComposer = "Vincent Belorgey",
        explicitStatus = "clean",
        discNumber = 2,
        year = 2013,
    )

    private val richAlbum = album.copy(
        year = 2013,
        musicBrainzId = "3f0a4f44-1f1b-4b3c-9c62-7a7d7e2c1a10",
        originalReleaseDate = ItemDate(1979, 5, 1),
        discTitles = listOf(DiscTitle(1, "Night One"), DiscTitle(2, "Night Two")),
    )

    private val artists = listOf(
        Artist("ar1", "Kavinsky", musicBrainzId = "056e4f3e-d505-4dad-8ec1-d04f521cbb56"),
        Artist("ar2", "Angèle", musicBrainzId = ""),
    )

    @Test
    fun theOpenSubsonicDetailsAreKept() {
        val row = buildServerCatalog(source, Library(listOf(rich), listOf(richAlbum), artists)).tracks.single()
        assertEquals("Disco", row.genre)
        assertEquals("Disco\nFunk", row.genres)
        assertEquals("Kavinsky\nAngèle", row.artists)
        assertEquals("b1a9c0e9-d987-4042-ae91-78d6a3267d69", row.mbRecordingId)
        assertEquals("3f0a4f44-1f1b-4b3c-9c62-7a7d7e2c1a10", row.mbAlbumId)
        // Only the artist the server has an id for.
        assertEquals("056e4f3e-d505-4dad-8ec1-d04f521cbb56", row.mbArtistIds)
        assertEquals(116, row.bpm)
        assertEquals("Single edit", row.comment)
        assertEquals("Vincent Belorgey", row.composer)
        assertEquals(false, row.explicit)
        assertEquals("Night Two", row.discTitle)
        assertEquals(2013, row.year)
        assertEquals(1979, row.originalYear)
    }

    @Test
    fun anAlbumShowsItsFirstEditionYear() {
        val row = buildServerCatalog(source, Library(listOf(rich), listOf(richAlbum), artists)).albums.single()
        assertEquals(1979, row.year)
        // A first edition said to come after this one is a mistake.
        val wrong = richAlbum.copy(originalReleaseDate = ItemDate(2020))
        val catalog = buildServerCatalog(source, Library(listOf(rich), listOf(wrong), artists))
        assertEquals(2013, catalog.albums.single().year)
        assertNull(catalog.tracks.single().originalYear)
    }

    @Test
    fun aSongInTheMembersOwnLibraryIsKeptAsTheirs() {
        val catalog = buildServerCatalog(source, Library(listOf(song.copy(octoPersonal = true), song.copy(id = "s2")), listOf(album), emptyList()))
        assertEquals(mapOf(true to 1, false to 1), catalog.tracks.groupingBy { it.personal }.eachCount())
    }

    @Test
    fun blankDetailsAreNotKept() {
        val blank = song.copy(musicBrainzId = "", comment = "", displayComposer = " ", explicitStatus = "", bpm = 0)
        val row = buildServerCatalog(source, Library(listOf(blank), listOf(album), emptyList())).tracks.single()
        assertNull(row.mbRecordingId)
        assertNull(row.comment)
        assertNull(row.composer)
        assertNull(row.explicit)
        assertNull(row.bpm)
        assertNull(row.originalYear)
        assertEquals("", row.mbArtistIds)
    }

    @Test
    fun onlyTheSongsOwnMarkCountsNotItsAlbums() {
        // An album is marked explicit when any one of its songs is.
        val explicitAlbum = album.copy(explicitStatus = "explicit")
        val plain = buildServerCatalog(source, Library(listOf(song.copy(explicitStatus = "")), listOf(explicitAlbum), emptyList()))
        assertNull(plain.tracks.single().explicit)
        val marked = buildServerCatalog(source, Library(listOf(song.copy(explicitStatus = "explicit")), listOf(album), emptyList()))
        assertEquals(true, marked.tracks.single().explicit)
    }

    @Test
    fun anAlbumsSongsShareOneCoverWithOneFallback() {
        val songs = listOf(song("b", 1, 2).copy(coverArt = "mf-b_1"), song("a", 1, 1).copy(coverArt = "mf-a_1"))
        val catalog = buildServerCatalog(source, Library(songs, listOf(album), emptyList()))
        // The first song in album order gives the fallback, for every song.
        assertEquals(setOf("server:$source|al-al1_6aafffab|mf-a_1"), catalog.tracks.map { it.artwork }.toSet())
        assertEquals("server:$source|al-al1_6aafffab|mf-a_1", catalog.albums.single().artwork)
    }

    @Test
    fun aSongWithNoAlbumCoverIsDrawnWithItsOwn() {
        val bare = album.copy(coverArt = null)
        val row = buildServerCatalog(source, Library(listOf(song), listOf(bare), emptyList())).tracks.single()
        assertEquals("server:$source|mf-s1_6aafffab", row.artwork)
    }

    @Test
    fun aGenreTextJoiningSeveralGivesEachOne() {
        val row = buildServerCatalog(source, Library(listOf(song.copy(genre = "Rock; Pop")), listOf(album), emptyList())).tracks.single()
        assertEquals("Rock", row.genre)
        assertEquals("Rock\nPop", row.genres)
    }

    @Test
    fun anAlbumMapsToItsRow() {
        val catalog = buildServerCatalog(source, Library(listOf(song), listOf(album), emptyList()))
        val expected = SourceAlbumEntity(
            id = "$source:al1",
            sourceId = source,
            nativeId = "al1",
            title = "Nightcall",
            searchKey = "nightcall kavinsky",
            sortKey = "nightcall",
            artist = "Kavinsky",
            artistId = "$source:ar1",
            year = 2024,
            songCount = 1,
            durationMs = 179_000,
            addedAt = 1_789_919_475,
            // The album's cover, then the album's first song's own, for when
            // the server answers the album's with its stand-in picture.
            artwork = "server:$source|al-al1_6aafffab|mf-s1_6aafffab",
        )
        assertEquals(listOf(expected), catalog.albums)
    }

    @Test
    fun anAlbumKeepsItsReleaseTypesForTheArtistsShelves() {
        val live = album.copy(releaseTypes = listOf("Album", " Live ", ""))
        val row = buildServerCatalog(source, Library(listOf(song), listOf(live), emptyList())).albums.single()
        assertEquals(joinLines(listOf("Album", "Live")), row.releaseTypes)
        // Not tagged, nothing kept.
        assertEquals("", buildServerCatalog(source, Library(listOf(song), listOf(album), emptyList())).albums.single().releaseTypes)
    }

    @Test
    fun artistsAreAlbumArtistsNamedByTheArtistList() {
        val newer = album.copy(id = "al2", name = "OutRun", coverArt = "al-al2_1", created = "2026-09-21T10:00:00Z")
        val catalog = buildServerCatalog(
            source,
            Library(listOf(song), listOf(album, newer), listOf(Artist(id = "ar1", name = "KAVINSKY", coverArt = "ar-ar1_0"))),
        )
        val expected = SourceArtistEntity(
            id = "$source:ar1",
            sourceId = source,
            name = "KAVINSKY",
            searchKey = "kavinsky",
            sortKey = "kavinsky",
            albumCount = 2,
            songCount = 1,
            artwork = "server:$source|al-al2_1",
        )
        assertEquals(listOf(expected), catalog.artists)
    }

    @Test
    fun albumOrderFollowsDiscThenTrack() {
        val songs = listOf(song("c", 2, 1), song("b", 1, 2), song("a", 1, 1), song("d", 0, 0))
        val catalog = buildServerCatalog(source, Library(songs, listOf(album), emptyList()))
        val order = catalog.tracks.sortedBy { it.albumOrder }
        assertEquals(listOf("a", "b", "d", "c"), order.map { it.nativeId })
        // A 0 from the server means it does not know.
        assertNull(order[2].trackNo)
        assertNull(order[2].discNo)
    }

    @Test
    fun aSongWhoseAlbumWasNotListedStillGetsOne() {
        val late = song.copy(id = "s9", albumId = "al9", album = "Late Album", displayAlbumArtist = "Someone")
        val catalog = buildServerCatalog(source, Library(listOf(late), emptyList(), emptyList()))
        val made = catalog.albums.single()
        assertEquals("$source:al9", made.id)
        assertEquals("Late Album", made.title)
        assertEquals("Someone", made.artist)
        assertEquals(made.id, catalog.tracks.single().albumId)
        assertEquals(made.artistId, catalog.artists.single().id)
    }

    @Test
    fun aRepeatedSongIsKeptOnce() {
        val catalog = buildServerCatalog(source, Library(listOf(song, song), listOf(album), emptyList()))
        assertEquals(1, catalog.tracks.size)
    }

    @Test
    fun sourceIdNamesThePortOnlyWhenItIsNotTheUsualOne() {
        assertEquals("server:10.0.0.5:4533", serverSourceId("http://10.0.0.5:4533/".toHttpUrl()))
        assertEquals("server:music.example.com", serverSourceId("https://music.example.com/navidrome/".toHttpUrl()))
        assertEquals("server:music.example.com", serverSourceId("http://music.example.com:80/".toHttpUrl()))
        assertEquals("server:music.example.com:80", serverSourceId("https://music.example.com:80/".toHttpUrl()))
    }

    @Test
    fun datesWithAndWithoutAZone() {
        assertEquals(1_790_150_400_000, epochMs("2026-09-23T08:00:00Z"))
        assertEquals(1_790_150_400_000, epochMs("2026-09-23T10:00:00+02:00"))
        assertEquals(1_790_150_400_000, epochMs("2026-09-23T08:00:00"))
        assertNull(epochMs("yesterday"))
        assertNull(epochMs(null))
    }

    @Test
    fun keepsTheServersLoudnessAndRating() {
        val rated = song.copy(
            replayGain = SongReplayGain(trackGain = -8.4f, albumGain = -7.9f, trackPeak = 0.98f, albumPeak = 0f, baseGain = 0f, fallbackGain = -6f),
            userRating = 4,
        )
        val row = buildServerCatalog(source, Library(listOf(rated), listOf(album), emptyList())).tracks.single()
        assertEquals(-8.4f, row.trackGain)
        assertEquals(-7.9f, row.albumGain)
        assertEquals(0.98f, row.trackPeak)
        // A peak of nothing is no peak.
        assertNull(row.albumPeak)
        assertEquals(0f, row.baseGain)
        assertEquals(-6f, row.fallbackGain)
        assertEquals(4, row.rating)

        val plain = buildServerCatalog(source, Library(listOf(song), listOf(album), emptyList())).tracks.single()
        assertNull(plain.trackGain)
        assertNull(plain.rating)
    }

    // A search or a look takes music in ahead of the next full copy: what
    // the library lacks goes in, an album read whole replaces the kept one
    // (it has another song count now), and nothing it has is put in again.
    @Test
    fun takingInAddsOnlyWhatTheLibraryLacks() {
        val grown = album.copy(songCount = 2)
        val added = song.copy(id = "s2", title = "Odd Look", track = 2)
        val loose = Song(id = "s9", title = "Single", album = "Single", albumId = "al9", artist = "Kavinsky", artistId = "ar1")
        val rows = buildServerCatalog(source, Library(listOf(song, added, loose), listOf(grown), emptyList()))

        val read = rowsToTakeIn(rows, haveSongs = setOf("s1"), haveAlbums = setOf("al1", "al9"), readAlbums = setOf("al1"), haveArtists = setOf("$source:ar1"))
        assertEquals(listOf("s2", "s9"), read.tracks.map { it.nativeId }.sorted())
        // al9 is only made up from its one song, so the kept one stays.
        assertEquals(listOf("al1"), read.albums.map { it.nativeId })
        assertEquals(2, read.albums.single().songCount)
        // The kept artist is not put in again; the made-up album names its
        // artist by name.
        assertEquals(listOf("$source:artist:kavinsky"), read.artists.map { it.id })

        val fresh = rowsToTakeIn(rows, haveSongs = emptySet(), haveAlbums = emptySet(), readAlbums = emptySet(), haveArtists = emptySet())
        assertEquals(3, fresh.tracks.size)
        assertEquals(listOf("al1", "al9"), fresh.albums.map { it.nativeId }.sorted())
        assertEquals(listOf("$source:ar1", "$source:artist:kavinsky"), fresh.artists.map { it.id }.sorted())

        val nothing = rowsToTakeIn(rows, haveSongs = setOf("s1", "s2", "s9"), haveAlbums = setOf("al1", "al9"), readAlbums = emptySet(), haveArtists = setOf("$source:ar1", "$source:artist:kavinsky"))
        assertTrue(nothing.isEmpty)
    }
}
