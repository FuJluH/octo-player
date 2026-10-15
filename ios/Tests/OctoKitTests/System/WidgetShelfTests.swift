import Foundation
import Testing
@testable import OctoSystem

/// What the app leaves for the widgets, and the ids Siri names library items by.
@Suite struct WidgetShelfTests {
    func shelf() -> WidgetShelf {
        WidgetShelf(directory: FileManager.default.temporaryDirectory.appendingPathComponent("octo-shelf-" + UUID().uuidString))
    }

    func covers(_ shelf: WidgetShelf) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: shelf.directory.path)) ?? []).filter { $0.hasPrefix("cover-") }
    }

    @Test func anEmptyShelfReadsAsNothing() {
        #expect(shelf().read() == nil)
    }

    @Test func theSongAndItsCoverGoTogether() throws {
        let shelf = shelf()
        defer { try? FileManager.default.removeItem(at: shelf.directory) }
        let song = WidgetPlayback(title: "Angel", artist: "Massive Attack", isPlaying: true)
        try shelf.write(song, cover: .new(Data([1, 2, 3])), now: Date(timeIntervalSince1970: 10))
        let read = try #require(shelf.read())
        #expect(read.playback == song)
        #expect(read.writtenAt == 10)
        let url = try #require(shelf.coverURL(read))
        #expect(try Data(contentsOf: url) == Data([1, 2, 3]))
    }

    @Test func pausingKeepsTheCover() throws {
        let shelf = shelf()
        defer { try? FileManager.default.removeItem(at: shelf.directory) }
        let first = try shelf.write(WidgetPlayback(title: "Angel", artist: "Massive Attack", isPlaying: true), cover: .new(Data([7])))
        let second = try shelf.write(WidgetPlayback(title: "Angel", artist: "Massive Attack", isPlaying: false), cover: .keep)
        #expect(second.cover == first.cover)
        #expect(shelf.read()?.playback?.isPlaying == false)
        #expect(covers(shelf).count == 1)
    }

    @Test func aNewCoverTakesTheOldOneAway() throws {
        let shelf = shelf()
        defer { try? FileManager.default.removeItem(at: shelf.directory) }
        let first = try shelf.write(WidgetPlayback(title: "One", artist: nil, isPlaying: true), cover: .new(Data([1])))
        let second = try shelf.write(WidgetPlayback(title: "Two", artist: nil, isPlaying: true), cover: .new(Data([2])))
        #expect(first.cover != second.cover)
        #expect(covers(shelf) == [second.cover].compactMap { $0 })
    }

    @Test func nothingLoadedLeavesNoCover() throws {
        let shelf = shelf()
        defer { try? FileManager.default.removeItem(at: shelf.directory) }
        try shelf.write(WidgetPlayback(title: "One", artist: nil, isPlaying: true), cover: .new(Data([1])))
        let empty = try shelf.write(nil, cover: .none)
        #expect(empty.playback == nil)
        #expect(shelf.coverURL(empty) == nil)
        #expect(covers(shelf).isEmpty)
    }

    @Test func itemIdsCarryTheirKind() throws {
        let album = MusicItemRef(kind: .album, libraryId: "server:1|al-9", title: "Mezzanine", subtitle: "Massive Attack")
        #expect(album.id == "album:server:1|al-9")
        let parsed = try #require(MusicItemRef.parse(album.id))
        #expect(parsed.kind == .album)
        #expect(parsed.libraryId == "server:1|al-9")
        #expect(MusicItemRef.liked.id == "liked")
        #expect(MusicItemRef.parse("liked")?.kind == .liked)
        #expect(MusicItemRef.parse("album:") == nil)
        #expect(MusicItemRef.parse("liked:x") == nil)
        #expect(MusicItemRef.parse("station:1") == nil)
        #expect(MusicItemRef.parse("nothing") == nil)
    }

    @Test func anItemWithoutASubtitleShowsItsKind() {
        #expect(MusicItemRef(kind: .artist, libraryId: "a", title: "Drake").subtitle == "Artist")
        #expect(MusicItemRef(kind: .song, libraryId: "s", title: "Angel", subtitle: " ").subtitle == "Song")
        #expect(MusicItemRef.liked.subtitle == "Playlist")
    }

    @Test func aProfileSaysWhatItGrants() {
        let profile = Data("""
            junk<?xml version="1.0" encoding="UTF-8"?>
            <plist version="1.0"><dict><key>Entitlements</key><dict>
            <key>com.apple.developer.siri</key><true/>
            <key>get-task-allow</key><false/>
            <key>com.apple.security.application-groups</key><array><string>group.XTL-1.app.winters.octo</string></array>
            </dict></dict></plist>junk
            """.utf8)
        let grants = ProvisioningProfile.grants(profile)
        #expect(grants.contains("com.apple.developer.siri"))
        #expect(grants.contains("com.apple.security.application-groups"))
        #expect(!grants.contains("get-task-allow"))
        #expect(ProvisioningProfile.grants(nil).isEmpty)
        #expect(ProvisioningProfile.grants(Data("no plist".utf8)).isEmpty)
    }
}
