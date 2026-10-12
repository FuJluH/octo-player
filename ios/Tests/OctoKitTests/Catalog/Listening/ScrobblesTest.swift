import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import OctoKit

@Suite struct ScrobblesTest {
    @Test func waitingPlaysGoOldestFirst() {
        let queue = [PendingPlay]()
            .plusPlay(PendingPlay(serverId: "b", startedAt: 200))
            .plusPlay(PendingPlay(serverId: "a", startedAt: 100))
        #expect(queue.map(\.startedAt) == [100, 200])
    }

    @Test func theSamePlayWaitsOnce() {
        let queue = [PendingPlay]().plusPlay(PendingPlay(serverId: "a", startedAt: 100)).plusPlay(PendingPlay(serverId: "a", startedAt: 100))
        #expect(queue.count == 1)
    }

    @Test func aFullQueueLetsTheOldestGo() {
        let queue = (1...(maxPendingPlays + 5)).reduce([PendingPlay]()) { q, i in q.plusPlay(PendingPlay(serverId: "s", startedAt: Int64(i))) }
        #expect(queue.count == maxPendingPlays)
        #expect(queue.first?.startedAt == 6)
    }

    @Test func waitingPlaysRoundTrip() {
        let plays = [PendingPlay(serverId: "a", startedAt: 100), PendingPlay(serverId: "id with spaces", startedAt: 200)]
        #expect(decodePending(encodePending(plays)) == plays)
    }

    @Test func brokenWaitingLinesAreSkipped() {
        #expect(decodePending(["", "x a", "100", "100 "]) == [])
    }

    @Test func onlyPassingTroubleIsRetried() {
        #expect(worthRetrying(URLError(.notConnectedToInternet)))
        #expect(worthRetrying(OctoError.http(502)))
        #expect(worthRetrying(OctoError.notSubsonic))
        #expect(worthRetrying(OctoError.wrongCredentials("Wrong username or password")))
        #expect(!worthRetrying(OctoError.notFound("Song not found")))
        #expect(!worthRetrying(OctoError.server(code: 0, message: "Failed")))
    }

    @Test func stoppedWorkIsNotRetried() {
        #expect(!worthRetrying(CancellationError()))
        #expect(!worthRetrying(URLError(.cancelled)))
    }
}
