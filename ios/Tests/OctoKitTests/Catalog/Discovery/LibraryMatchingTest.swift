import Foundation
import Testing
@testable import OctoKit

@Suite struct LibraryMatchingTest {
    private func suggested(_ id: String, _ title: String, by: String? = nil) -> Song {
        var song = Song(id: id, title: title)
        song.octoSuggestedBy = by
        return song
    }

    @Test func eachTrackKeepsTheSourceThatSuggestedIt() {
        let songs = [
            suggested("s1", "One", by: "YouTube Music"),
            suggested("s2", "Two", by: " "),
            suggested("s3", "Three"),
            suggested("s4", "Four", by: "Sounds alike"),
        ]
        #expect(suggestionsOf(["t1", "t2", "t3", "t4"], songs) == ["t1": "YouTube Music", "t4": "Sounds alike"])
        #expect(suggestionsOf([nil], [songs[0]]) == [:])
    }

    /// A clock the test moves by hand.
    private final class Clock: @unchecked Sendable {
        private let lock = NSLock()
        private var ms: Int64 = 0

        var now: Int64 {
            get { lock.lock(); defer { lock.unlock() }; return ms }
            set { lock.lock(); ms = newValue; lock.unlock() }
        }
    }

    @Test func theOldestSuggestionsGoFirstAndAnOldOneIsForgotten() {
        let clock = Clock()
        let memory = Suggestions(kept: 2, lifetimeMs: 1_000, now: { clock.now })
        memory.putAll(["a": "Last.fm", "b": "YouTube Music"])
        // Suggested again: now the newest, so "b" is the one that goes.
        memory.putAll(["a": "ListenBrainz"])
        memory.putAll(["c": "Sounds alike"])
        #expect(memory["a"] == "ListenBrainz")
        #expect(memory["b"] == nil)
        #expect(memory["c"] == "Sounds alike")

        clock.now = 1_001
        #expect(memory["a"] == nil)
    }

    private func track(_ id: String, _ title: String, _ artist: String, ms: Int64 = 200_000) -> LibraryTrack {
        LibraryTrack(id: id, sourceId: "device", nativeId: id, title: title, searchKey: title.lowercased(), sortKey: title.lowercased(),
                     artist: artist, artistId: "a", album: "Album", albumId: "al", durationMs: ms, addedAt: 0)
    }

    private func song(_ id: String, _ title: String, _ artist: String, seconds: Int = 180, suffix: String = "m4a") -> Song {
        var song = Song(id: id, title: title, artist: artist, album: title, albumId: "alb\(id)", duration: seconds, coverArt: id, suffix: suffix)
        song.bitRate = 128
        return song
    }

    private func find(_ id: String, _ title: String, _ artist: String, requestedAt: Int64 = 0) -> OnlineSong {
        OnlineSong(id: id, sourceId: "s", nativeId: String(id.dropFirst(findPrefix.count)), title: title, artist: artist, seenAt: 0,
                   requestedAt: requestedAt)
    }

    @Test func aSyncedServerSongIsItsLibrarySong() {
        let out = resolveSongs([song("s1", "One More Time", "Daft Punk")], sourceId: "server:x", links: ["s1": "p1"], library: [], now: 0)
        #expect(out == [.inLibrary(trackId: "p1")])
    }

    @Test func aSongTheServerMarksAsOutsideIsAFindWhateverAnOldLinkSays() {
        var online = song("s1", "One More Time", "Daft Punk")
        online.isExternal = true
        let out = resolveSongs([online], sourceId: "server:x", links: ["s1": "p1"], library: [], now: 0)
        #expect(out.count == 1)
        guard case .found(let found) = out.first else {
            Issue.record("expected a find")
            return
        }
        #expect(found.id == "find:s1")
    }

    @Test func theSameSongOnThePhoneWinsOverAStream() {
        let phone = track("p9", "Digital Love", "Daft Punk", ms: 301_000)
        let out = resolveSongs([song("s9", "Digital Love", "Daft Punk")], sourceId: "server:x", links: [:], library: [phone], now: 0)
        #expect(out == [.inLibrary(trackId: "p9")])
    }

