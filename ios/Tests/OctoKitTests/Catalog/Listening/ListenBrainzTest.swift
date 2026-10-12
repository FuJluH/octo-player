import Foundation
import Testing
@testable import OctoKit

/// Building what goes to ListenBrainz, the queue, retries and which plays go.
@Suite struct ListenBrainzTest {
    let song = PlayedSong(title: "Glory Box", artist: "Portishead", album: "Dummy", durationMs: 306_000, trackNumber: 11,
                          reachesServer: false)

    func json(_ type: String, _ listens: [Listen], _ version: String) throws -> ListeningJSON {
        try #require(ListeningJSON.parse(listensJSON(type: type, listens: listens, clientVersion: version)))
    }

    @Test func aPlayCarriesItsStartInSecondsAndTheSong() throws {
        let listen = try #require(song.listenAt(1_700_000_123_456))
        let body = try json("single", [listen], "0.1.0")

        #expect(body["listen_type"]?.string == "single")
        let play = try #require(body.onlyPayload)
        #expect(play["listened_at"]?.integer == 1_700_000_123)
        let meta = try #require(play["track_metadata"])
        #expect(meta["artist_name"]?.string == "Portishead")
        #expect(meta["track_name"]?.string == "Glory Box")
        #expect(meta["release_name"]?.string == "Dummy")
    }

    @Test func additionalInfoNamesOctoAndTheSongDetails() throws {
        let listen = try #require(song.listenAt(1_000_000))
        let info = try #require(try json("single", [listen], "0.1.0").onlyPayload?["track_metadata"]?["additional_info"])

        #expect(info["media_player"]?.string == "Octo")
        #expect(info["media_player_version"]?.string == "0.1.0")
        #expect(info["submission_client"]?.string == "Octo")
        #expect(info["submission_client_version"]?.string == "0.1.0")
        #expect(info["duration_ms"]?.integer == 306_000)
        // A string, as ListenBrainz documents it.
        #expect(info["tracknumber"]?.isString == true)
        #expect(info["tracknumber"]?.string == "11")
    }

