import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import OctoKit

@Suite struct QueueSyncTest {
    func snapshot(_ ids: [String], _ index: Int, positionMs: Int = 5_000, shuffle: Bool = false, order: [Int] = []) -> QueueSnapshot {
        QueueSnapshot(trackIds: ids, shuffleOrder: order, index: index, positionMs: positionMs, repeatMode: 0, shuffle: shuffle)
    }

    /// Songs "a" to "e" are on the server as "sa" to "se", except the ones named here.
    func server(_ missing: String...) -> (String) -> String? { { missing.contains($0) ? nil : "s\($0)" } }

    @Test func theQueueGoesAsItIs() {
        #expect(serverQueueOf(snapshot(["a", "b", "c"], 1), serverIdOf: server()) == ServerQueue(["sa", "sb", "sc"], 1, 5_000))
    }

    @Test func songsNotOnTheServerAreLeftOut() {
        #expect(serverQueueOf(snapshot(["a", "b", "c"], 2), serverIdOf: server("b")) == ServerQueue(["sa", "sc"], 1, 5_000))
    }

    @Test func aCurrentSongNotOnTheServerHandsOverToTheNextOneFromItsStart() {
        #expect(serverQueueOf(snapshot(["a", "b", "c"], 1), serverIdOf: server("b")) == ServerQueue(["sa", "sc"], 1, 0))
        #expect(serverQueueOf(snapshot(["a", "b", "c"], 2), serverIdOf: server("b", "c")) == ServerQueue(["sa"], 0, 0))
    }

    @Test func nothingOnTheServerSavesNothing() {
        #expect(serverQueueOf(snapshot(["a", "b"], 0), serverIdOf: server("a", "b")) == nil)
        #expect(serverQueueOf(snapshot([], 0), serverIdOf: server()) == nil)
    }

    @Test func aShuffledQueueGoesInTheOrderItWillPlay() {
        let shuffled = snapshot(["a", "b", "c", "d"], 2, shuffle: true, order: [3, 2, 0, 1])
        #expect(serverQueueOf(shuffled, serverIdOf: server()) == ServerQueue(["sd", "sc", "sa", "sb"], 1, 5_000))
        let broken = snapshot(["a", "b", "c"], 0, shuffle: true, order: [0, 0, 1])
        #expect(serverQueueOf(broken, serverIdOf: server()) == ServerQueue(["sa", "sb", "sc"], 0, 5_000))
    }

    @Test func duplicatesStayInTheQueue() {
        #expect(serverQueueOf(snapshot(["a", "b", "a"], 2), serverIdOf: server()) == ServerQueue(["sa", "sb", "sa"], 2, 5_000))
    }

    @Test func aLongQueueIsCutDownAroundTheCurrentSong() {
        let ids = (0..<1000).map { "s\($0)" }
        let middle = ServerQueue(ids, 500, 7_000).trimmed(400)
        #expect(middle.ids.count == 400)
        #expect(middle.ids.first == "s450")
        #expect(middle.ids[middle.index] == "s500")
        #expect(middle.positionMs == 7_000)
        #expect(ServerQueue(ids, 10, 0).trimmed(400).ids.first == "s0")
        let end = ServerQueue(ids, 990, 0).trimmed(400)
        #expect(end.ids.last == "s999")
        #expect(end.ids[end.index] == "s990")
        let short = ServerQueue(["a", "b"], 1, 0)
        #expect(short.trimmed(400) == short)
    }

    func song(_ id: String) -> Song { Song(id: id, title: id.uppercased()) }

    @Test func readsARemoteQueueEitherWay() {
        let byIndex = remoteQueueOf(byIndex: ServerPlayQueue(entry: [song("x"), song("y")], currentIndex: 1, position: 30_000,
                                                             changed: "2026-09-26T10:00:00Z", changedBy: "Desktop"))
        #expect(byIndex.current?.id == "y")
        #expect(byIndex.positionMs == 30_000)
        #expect(byIndex.changedAt == 1_790_416_800_000)
        let legacy = remoteQueueOf(byId: ServerPlayQueue(entry: [song("x"), song("y")], current: "y", position: 12_000, changedBy: "Web"))
        #expect(legacy.index == 1)
        #expect(legacy.positionMs == 12_000)
        let lost = remoteQueueOf(byId: ServerPlayQueue(entry: [song("x")], current: "gone", position: 12_000))
        #expect(lost.index == 0)
        #expect(lost.positionMs == 0)
    }

    @Test func readsServerTimes() {
        #expect(serverTime("2026-09-26T10:00:00Z") == 1_790_416_800_000)
        #expect(serverTime("2026-09-26T10:00:00.5Z") == 1_790_416_800_500)
        #expect(serverTime("2026-09-26T12:00:00+02:00") == 1_790_416_800_000)
        #expect(serverTime("2026-09-19T01:44:59.636933547Z") != nil)
        #expect(serverTime("yesterday") == nil)
        #expect(serverTime(nil) == nil)
    }

