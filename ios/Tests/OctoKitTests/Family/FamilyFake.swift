import Foundation
@testable import OctoKit

/// A pretend Octo server with Family on, answering the octoFamily calls by endpoint. Every call
/// is kept.
final class FamilyFake: @unchecked Sendable {
    let server = FakeServer()
    private let lock = NSLock()
    private var answers: [String: @Sendable (FakeServer.Request) -> FakeServer.Reply] = [:]

    init() {
        let fake = self
        server.route { request in fake.reply(request) }
        answer("getFamily") { _ in #""family":{"me":\#(FamilyFake.me())}"# }
        answer("getFamilyRequests") { _ in #""familyRequests":{"request":[]}"# }
        answer("getFamilyDevices") { _ in #""familyDevices":{"device":[]}"# }
        answer("getStarred2") { _ in #""starred2":{}"# }
    }

    var url: URL { server.base }
    var calls: [FakeServer.Request] { server.requests }

    func client() -> SubsonicClient { server.client(username: "alex", password: "secret") }

    func called(_ endpoint: String) -> [FakeServer.Request] { calls.filter { $0.endpoint == endpoint } }

    func answer(_ endpoint: String, _ payload: @escaping @Sendable (FakeServer.Request) -> String) {
        lock.withLock {
            answers[endpoint] = { request in FakeServer.Reply(status: 200, body: Data(FakeServer.okBody(payload(request)).utf8)) }
        }
    }

    /// Answers with this body as it is, as the family page's JSON calls do. Nil refuses with a 401.
    func raw(_ endpoint: String, _ body: @escaping @Sendable (FakeServer.Request) -> String?) {
        lock.withLock {
            answers[endpoint] = { request in
                guard let text = body(request) else { return FakeServer.Reply(status: 401, body: Data()) }
                return FakeServer.Reply(status: 200, body: Data(text.utf8))
            }
        }
    }

    func fail(_ endpoint: String, _ code: Int, _ message: String) {
        lock.withLock {
            answers[endpoint] = { _ in FakeServer.Reply(status: 200, body: Data(FamilyFake.failure(code, message).utf8)) }
        }
    }

    func close() { server.close() }

    private func reply(_ request: FakeServer.Request) -> FakeServer.Reply {
        let handler = lock.withLock { answers[request.endpoint] }
        return handler?(request) ?? FakeServer.Reply(status: 200, body: Data(Self.failure(70, "Not found").utf8))
    }

    static func failure(_ code: Int, _ message: String) -> String {
        #"{"subsonic-response":{"status":"failed","version":"1.16.1","type":"octo","openSubsonic":true,"error":{"code":\#(code),"message":"\#(message)"}}}"#
    }

    static func me(role: String = "Listener", addToLibrary: String = "Request", requestQuality: String = "Flac", weeklyLimit: Int = 10,
                   used: Int = 3, storageUsed: Int64 = 5_400_000_000, storageLimit: Int = 10, offlineCopies: Bool = false,
                   approveRequests: Bool = false, manageFamily: Bool = false, managed: Bool = true) -> String {
        #"{"username":"alex","displayName":"Alex","role":"\#(role)","managed":\#(managed),"abilities":{"addToLibrary":"\#(addToLibrary)","requestQuality":"\#(requestQuality)","autoApprove":false,"weeklyRequestLimit":\#(weeklyLimit),"streamCap":192,"awayCap":128,"away":true,"devicesAtOnce":2,"downloadFiles":false,"offlineCopies":\#(offlineCopies),"share":false,"importPlaylists":true,"cleanOnly":false,"familyPlaylistsEdit":true,"manageFamily":\#(manageFamily),"approveRequests":\#(approveRequests),"storageLimitGb":\#(storageLimit),"instantFromFamily":true},"requestsThisWeek":\#(used),"storageUsedBytes":\#(storageUsed),"place":"Home","deviceId":"d_7Qm2abc"}"#
    }

    static func request(_ id: String, state: String = "Pending", outcome: String? = nil, title: String = "Song", note: String = "",
                        username: String = "alex") -> String {
        let display = username.prefix(1).uppercased() + username.dropFirst()
        let outcomeText = outcome.map { "\"\($0)\"" } ?? "null"
        return #"{"id":"\#(id)","username":"\#(username)","displayName":"\#(display)","kind":"Song","target":"ext-deezer-song-\#(id)","title":"\#(title)","artist":"Artist","album":"Album","coverArt":null,"quality":"Flac","state":"\#(state)","created":"2026-10-20T18:00:00Z","decided":null,"decidedBy":null,"note":"\#(note)","failure":null,"librarySongId":null,"outcome":\#(outcomeText)}"#
    }
}

/// Waits up to five seconds for a check to hold.
@MainActor
func until(_ what: String, _ check: @MainActor () -> Bool) async -> Bool {
    for _ in 0..<500 {
        if check() { return true }
        try? await Task.sleep(nanoseconds: 10_000_000)
    }
    return check()
}

/// Lets running tasks get on for a moment.
func settle(_ ms: UInt64 = 200) async {
    try? await Task.sleep(nanoseconds: ms * 1_000_000)
}
