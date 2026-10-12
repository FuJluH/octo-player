import Foundation
import Testing
@testable import OctoKit

@Suite struct PhoneFilesTest {
    private func copy(_ id: String, _ source: String, _ song: String, _ uri: String?, _ mime: String? = "audio/mpeg") -> SourceTrack {
        SourceTrack(
            id: id, sourceId: source, nativeId: id, title: "Midnight City", searchKey: "", sortKey: "",
            artist: "M83", artistId: "", album: "Hurry Up, We're Dreaming", albumId: "", trackNo: nil, discNo: nil, year: nil,
            durationMs: 244_000, addedAt: 0, mimeType: mime, sizeBytes: nil, artwork: nil, uri: uri,
            albumOrder: 0, relinkKey: "", genre: "", mergedId: song
        )
    }

    var phoneA: SourceTrack { copy("device:1", deviceSource, "a", "content://media/external/audio/media/1") }
    var phoneA2: SourceTrack { copy("device:2", deviceSource, "a", "content://media/external/audio/media/2", "audio/flac") }
    var serverA: SourceTrack { copy("server:x:9", "server:x", "a", "https://music.example/rest/stream?id=9") }
    var phoneB: SourceTrack { copy("device:3", deviceSource, "b", "content://media/external/audio/media/3", "audio/flac") }
    var serverC: SourceTrack { copy("server:x:10", "server:x", "c", nil) }

    @Test func onlyThePhonesOwnFilesCount() {
        let files = phoneFiles([phoneA, serverA, phoneB, serverC])
        #expect(files.map(\.uri) == ["content://media/external/audio/media/1", "content://media/external/audio/media/3"])
        #expect(files.map(\.trackId) == ["a", "b"])
        // A phone row not yet merged into a song, or with no media address, is left out.
        #expect(phoneFiles([copy("device:4", deviceSource, "", "content://media/external/audio/media/4")]) == [])
        #expect(phoneFiles([copy("device:5", deviceSource, "e", "file:///sdcard/Music/e.mp3")]) == [])
    }

    @Test func deletingTakesEveryPhoneFileOfEachSong() {
        let files = phoneFiles([phoneB, phoneA, serverA, phoneA2])
        let plan = deletePlan(["a", "b"], files)
        #expect(plan?.trackIds == ["a", "b"])
        #expect(plan?.uris == [
            "content://media/external/audio/media/1",
            "content://media/external/audio/media/2",
            "content://media/external/audio/media/3",
        ])
    }

    @Test func aSongOnlyOnAServerIsNeverDeleted() {
        let files = phoneFiles([serverA, serverC, phoneB])
        #expect(deletePlan(["c"], files) == nil)
        // Picked with a phone song, it is simply left out.
        #expect(deletePlan(["c", "b", "b"], files)?.trackIds == ["b"])
    }

    @Test func sharingSendsOneFilePerSongInTheOrderPicked() {
        let files = phoneFiles([phoneA, phoneA2, phoneB])
        #expect(filesToShare(["b", "a", "c"], files).map(\.uri)
            == ["content://media/external/audio/media/3", "content://media/external/audio/media/1"])
    }

    @Test func theShareNamesTheFilesType() {
        #expect(shareType(["audio/mpeg"]) == "audio/mpeg")
        #expect(shareType(["audio/flac", "AUDIO/FLAC"]) == "audio/flac")
        #expect(shareType(["audio/flac", "audio/mpeg"]) == "audio/*")
        #expect(shareType([nil]) == "audio/*")
        #expect(shareType(["audio/flac", nil]) == "audio/*")
        #expect(shareType(["audio/mpeg", "application/ogg"]) == "*/*")
    }

    @Test func eachSoundChoiceSetsItsOwnKind() {
        // The kinds: ringtone 1, notification 2, alarm 4.
        #expect(PhoneSound.allCases.map(\.type) == [1, 2, 4])
        #expect(PhoneSound.allCases.map(\.label) == ["Ringtone", "Notification sound", "Alarm"])
        #expect(phoneSoundAt(0) == .ringtone)
        #expect(phoneSoundAt(1) == .notification)
        #expect(phoneSoundAt(2) == .alarm)
        #expect(phoneSoundAt(3) == nil)
        #expect(phoneSoundAt(-1) == nil)
        #expect(PhoneSound.ringtone.done == "Set as your ringtone")
        #expect(PhoneSound.notification.done == "Set as your notification sound")
        #expect(PhoneSound.alarm.done == "Set as your alarm")
    }

    @Test func filesInTheAppsOwnFolderCount() {
        let own = copy("device:7", deviceSource, "g", "file:///var/mobile/Documents/Albums/g.mp3", "audio/mpeg")
        let elsewhere = copy("device:8", deviceSource, "h", "file:///var/mobile/tmp/h.mp3", "audio/mpeg")
        #expect(phoneFiles([own, elsewhere], ownFolder: "file:///var/mobile/Documents/").map(\.trackId) == ["g"])
        #expect(phoneFiles([own, elsewhere]) == [])
    }

    @Test func theIPhoneMediaLibrarysAddressesCount() {
        let phone = copy("device:6", deviceSource, "f", "ipod-library://item/item.m4a?id=6", "audio/mp4")
        #expect(phoneFiles([phone]) == [PhoneFile(trackId: "f", uri: "ipod-library://item/item.m4a?id=6", mimeType: "audio/mp4")])
    }
}
