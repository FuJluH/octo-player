import Foundation
import Testing
@testable import OctoKit

@Suite struct SongItemsTest {
    private func song(_ id: String, album: String? = "al", disc: Int? = nil, track: Int? = nil) -> Song {
        var made = Song(id: id, title: "Song \(id)", artist: "Artist", album: "Album", albumId: album, duration: 200, coverArt: "c\(id)")
        made.discNumber = disc
        made.track = track
        return made
    }

    @Test func anAlbumInOrderCountsUpByOne() {
        let songs = [song("a", track: 1), song("b", track: 2), song("c", track: 3)]
        #expect(albumOrders(songs) == [0, 1, 2])
    }

    @Test func discsFollowEachOther() {
        let songs = [song("a", disc: 1, track: 12), song("b", disc: 2, track: 1), song("c", disc: 2, track: 2)]
        #expect(albumOrders(songs) == [0, 1, 2])
    }

    @Test func songsWithoutAnAlbumOrTrackHaveNoPlace() {
        let songs = [song("a", album: nil, track: 1), song("b", track: nil), song("c", album: "other", track: 7)]
        #expect(albumOrders(songs) == [nil, nil, 0])
    }

    @Test func aServerSongStreamsUnderItsPrivateAddress() {
        var made = song("s1", track: 3)
        made.contentType = "audio/flac"
        made.bitRate = 900
        made.explicitStatus = "explicit"
        let item = queueItem(made, sourceId: "server:music.test", quality: .mp3(kbps: 192), source: .you, albumOrder: 2)
        let ref = parseStreamUri(item.uri)
        #expect(ref?.serverId == "s1")
        #expect(ref?.sourceId == "server:music.test")
        #expect(ref?.mimeType == "audio/flac")
        #expect(ref?.bitrate == 900_000)
        #expect(item.mimeType == "audio/mpeg")
        #expect(item.fileMime == "audio/flac")
        #expect(item.durationMs == 200_000)
        #expect(item.albumOrder == 2)
        #expect(item.explicit)
        #expect(item.source == .you)
        #expect(item.trackId == "s1")
    }

    @Test func theFileAsItIsKeepsItsType() {
        var made = song("s2")
        made.contentType = "audio/mpeg"
        let item = queueItem(made, sourceId: nil, quality: .original)
        #expect(item.mimeType == "audio/mpeg")
        #expect(parseStreamUri(item.uri)?.sourceId == nil)
    }

    @Test func aQueueItemShowsAsItsSong() {
        let item = QueueItem(trackId: "t", uri: "file:///x.flac", title: "Title", artist: "Who", album: "Where", durationMs: 61_499,
                             trackNo: 4, artwork: "art", albumId: "al", isFind: true)
        let shown = songOf(item)
        #expect(shown.id == "t")
        #expect(shown.title == "Title")
        #expect(shown.duration == 61)
        #expect(shown.track == 4)
        #expect(shown.isExternal)
    }

    @Test func storedLoudnessGoesBackIntoASong() {
        let gain = ReplayGain(trackGain: -6, trackPeak: 0.9, albumGain: -7, albumPeak: 1)
        #expect(gain.trackGain == -6)
        #expect(gain.albumPeak == 1)
    }
}