    func remote(_ changedAt: Int?, _ by: String?, songs: [Song]? = nil) -> RemoteQueue {
        RemoteQueue(songs: songs ?? [Song(id: "x", title: "")], index: 0, positionMs: 0, changedAt: changedAt, changedBy: by)
    }

    @Test func offersAQueueSavedLaterElsewhere() {
        #expect(shouldOfferResume(remote(2_000, "Desktop"), lastSavedAt: 1_000, answeredUpTo: 0, ownStamp: 500))
        #expect(shouldOfferResume(remote(2_000, "Octo"), lastSavedAt: 1_000, answeredUpTo: 0, ownStamp: 500))
        #expect(shouldOfferResume(remote(2_000, nil), lastSavedAt: 1_000, answeredUpTo: 0, ownStamp: nil))
    }

    @Test func doesNotOfferOurOwnQueue() {
        #expect(!shouldOfferResume(remote(2_000, "Octo"), lastSavedAt: 1_000, answeredUpTo: 0, ownStamp: 2_000))
    }

    @Test func doesNotOfferAQueueOlderThanOurLastSave() {
        #expect(!shouldOfferResume(remote(1_000, "Desktop"), lastSavedAt: 2_000, answeredUpTo: 0, ownStamp: nil))
        #expect(!shouldOfferResume(remote(1_000, "Desktop"), lastSavedAt: 1_000, answeredUpTo: 0, ownStamp: nil))
    }

    @Test func doesNotOfferAQueueAlreadyAnswered() {
        #expect(!shouldOfferResume(remote(2_000, "Desktop"), lastSavedAt: 1_000, answeredUpTo: 2_000, ownStamp: nil))
        #expect(shouldOfferResume(remote(3_000, "Desktop"), lastSavedAt: 1_000, answeredUpTo: 2_000, ownStamp: nil))
    }

    @Test func doesNotOfferWhatCannotBeToldApart() {
        #expect(!shouldOfferResume(nil, lastSavedAt: 0, answeredUpTo: 0, ownStamp: nil))
        #expect(!shouldOfferResume(remote(nil, "Desktop"), lastSavedAt: 0, answeredUpTo: 0, ownStamp: nil))
        #expect(!shouldOfferResume(remote(2_000, "Desktop", songs: []), lastSavedAt: 0, answeredUpTo: 0, ownStamp: nil))
    }

    @Test func aSaveSendsTheIdsThenWherePlaybackIs() {
        let byIndex = queueSaveParams(["a", "b"], currentIndex: 1, positionMs: -5, indexBased: true)
        #expect(byIndex.map { "\($0.0)=\($0.1)" } == ["id=a", "id=b", "currentIndex=1", "position=0"])
        let byId = queueSaveParams(["a", "b"], currentIndex: 1, positionMs: 900, indexBased: false)
        #expect(byId.map { "\($0.0)=\($0.1)" } == ["id=a", "id=b", "current=b", "position=900"])
        #expect(queueSaveParams(["a"], currentIndex: 3, positionMs: 0, indexBased: true).map(\.0) == ["id"])
    }
}

/// Answers requests from a table of paths, and keeps the paths asked for.
final class StubServer: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var answers: [String: [String]] = [:]
    nonisolated(unsafe) static var asked: [URL] = []
    static let lock = NSLock()

    static func reset() {
        lock.withLock {
            answers = [:]
            asked = []
        }
    }

    static func answer(_ path: String, _ inner: String) {
        let body = #"{"subsonic-response":{"status":"ok","version":"1.16.1","type":"octo","openSubsonic":true,"# + inner + "}}"
        lock.withLock { answers[path, default: []].append(body) }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        let body: String? = Self.lock.withLock {
            Self.asked.append(url)
            guard var queue = Self.answers[url.path], !queue.isEmpty else { return nil }
            let first = queue.removeFirst()
            Self.answers[url.path] = queue
            return first
        }
        let response = HTTPURLResponse(url: url, statusCode: body == nil ? 404 : 200, httpVersion: "HTTP/1.1", headerFields: [:])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data((body ?? "").utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static func client() -> SubsonicClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubServer.self]
        return SubsonicClient(baseURL: URL(string: "http://octo.test")!, credentials: Credentials(username: "winters", password: "pw"),
                              device: DeviceIdentity(id: "t", name: "Test"), appVersion: "1", session: URLSession(configuration: config))
    }
}

/// The phone asks the server in use for the transition profiles of the songs it plays from it,
/// keeps them, and plans with them in place of scouting.
@Suite(.serialized) struct ServerProfilesTest {
    func session(_ extensions: [String], isOcto: Bool = true) -> ProfileSession {
        ProfileSession(sourceId: "octo", isOcto: isOcto, extensions: extensions, client: StubServer.client())
    }