    @Test func anythingElseIsAFindThatStreams() {
        let out = resolveSongs([song("e1", "Genesis", "Justice")], sourceId: "server:x", links: [:],
                               library: [track("p1", "Genesis", "Phil Collins")], now: 7)
        #expect(out.count == 1)
        guard case .found(let find) = out.first else {
            Issue.record("expected a find")
            return
        }
        #expect(find.id == "find:e1")
        #expect(find.nativeId == "e1")
        #expect(find.durationMs == 0)
        #expect(find.mimeType == "audio/mp4")
        #expect(find.bitrate == 128)
        #expect(find.seenAt == 7)
    }

    @Test func featuredArtistsAndExtrasStillMatch() {
        let lib = track("p1", "One Dance", "Drake feat. Wizkid & Kyla")
        #expect(sameSong("One Dance (feat. Wizkid)", "Drake", 0, lib))
        #expect(!sameSong("One Dance", "Drake Bell", 0, lib))
    }

    @Test func aRemixIsNotTheOriginalEvenWithoutALength() {
        let lib = track("p1", "Nightcall", "Kavinsky", ms: 179_000)
        #expect(!sameSong("Nightcall (Breakbot Remix)", "Kavinsky", 0, lib))
        #expect(!sameSong("Nightcall - Live", "Kavinsky", 0, lib))
        #expect(sameSong("Nightcall [Remastered]", "Kavinsky", 0, lib))
        #expect(sameSong("Nightcall (Breakbot remix)", "Kavinsky", 0, track("p2", "Nightcall (Breakbot Remix)", "Kavinsky")))
    }

    @Test func knownLengthsThatDifferAreDifferentRecordings() {
        let lib = track("p1", "Around the World", "Daft Punk", ms: 429_000)
        #expect(!sameSong("Around the World", "Daft Punk", 238_000, lib))
        #expect(sameSong("Around the World", "Daft Punk", 0, lib))
    }

    @Test func aFindShowsAsASongWithNothingToOpen() {
        let row = OnlineSong(id: "find:e1", sourceId: "server:x", nativeId: "e1", title: "Genesis", artist: "Justice", album: "Cross",
                             albumId: "al1", artistId: "ar1", durationMs: 0, coverId: "e1", mimeType: "audio/mp4", bitrate: 128, seenAt: 0)
        let t = row.asTrack
        #expect(t.id == "find:e1")
        #expect(t.albumId == "")
        #expect(t.artistId == "")
        #expect(!t.onPhone)
        // Its cover is kept apart from library covers.
        #expect(t.artwork == "online:server:x|e1")
    }

    @Test func aFindKeepsTheServersExplicitMarkThroughToItsRow() {
        var explicitSong = song("e2", "Dracula", "Tame Impala")
        explicitSong.explicitStatus = "explicit"
        let explicit = explicitSong.toFind(sourceId: "server:x", now: 0)
        #expect(explicit.explicit == true)
        #expect(explicit.asTrack.explicit == true)
        var cleanSong = song("e3", "Dracula", "Tame Impala")
        cleanSong.explicitStatus = "clean"
        #expect(cleanSong.toFind(sourceId: "server:x", now: 0).explicit == false)
        #expect(song("e4", "Dracula", "Tame Impala").toFind(sourceId: "server:x", now: 0).asTrack.explicit == nil)
    }

    @Test func aFinishedDownloadIsKnownByTitleAndArtist() {
        let find = find("find:e1", "Genesis", "Justice")
        #expect(downloadMatches(find, title: "Genesis", artist: "Justice"))
        #expect(downloadMatches(find, title: "Genesis [Remastered]", artist: "Justice feat. Someone"))
        #expect(!downloadMatches(find, title: "Genesis (Live)", artist: "Justice"))
        #expect(!downloadMatches(find, title: "Genesis", artist: "Phil Collins"))
    }

