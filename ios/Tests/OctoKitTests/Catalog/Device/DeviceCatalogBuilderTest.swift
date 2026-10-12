import Foundation
import Testing
@testable import OctoKit

@Suite struct DeviceCatalogBuilderTest {
    private func row(
        _ id: Int64,
        album: String? = "Album",
        title: String?? = .none,
        artist: String? = "Artist",
        albumArtist: String? = nil,
        track: Int? = nil,
        disc: Int? = nil,
        year: Int? = nil,
        fileName: String? = nil,
        folder: String? = "Music/Album/",
        compilation: Bool = false,
        mbAlbumId: String? = nil,
        genres: [String] = [],
        tags: FileTags = FileTags()
    ) -> DeviceRow {
        DeviceRow(
            id: id,
            uri: "content://media/external/audio/media/\(id)",
            fileName: fileName ?? "Song \(id).flac",
            folder: folder,
            title: title ?? "Song \(id)",
            artist: artist,
            albumArtist: albumArtist,
            album: album,
            track: track,
            disc: disc,
            year: year,
            compilation: compilation,
            mbAlbumId: mbAlbumId,
            genres: genres,
            durationMs: 180_000,
            addedAtSeconds: 1_700_000_000 + id,
            mimeType: "audio/flac",
            sizeBytes: 30_000_000,
            tags: tags
        )
    }

    private func byAlbumOrder(_ catalog: DeviceCatalog) -> [SourceTrack] {
        catalog.tracks.enumerated().sorted { ($0.element.albumOrder, $0.offset) < ($1.element.albumOrder, $1.offset) }
            .map(\.element)
    }

    private func byId(_ catalog: DeviceCatalog) -> [SourceTrack] {
        catalog.tracks.enumerated().sorted { ($0.element.id, $0.offset) < ($1.element.id, $1.offset) }.map(\.element)
    }

    @Test func sameAlbumInTwoFoldersIsOneAlbum() throws {
        let catalog = buildDeviceCatalog([
            row(1, album: "#1 Hits of Garth Brooks", folder: "Music/A/"),
            row(2, album: "#1 Hits of Garth Brooks", folder: "Music/B/"),
        ])
        #expect(catalog.albums.count == 1)
        #expect(try #require(catalog.albums.first).songCount == 2)
    }

    @Test func sameNameSplitsWhenEveryTrackNamesItsAlbumArtist() {
        let catalog = buildDeviceCatalog([
            row(1, album: "Greatest Hits", albumArtist: "Queen"),
            row(2, album: "Greatest Hits", albumArtist: "ABBA"),
        ])
        #expect(catalog.albums.count == 2)
    }

    @Test func partlyTaggedSameNameStaysTogether() throws {
        let catalog = buildDeviceCatalog([row(1, album: "X", albumArtist: "Queen"), row(2, album: "X", albumArtist: nil)])
        #expect(catalog.albums.count == 1)
        #expect(try #require(catalog.albums.first).artist == "Queen")
    }

    @Test func releaseIdsSplitOnlyWithFullCoverage() {
        let full = buildDeviceCatalog([row(1, mbAlbumId: "a"), row(2, mbAlbumId: "b")])
        #expect(full.albums.count == 2)
        let partial = buildDeviceCatalog([row(1, mbAlbumId: "a"), row(2)])
        #expect(partial.albums.count == 1)
    }

    @Test func albumArtistKeepsFeaturedTracksTogether() throws {
        let catalog = buildDeviceCatalog([
            row(1, artist: "Kavinsky", albumArtist: "Kavinsky"),
            row(2, artist: "Kavinsky feat. Angèle", albumArtist: "Kavinsky"),
        ])
        #expect(catalog.artists.count == 1)
        #expect(try #require(catalog.artists.first).name == "Kavinsky")
    }

    @Test func withoutAlbumArtistMostCommonArtistWins() throws {
        let catalog = buildDeviceCatalog([row(1, artist: "A"), row(2, artist: "A"), row(3, artist: "B")])
        #expect(catalog.albums.count == 1)
        #expect(try #require(catalog.albums.first).artist == "A")
    }

