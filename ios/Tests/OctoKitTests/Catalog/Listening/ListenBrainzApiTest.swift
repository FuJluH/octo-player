import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import OctoKit

/// Talking to ListenBrainz, always against a local stand-in, never the real one. Waits between
/// calls pass on a clock of their own, so they take no real time.
@Suite struct ListenBrainzApiTest {
    let server = ListeningStub()
    let clock = ListeningClock()
    let token = "3fa85f64-5717-4562-b3fc-2c963f66afa6"
    let play = Listen(listenedAt: 1_700_000_000, track: "Roads", artist: "Portishead", album: "Dummy", durationMs: 305_000,
                      trackNumber: 3)

    func api(base: URL? = nil) -> ListenBrainzApi {
        let clock = clock
        let client = ListenBrainzClient(userAgent: "Octo/test", allowed: base ?? server.base, configuration: server.configuration)
        return ListenBrainzApi(client: client, base: base ?? server.base, limits: RateLimits { clock.now },
                               pause: { clock.advance($0) })
    }

    func answer(code: Int = 200, body: String = #"{"status":"ok"}"#, headers: [String: String] = [:]) {
        server.answer(code: code, body: body, headers: headers)
    }

    @Test func aGoodTokenSaysWhoseItIs() async throws {
        answer(body: #"{"code":200,"message":"Token valid.","valid":true,"user_name":"winters"}"#)

        #expect(try await api().validate(token) == .valid(user: "winters"))
        let request = server.takeRequest()
        #expect(request.method == "GET")
        #expect(request.path == "/1/validate-token")
        #expect(request.header("Authorization") == "Token \(token)")
        // The token never goes in the address.
        #expect(!request.url.absoluteString.contains(token))
    }

    @Test func aTokenListenBrainzDoesNotKnowIsInvalid() async throws {
        answer(body: #"{"code":200,"message":"Token invalid.","valid":false}"#)
        answer(code: 401, body: #"{"code":401,"error":"Invalid authorization token."}"#)

        #expect(try await api().validate(token) == .invalid)
        #expect(try await api().validate(token) == .invalid)
    }

    @Test func textThatIsNotATokenIsNeverSent() async throws {
        #expect(try await api().validate("not a token") == .invalid)
        #expect(server.requestCount == 0)
    }

    @Test func noAnswerMeansUnreachable() async throws {
        server.unreachable()
        #expect(try await api().validate(token) == .unreachable)
    }

    @Test func onePlayGoesAsSingle() async throws {
        answer()

        #expect(try await api().submit(token, [play], clientVersion: "0.1.0") == .sent)
        let request = server.takeRequest()
        #expect(request.method == "POST")
        #expect(request.path == "/1/submit-listens")
        #expect(request.header("Authorization") == "Token \(token)")
        #expect(request.header("Content-Type")?.hasPrefix("application/json") == true)
        let body = try #require(ListeningJSON.parse(request.body))
        #expect(body["listen_type"]?.string == "single")
        let sent = try #require(body.onlyPayload)
        #expect(sent["listened_at"]?.integer == 1_700_000_000)
    }

    @Test func severalPlaysGoAsOneImport() async throws {
        answer()
        let plays = (0..<maxListensPerRequest).map { offset in
            var copy = play
            copy.listenedAt = play.listenedAt + Int64(offset)
            return copy
        }

        #expect(try await api().submit(token, plays, clientVersion: "0.1.0") == .sent)
        let body = try #require(ListeningJSON.parse(server.takeRequest().body))
        #expect(body["listen_type"]?.string == "import")
        #expect(body["payload"]?.array?.count == maxListensPerRequest)
    }

    @Test func moreThanOneRequestHoldsIsNeverSent() async throws {
        let plays = (0...maxListensPerRequest).map { offset in
            var copy = play
            copy.listenedAt = play.listenedAt + Int64(offset)
            return copy
        }
        await #expect(throws: ListenBrainzError.batchSize(maxListensPerRequest + 1)) {
            _ = try await api().submit(token, plays, clientVersion: "0.1.0")
        }
        #expect(server.requestCount == 0)
    }

    @Test func answersSayWhatToDoNext() async throws {
        answer(code: 401)
        answer(code: 400)
        answer(code: 503)
        let api = api()

        #expect(try await api.submit(token, [play], clientVersion: "1") == .unauthorized)
        #expect(try await api.submit(token, [play], clientVersion: "1") == .rejected)
        #expect(try await api.submit(token, [play], clientVersion: "1") == .failed)
    }

    @Test func tooManyCallsWaitsAsLongAsListenBrainzSays() async throws {
        answer(code: 429, body: #"{"code":429,"error":"Too many requests"}"#,
               headers: ["X-RateLimit-Reset-In": "7", "X-RateLimit-Remaining": "0"])
        let api = api()

        #expect(try await api.submit(token, [play], clientVersion: "1") == .rateLimited(retryInMs: 7_000))
        // Now playing is skipped rather than held back while no calls are left.
        if case .rateLimited = try await api.playingNow(token, play, clientVersion: "1") {} else {
            Issue.record("Now playing went out while no calls were left")
        }
        #expect(server.requestCount == 1)
    }

    @Test func anEmptyWindowIsWaitedOutBeforeTheNextCall() async throws {
        answer(headers: ["X-RateLimit-Remaining": "0", "X-RateLimit-Reset-In": "5"])
        answer()
        let api = api()

        _ = try await api.submit(token, [play], clientVersion: "1")
        let before = clock.now
        #expect(try await api.submit(token, [play], clientVersion: "1") == .sent)
        #expect(clock.now - before >= 4_000)
        #expect(server.requestCount == 2)
    }

    @Test func theListenBrainzClientDropsEverythingAddedForTheServer() async throws {
        let shared = server.configuration
        shared.httpAdditionalHeaders = ["X-Server-Secret": "s1", "CF-Access-Client-Id": "s2"]
        let client = ListenBrainzClient(userAgent: "Octo/test", allowed: server.base, configuration: shared)
        #expect(client.session.configuration.httpAdditionalHeaders?.isEmpty ?? true)
        #expect(client.session.delegate is ListenBrainzNoRedirects)

        answer()
        var request = URLRequest(url: URL(string: "1/validate-token", relativeTo: server.base)!.absoluteURL)
        request.httpMethod = "GET"
        _ = try await client.send(request)
        let seen = server.takeRequest()
        #expect(seen.header("X-Server-Secret") == nil)
        #expect(seen.header("CF-Access-Client-Id") == nil)
        #expect(seen.header("User-Agent") == "Octo/test")
    }

    @Test func theListenBrainzClientOnlyTalksToListenBrainzOverHttps() async throws {
        let client = ListenBrainzClient(userAgent: "Octo/test", configuration: server.configuration)
        let elsewhere = URLRequest(url: URL(string: "1/submit-listens", relativeTo: server.base)!.absoluteURL)
        await #expect(throws: ListenBrainzError.notListenBrainz) { _ = try await client.send(elsewhere) }
        let plain = URLRequest(url: URL(string: "http://api.listenbrainz.org/1/submit-listens")!)
        await #expect(throws: ListenBrainzError.notListenBrainz) { _ = try await client.send(plain) }
        #expect(server.requestCount == 0)
        #expect(listenBrainzAPI.scheme == "https")
        #expect(listenBrainzAPI.host == "api.listenbrainz.org")
        #expect(client.isAllowed(URL(string: "https://API.listenbrainz.org:443/1/submit-listens")!))
        #expect(!client.isAllowed(URL(string: "https://api.listenbrainz.org:8443/1/submit-listens")!))
    }

    @Test func aRedirectIsNeverFollowed() async throws {
        let session = URLSession(configuration: .ephemeral)
        let task = session.dataTask(with: listenBrainzAPI)
        let redirect = HTTPURLResponse(url: listenBrainzAPI, statusCode: 302, httpVersion: "HTTP/1.1",
                                       headerFields: ["Location": "https://elsewhere.example/"])!
        let followed = await withCheckedContinuation { (done: CheckedContinuation<URLRequest?, Never>) in
            ListenBrainzNoRedirects().urlSession(session, task: task, willPerformHTTPRedirection: redirect,
                                                 newRequest: URLRequest(url: URL(string: "https://elsewhere.example/")!)) {
                done.resume(returning: $0)
            }
        }
        #expect(followed == nil)
        session.invalidateAndCancel()

        // A redirect answer comes back as it is, and is no success.
        answer(code: 302, body: "", headers: ["Location": "https://listening-elsewhere.stub/"])
        #expect(try await api().submit(token, [play], clientVersion: "1") == .failed)
    }
}
