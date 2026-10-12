import Foundation
import Testing
@testable import OctoKit

@Suite struct ShuffleQueueTest {
    /// The songs in the order they play, by name, for a queue in queue order.
    func played(_ queue: [String], _ order: [Int]) -> [String] { order.map { queue[$0] } }

    /// What a player does when songs are added: they go into the queue at `at`, and into the
    /// play order at the rank the rules give.
    func add(_ queue: [String], _ order: [Int], current: Int, at: Int, songs: [String], playNext: Bool = false,
             autoplay: Set<String> = []) -> ([String], [Int]) {
        let rank = shuffleRankFor(order, at: at, size: queue.count, current: current, playNext: playNext,
                                  beforeAutoplay: at < queue.count && autoplay.contains(queue[at]))
        let newQueue = Array(queue[0..<at]) + songs + Array(queue[at...])
        return (newQueue, insertIntoShuffle(order, at: at, count: songs.count, rank: rank))
    }

    let queue = ["a", "b", "c", "d", "e", "f"]
    let order = [4, 0, 2, 5, 1, 3]
    let current = 2

    @Test func playNextPlaysRightAfterTheCurrentSongInShuffledOrder() {
        let (q, o) = add(queue, order, current: current, at: current + 1, songs: ["x"], playNext: true)
        #expect(played(q, o) == ["e", "a", "c", "x", "f", "b", "d"])
    }

    @Test func playNextOfSeveralSongsKeepsTheirOwnOrder() {
        let (q, o) = add(queue, order, current: current, at: current + 1, songs: ["x", "y", "z"], playNext: true)
        #expect(played(q, o) == ["e", "a", "c", "x", "y", "z", "f", "b", "d"])
    }

    @Test func playNextWhileTheLastSongInTheQueueIsOnStillPlaysNext() {
        let (q, o) = add(queue, order, current: 5, at: 6, songs: ["x"], playNext: true)
        #expect(played(q, o) == ["e", "a", "c", "f", "x", "b", "d"])
    }

    @Test func addToQueueGoesToTheEndOfTheShuffledOrder() {
        let (q, o) = add(queue, order, current: current, at: queue.count, songs: ["x", "y"])
        #expect(played(q, o) == ["e", "a", "c", "f", "b", "d", "x", "y"])
    }

    @Test func theLatestPlayNextPlaysFirst() {
        let (q1, o1) = add(queue, order, current: current, at: current + 1, songs: ["x"], playNext: true)
        let (q2, o2) = add(q1, o1, current: current, at: current + 1, songs: ["y"], playNext: true)
        #expect(played(q2, o2) == ["e", "a", "c", "y", "x", "f", "b", "d"])
    }

    @Test func ownSongsGoBeforeAutoplaySongsStillToCome() {
        let q0 = ["a", "b", "c", "p", "q"]
        let o0 = [1, 0, 2, 3, 4]
        let autoplay: Set<String> = ["p", "q"]
        let flags = q0.map { autoplay.contains($0) }
        let at = ownSongsAt(q0.count, upcoming: [3, 4], autoplay: flags)
        #expect(at == 3)
        let (q, o) = add(q0, o0, current: 2, at: at, songs: ["x"], autoplay: autoplay)
        #expect(played(q, o) == ["b", "a", "c", "x", "p", "q"])
    }

    @Test func withNoAutoplaySongsAheadOwnSongsGoAtTheEnd() {
        let flags = [false, true, false]
        #expect(ownSongsAt(3, upcoming: [2], autoplay: flags) == 3)
        #expect(ownSongsAt(1, upcoming: [2], autoplay: flags) == 1)
    }

    @Test func songsPutInTheMiddleFollowTheSongBeforeThem() {
        let (q, o) = add(queue, order, current: 0, at: 3, songs: ["x"])
        #expect(played(q, o) == ["e", "a", "c", "x", "f", "b", "d"])
    }

    @Test func songsAddedAtTheStartOfTheQueueGoFirst() {
        let (q, o) = add(queue, order, current: 2, at: 0, songs: ["x"])
        #expect(played(q, o) == ["x", "e", "a", "c", "f", "b", "d"])
    }