    @Test func compilationWithoutAlbumArtistIsVariousArtists() throws {
        let catalog = buildDeviceCatalog([row(1, artist: "A", compilation: true), row(2, artist: "B")])
        #expect(catalog.albums.count == 1)
        #expect(try #require(catalog.albums.first).artist == "Various Artists")
    }

    @Test func tagTrackNumbersOrderTheAlbum() {
        let catalog = buildDeviceCatalog([row(1, title: "b", track: 2), row(2, title: "a", track: 1)])
        #expect(byAlbumOrder(catalog).map(\.title) == ["a", "b"])
    }

    @Test func fileNameNumbersOrderAnUntaggedAlbum() {
        let catalog = buildDeviceCatalog([
            row(1, title: "Zed", fileName: "02 - Zed.flac"),
            row(2, title: "Alpha", fileName: "01. Alpha.flac"),
        ])
        let ordered = byAlbumOrder(catalog)
        #expect(ordered.map(\.title) == ["Alpha", "Zed"])
        #expect(ordered.map(\.trackNo) == [1, 2])
    }

    @Test func artistNamesThatStartWithNumbersAreNotTrackNumbers() {
        let catalog = buildDeviceCatalog([
            row(1, title: "In Da Club", fileName: "50 Cent - In Da Club.flac"),
            row(2, title: "Candy Shop", fileName: "50 Cent - Candy Shop.flac"),
        ])
        #expect(catalog.tracks.allSatisfy { $0.trackNo == nil })
        #expect(byAlbumOrder(catalog).map(\.title) == ["Candy Shop", "In Da Club"])
    }

    @Test func missingTagsFallBackToFileAndFolderNames() throws {
        let catalog = buildDeviceCatalog([
            row(1, album: nil, title: .some(nil), artist: nil, fileName: "Intro.flac", folder: "Music/Live Tapes/"),
        ])
        #expect(catalog.tracks.count == 1)
        #expect(try #require(catalog.tracks.first).title == "Intro")
        #expect(try #require(catalog.albums.first).title == "Live Tapes")
        #expect(try #require(catalog.artists.first).name == "Unknown artist")
    }

    @Test func albumYearIsTheLatestTrackYear() throws {
        let catalog = buildDeviceCatalog([row(1, year: 2001), row(2, year: 2003), row(3, year: nil)])
        #expect(try #require(catalog.albums.first).year == 2003)
    }

    @Test func idsAreStableAcrossScans() throws {
        let first = buildDeviceCatalog([row(42, album: "Nightcall", albumArtist: "Kavinsky")])
        let second = buildDeviceCatalog([row(42, album: "Nightcall", albumArtist: "Kavinsky")])
        #expect(try #require(first.tracks.first).id == "device:42")
        #expect(try #require(first.albums.first).id == second.albums.first?.id)
        #expect(try #require(first.albums.first).id.hasPrefix("device:album:"))
    }

    @Test func albumSearchKeyHoldsTitleAndArtist() throws {
        let catalog = buildDeviceCatalog([row(1, album: "Nightcall", albumArtist: "Kavinsky")])
        #expect(try #require(catalog.albums.first).searchKey == "nightcall kavinsky")
    }

    @Test func songsTakeTheirFirstGenre() {
        let catalog = buildDeviceCatalog([row(1, genres: ["Synthwave", "Electronic"]), row(2)])
        #expect(byId(catalog).map(\.genre) == ["Synthwave", ""])
    }

    @Test func genreSpellingsMergeToTheMostCommon() {
        let catalog = buildDeviceCatalog([
            row(1, genres: ["hip-hop"]),
            row(2, genres: ["Hip-Hop"]),
            row(3, genres: ["Hip-Hop"]),
            row(4, genres: ["Pop", "HIP-HOP"]),
        ])
        #expect(byId(catalog).map(\.genre) == ["Hip-Hop", "Hip-Hop", "Hip-Hop", "Pop"])
    }

