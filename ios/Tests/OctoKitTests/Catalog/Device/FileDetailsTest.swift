import Foundation
import Testing
@testable import OctoKit

/// When a phone file counts as added, and a file's tags surviving the trip to the database and
/// back.
@Suite struct FileDetailsTest {
    let now: Int64 = 1_790_000_000 // September 2026

    @Test func aCopiedLibraryKeepsItsFilesOwnDates() {
        // A file from 2020 copied onto the phone in September 2026.
        #expect(fileAddedAt(modifiedSeconds: 1_583_485_817, addedSeconds: 1_789_693_267, takenMs: nil, nowSeconds: now)
            == 1_583_485_817)
    }

    @Test func aFileEditedAfterArrivingKeepsItsArrivalDate() {
        #expect(fileAddedAt(modifiedSeconds: 1_750_000_000, addedSeconds: 1_700_000_000, takenMs: nil, nowSeconds: now)
            == 1_700_000_000)
    }

    @Test func aTakenDateCountsWhenAPhoneSetsOne() {
        #expect(fileAddedAt(modifiedSeconds: 1_600_000_000, addedSeconds: 1_700_000_000, takenMs: 1_500_000_000_000,
                            nowSeconds: now) == 1_500_000_000)
    }

    @Test func brokenClocksArePassedOver() {
        // Unset (1970), before 1990, and far in the future.
        #expect(fileAddedAt(modifiedSeconds: 0, addedSeconds: 1_700_000_000, takenMs: nil, nowSeconds: now) == 1_700_000_000)
        #expect(fileAddedAt(modifiedSeconds: 86_400, addedSeconds: 1_700_000_000, takenMs: nil, nowSeconds: now)
            == 1_700_000_000)
        #expect(fileAddedAt(modifiedSeconds: now + 30 * 86_400, addedSeconds: 1_700_000_000, takenMs: nil, nowSeconds: now)
            == 1_700_000_000)
        #expect(fileAddedAt(modifiedSeconds: 1_600_000_000, addedSeconds: 1_700_000_000, takenMs: 0, nowSeconds: now)
            == 1_600_000_000)
    }

    @Test func withNoRealTimeThePhonesOwnIsKept() {
        #expect(fileAddedAt(modifiedSeconds: 0, addedSeconds: 5, takenMs: nil, nowSeconds: now) == 5)
        #expect(fileAddedAt(modifiedSeconds: 0, addedSeconds: -1, takenMs: nil, nowSeconds: now) == 0)
    }

    @Test func everyTagSurvivesBeingKept() {
        let tags = FileTags(
            title: "T", artist: "A feat. B", albumArtist: "A", album: "L", trackNo: 3, discNo: 2, year: 2017,
            compilation: true, mbAlbumId: "r", genres: ["Rock", "Pop"], originalYear: 1977,
            artists: ["A", "B"], composer: "C", bpm: 120, comment: "note", explicit: false,
            discTitle: "Side B", mbRecordingId: "rec", mbReleaseGroupId: "grp", mbArtistIds: ["x", "y"],
            sortTitle: "T, The", sortAlbum: "L, The", sortAlbumArtist: "A, The",
            trackGain: -6.5, albumGain: -7, trackPeak: 0.9, albumPeak: 1
        )
        let saved = savedTags(mediaId: 7, modifiedAt: 100, size: 200, tags: tags, version: 2)
        #expect(saved.toTags() == tags)
        #expect(saved.tagsVersion == 2)
        #expect(saved.readOk == true)
        // Every field of FileTags is kept, so a new one cannot be forgotten here.
        #expect(Mirror(reflecting: FileTags()).children.count == 27)
    }

    @Test func aFileThatCouldNotBeReadIsKeptAsUnread() {
        let saved = savedTags(mediaId: 7, modifiedAt: 100, size: 200, tags: nil, version: 2)
        #expect(saved.readOk == false)
        #expect(saved.toTags() == FileTags())
    }
}