    @Test func removingSongsKeepsTheRestInTheirPlayOrder() {
        let o = removeFromShuffle(order, from: 1, to: 3)
        #expect(played(["a", "d", "e", "f"], o) == ["e", "a", "f", "d"])
    }

    @Test func movingSongsInTheQueueKeepsThePlayOrder() {
        let o = moveInShuffle(order, from: 1, to: 3, newFrom: 4)
        #expect(played(["a", "d", "e", "f", "b", "c"], o) == played(queue, order))
    }
}

@Suite struct QueueRunsTest {
    func remove(_ queue: [String], _ positions: [Int]) -> [String] {
        var out = queue
        for run in removalRuns(positions) { out.removeSubrange(run) }
        return out
    }

    func putBack(_ before: [String], _ now: [String]) -> [String]? {
        guard let runs = putBackRuns(before, now) else { return nil }
        var out = now
        for run in runs { out.insert(contentsOf: run.old.map { before[$0] }, at: run.at) }
        return out
    }

    @Test func runsComeOffFromTheBack() {
        #expect(removalRuns([8, 1, 5, 2, 7]) == [7...8, 5...5, 1...2])
        #expect(remove(["a", "b", "c", "d", "e", "f", "g"], [1, 2, 5]) == ["a", "d", "e", "g"])
    }

    @Test func undoPutsRemovedSongsBackWhereTheyWere() {
        let before = ["a", "b", "c", "d", "e"]
        let now = remove(before, [1, 3])
        #expect(now == ["a", "c", "e"])
        #expect(putBack(before, now) == before)
    }

    @Test func undoOfClearKeepsTheCurrentSongInPlace() {
        let before = ["a", "b", "c", "d"]
        let now = remove(before, [0, 1, 3])
        #expect(now == ["c"])
        let runs = putBackRuns(before, now)
        #expect(runs?.map(\.at) == [0, 3])
        #expect(runs?.map(\.old) == [[0, 1], [3]])
        #expect(putBack(before, now) == before)
    }

    @Test func undoDoesNothingOnceTheQueueChangedSomeOtherWay() {
        let before = ["a", "b", "c", "d"]
        #expect(putBackRuns(before, ["c", "x"]) == nil)
        #expect(putBackRuns(before, ["c", "a"]) == nil)
        #expect(putBackRuns(before, before) == nil)
    }

    @Test func songsAboutToBeDeletedLeaveTheQueueEveryTimeTheyAreInIt() {
        let queue = ["a", "b", "c", "b", "d"]
        #expect(queuePositionsOf(queue, ["b"]) == [1, 3])
        #expect(queuePositionsOf(queue, ["a", "b", "d"]) == [0, 1, 3, 4])
        #expect(queuePositionsOf(queue, ["z"]).isEmpty)
        #expect(remove(queue, queuePositionsOf(queue, ["b"])) == ["a", "c", "d"])
        #expect(remove(queue, queuePositionsOf(queue, ["a", "b", "d"])) == ["c"])
    }
}

@Suite struct QueueUndoTest {
    @Test func anUntouchedQueueHasTheSongWhereItWentIn() {
        #expect(findInserted(["now", "new", "later"], ["new"], insertedAt: 1) == 1)
    }

    @Test func aSongMovedSinceIsFoundWhereItIsNow() {
        #expect(findInserted(["now", "other", "new", "later"], ["new"], insertedAt: 1) == 2)
    }

    @Test func theSameSongTwiceTakesTheCopyNearestWhereItWentIn() {
        #expect(findInserted(["now", "new", "a", "b", "c", "new"], ["new"], insertedAt: 1) == 1)
        #expect(findInserted(["new", "a", "b", "c", "now", "new"], ["new"], insertedAt: 5) == 5)
    }

    @Test func songsPutInTogetherAreFoundTogether() {
        #expect(findInserted(["now", "x", "a", "b", "later"], ["a", "b"], insertedAt: 1) == 2)
        #expect(findInserted(["now", "a", "x", "b"], ["a", "b"], insertedAt: 1) == nil)
    }

