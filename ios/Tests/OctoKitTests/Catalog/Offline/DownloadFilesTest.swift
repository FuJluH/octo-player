import Foundation
import Testing
@testable import OctoKit

@Suite struct DownloadFilesTest {
    let source = "server:music.example"

    @Test func aNameReadsAsArtistAndTitle() {
        let name = downloadFileName(artist: "Drake", title: "Hotline Bling", sourceId: source, serverId: "tr-1", format: "audio/flac")
        #expect(name.wholeMatch(of: /Drake - Hotline Bling \[[0-9a-f]{8}\]\.flac/) != nil, "\(name)")
    }

    @Test func charactersNoFileSystemTakesAreLeftOut() {
        let name = downloadFileName(artist: "AC/DC", title: "What? <Live>: \"Take\" 1|2*\\", sourceId: source, serverId: "tr-2",
                                    format: "audio/mpeg")
        let stem = name.before(" [")
        #expect(!stem.contains { "\\/:*?\"<>|".contains($0) }, "\(name)")
        #expect(stem.replacing(/\s+/, with: " ") == "AC DC - What Live Take 1 2")
        #expect(name.hasSuffix(".mp3"))
    }

    @Test func controlCharactersAndDotsAtTheEndsGo() {
        let name = downloadFileName(artist: "  ..Band\u{0000}\n", title: "Song...", sourceId: source, serverId: "tr-3", format: nil)
        #expect(name.hasPrefix("Band - Song ["), "\(name)")
        #expect(name.hasSuffix(".audio"))
    }

    @Test func songsWithTheSameNameNeverShareAFile() {
        let one = downloadFileName(artist: "Artist", title: "Intro", sourceId: source, serverId: "tr-1", format: "audio/flac")
        let two = downloadFileName(artist: "Artist", title: "Intro", sourceId: source, serverId: "tr-2", format: "audio/flac")
        let other = downloadFileName(artist: "Artist", title: "Intro", sourceId: "server:other.example", serverId: "tr-1",
                                     format: "audio/flac")
        #expect(one != two)
        #expect(one != other)
        // And the same song always has the same name.
        #expect(one == downloadFileName(artist: "Artist", title: "Intro", sourceId: source, serverId: "tr-1", format: "audio/flac"))
    }

    @Test func longNamesAreCutAndEmptyOnesStillName() {
        let long = downloadFileName(artist: String(repeating: "A", count: 200), title: String(repeating: "B", count: 200),
                                    sourceId: source, serverId: "tr-9", format: "audio/ogg")
        #expect(long.utf16.count <= 80 + " [12345678].ogg".utf16.count)
        #expect(downloadFileName(artist: "", title: "", sourceId: source, serverId: "tr-0", format: "audio/opus").hasPrefix("Song ["))
    }

    @Test func theEndingFollowsTheType() {
        #expect(downloadExtension(for: "audio/mpeg") == "mp3")
        #expect(downloadExtension(for: "audio/x-flac") == "flac")
        #expect(downloadExtension(for: "audio/mp4") == "m4a")
        #expect(downloadExtension(for: "audio/opus") == "opus")
        #expect(downloadExtension(for: "AUDIO/OGG; codecs=vorbis") == "ogg")
        #expect(downloadExtension(for: "application/octet-stream") == "audio")
    }

    @Test func theBracketsHoldTheFirstFourBytesOfTheSha1() {
        let name = downloadFileName(artist: "Artist", title: "Intro", sourceId: source, serverId: "tr-1", format: "audio/flac")
        let hash = String(Hashes.sha1Hex("\(source)|tr-1").prefix(8))
        #expect(name == "Artist - Intro [\(hash)].flac")
    }

    @Test func aCutNameLosesTheDotsAndDashesAtItsEnd() {
        // The cut lands right after " - ", which goes with it.
        let artist = String(repeating: "A", count: 77)
        let name = downloadFileName(artist: artist, title: "Title", sourceId: source, serverId: "tr-1", format: "audio/flac")
        #expect(name.before(" [") == artist)
    }
}