    @Test func everyDetailOfTheFileReachesItsRow() throws {
        let tags = FileTags(
            originalYear: 1977, artists: ["A", "B"], composer: "C", bpm: 120, comment: "note", explicit: true,
            discTitle: "Side B", mbRecordingId: "rec", mbReleaseGroupId: "grp", mbArtistIds: ["x", "y"],
            trackGain: -6, albumGain: -7, trackPeak: 0.9, albumPeak: 1
        )
        let catalog = buildDeviceCatalog([row(1, year: 2017, mbAlbumId: "rel", genres: ["Rock", "Pop"], tags: tags)])
        #expect(catalog.tracks.count == 1)
        let track = try #require(catalog.tracks.first)
        // The row keeps this edition's year; the library shows the original.
        #expect(track.year == 2017)
        #expect(track.originalYear == 1977)
        #expect(track.genres == "Rock\nPop")
        #expect(track.artists == "A\nB")
        #expect(track.composer == "C")
        #expect(track.bpm == 120)
        #expect(track.comment == "note")
        #expect(track.explicit == true)
        #expect(track.discTitle == "Side B")
        #expect(track.mbRecordingId == "rec")
        #expect(track.mbAlbumId == "rel")
        #expect(track.mbReleaseGroupId == "grp")
        #expect(track.mbArtistIds == "x\ny")
        #expect(track.trackGain == -6)
        #expect(track.albumPeak == 1)
    }

    @Test func anAlbumShowsItsOriginalYear() throws {
        let original = buildDeviceCatalog([row(1, year: 2017, tags: FileTags(originalYear: 1977))])
        #expect(try #require(original.albums.first).year == 1977)
    }

    @Test func sortTagsFileTitlesAlbumsAndArtists() throws {
        let catalog = buildDeviceCatalog([
            row(1, album: "The Album", title: "The Song", albumArtist: "The Band",
                tags: FileTags(sortTitle: "Song, The", sortAlbum: "Album, The", sortAlbumArtist: "Band, The")),
        ])
        #expect(try #require(catalog.tracks.first).sortKey == "song, the")
        #expect(try #require(catalog.albums.first).sortKey == "album, the")
        #expect(try #require(catalog.artists.first).sortKey == "band, the")
        // Without sort tags the names file as before.
        let plain = buildDeviceCatalog([row(1, album: "The Album", title: "The Song", albumArtist: "The Band")])
        #expect(try #require(plain.tracks.first).sortKey == "song")
        #expect(try #require(plain.artists.first).sortKey == "band")
    }

    @Test func idsArtworkAndKeysFollowTheirForms() throws {
        let catalog = buildDeviceCatalog([row(7, album: "Nightcall", albumArtist: "Kavinsky", track: 1)])
        let album = try #require(catalog.albums.first)
        let nativeId = Hashes.hex(Hashes.sha1(Array("nightcall|by:kavinsky".utf8)).prefix(8))
        #expect(album.nativeId == nativeId)
        #expect(album.id == "device:album:\(nativeId)")
        #expect(album.sourceId == "device")
        #expect(album.artistId == "device:artist:kavinsky")
        let artwork = ArtworkRef.device(key: "album:device:album:\(nativeId)", uri: "content://media/external/audio/media/7")
        #expect(album.artwork == artwork.encode())
        let track = try #require(catalog.tracks.first)
        #expect(track.nativeId == "7")
        #expect(track.sourceId == "device")
        #expect(track.artwork == album.artwork)
        #expect(track.uri == "content://media/external/audio/media/7")
        #expect(track.relinkKey == relinkKey(albumArtist: "Kavinsky", album: "Nightcall", disc: nil, track: 1, title: "Song 7",
                                             durationMs: 180_000))
        let artist = try #require(catalog.artists.first)
        #expect(artist.id == "device:artist:kavinsky")
        #expect(artist.albumCount == 1)
        #expect(artist.songCount == 1)
        #expect(artist.artwork == album.artwork)
    }

    @Test func discsComeBeforeTrackNumbers() {
        let catalog = buildDeviceCatalog([
            row(1, title: "Two-one", track: 1, disc: 2),
            row(2, title: "One-two", track: 2, disc: nil),
            row(3, title: "One-one", track: 1, disc: 1),
        ])
        #expect(byAlbumOrder(catalog).map(\.title) == ["One-one", "One-two", "Two-one"])
    }
}
