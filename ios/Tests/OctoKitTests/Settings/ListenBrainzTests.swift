import Foundation
import Testing
@testable import OctoKit
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@Suite struct ListenBrainzTests {
    let song = PlayedSong("Glory Box", "Portishead", "Dummy", durationMs: 306_000, trackNumber: 11, reachesServer: false)

    private func first(_ body: [String: Any]) -> [String: Any] {
        (body["payload"] as! [[String: Any]]).first!
    }

    private func info(_ body: [String: Any]) -> [String: Any] {
        (first(body)["track_metadata"] as! [String: Any])["additional_info"] as! [String: Any]
    }

    @Test func aPlayCarriesItsStartInSecondsAndTheSong() {
        let body = listensJson("single", [song.listen(startedAtMs: 1_700_000_123_456)!], clientVersion: "0.1.0")
        #expect(body["listen_type"] as? String == "single")
        #expect(first(body)["listened_at"] as? Int64 == 1_700_000_123)
        let meta = first(body)["track_metadata"] as! [String: Any]
        #expect(meta["artist_name"] as? String == "Portishead")
        #expect(meta["track_name"] as? String == "Glory Box")
        #expect(meta["release_name"] as? String == "Dummy")
    }

    @Test func additionalInfoNamesOctoAndTheSongDetails() {
        let info = info(listensJson("single", [song.listen(startedAtMs: 1_000_000)!], clientVersion: "0.1.0"))
        #expect(info["media_player"] as? String == "Octo")
        #expect(info["media_player_version"] as? String == "0.1.0")
        #expect(info["submission_client"] as? String == "Octo")
        #expect(info["submission_client_version"] as? String == "0.1.0")
        #expect(info["duration_ms"] as? Int64 == 306_000)
        // A string, as ListenBrainz documents it.
        #expect(info["tracknumber"] as? String == "11")
    }

    @Test func unknownDetailsAreLeftOut() {
        let bare = PlayedSong("Song", "Artist", "", durationMs: 0, trackNumber: nil, reachesServer: false).listen(startedAtMs: 5_000)!
        let body = listensJson("single", [bare], clientVersion: "1")
        let meta = first(body)["track_metadata"] as! [String: Any]
        let info = meta["additional_info"] as! [String: Any]
        #expect(meta["release_name"] == nil)
        #expect(info["duration_ms"] == nil)
        #expect(info["tracknumber"] == nil)
        #expect(info["recording_mbid"] == nil)
        #expect(info["artist_mbids"] == nil)
    }

    @Test func musicBrainzIdsGoWhenKnownAndWellFormed() {
        let recording = "b1a9c0e9-d987-4042-ae91-78d6a3267d69"
        let release = "3f0a4f44-1f1b-4b3c-9c62-7a7d7e2c1a10"
        let group = "7c3218d7-75e0-4e8c-971f-f097b6c308c5"
        let artist = "056e4f3e-d505-4dad-8ec1-d04f521cbb56"
        var tagged = song
        tagged.recordingMbid = recording.uppercased()
        tagged.releaseMbid = release
        tagged.releaseGroupMbid = group
        tagged.artistMbids = [artist, "not-an-id", artist]
        let info = info(listensJson("single", [tagged.listen(startedAtMs: 1_000_000)!], clientVersion: "1"))
        #expect(info["recording_mbid"] as? String == recording)
        #expect(info["release_mbid"] as? String == release)
        #expect(info["release_group_mbid"] as? String == group)
        #expect(info["artist_mbids"] as? [String] == [artist])

        var broken = song
        broken.recordingMbid = "12345"
        broken.releaseMbid = ""
        let listen = broken.listen(startedAtMs: 1_000_000)!
        #expect(listen.recordingMbid == nil)
        #expect(listen.releaseMbid == nil)
    }

    @Test func playingNowHasNoTime() {
        let body = listensJson("playing_now", [song.listen(startedAtMs: 1_000_000)!], clientVersion: "1")
        #expect(body["listen_type"] as? String == "playing_now")
        #expect(first(body)["listened_at"] == nil)
    }

    @Test func aSongWithoutTitleOrArtistIsNotSent() {
        var blank = song
        blank.title = " "
        #expect(blank.listen(startedAtMs: 1_000) == nil)
        var noArtist = song
        noArtist.artist = ""
        #expect(noArtist.listen(startedAtMs: 1_000) == nil)
    }

    @Test func oneIsSingleAndMoreIsImport() {
        #expect(listenType(1) == "single")
        #expect(listenType(2) == "import")
        #expect(listenType(maxListensPerRequest) == "import")
    }

    @Test func batchesHoldAtMostOneThousandOldestFirst() {
        var queue = (1...2_500).map { Listen(Int64($0), "t\($0)", "a") }
        var sizes: [Int] = []
        while !queue.isEmpty {
            let batch = nextBatch(queue)
            #expect(batch.first == queue.first)
            sizes.append(batch.count)
            let sent = Set(batch)
            queue.removeAll { sent.contains($0) }
        }
        #expect(sizes == [1_000, 1_000, 500])
    }

    @Test func theQueueKeepsEachPlayOnceInOrder() {
        let queue = [Listen]().plusListen(Listen(200, "b", "x")).plusListen(Listen(100, "a", "x")).plusListen(Listen(200, "b", "x"))
        #expect(queue.map(\.listenedAt) == [100, 200])
    }

    @Test func aFullQueueLetsTheOldestGo() {
        var queue: [Listen] = []
        for i in 1...(maxQueuedListens + 3) { queue = queue.plusListen(Listen(Int64(i), "t", "a")) }
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
        for n in 1..<40 { #expect(retryDelayMs(n + 1) >= retryDelayMs(n)) }
    }

    @Test func whichPlaysGo() {
        #expect(shouldSend(.all, reachesServer: true))
        #expect(shouldSend(.all, reachesServer: false))
        #expect(!shouldSend(.phoneOnly, reachesServer: true))
        #expect(shouldSend(.phoneOnly, reachesServer: false))
        #expect(playReachesServer(isFind: true, copySources: []))
        #expect(playReachesServer(isFind: false, copySources: ["device", "server:home"]))
        #expect(!playReachesServer(isFind: false, copySources: ["device"]))
    }

    @Test func onlyTokenShapedTextIsATokenAtAll() {
        #expect(looksLikeToken("3fa85f64-5717-4562-b3fc-2c963f66afa6"))
        #expect(!looksLikeToken("has space in it"))
        #expect(!looksLikeToken("abcdefgh\r\nX-Other: 1"))
        #expect(!looksLikeToken("short"))
        #expect(!looksLikeToken("ábcdefghij"))
    }

    @Test func callsKeepASecondApartAndWaitOutAnEmptyWindow() {
        let now = Clock(10_000)
        let limits = RateLimits { now.value }
        #expect(limits.waitMs() == 0)
        limits.called()
        #expect(limits.waitMs() == 1_000)
        now.value += 1_000
        #expect(limits.waitMs() == 0)
        limits.heard(remaining: 3, resetInSeconds: 20)
        #expect(limits.blockedMs() == 0)
        limits.heard(remaining: 0, resetInSeconds: 20)
        #expect(limits.waitMs() == 20_000)
        #expect(limits.blockedMs() == 20_000)
        now.value += 20_000
        #expect(limits.waitMs() == 0)
    }

    @Test func theTransportOnlyTalksToListenBrainzOverHttps() {
        let transport = ListenBrainzTransport(userAgent: "Octo/test")
        #expect(transport.allows(URL(string: "https://api.listenbrainz.org/1/submit-listens")))
        #expect(!transport.allows(URL(string: "http://api.listenbrainz.org/1/submit-listens")))
        #expect(!transport.allows(URL(string: "https://evil.example/1/submit-listens")))
        #expect(!transport.allows(URL(string: "https://api.listenbrainz.org:8443/1/submit-listens")))
        #expect(listenBrainzAPI.scheme == "https")
        #expect(listenBrainzAPI.host == "api.listenbrainz.org")
    }

    @Test func savedPlaysReadBack() throws {
        let listen = Listen(1, "t", "a", album: "b", durationMs: 2, trackNumber: 3, artistMbids: ["x"])
        let data = try JSONEncoder().encode([listen])
        #expect(try JSONDecoder().decode([Listen].self, from: data) == [listen])
    }
}

/// A clock a test moves by hand.
final class Clock: @unchecked Sendable {
    var value: Int64
    init(_ value: Int64) { self.value = value }
}

/// A stand-in ListenBrainz: answers in order, and keeps every request.
final class FakeListenBrainz: @unchecked Sendable {
    var answers: [ListenBrainzAnswer?] = []
    var requests: [URLRequest] = []
    var slept: Int64 = 0

    func answer(_ status: Int = 200, _ body: String = #"{"status":"ok"}"#, headers: [String: String] = [:]) {
        answers.append(ListenBrainzAnswer(status: status, body: Data(body.utf8), headers: headers))
    }

    func api(limits: RateLimits = RateLimits()) -> ListenBrainzApi {
        ListenBrainzApi(send: { request in
            self.requests.append(request)
            return self.answers.isEmpty ? nil : self.answers.removeFirst()
        }, limits: limits, sleep: { ms in self.slept += ms })
    }
}

@Suite(.serialized) struct ListenBrainzApiTests {
    let token = "3fa85f64-5717-4562-b3fc-2c963f66afa6"
    let play = Listen(1_700_000_000, "Roads", "Portishead", album: "Dummy", durationMs: 305_000, trackNumber: 3)

    @Test func aGoodTokenSaysWhoseItIs() async {
        let fake = FakeListenBrainz()
        fake.answer(200, #"{"code":200,"message":"Token valid.","valid":true,"user_name":"winters"}"#)
        #expect(await fake.api().validate(token) == .valid(user: "winters"))
        let request = fake.requests[0]
        #expect(request.httpMethod == "GET")
        #expect(request.url?.path == "/1/validate-token")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Token \(token)")
        // The token never goes in the address.
        #expect(!(request.url?.absoluteString.contains(token) ?? true))
    }

    @Test func aTokenListenBrainzDoesNotKnowIsInvalid() async {
        let fake = FakeListenBrainz()
        fake.answer(200, #"{"code":200,"message":"Token invalid.","valid":false}"#)
        fake.answer(401, #"{"code":401,"error":"Invalid authorization token."}"#)
        let api = fake.api()
        #expect(await api.validate(token) == .invalid)
        #expect(await api.validate(token) == .invalid)
    }

    @Test func textThatIsNotATokenIsNeverSent() async {
        let fake = FakeListenBrainz()
        #expect(await fake.api().validate("not a token") == .invalid)
        #expect(fake.requests.isEmpty)
    }

    @Test func noAnswerMeansUnreachable() async {
        let fake = FakeListenBrainz()
        #expect(await fake.api().validate(token) == .unreachable)
    }

    @Test func onePlayGoesAsSingle() async throws {
        let fake = FakeListenBrainz()
        fake.answer()
        #expect(await fake.api().submit(token, [play], clientVersion: "0.1.0") == .sent)
        let request = fake.requests[0]
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/1/submit-listens")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Token \(token)")
        #expect(request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("application/json") == true)
        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        #expect(body["listen_type"] as? String == "single")
        let sent = (body["payload"] as! [[String: Any]])[0]
        #expect((sent["listened_at"] as? NSNumber)?.int64Value == 1_700_000_000)
    }

    @Test func severalPlaysGoAsOneImport() async throws {
        let fake = FakeListenBrainz()
        fake.answer()
        let plays = (0..<maxListensPerRequest).map { var p = play; p.listenedAt += Int64($0); return p }
        #expect(await fake.api().submit(token, plays, clientVersion: "0.1.0") == .sent)
        let body = try JSONSerialization.jsonObject(with: fake.requests[0].httpBody!) as! [String: Any]
        #expect(body["listen_type"] as? String == "import")
        #expect((body["payload"] as! [Any]).count == maxListensPerRequest)
    }

    @Test func moreThanOneRequestHoldsIsNeverSent() async {
        let fake = FakeListenBrainz()
        let plays = (0...maxListensPerRequest).map { var p = play; p.listenedAt += Int64($0); return p }
        #expect(await fake.api().submit(token, plays, clientVersion: "0.1.0") == .rejected)
        #expect(fake.requests.isEmpty)
    }

    @Test func answersSayWhatToDoNext() async {
        let fake = FakeListenBrainz()
        fake.answer(401)
        fake.answer(400)
        fake.answer(503)
        let api = fake.api()
        #expect(await api.submit(token, [play], clientVersion: "1") == .unauthorized)
        #expect(await api.submit(token, [play], clientVersion: "1") == .rejected)
        #expect(await api.submit(token, [play], clientVersion: "1") == .failed)
    }

    @Test func tooManyCallsWaitsAsLongAsListenBrainzSays() async {
        let fake = FakeListenBrainz()
        fake.answer(429, #"{"code":429,"error":"Too many requests"}"#, headers: ["X-RateLimit-Reset-In": "7", "X-RateLimit-Remaining": "0"])
        let api = fake.api()
        #expect(await api.submit(token, [play], clientVersion: "1") == .rateLimited(retryInMs: 7_000))
        // Now playing is skipped rather than held back while no calls are left.
        if case .rateLimited = await api.playingNow(token, play, clientVersion: "1") {} else { Issue.record("now playing went out") }
        #expect(fake.requests.count == 1)
    }

    @Test func anEmptyWindowIsWaitedOutBeforeTheNextCall() async {
        let fake = FakeListenBrainz()
        fake.answer(headers: ["X-RateLimit-Remaining": "0", "X-RateLimit-Reset-In": "5"])
        fake.answer()
        let api = fake.api()
        _ = await api.submit(token, [play], clientVersion: "1")
        #expect(await api.submit(token, [play], clientVersion: "1") == .sent)
        #expect(fake.slept >= 4_000)
        #expect(fake.requests.count == 2)
    }
}

/// Which plays go to ListenBrainz under each "send plays" choice.
@Suite struct ListenBrainzSendTest {
    @Test func allSongsSendsEverything() {
        #expect(shouldSend(.all, reachesServer: true))
        #expect(shouldSend(.all, reachesServer: false))
    }

    @Test func onlySongsOnThisPhoneLeavesOutWhatTheServerHears() {
        #expect(!shouldSend(.phoneOnly, reachesServer: true))
        #expect(shouldSend(.phoneOnly, reachesServer: false))
    }

    @Test func theServerHearsFindsAndSongsWithAServerCopy() {
        #expect(playReachesServer(isFind: isFind("find:abc"), copySources: []))
        #expect(playReachesServer(isFind: false, copySources: ["device", "server:home"]))
        #expect(!playReachesServer(isFind: false, copySources: ["device"]))
        #expect(!playReachesServer(isFind: isFind("file:content%3A%2F%2Fx::"), copySources: []))
    }
}