    let ready = #""transitionProfile":{"id":"nd-1","ready":true,"version":1,"durationMs":200000,"bodyDb":-14.0,"tempo":{"bpm":120.0,"trusted":true,"beatMs":500.0,"firstBeatMs":0.0,"downbeatMs":0.0,"confidence":2.0,"consistency":0.9,"steady":true},"head":{"startMs":0,"hopMs":100,"levels":"qqqq","bodyDb":-14.0,"gateDb":-59.0,"soundStartMs":0,"soundEndMs":30000,"boundariesMs":[]},"tail":{"startMs":140000,"hopMs":100,"levels":"qqqq","bodyDb":-14.0,"gateDb":-59.0,"soundStartMs":140000,"soundEndMs":199000,"outroStartMs":190000,"boundariesMs":[]}}"#

    func song(_ id: String, _ source: String?) -> String { streamUri(StreamRef(sourceId: source, serverId: id, mimeType: "audio/flac", bitrate: 900)) }

    func ask(_ profiles: ServerProfiles, _ uri: String) async -> TransitionProfile? {
        await withCheckedContinuation { continuation in
            let asked = profiles.request(uri) { continuation.resume(returning: $0) }
            if !asked { continuation.resume(returning: nil) }
        }
    }

    @Test func aSongFromTheServerInUseIsNamedByItsIdThere() {
        #expect(serverSongOf(song("nd-1", "home"), sourceId: "home") == "nd-1")
        #expect(serverSongOf(song("nd-1", nil), sourceId: "home") == "nd-1")
        #expect(serverSongOf(song("nd-1", "other"), sourceId: "home") == nil)
        #expect(serverSongOf("file:///sdcard/Music/a.flac", sourceId: "home") == nil)
        #expect(serverSongOf(nil, sourceId: "home") == nil)
    }

    @Test func aProfileIsAskedForOnceAndKept() async {
        StubServer.reset()
        let signedIn = session(["\(octoTransitions):1"])
        let profiles = ServerProfiles { signedIn }
        StubServer.answer("/rest/getTransitionProfile", ready)
        let uri = song("nd-1", signedIn.sourceId)
        let profile = await ask(profiles, uri)
        #expect(profile?.tail.features.outroStartMs == 190_000)
        #expect(profile?.tempoPrior == 120)
        #expect(profiles.cached(uri) === profile)
        let asked = StubServer.lock.withLock { StubServer.asked }
        #expect(asked.map(\.path) == ["/rest/getTransitionProfile"])
        #expect(URLComponents(url: asked[0], resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "id" }?.value == "nd-1")
    }

    @Test func aServerThatDoesNotSayIsAskedOnceAndThenLeftAlone() async {
        StubServer.reset()
        let signedIn = session([])
        let profiles = ServerProfiles { signedIn }
        StubServer.answer("/rest/getOpenSubsonicExtensions", #""openSubsonicExtensions":[{"name":"octoAcquisitions","versions":[1,2]}]"#)
        #expect(await ask(profiles, song("nd-1", signedIn.sourceId)) == nil)
        #expect(StubServer.lock.withLock { StubServer.asked.map(\.path) } == ["/rest/getOpenSubsonicExtensions"])
        #expect(!profiles.request(song("nd-2", signedIn.sourceId)) { _ in })
        #expect(StubServer.lock.withLock { StubServer.asked.count } == 1)
    }

    @Test func nothingIsAskedOfAServerThatIsNotOcto() {
        StubServer.reset()
        let signedIn = session(["\(octoTransitions):1"], isOcto: false)
        let profiles = ServerProfiles { signedIn }
        #expect(!profiles.request(song("nd-1", signedIn.sourceId)) { _ in })
        #expect(profiles.cached(song("nd-1", signedIn.sourceId)) == nil)
        #expect(StubServer.lock.withLock { StubServer.asked.isEmpty })
    }

    @Test func withAProfileThePlannerHearsNoLevelAndTheWholeSongsTempo() async {
        StubServer.reset()
        let signedIn = session(["\(octoTransitions):1"])
        let profiles = ServerProfiles { signedIn }
        StubServer.answer("/rest/getTransitionProfile", ready)
        let profile = await ask(profiles, song("nd-1", signedIn.sourceId))
        let heard = heardFor(profile, heardLevelDb: -12, heardTempo: 98)
        #expect(heard.level == nil && heard.tempo == 120)
        let unheard = heardFor(nil, heardLevelDb: -12, heardTempo: 98)
        #expect(unheard.level == -12 && unheard.tempo == 98)
    }

    @Test func aRangedAnswerIsToldApartFromAWholeOne() {
        #expect(answersRanges(["Content-Range": ["bytes 0-0/1234"]]))
        #expect(answersRanges(["content-range": ["bytes 0-0/1234"]]))
        #expect(!answersRanges(["Content-Range": [" "]]))
        #expect(!answersRanges(["Content-Length": ["1234"]]))
    }
}
