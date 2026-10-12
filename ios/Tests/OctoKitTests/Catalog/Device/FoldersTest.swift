import Foundation
import Testing
@testable import OctoKit

@Suite struct FoldersTest {
    private func file(_ id: Int64, _ folder: String?, volume: String? = nil) -> DeviceFile {
        DeviceFile(
            id: id,
            uri: "content://media/external/audio/media/\(id)",
            fileName: "\(id).flac",
            folder: folder,
            modifiedAt: 0,
            sizeBytes: 0,
            durationMs: 0,
            addedAtSeconds: 0,
            mimeType: nil,
            fallback: FileTags(),
            volume: volume
        )
    }

    @Test func topFolderIsTheFirstLevel() {
        #expect(topFolder("Music/Kavinsky/Nightcall/") == "Music")
        #expect(topFolder("Download/") == "Download")
        #expect(topFolder(nil) == "")
    }

    @Test func switchedOffFoldersAreLeftOut() {
        let files = [file(1, "Music/A/"), file(2, "WhatsApp/Media/"), file(3, "Music/")]
        #expect(files.withoutFolders(["WhatsApp"]).map(\.id) == [1, 3])
        #expect(files.withoutFolders([]).count == 3)
    }

    @Test func folderListKeepsSwitchedOffFoldersAndCounts() {
        let files = [file(1, "Music/A/"), file(2, "Music/B/"), file(3, "WhatsApp/")]
        let folders = files.folders(["WhatsApp"])
        #expect(folders.map(\.name) == ["Music", "WhatsApp"])
        #expect(folders.map(\.songs) == [2, 1])
        #expect(folders.map(\.included) == [true, false])
    }

    @Test func pathsLeaveOutTheStorageWhenThereIsOnlyOne() {
        let files = [file(1, "Music/Kavinsky/"), file(2, "Music/", volume: "external_primary")]
        #expect(files.folderPaths() == [1: ["Music", "Kavinsky"], 2: ["Music"]])
    }

    @Test func pathsStartWithTheStorageWhenThereAreSeveral() {
        let files = [file(1, "Music/", volume: "external_primary"), file(2, "Music/", volume: "1a2b-3c4d")]
        #expect(files.folderPaths() == [1: ["Internal storage", "Music"], 2: ["SD card", "Music"]])
    }

    @Test func severalCardsAreToldApartByTheirIds() {
        #expect(storageName("1a2b-3c4d", cardCount: 1) == "SD card")
        #expect(storageName("1a2b-3c4d", cardCount: 2) == "SD card 1A2B-3C4D")
        #expect(storageName(nil, cardCount: 2) == "Internal storage")
    }

    @Test func aFilesPathJoinsItsFolderAndName() {
        #expect(relativeFile("Music/Kavinsky/Nightcall/", "01 Nightcall.mp3") == "Music/Kavinsky/Nightcall/01 Nightcall.mp3")
        #expect(relativeFile("/Music/", "a.mp3") == "Music/a.mp3")
        #expect(relativeFile("", "a.mp3") == "a.mp3")
        #expect(relativeFile(nil, "a.mp3") == "a.mp3")
        #expect(file(4, "Music/A/").relativePath == "Music/A/4.flac")
        #expect([file(4, "Music/A/"), file(5, nil)].relativeFiles() == [4: "Music/A/4.flac", 5: "5.flac"])
    }

    @Test func switchingAFolderOnAndOff() {
        #expect(excludedFolders([], switching: "WhatsApp", included: false) == ["WhatsApp"])
        #expect(excludedFolders(["WhatsApp", "Download"], switching: "WhatsApp", included: true) == ["Download"])
        #expect(excludedFolders(["Download"], switching: "Music", included: true) == ["Download"])
    }

    @Test func equalCountsKeepTheOrderFound() {
        let files = [file(1, "Podcasts/"), file(2, "Music/"), file(3, "Download/"), file(4, "Music/")]
        #expect(files.folders([]).map(\.name) == ["Music", "Podcasts", "Download"])
    }
}
