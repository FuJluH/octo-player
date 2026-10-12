import Foundation
import Testing
@testable import OctoKit

/// Rows for the phone health tests.
enum HealthRows {
    static let server = "server:home"

    static func copy(_ id: String, _ title: String, merged: String? = nil, source: String = server, seconds: Int64 = 200,
                     mime: String = "audio/flac", bitrate: Int? = 900, depth: Int? = 16, rate: Int? = 44_100, album: String = "Album",
                     genre: String = "Rock", mbid: String? = nil, releaseGroup: String? = nil) -> SourceTrack {
        SourceTrack(id: "\(source)/\(id)", sourceId: source, nativeId: id, title: title, searchKey: title.lowercased(),
                    sortKey: title.lowercased(), artist: "Artist", artistId: "ar", album: album, albumId: "al-\(album)", trackNo: 1,
                    discNo: 1, year: 2020, durationMs: seconds * 1_000, addedAt: 0, mimeType: mime, artwork: "art", genre: genre,
                    bitrate: bitrate, sampleRate: rate, bitDepth: depth, mergedId: merged ?? id, mbRecordingId: mbid,
                    mbReleaseGroupId: releaseGroup)
    }

    static func track(_ id: String, _ title: String, artist: String = "Artist", album: String = "Album", albumId: String? = nil,
                      seconds: Int64 = 200, genre: String = "Rock", year: Int? = 2020, trackNo: Int? = 1, artwork: String? = "art",
                      source: String = server) -> LibraryTrack {
        LibraryTrack(id: id, sourceId: source, nativeId: id, title: title, searchKey: title.lowercased(), sortKey: title.lowercased(),
                     artist: artist, artistId: "ar", album: album, albumId: albumId ?? "al-\(album)", trackNo: trackNo, discNo: 1,
                     year: year, durationMs: seconds * 1_000, addedAt: 0, mimeType: "audio/flac", artwork: artwork, genre: genre)
    }

    static func album(_ id: String, _ title: String, artist: String = "Artist") -> LibraryAlbum {
        LibraryAlbum(id: id, sourceId: server, nativeId: id, title: title, searchKey: title.lowercased(), sortKey: title.lowercased(),
                     artist: artist, artistId: "ar", year: 2020, songCount: 1, durationMs: 0, addedAt: 0)
    }
}

/// Library health on the phone: copies found among a source's own, the rest on the library as the
/// phone shows it, and the lines the pages draw.
@Suite struct PhoneHealthTests {
    typealias R = HealthRows

    @Test func twoFilesOfOneSongOnTheServerAreCopiesTheBestFirst() throws {
        let tracks = [R.track("t1", "Holocene", album: "Bon Iver"), R.track("t2", "Holocene", album: "Holocene")]
        let copies = [
            R.copy("mp3", "Holocene", merged: "t2", mime: "audio/mpeg", bitrate: 320, depth: nil, album: "Holocene"),
            R.copy("flac", "Holocene", merged: "t1", album: "Bon Iver"),
        ]
        let health = phoneHealth(tracks, albums: [], copies: copies)
        let group = try #require(health.report.duplicates.first)
        #expect(health.report.duplicates.count == 1)
        #expect(group.copies.map(\.id) == ["t1", "t2"])
        #expect(group.bestReason == .sound)
        let lines = health.lines(.duplicates)
        #expect(lines[0] == .heading(title: "Holocene by Artist",
                                     detail: "2 copies. Same title, artist and length. Keep the first, FLAC, 16-bit, 44.1 kHz."))
        if case .song(_, let note) = lines[1] { #expect(note == "FLAC, 16-bit, 44.1 kHz • Bon Iver") } else { Issue.record("not a song") }
        if case .song(_, let note) = lines[2] { #expect(note == "MP3, 320 kbps • Holocene") } else { Issue.record("not a song") }
        #expect(health.songs(.duplicates).map(\.id) == ["t1", "t2"])
    }

    @Test func theSongOnThePhoneAndOnTheServerIsNotACopy() {
        // Joined into one library song, or kept as two, it is never a copy.
        let joined = [R.copy("p", "Holocene", merged: "t1", source: "device"), R.copy("s", "Holocene", merged: "t1")]
        let apart = [R.copy("p", "Holocene", merged: "tp", source: "device"), R.copy("s", "Holocene", merged: "ts")]
        #expect(phoneHealth([R.track("t1", "Holocene")], albums: [], copies: joined).report.duplicates.isEmpty)
        #expect(phoneHealth([R.track("tp", "Holocene", source: "device"), R.track("ts", "Holocene")], albums: [], copies: apart)
            .report.duplicates.isEmpty)
    }

    @Test func aSharedMusicBrainzRecordingIsOneRecordingOnThePhoneToo() {
        let tracks = [R.track("t1", "Teardrop"), R.track("t2", "Tear Drop")]
        let copies = [R.copy("a", "Teardrop", merged: "t1", mbid: "f200"), R.copy("b", "Tear Drop", merged: "t2", seconds: 205, mbid: "F200")]
        #expect(phoneHealth(tracks, albums: [], copies: copies).report.duplicates.count == 1)
    }

    @Test func missingTagsAreThoseThePhoneShowsAndNeverAnAlbumArtist() {
        let tracks = [
            R.track("a", "One", albumId: "x", genre: ""),
            R.track("b", "Two", albumId: "x", year: nil, trackNo: nil),
            R.track("c", "Three", albumId: "x", artwork: nil),
        ]
        let report = phoneHealth(tracks, albums: [], copies: []).report
        #expect(report.missing[.genre]?.map(\.id) == ["a"])
        #expect(report.missing[.year]?.map(\.id) == ["b"])
        #expect(report.missing[.trackNumber]?.map(\.id) == ["b"])
        #expect(report.missing[.cover]?.map(\.id) == ["c"])
        #expect(report.missing[.albumArtist] == nil)
    }

    @Test func anAlbumSplitByItsAlbumArtistSaysSo() {
        let tracks = [R.track("a", "One", album: "It Was Fun", albumId: "x"), R.track("b", "Two", album: "It Was Fun", albumId: "y")]
        let albums = [R.album("x", "It Was Fun", artist: "SueCo"), R.album("y", "It Was Fun", artist: "Sueco")]
        let health = phoneHealth(tracks, albums: albums, copies: [])
        let lines = health.lines(.splitAlbums)
        #expect(lines.first == .heading(title: "It Was Fun by SueCo, shown as 2 albums", detail: "The album artist differs: SueCo, Sueco."))
        #expect(health.songs(.splitAlbums).map(\.id) == ["a", "b"])
    }

    @Test func aTidyLibraryHasNothingToShow() {
        let tracks = [R.track("a", "One", albumId: "x"), R.track("b", "Two", albumId: "x", seconds: 180)]
        let health = phoneHealth(tracks, albums: [], copies: tracks.map { R.copy($0.id, $0.title, merged: $0.id, seconds: $0.durationMs / 1_000) })
        #expect(health.report.clean)
    }

    @Test func formatsReadFromTheirTypes() {
        #expect(formatOf("audio/flac") == "flac")
        #expect(formatOf("audio/mpeg") == "mp3")
        #expect(formatOf("audio/x-m4a") == "m4a")
        #expect(formatOf("audio/vnd.wave; codecs=1") == "wav")
        #expect(formatOf("audio/") == nil)
        #expect(formatOf(nil) == nil)
    }
}
