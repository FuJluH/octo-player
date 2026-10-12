import Foundation
import Testing
@testable import OctoKit

/// One media library file as a plain record, and its row with the best tags known.
@Suite struct DeviceRowTest {
    private func file(fallback: FileTags) -> DeviceFile {
        DeviceFile(id: 9, uri: "ipod-library://item/item.m4a?id=9", fileName: "09 Song.m4a", folder: "Music/Album/",
                   modifiedAt: 1_600_000_000, sizeBytes: 8_000_000, durationMs: 200_000, addedAtSeconds: 1_600_000_000,
                   mimeType: "audio/mp4", fallback: fallback)
    }

    @Test func theLibrarysUnknownArtistAndBlanksAreDropped() {
        let tags = libraryTags(title: "  ", artist: "<unknown>", albumArtist: "", album: " ", track: nil, disc: nil, year: nil,
                               genre: nil)
        #expect(tags == FileTags())
        #expect(libraryTags(title: "T", artist: "A", albumArtist: "B", album: "L", track: nil, disc: nil, year: nil, genre: nil)
            == FileTags(title: "T", artist: "A", albumArtist: "B", album: "L"))
    }

    @Test func aDiscPackedIntoTheTrackIsTakenApart() {
        func split(_ track: Int?, _ disc: Int? = nil) -> [Int?] {
            let tags = libraryTags(title: nil, artist: nil, albumArtist: nil, album: nil, track: track, disc: disc, year: nil,
                                   genre: nil)
            return [tags.discNo, tags.trackNo]
        }
        #expect(split(2003) == [2, 3])
        #expect(split(7) == [nil, 7])
        #expect(split(2003, 1) == [1, 3])
        #expect(split(1000) == [1, nil])
        #expect(split(0) == [nil, nil])
        #expect(split(5, 0) == [nil, 5])
        #expect(split(nil, 2) == [2, nil])
    }

    @Test func zeroYearsAndGenreListsAreRead() {
        let none = libraryTags(title: nil, artist: nil, albumArtist: nil, album: nil, track: nil, disc: nil, year: 0, genre: nil)
        #expect(none.year == nil)
        #expect(none.genres == [])
        let some = libraryTags(title: nil, artist: nil, albumArtist: nil, album: nil, track: nil, disc: nil, year: 1999,
                               genre: "Rock; Pop")
        #expect(some.year == 1999)
        #expect(some.genres == ["Rock", "Pop"])
    }

    @Test func aScannedFileKeepsItsOwnDatesAndTheLibrarysReading() {
        let scanned = DeviceFile.scanned(
            id: 4, uri: "ipod-library://item/item.mp3?id=4", fileName: "04 Nightcall.mp3", folder: "Music/Kavinsky/",
            modifiedSeconds: 1_583_485_817, sizeBytes: 9_000_000, durationMs: 258_000, addedSeconds: 1_789_693_267,
            nowSeconds: 1_790_000_000, mimeType: "audio/mpeg", title: "Nightcall", artist: "<unknown>", track: 1004
        )
        #expect(scanned.addedAtSeconds == 1_583_485_817)
        #expect(scanned.modifiedAt == 1_583_485_817)
        #expect(scanned.fallback == FileTags(title: "Nightcall", trackNo: 4, discNo: 1))
        #expect(scanned.relativePath == "Music/Kavinsky/04 Nightcall.mp3")
    }

    @Test func theFilesOwnTagsWinOverTheLibrarys() {
        let fallback = FileTags(title: "Lib title", artist: "Lib artist", albumArtist: "Lib band", album: "Lib album", trackNo: 1,
                                discNo: 1, year: 1990, genres: ["Lib genre"])
        let own = FileTags(title: "Own title", artist: "Own artist", albumArtist: "Own band", album: "Own album", trackNo: 2,
                           discNo: 2, year: 2001, compilation: true, mbAlbumId: "rel", genres: ["Own genre"], bpm: 120)
        let row = file(fallback: fallback).toRow(own)
        #expect(row.title == "Own title")
        #expect(row.artist == "Own artist")
        #expect(row.albumArtist == "Own band")
        #expect(row.album == "Own album")
        #expect(row.track == 2)
        #expect(row.disc == 2)
        #expect(row.year == 2001)
        #expect(row.compilation)
        #expect(row.mbAlbumId == "rel")
        #expect(row.genres == ["Own genre"])
        #expect(row.tags == own)
        #expect(row.id == 9)
        #expect(row.uri == "ipod-library://item/item.m4a?id=9")
        #expect(row.fileName == "09 Song.m4a")
        #expect(row.folder == "Music/Album/")
        #expect(row.durationMs == 200_000)
        #expect(row.addedAtSeconds == 1_600_000_000)
        #expect(row.mimeType == "audio/mp4")
        #expect(row.sizeBytes == 8_000_000)
    }

    @Test func theLibrarysReadingFillsWhatTheFileDidNotSay() {
        let fallback = FileTags(title: "Lib title", artist: "Lib artist", albumArtist: "Lib band", album: "Lib album", trackNo: 1,
                                discNo: 1, year: 1990, compilation: true, mbAlbumId: "lib", genres: ["Lib genre"])
        let partial = file(fallback: fallback).toRow(FileTags(title: "Own title"))
        #expect(partial.title == "Own title")
        #expect(partial.artist == "Lib artist")
        #expect(partial.albumArtist == "Lib band")
        #expect(partial.album == "Lib album")
        #expect(partial.track == 1)
        #expect(partial.disc == 1)
        #expect(partial.year == 1990)
        #expect(partial.genres == ["Lib genre"])
        // Only the file says whether it is a compilation or which release it is from.
        #expect(!partial.compilation)
        #expect(partial.mbAlbumId == nil)

        let unread = file(fallback: fallback).toRow(nil)
        #expect(unread.title == "Lib title")
        #expect(unread.genres == ["Lib genre"])
        #expect(!unread.compilation)
        #expect(unread.tags == FileTags())
    }
}
