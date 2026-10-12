import Foundation
import Testing
@testable import OctoKit

/// Keeping the phone's music in step: which files are read again, which saved tags are
/// forgotten, access, and one whole scan.
@Suite struct DeviceLibraryTest {
    private func file(_ id: Int64, _ folder: String? = "Music/Album/", modified: Int64 = 100, size: Int64 = 200,
                      fallback: FileTags = FileTags()) -> DeviceFile {
        DeviceFile(id: id, uri: "ipod-library://item/item.mp3?id=\(id)", fileName: "Song \(id).mp3", folder: folder,
                   modifiedAt: modified, sizeBytes: size, durationMs: 180_000, addedAtSeconds: 1_700_000_000 + id,
                   mimeType: "audio/mpeg", fallback: fallback)
    }

    private func saved(_ id: Int64, modified: Int64 = 100, size: Int64 = 200, tags: FileTags? = FileTags(title: "T"),
                       version: Int = deviceTagsVersion) -> FileTagsRow {
        savedTags(mediaId: id, modifiedAt: modified, size: size, tags: tags, version: version)
    }

    @Test func onlyNewOrChangedFilesAreReadAgain() {
        #expect(deviceTagsVersion == 2)
        #expect(needsTagRead(nil, file(1)))
        #expect(!needsTagRead(saved(1), file(1)))
        #expect(needsTagRead(saved(1, modified: 99), file(1)))
        #expect(needsTagRead(saved(1, size: 199), file(1)))
        // Rows from another way of reading tags are read again, older or newer.
        #expect(needsTagRead(saved(1, version: 1), file(1)))
        #expect(needsTagRead(saved(1, version: 0), file(1)))
        #expect(needsTagRead(saved(1, version: 3), file(1)))
        // A file that could not be read is not tried again until it changes.
        #expect(!needsTagRead(saved(1, tags: nil), file(1)))
    }

    @Test func aRefreshReadsTheStaleAndForgetsTheGone() {
        let files = [file(1), file(2, modified: 150), file(3)]
        let plan = tagRefreshPlan(files, saved: [saved(9), saved(1), saved(2)])
        #expect(plan.toRead.map(\.id) == [2, 3])
        #expect(plan.forget == [9])
        // Files in switched-off folders keep their tags too.
        #expect(tagRefreshPlan([file(1, "WhatsApp/")], saved: [saved(1)]) == TagRefreshPlan(toRead: [], forget: []))
    }

    @Test func readsAreSplitForFourReaders() {
        #expect(deviceTagReaders == 4)
        let ten = (1...10).map { file(Int64($0)) }
        #expect(tagReadBatches(ten).map { $0.map(\.id) } == [[1, 2, 3], [4, 5, 6], [7, 8, 9], [10]])
        #expect(tagReadBatches(Array(ten.prefix(3))).map { $0.map(\.id) } == [[1, 2], [3]])
        #expect(tagReadBatches(Array(ten.prefix(1))).map { $0.map(\.id) } == [[1]])
        #expect(tagReadBatches([]).isEmpty)
    }

    @Test func theKnownTagsAreTheSavedWithTheFreshOverThem() {
        let known = knownTags(
            saved: [saved(1, tags: FileTags(title: "One")), saved(2, tags: FileTags(title: "Two")), saved(9)],
            fresh: [saved(2, tags: nil), saved(3, tags: FileTags(title: "Three"))],
            forget: [9]
        )
        // A file that could no longer be read falls back to the media library's reading.
        #expect(known == [1: FileTags(title: "One"), 3: FileTags(title: "Three")])
    }

    @Test func accessFollowsTheAnswer() {
        #expect(accessAfterAsking(granted: true, canAskAgain: false) == .granted)
        #expect(accessAfterAsking(granted: false, canAskAgain: true) == .denied)
        #expect(accessAfterAsking(granted: false, canAskAgain: false) == .deniedForever)
    }

    @Test func accessCanChangeWhileTheAppIsAway() {
        #expect(accessOnReturn(.notAsked, grantedNow: true) == .granted)
        #expect(accessOnReturn(.deniedForever, grantedNow: true) == .granted)
        #expect(accessOnReturn(.granted, grantedNow: false) == .notAsked)
        #expect(accessOnReturn(.denied, grantedNow: false) == .denied)
        #expect(accessOnReturn(.deniedForever, grantedNow: false) == .deniedForever)
        #expect(accessOnReturn(.granted, grantedNow: true) == .granted)
        #expect(deviceRescanQuietMs == 2_000)
    }

    @Test func aScanLeavesOutSwitchedOffFoldersButListsThem() throws {
        let files = [
            file(1, "Music/Kavinsky/", fallback: FileTags(title: "Library title", album: "Nightcall")),
            file(2, "Music/Kavinsky/", fallback: FileTags(album: "Nightcall")),
            file(3, "WhatsApp/Audio/", fallback: FileTags(album: "Voice notes")),
        ]
        let scan = deviceScan(files, tags: [1: FileTags(title: "Nightcall", artist: "Kavinsky")], excluded: ["WhatsApp"])
        #expect(scan.folders == [MusicFolder("Music", songs: 2, included: true),
                                 MusicFolder("WhatsApp", songs: 1, included: false)])
        #expect(scan.catalog.tracks.map(\.id).sorted() == ["device:1", "device:2"])
        #expect(scan.catalog.albums.map(\.title) == ["Nightcall"])
        #expect(scan.catalog.tracks.first { $0.id == "device:1" }?.title == "Nightcall")
        #expect(scan.catalog.tracks.first { $0.id == "device:2" }?.title == "Song 2")
        #expect(scan.paths == [1: ["Music", "Kavinsky"], 2: ["Music", "Kavinsky"]])
        #expect(scan.files == [1: "Music/Kavinsky/Song 1.mp3", 2: "Music/Kavinsky/Song 2.mp3"])
    }
}
