import Foundation
import Testing
@testable import OctoKit

private func track(_ id: String, _ title: String, trackNo: Int? = nil, disc: Int? = nil) -> LibraryTrack {
    LibraryTrack(id: id, sourceId: "server:x", nativeId: id, title: title, searchKey: title.lowercased(), sortKey: title.lowercased(),
                 artist: "Radiohead", artistId: "a", album: "Amnesiac", albumId: "al", trackNo: trackNo, discNo: disc,
                 durationMs: 200_000, addedAt: 0)
}

private func sent(_ id: String, _ number: Int?, outside: Bool, disc: Int? = 1) -> Song {
    var song = Song(id: id, title: "Song \(id)", artist: "Radiohead", isExternal: outside)
    song.track = number
    song.discNumber = disc
    return song
}

@Suite struct WholeAlbumTests {
    private let two = track("t2", "Pyramid Song", trackNo: 2)
    private let six = track("t6", "Knives Out", trackNo: 6)

    @Test func songsTheServerMarksBecomeFindsNumberedAsTheAlbumNumbersThem() {
        let server = [sent("s1", 1, outside: true), sent("s2", 2, outside: false), sent("s3", 3, outside: true, disc: 2)]
        let resolved = [track("find:s1", "Song s1"), two, track("find:s3", "Song s3")]
        let out = outsideAlbumSongs(server, resolved)
        #expect(out.map(\.id) == ["find:s1", "t2", "find:s3"])
        #expect(out[0].trackNo == 1)
        #expect(out[2].discNo == 2)
    }

    @Test func anUnmarkedSongTheLibraryLacksIsLeftForTheNextCopy() {
        #expect(outsideAlbumSongs([sent("s9", 9, outside: false)], [track("find:s9", "Song s9")]).isEmpty)
    }

    @Test func theWholeAlbumKeepsTheServersOrder() {
        let server = [track("find:s1", "One", trackNo: 1), two, track("find:s3", "Three", trackNo: 3), six]
        #expect(wholeAlbum([two, six], server: server).map(\.id) == ["find:s1", "t2", "find:s3", "t6"])
    }

    @Test func withNoFindsTheAlbumIsTheLibrarysOwn() {
        #expect(wholeAlbum([two, six], server: [six, two]) == [two, six])
        #expect(wholeAlbum([two, six], server: []) == [two, six])
    }

    @Test func aFindTheLibraryTookInShowsAsItsLibrarySongInItsPlace() {
        let arrived = track("t1", "One", trackNo: 1)
        let server = [track("find:s1", "One", trackNo: 1), two, six]
        #expect(wholeAlbum([arrived, two, six], server: server, adoptions: ["find:s1": "t1"]).map(\.id) == ["t1", "t2", "t6"])
    }

    @Test func aLibrarySongTheServerDidNotListFollows() {
        let phoneOnly = track("p7", "Bonus", trackNo: 12)
        let server = [track("find:s1", "One", trackNo: 1), two]
        #expect(wholeAlbum([two, phoneOnly], server: server).map(\.id) == ["find:s1", "t2", "p7"])
    }

    @Test func aFindKeepsNoNumberTheServerDidNotGive() {
        let out = outsideAlbumSongs([sent("s1", nil, outside: true, disc: nil)], [track("find:s1", "x", trackNo: 5)])
        #expect(out.first?.trackNo == nil)
    }
}

@Suite struct BiographyTests {
    @Test func theReadMoreLinkAndTagsGo() {
        let bio = "Vincent Belorgey, known as <b>Kavinsky</b>, is a French musician. "
            + "<a target='_blank' href=\"https://www.last.fm/music/Kavinsky\" rel=\"nofollow\">Read more on Last.fm</a>"
        #expect(cleanBiography(bio) == "Vincent Belorgey, known as Kavinsky, is a French musician.")
    }

    @Test func aLinkInsideTheTextKeepsItsWords() {
        #expect(cleanBiography("Signed to <a href=\"https://example.test/label\">Record Makers</a> in 2006.") == "Signed to Record Makers in 2006.")
    }

    @Test func charactersAreWrittenOut() {
        #expect(cleanBiography("Daft Punk &amp; Justice &quot;live&quot; at the caf&#233;&#x27;s &lt;best&gt;&nbsp;night")
            == "Daft Punk & Justice \"live\" at the café's <best> night")
        // "&amp;lt;" is the text "&lt;", not a "<".
        #expect(cleanBiography("a &amp;lt; b") == "a &lt; b")
    }

    @Test func spacingIsTidied() {
        #expect(cleanBiography("  First   paragraph.<br/><br />\n  Second one,<br>with a break.  ") == "First paragraph.\n\nSecond one,\nwith a break.")
    }

    @Test func nothingLeftIsNoBiography() {
        #expect(cleanBiography("") == nil)
        #expect(cleanBiography("   ") == nil)
        #expect(cleanBiography("<a href=\"https://www.last.fm/music/X\">Read more on Last.fm</a>") == nil)
    }
}

@Suite struct ArtistExtrasTests {
    @Test func theServersIdComesFromItsOwnArtistRows() {
        let source = "server:music.example"
        #expect(serverArtistIdOf("server:music.example:ar1", sourceId: source) == "ar1")
        #expect(serverArtistIdOf("server:music.example:artist:kavinsky", sourceId: source) == nil)
        #expect(serverArtistIdOf("device:artist:kavinsky", sourceId: source) == nil)
        #expect(serverArtistIdOf("server:other.example:ar1", sourceId: source) == nil)
        #expect(serverArtistIdOf("server:music.example:", sourceId: source) == nil)
    }

    @Test func topSongsByNameKeepOnlyTheArtistsOwn() {
        let songs = [
            Song(id: "1", title: "Nightcall", artist: "Kavinsky"),
            Song(id: "2", title: "Odd Look", artist: "Kavinsky feat. The Weeknd"),
            Song(id: "3", title: "Something", artist: "Kavinsky Tribute Band"),
            Song(id: "4", title: "Nothing", artist: nil),
        ]
        #expect(ownSongs(songs, artist: "Kavinsky").map(\.id) == ["1", "2"])
    }
}

