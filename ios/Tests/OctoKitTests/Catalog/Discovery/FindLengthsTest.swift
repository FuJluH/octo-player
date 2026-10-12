import Foundation
import Testing
@testable import OctoKit

/// A find's length, learned from the player when the server sent none.
@Suite struct FindLengthsTest {
    private func find(_ id: String, ms: Int64, requestedAt: Int64 = 0, adoptedId: String = "") -> OnlineSong {
        OnlineSong(id: id, sourceId: "server:x", nativeId: String(id.dropFirst(findPrefix.count)), title: "Song", artist: "Artist",
                   album: "", albumId: nil, artistId: nil, durationMs: ms, coverId: nil, mimeType: "audio/mp4", bitrate: 128, seenAt: 1,
                   requestedAt: requestedAt, adoptedId: adoptedId)
    }

    // A row shows the real length once playing the song found its listing wrong, and the listing
    // until then.
    @Test func aRowShowsTheRealLengthFirst() {
        #expect(shownLengthMs(200_000, learnedMs: 215_000) == 215_000)
        #expect(shownLengthMs(0, learnedMs: 215_000) == 215_000)
        #expect(shownLengthMs(200_000, learnedMs: nil) == 200_000)
        #expect(shownLengthMs(0, learnedMs: nil) == 0)
    }

    @Test func theServerSendingNoLengthAgainKeepsTheLearnedOne() {
        let stored = find("find:a", ms: 215_000, requestedAt: 5, adoptedId: "t-1")
        let kept = keptFind(find("find:a", ms: 0), stored)
        #expect(kept.durationMs == 215_000)
        #expect(kept.requestedAt == 5)
        #expect(kept.adoptedId == "t-1")
        // A length the server does send wins.
        #expect(keptFind(find("find:a", ms: 190_000), stored).durationMs == 190_000)
    }

    // What the server sends again for a find already stored, as the app reads it: a placeholder
    // of exactly three minutes reads as unknown.
    private func refreshed(_ seconds: Int) -> OnlineSong {
        Song(id: "a", title: "Song", artist: "Artist", duration: seconds).toFind(sourceId: "server:x", now: 2)
    }

    @Test func aKnownLengthFromTheServerReplacesAnUnknownOne() {
        let stored = find("find:a", ms: 0)
        #expect(keptFind(refreshed(212), stored).durationMs == 212_000)
    }

    @Test func noLengthOrThePlaceholderNeverReplacesAKnownOne() {
        // Learned from the player, or sent by the server before.
        let stored = find("find:a", ms: 215_000)
        #expect(keptFind(refreshed(0), stored).durationMs == 215_000)
        #expect(keptFind(refreshed(180), stored).durationMs == 215_000)
        // And an unknown one stays unknown.
        #expect(keptFind(refreshed(180), find("find:a", ms: 0)).durationMs == 0)
    }

    /// Storage of finds' lengths, as the real one keeps them.
    private actor Lengths {
        var rows: [String: Int64]
        var asked = 0

        init(_ rows: [String: Int64]) { self.rows = rows }

        func store(_ id: String, _ ms: Int64) -> Int {
            asked += 1
            guard rows[id] != nil else { return 0 }
            rows[id] = ms
            return 1
        }
    }

    /// Stands in for the player's length corrections: a length of a second to a day that is more
    /// than a second off the listing is kept in memory and answered; anything else is not.
    private actor RealLengths {
        var corrected: [String: Int64] = [:]

        func learn(_ trackId: String, _ listedMs: Int64, _ playerMs: Int64) -> Int64? {
            guard playerMs >= 1_000, playerMs <= 24 * 60 * 60_000 else { return nil }
            if listedMs > 0 && abs(playerMs - listedMs) <= 1_000 { return nil }
            corrected[trackId] = playerMs
            return playerMs
        }

        func lengthMs(_ trackId: String, _ listedMs: Int64) -> Int64 { corrected[trackId] ?? listedMs }
    }

    private func makeLengths(_ storage: Lengths, _ real: RealLengths) -> FindLengths {
        FindLengths(store: { id, ms in await storage.store(id, ms) }, correct: { id, listed, player in await real.learn(id, listed, player) })
    }

    // A find listed with no length, or with one more than a second off its sound, takes the
    // player's length, in storage and on screen.
    @Test func aMissingOrWrongLengthIsStoredAndShown() async throws {
        let storage = Lengths(["find:a": 0, "find:b": 296_000, "find:c": 213_000])
        let real = RealLengths()
        let lengths = makeLengths(storage, real)
        try await lengths.learn("find:a", listedMs: 0, playerMs: 215_000)
        try await lengths.learn("find:b", listedMs: 296_000, playerMs: 291_000)
        try await lengths.learn("find:c", listedMs: 213_000, playerMs: 213_400)
        #expect(await storage.rows["find:a"] == 215_000)
        #expect(await storage.rows["find:b"] == 291_000)
        // Within a second: the listing was right.
        #expect(await storage.rows["find:c"] == 213_000)
        #expect(await real.corrected == ["find:a": 215_000, "find:b": 291_000])
    }

    @Test func aLengthThatIsNotASongsIsNotKept() async throws {
        let storage = Lengths(["find:a": 0])
        let real = RealLengths()
        let lengths = makeLengths(storage, real)
        try await lengths.learn("find:a", listedMs: 0, playerMs: 0)
        try await lengths.learn("find:a", listedMs: 0, playerMs: -1)
        try await lengths.learn("find:a", listedMs: 0, playerMs: 400)
        try await lengths.learn("find:a", listedMs: 0, playerMs: 25 * 60 * 60_000)
        #expect(await storage.asked == 0)
        #expect(await real.corrected == [:])
    }

    // A library song's wrong listing is corrected on screen only (the next library read would undo
    // a stored one); repeats store nothing again.
    @Test func librarySongsAndRepeatsStoreNothing() async throws {
        let storage = Lengths(["find:a": 0])
        let real = RealLengths()
        let lengths = makeLengths(storage, real)
        try await lengths.learn("t-42", listedMs: 200_000, playerMs: 215_000)
        try await lengths.learn("find:a", listedMs: 0, playerMs: 215_000)
        try await lengths.learn("find:a", listedMs: 0, playerMs: 215_000)
        #expect(await storage.asked == 1)
        #expect(await storage.rows["find:a"] == 215_000)
        #expect(await real.lengthMs("t-42", 200_000) == 215_000)
    }

    /// A store that fails leaves the find to be stored the next time it opens.
    @Test func aFailedStoreIsTriedAgain() async throws {
        struct Refused: Error {}
        let tries = Lengths(["find:a": 0])
        let real = RealLengths()
        let failing = FindLengths(store: { id, ms in
            let count = await tries.store(id, ms)
            if await tries.asked == 1 { throw Refused() }
            return count
        }, correct: { id, listed, player in await real.learn(id, listed, player) })
        await #expect(throws: Refused.self) { try await failing.learn("find:a", listedMs: 0, playerMs: 215_000) }
        try await failing.learn("find:a", listedMs: 0, playerMs: 215_000)
        #expect(await tries.asked == 2)
    }
}