    @Test func unknownDetailsAreLeftOut() throws {
        let bare = try #require(PlayedSong(title: "Song", artist: "Artist", album: "", durationMs: 0, trackNumber: nil,
                                           reachesServer: false).listenAt(5_000))
        let meta = try #require(try json("single", [bare], "1").onlyPayload?["track_metadata"])
        let info = try #require(meta["additional_info"])

        #expect(meta["release_name"] == nil)
        #expect(info["duration_ms"] == nil)
        #expect(info["tracknumber"] == nil)
        #expect(info["recording_mbid"] == nil)
        #expect(info["artist_mbids"] == nil)
    }

    @Test func musicBrainzIdsGoWhenKnownAndWellFormed() throws {
        let recording = "b1a9c0e9-d987-4042-ae91-78d6a3267d69"
        let release = "3f0a4f44-1f1b-4b3c-9c62-7a7d7e2c1a10"
        let group = "7c3218d7-75e0-4e8c-971f-f097b6c308c5"
        let artist = "056e4f3e-d505-4dad-8ec1-d04f521cbb56"
        var tagged = song
        tagged.recordingMbid = recording.uppercased()
        tagged.releaseMbid = release
        tagged.releaseGroupMbid = group
        tagged.artistMbids = [artist, "not-an-id", artist]
        let listen = try #require(tagged.listenAt(1_000_000))
        let info = try #require(try json("single", [listen], "1").onlyPayload?["track_metadata"]?["additional_info"])
        #expect(info["recording_mbid"]?.string == recording)
        #expect(info["release_mbid"]?.string == release)
        #expect(info["release_group_mbid"]?.string == group)
        #expect(info["artist_mbids"]?.array?.compactMap(\.string) == [artist])

        // A malformed id would get the whole request refused, so it stays home.
        var broken = song
        broken.recordingMbid = "12345"
        broken.releaseMbid = ""
        let stayed = try #require(broken.listenAt(1_000_000))
        #expect(stayed.recordingMbid == nil)
        #expect(stayed.releaseMbid == nil)
    }

    @Test func playingNowHasNoTime() throws {
        let body = try json("playing_now", [try #require(song.listenAt(1_000_000))], "1")
        #expect(body["listen_type"]?.string == "playing_now")
        #expect(body.onlyPayload?["listened_at"] == nil)
    }

    @Test func aSongWithoutTitleOrArtistIsNotSent() {
        var untitled = song
        untitled.title = " "
        #expect(untitled.listenAt(1_000) == nil)
        var unnamed = song
        unnamed.artist = ""
        #expect(unnamed.listenAt(1_000) == nil)
    }

    @Test func oneIsSingleAndMoreIsImport() {
        #expect(listenType(1) == "single")
        #expect(listenType(2) == "import")
        #expect(listenType(maxListensPerRequest) == "import")
    }

    @Test func batchesHoldAtMostOneThousandOldestFirst() {
        var queue = (1...2_500).map { Listen(listenedAt: Int64($0), track: "t\($0)", artist: "a") }
        var sizes: [Int] = []
        while !queue.isEmpty {
            let batch = nextBatch(queue)
            #expect(batch.first == queue.first)
            sizes.append(batch.count)
            let sent = Set(batch)
            queue = queue.filter { !sent.contains($0) }
        }
        #expect(sizes == [1_000, 1_000, 500])
    }

    @Test func theQueueKeepsEachPlayOnceInOrder() {
        let queue = [Listen]()
            .plusListen(Listen(listenedAt: 200, track: "b", artist: "x"))
            .plusListen(Listen(listenedAt: 100, track: "a", artist: "x"))
            .plusListen(Listen(listenedAt: 200, track: "b", artist: "x"))
        #expect(queue.map(\.listenedAt) == [100, 200])
    }

    @Test func aFullQueueLetsTheOldestGo() {
        let queue = (1...(maxQueuedListens + 3)).reduce([Listen]()) { q, i in
            q.plusListen(Listen(listenedAt: Int64(i), track: "t", artist: "a"))
        }
        #expect(queue.count == maxQueuedListens)
        #expect(queue.first?.listenedAt == 4)
    }

    @Test func retriesBackOffAndStopGrowing() {
        #expect(retryDelayMs(0) == 0)
        #expect(retryDelayMs(1) == 30_000)
        #expect(retryDelayMs(2) == 60_000)
        #expect(retryDelayMs(3) == 120_000)
        #expect(retryDelayMs(15) == 6 * 60 * 60 * 1000)
        #expect(retryDelayMs(500) == 6 * 60 * 60 * 1000)
        for a in 1..<40 { #expect(retryDelayMs(a + 1) >= retryDelayMs(a)) }
    }

    @Test func allSongsSendsEverything() {
        #expect(shouldSend(.all, reachesServer: true))
        #expect(shouldSend(.all, reachesServer: false))
    }

    @Test func onlySongsOnThisPhoneLeavesOutWhatTheServerHears() {
        #expect(!shouldSend(.phoneOnly, reachesServer: true))
        #expect(shouldSend(.phoneOnly, reachesServer: false))
    }

    @Test func theServerHearsFindsAndSongsWithAServerCopy() {
        #expect(playReachesServer("find:abc", copySources: []))
        #expect(playReachesServer("merged:1", copySources: ["device", "server:home"]))
        #expect(!playReachesServer("merged:1", copySources: ["device"]))
        #expect(!playReachesServer("file:content%3A%2F%2Fx::", copySources: []))
    }

    @Test func onlyTokenShapedTextIsATokenAtAll() {
        #expect(looksLikeToken("3fa85f64-5717-4562-b3fc-2c963f66afa6"))
        #expect(!looksLikeToken("has space in it"))
        #expect(!looksLikeToken("abcdefgh\r\nX-Other: 1"))
        #expect(!looksLikeToken("short"))
    }

    @Test func callsKeepASecondApartAndWaitOutAnEmptyWindow() {
        let clock = ListeningClock(10_000)
        let limits = RateLimits { clock.now }
        #expect(limits.waitMs() == 0)
        limits.called()
        #expect(limits.waitMs() == 1_000)
        clock.advance(1_000)
        #expect(limits.waitMs() == 0)

        limits.heard(remaining: 3, resetInSeconds: 20)
        #expect(limits.blockedMs() == 0)
        limits.heard(remaining: 0, resetInSeconds: 20)
        #expect(limits.waitMs() == 20_000)
        #expect(limits.blockedMs() == 20_000)
        clock.advance(20_000)
        #expect(limits.waitMs() == 0)
    }

    @Test func theAppNamesItselfAsTheIPhoneApp() {
        #expect(listenBrainzUserAgent(version: "1.6.0") == "Octo/1.6.0 (iOS)")
    }

    @Test func aQueueOutOfOrderIsPutInOrder() {
        let messy = [
            Listen(listenedAt: 300, track: "c", artist: "x"),
            Listen(listenedAt: 100, track: "a", artist: "x"),
            Listen(listenedAt: 100, track: "a", artist: "x"),
        ]
        let queue = messy.plusListen(Listen(listenedAt: 200, track: "b", artist: "x"))
        #expect(queue.map(\.track) == ["a", "b", "c"])
    }

    @Test func playsStartingTogetherKeepTheirOrder() {
        let queue = [Listen]()
            .plusListen(Listen(listenedAt: 100, track: "a", artist: "x"))
            .plusListen(Listen(listenedAt: 100, track: "b", artist: "x"))
            .plusListen(Listen(listenedAt: 50, track: "c", artist: "x"))
            .plusListen(Listen(listenedAt: 100, track: "a", artist: "x"))
        #expect(queue.map(\.track) == ["c", "a", "b"])
    }
}
