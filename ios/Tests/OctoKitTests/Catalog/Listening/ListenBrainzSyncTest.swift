import Foundation
import Testing
@testable import OctoKit

/// When plays are kept and sent, and how a refused batch is split.
@Suite struct ListenBrainzSyncTest {
    let song = PlayedSong(title: "Roads", artist: "Portishead", album: "Dummy", durationMs: 305_000, trackNumber: 3,
                          reachesServer: true)

    func listens(_ count: Int) -> [Listen] {
        (1...count).map { Listen(listenedAt: Int64($0), track: "t\($0)", artist: "a") }
    }

    @Test func playsAreKeptWhileSwitchedOnAndConnectedEvenNeedingAttention() {
        #expect(!ListenBrainzPrefs().keepsPlays)
        #expect(!ListenBrainzPrefs(enabled: true).keepsPlays)
        let attention = ListenBrainzPrefs(enabled: true, user: "winters", needsAttention: true)
        #expect(attention.keepsPlays)
        #expect(!attention.sends)
        #expect(ListenBrainzPrefs(enabled: true, user: "winters").sends)
    }

    @Test func theStoredChoiceIsReadBack() {
        #expect(sendPlaysOf("PhoneOnly") == .phoneOnly)
        #expect(sendPlaysOf("All") == .all)
        #expect(sendPlaysOf(nil) == .all)
        #expect(sendPlaysOf("Something") == .all)
    }

    @Test func onlySongsOnThisPhoneLeavesOutWhatTheServerHears() {
        let prefs = ListenBrainzPrefs(enabled: true, user: "winters", sendPlays: .phoneOnly)
        #expect(listenToQueue(prefs, song, startedAtMs: 10_000) == nil)
        var phoneSong = song
        phoneSong.reachesServer = false
        #expect(listenToQueue(prefs, phoneSong, startedAtMs: 10_000)?.listenedAt == 10)
        #expect(listenToQueue(ListenBrainzPrefs(enabled: true, user: "winters"), song, startedAtMs: 10_000) != nil)
        #expect(listenToQueue(ListenBrainzPrefs(), song, startedAtMs: 10_000) == nil)
        #expect(listenToQueue(prefs, nil, startedAtMs: 10_000) == nil)
    }

    @Test func nowPlayingGoesOnlyWhileSendingAndSwitchedOn() {
        let on = ListenBrainzPrefs(enabled: true, user: "winters")
        #expect(listenPlayingNow(on, song, nowMs: 5_000) != nil)
        var off = on
        off.nowPlaying = false
        #expect(listenPlayingNow(off, song, nowMs: 5_000) == nil)
        var attention = on
        attention.needsAttention = true
        #expect(listenPlayingNow(attention, song, nowMs: 5_000) == nil)
    }

    @Test func anotherAccountLetsTheWaitingPlaysGo() {
        #expect(connectingLetsQueueGo(previousUser: "someone", user: "winters"))
        #expect(!connectingLetsQueueGo(previousUser: "winters", user: "winters"))
        #expect(!connectingLetsQueueGo(previousUser: nil, user: "winters"))
    }

    @Test func theQueueFileRoundTrips() {
        let queue = [
            Listen(listenedAt: 1, track: "a", artist: "x"),
            Listen(listenedAt: 2, track: "b", artist: "y", album: "z", durationMs: 1_000, trackNumber: 4,
                   recordingMbid: "b1a9c0e9-d987-4042-ae91-78d6a3267d69", artistMbids: ["056e4f3e-d505-4dad-8ec1-d04f521cbb56"]),
        ]
        #expect(decodeListenQueue(encodeListenQueue(queue)) == queue)
        #expect(decodeListenQueue(nil) == [])
        #expect(decodeListenQueue(Data("not json".utf8)) == [])
        // Fields at their defaults are left out, and missing ones read back as defaults.
        let bare = String(decoding: encodeListenQueue([queue[0]]), as: UTF8.self)
        #expect(!bare.contains("album") && !bare.contains("durationMs") && !bare.contains("artistMbids"))
        #expect(decodeListenQueue(Data(#"[{"listenedAt":5,"track":"t","artist":"a","extra":1}]"#.utf8))
            == [Listen(listenedAt: 5, track: "t", artist: "a")])
    }

    @Test func sentPlaysLeaveTheQueue() {
        let queue = listens(3)
        #expect(queue.removingListens([queue[1]]) == [queue[0], queue[2]])
    }

    @Test func aNewPlayWaitsOutTheBackoffButATryNowDoesNot() {
        var backoff = ListenBrainzBackoff()
        #expect(backoff.allowsSend(now: false, atMs: 0))
        #expect(backoff.heard(.failed, atMs: 1_000) == .retry(afterMs: 30_000))
        #expect(!backoff.allowsSend(now: false, atMs: 2_000))
        #expect(backoff.allowsSend(now: true, atMs: 2_000))
        #expect(backoff.allowsSend(now: false, atMs: 31_000))
        #expect(backoff.heard(.rejected, atMs: 31_000) == .retry(afterMs: 60_000))
        #expect(backoff.heard(.rateLimited(retryInMs: 7_000), atMs: 100_000) == .retry(afterMs: 7_000))
        #expect(backoff.failures == 2)
        #expect(backoff.heard(.unauthorized, atMs: 100_000) == .needsAttention)
        #expect(backoff.heard(.sent, atMs: 200_000) == .goOn)
        #expect(backoff == ListenBrainzBackoff())
    }

    @Test func aRefusedBatchIsSplitSoOneBadPlayHoldsNothingBack() async throws {
        let batch = listens(5)
        let bad = batch[3]
        let removed = BatchLog()
        let submitted = BatchLog()
        let result = await deliverListens(batch, submit: { part in
            submitted.add(part.map(\.track))
            return part.contains(bad) ? .rejected : .sent
        }, remove: { part in
            removed.add(part.map(\.track))
        })
        #expect(result == .sent)
        #expect(submitted.batches == [["t1", "t2", "t3", "t4", "t5"], ["t1", "t2"], ["t3", "t4", "t5"], ["t3"], ["t4", "t5"], ["t4"], ["t5"]])
        // The bad play is let go with the rest, so it is never sent again.
        #expect(removed.batches.flatMap { $0 }.sorted() == ["t1", "t2", "t3", "t4", "t5"])
    }

    @Test func aFailureStopsTheSplitWhereItHappens() async throws {
        let batch = listens(4)
        let calls = BatchLog()
        let result = await deliverListens(batch, submit: { part in
            calls.add(part.map(\.track))
            return part.count == 4 ? .rejected : .failed
        }, remove: { _ in })
        #expect(result == .failed)
        #expect(calls.batches == [["t1", "t2", "t3", "t4"], ["t1", "t2"]])
    }

    @Test func aPastedTokenLosesItsSpaces() {
        #expect(cleanListenBrainzToken("  3fa85f64-5717-4562-b3fc-2c963f66afa6\n") == "3fa85f64-5717-4562-b3fc-2c963f66afa6")
    }
}