    @Test func aSongGoneFromTheQueueIsNotFound() {
        #expect(findInserted(["now", "later"], ["new"], insertedAt: 1) == nil)
        #expect(findInserted([], ["new"], insertedAt: 0) == nil)
        #expect(findInserted(["now"], [], insertedAt: 0) == nil)
    }
}

@Suite struct QueueSourcesTest {
    let album = QueueSource.played("OK Computer")
    let you = QueueSource.you

    @Test func headingsSayWhereSongsCameFrom() {
        #expect(queueSourceTitle(you) == "Next from you")
        #expect(queueSourceTitle(album) == "Next from OK Computer")
        #expect(queueSourceTitle(.none) == "Up next")
        #expect(queueSourceTitle(.autoplay) == "Next from Autoplay")
    }

    @Test func songsToComeAreCutIntoRunsInPlayOrder() {
        let songs: [(String, QueueSource)] = [("x", you), ("y", you), ("a", album), ("b", album), ("z", you)]
        let runs = sourceRuns(songs) { $0.1 }.map { ($0.source, $0.items.map(\.0)) }
        #expect(runs.map(\.0) == [you, album, you])
        #expect(runs.map(\.1) == [["x", "y"], ["a", "b"], ["z"]])
        #expect(sourceRuns([String]()) { _ in .you }.isEmpty)
    }

    @Test func aMovedSongJoinsTheRunItLandsIn() {
        #expect(movedSource(album, before: you, after: you) == you)
        #expect(movedSource(you, before: album, after: album) == album)
        #expect(movedSource(album, before: nil, after: you) == you)
        #expect(movedSource(you, before: album, after: nil) == album)
        #expect(movedSource(album, before: you, after: album) == album)
        #expect(movedSource(you, before: you, after: album) == you)
        #expect(movedSource(album, before: nil, after: nil) == album)
    }

    @Test func aSongNeverBecomesAutoplaysByMoving() {
        #expect(movedSource(you, before: .autoplay, after: nil) == you)
        #expect(movedSource(album, before: .autoplay, after: .autoplay) == album)
        #expect(movedSource(.autoplay, before: you, after: you) == you)
    }

    @Test func sourcesSurviveBeingSaved() {
        for source in [you, album, QueueSource.none, .autoplay, .played("Radio: a:b")] {
            #expect(queueSourceOf(source.encoded) == source)
        }
        #expect(queueSourceOf(nil) == .none)
        #expect(queueSourceOf("something new") == .none)
    }
}

@Suite struct AutoplayPicksTest {
    @Test func theServersSimilarSongsComeFirstInItsOrder() {
        #expect(autoplayPicks(similar: ["s1", "s2", "s3"], sameArtist: ["a1"], sameGenre: ["g1"], exclude: []) == ["s1", "s2", "s3"])
    }

    @Test func recentPlaysAndTheQueueAreNeverPicked() {
        #expect(autoplayPicks(similar: ["s1", "s2", "s3", "s2"], sameArtist: [], sameGenre: [], exclude: ["s1"]) == ["s2", "s3"])
    }

    @Test func withoutTheServerTheSameArtistComesBeforeTheSameGenre() {
        #expect(autoplayPicks(similar: [], sameArtist: ["a1", "a2", "seed"], sameGenre: ["a2", "g1", "g2"], exclude: ["seed"])
            == ["a1", "a2", "g1", "g2"])
    }

    @Test func whenTheServerOnlyOffersSongsJustPlayedTheLibraryFillsIn() {
        #expect(autoplayPicks(similar: ["s1"], sameArtist: ["a1"], sameGenre: [], exclude: ["s1"]) == ["a1"])
    }

    @Test func addsOneBatchAtATime() {
        let picks = autoplayPicks(similar: (0..<30).map { "s\($0)" }, sameArtist: [], sameGenre: [], exclude: [])
        #expect(picks.count == autoplayBatch)
        #expect(picks.first == "s0")
    }

    @Test func nothingToPickIsNothing() {
        #expect(autoplayPicks(similar: [], sameArtist: ["seed"], sameGenre: [], exclude: ["seed"]).isEmpty)
    }
}