    @Test func stylizedNamesAreTheSameSong() {
        let lib = track("p1", "Suicide", "Suicideboys", ms: 169_000)
        #expect(sameSong("$UICIDE", "$uicideboy$", 170_000, lib))
        #expect(sameSong("＄UICIDE", "＄uicideboy＄", 0, lib))
        // Another song that holds the title is not it.
        #expect(!sameSong("Ultimate $uicide", "$uicideboy$", 170_000, lib))
    }

    @Test func aCurlyApostropheIsAnApostrophe() {
        #expect(sameSong("Huntin’ Wabbitz", "$uicideboy$", 0, track("p1", "Huntin' Wabbitz", "$uicideboy$")))
    }

    @Test func creditsJoinedAnyWayAreTheSameArtists() {
        #expect(sameArtist("Kanye West、Ty Dolla $ign", "Kanye West"))
        #expect(sameSong("Real Friends (Explicit)", "Kanye West、Ty Dolla $ign", 0, track("p1", "Real Friends", "Kanye West")))
        // An alias, with the name in another script beside it.
        #expect(sameArtist("Ye (侃爷)", "Kanye West"))
        #expect(sameSong("Can't Tell Me Nothing", "Ye (侃爷)", 0, track("p1", "Can’t Tell Me Nothing", "Kanye West")))
    }

    @Test func aKnownNameIsNeverSplit() {
        #expect(sameArtist("Tyler, The Creator", "Tyler The Creator"))
        #expect(sameArtist("Tyler, The Creator & Kali Uchis", "Tyler, The Creator"))
        #expect(!sameArtist("Tyler, The Creator", "Tyler"))
        #expect(!sameSong("EARFQUAKE", "Tyler", 0, track("p1", "EARFQUAKE", "Tyler, The Creator")))
    }

    @Test func differentGuestsAreAnotherCollaboration() {
        #expect(!sameSong("Song", "A feat. B", 0, track("p1", "Song", "A feat. C")))
        #expect(sameSong("Song", "A feat. B", 0, track("p1", "Song", "A")))
    }

    @Test func aServerSongSpelledAnotherWayIsItsLibrarySong() {
        let phone = track("p9", "Suicide", "Suicideboys", ms: 169_000)
        let out = resolveSongs([song("s9", "$UICIDE", "$uicideboy$", seconds: 170)], sourceId: "server:x", links: [:], library: [phone], now: 0)
        #expect(out == [.inLibrary(trackId: "p9")])
    }

    @Test func aFindIsAdoptedByTheSameRecordingOnly() {
        let library = [
            track("p1", "Movie Star (Clean)", "Jack Harlow"),
            track("p2", "Movie Star", "Jack Harlow"),
            track("p3", "Suicide", "Suicideboys"),
        ]
        let adopted = adoptions(
            [find("find:a", "Movie Star", "Jack Harlow"), find("find:b", "$UICIDE", "$uicideboy$"), find("find:c", "Mask Off", "Future")],
            library
        )
        // The clean edit is another version here, unlike for lyrics.
        #expect(adopted.mapValues(\.id) == ["find:a": "p2", "find:b": "p3"])
    }

    @Test func aFinishedDownloadIsKnownThroughAnAlias() {
        let find = find("find:e1", "Stronger", "Kanye West")
        #expect(downloadMatches(find, title: "Stronger (Explicit)", artist: "Ye (侃爷)"))
        #expect(!downloadMatches(find, title: "Stronger (Clean)", artist: "Ye"))
    }

    @Test func aDownloadAskedForLongAgoCanBeAskedAgain() {
        var row = find("find:e1", "T", "A", requestedAt: 1_000)
        #expect(stateOf(row.asFindSong, now: 1_000 + 60_000) == DownloadState.requested)
        #expect(stateOf(row.asFindSong, now: 1_000 + 25 * 60 * 60_000) == DownloadState.none)
        row.adoptedId = "p1"
        #expect(stateOf(row.asFindSong, now: 1_000) == DownloadState.done)
    }
}
