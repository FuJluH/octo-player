import Foundation
import Testing
@testable import OctoKit

func item(_ id: String, source: QueueSource = .none) -> QueueItem {
    QueueItem(trackId: id, uri: "octo-stream://song/\(id)", title: id, source: source)
}

@Suite struct UpNextTest {
    func inOrder(_ order: [Int]) -> (Int) -> Int? { { i in order.firstIndex(of: i).flatMap { order.indices.contains($0 + 1) ? order[$0 + 1] : nil } } }

    func straight(_ count: Int) -> (Int) -> Int? { inOrder(Array(0..<count)) }

    @Test func startsAtTheCurrentSong() {
        #expect(upNextOrder(["a", "b", "c", "d"], current: 1, next: straight(4)).map(\.index) == [1, 2, 3])
    }

    @Test func theSameSongTwiceGetsTwoKeys() {
        #expect(upNextOrder(["a", "b", "a", "a"], current: 0, next: straight(4)).map(\.key) == ["a#0", "b#0", "a#1", "a#2"])
    }

    @Test func keysCountInQueueOrderNotPlayOrder() {
        #expect(upNextOrder(["a", "b", "a"], current: 2, next: inOrder([2, 0, 1])).map(\.key) == ["a#1", "a#0", "b#0"])
    }

    @Test func followsTheShuffleOrder() {
        #expect(upNextOrder(["a", "b", "c", "d", "e"], current: 0, next: inOrder([3, 0, 4, 1, 2])).map(\.index) == [0, 4, 1, 2])
    }

    @Test func lastSongHasNothingAfterIt() {
        #expect(upNextOrder(["a", "b", "c"], current: 2, next: straight(3)) == [QueueSlot(2, "c#0")])
    }

    @Test func emptyQueueIsEmpty() {
        #expect(upNextOrder([], current: 0, next: straight(0)).isEmpty)
    }

    @Test func entryIdsAreTheKeysWhenSongsHaveThem() {
        #expect(upNextOrder(["a", "b", "a"], current: 0, entryIds: ["q:1", "q:2", "q:3"], next: straight(3)).map(\.key) == ["q:1", "q:2", "q:3"])
    }

    @Test func playedSongsComeOldestFirstAndStopBeforeTheCurrentOne() {
        let order = [3, 0, 4, 1, 2]
        let previous: (Int) -> Int? = { i in order.firstIndex(of: i).flatMap { $0 > 0 ? order[$0 - 1] : nil } }
        #expect(playedOrder(["a", "b", "c", "d", "e"], current: 4, previous: previous).map(\.index) == [3, 0])
    }

    @Test func theFirstSongHasNothingPlayedBeforeIt() {
        #expect(playedOrder(["a", "b"], current: 0, previous: { _ in nil }).isEmpty)
    }

    @Test func anOrderThatLoopsStillEnds() {
        #expect(upNextOrder(["a", "b"], current: 0, next: { 1 - $0 }).map(\.index) == [0, 1])
    }

    @Test func twoQuickSwipesTakeOutTheTwoSongsSwiped() {
        var queue = queueKeys(["a", "b", "a", "c"], ["q:0", "q:1", "q:2", "q:3"])
        for key in ["q:2", "q:3"] { queue.remove(at: queue.firstIndex(of: key)!) }
        #expect(queue == ["q:0", "q:1"])
    }

    @Test func keysAreEntryIdsWhenSongsHaveThem() {
        #expect(queueKeys(["a", "a"], ["q:7", nil]) == ["q:7", "a#1"])
    }
}

/// A seeded generator, so a shuffled queue is the same every run.
struct SeededRandom: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}

@Suite struct PlayQueueTest {
    func queue(_ ids: [String], current: Int = 0, order: [Int]? = nil, shuffle: Bool = false) -> PlayQueue {
        var q = PlayQueue()
        var random = SeededRandom(state: 7)
        q.setItems(ids.map { item($0) }, startIndex: current, using: &random)
        if let order { q.setPlayOrder(order) }
        q.shuffle = shuffle
        return q
    }

    @Test func eachSongGetsItsOwnEntry() {
        var q = queue(["a", "a", "b"])
        #expect(q.entryIds == ["q:0", "q:1", "q:2"])
        q.add([item("c")], at: 3)
        #expect(q.entryIds.last == "q:3")
    }

    @Test func aNewQueueIsShuffledAtRandomButAnAddedSongIsNot() {
        var q = queue(["a", "b", "c", "d", "e", "f"])
        #expect(q.order.sorted() == Array(0..<6))
        let before = q.order
        q.add([item("g")], at: 6)
        #expect(q.order.last == 6)
        #expect(Array(q.order.prefix(6)) == before)
    }

    @Test func theOrderWalksForwardAndBack() {
        let q = queue(["a", "b", "c", "d", "e", "f"], current: 2, order: [4, 0, 2, 5, 1, 3], shuffle: true)
        #expect(q.firstIndex == 4)
        #expect(q.nextIndex(after: 2, repeatMode: .off, shuffle: true) == 5)
        #expect(q.previousIndex(before: 2, repeatMode: .off, shuffle: true) == 0)
        #expect(q.nextIndex(after: 3, repeatMode: .off, shuffle: true) == nil)
        #expect(q.previousIndex(before: 4, repeatMode: .off, shuffle: true) == nil)
        #expect(q.nextIndex(after: 3, repeatMode: .all, shuffle: true) == 4)
        #expect(q.nextIndex(after: 3, repeatMode: .one, shuffle: true) == 3)
    }

    @Test func repeatOneReplaysOnEndButSkipsMoveOn() {
        var q = queue(["a", "b", "c"], current: 1)
        q.repeatMode = .one
        #expect(q.nextOnEnd == 1)
        #expect(q.nextForSkip == 2)
        #expect(q.previousForSkip == 0)
        q.setCurrent(2)
        #expect(q.nextForSkip == nil)
        q.repeatMode = .all
        #expect(q.nextForSkip == 0)
    }

    @Test func playNextGoesRightAfterTheSongOnInBothOrders() {
        var q = queue(["a", "b", "c", "d", "e", "f"], current: 2, order: [4, 0, 2, 5, 1, 3], shuffle: true)
        q.addNext([item("x")])
        #expect(q.playOrder().map { q.items[$0].trackId } == ["e", "a", "c", "x", "f", "b", "d"])
        #expect(q.currentItem?.trackId == "c")
    }

    @Test func ownSongsAddedAtTheEndGoBeforeAutoplaysStillToCome() {
        var q = PlayQueue()
        var random = SeededRandom(state: 1)
        q.setItems([item("a"), item("b")], startIndex: 1, using: &random)
        q.add([item("p", source: .autoplay), item("q", source: .autoplay)], at: 2)
        q.add([item("x", source: .you)], at: q.count)
        #expect(q.trackIds == ["a", "b", "x", "p", "q"])
        q.add([item("r", source: .autoplay)], at: q.count)
        #expect(q.trackIds.last == "r")
    }

    @Test func removingTheSongOnPlaysTheNext() {
        var q = queue(["a", "b", "c"], current: 1)
        let result = q.remove(from: 1, to: 2)
        #expect(result.currentRemoved && !result.ended)
        #expect(q.currentItem?.trackId == "c")
        var last = queue(["a", "b", "c"], current: 2)
        let ended = last.remove(from: 2, to: 3).ended
        #expect(ended)
    }

    @Test func movingKeepsTheSongOnAndThePlayOrder() {
        var q = queue(["a", "b", "c", "d"], current: 1)
        q.move(from: 3, to: 4, newIndex: 0)
        #expect(q.trackIds == ["d", "a", "b", "c"])
        #expect(q.currentItem?.trackId == "b")
        q.move(from: 2, to: 3, newIndex: 3)
        #expect(q.trackIds == ["d", "a", "c", "b"])
        #expect(q.currentItem?.trackId == "b")
    }

    @Test func undoPutsTheQueueBackExactly() {
        var q = queue(["a", "b", "c", "d"], current: 2)
        let entries = q.entryIds
        let undo = q.clearAllButCurrent()!
        #expect(q.trackIds == ["c"])
        let undone = q.undo(undo)
        #expect(undone)
        #expect(q.trackIds == ["a", "b", "c", "d"])
        #expect(q.entryIds == entries)
        #expect(q.currentItem?.trackId == "c")
    }

    @Test func undoRefusesOnceTheQueueChangedOtherwise() {
        var q = queue(["a", "b", "c"], current: 0)
        let undo = q.removeEntry(q.keys[1])!
        q.add([item("x")], at: 2)
        let undone = q.undo(undo)
        #expect(!undone)
    }

    @Test func removingPlayedSongsKeepsTheRest() {
        var q = queue(["a", "b", "c", "d"], current: 2)
        _ = q.removePlayed()
        #expect(q.trackIds == ["c", "d"])
        #expect(q.currentItem?.trackId == "c")
    }

    @Test func aQueuedSongMovesToPlayNext() {
        var q = queue(["a", "b", "c", "d"], current: 0)
        let moved = q.playEntryNext(q.keys[3])
        #expect(moved)
        #expect(q.trackIds == ["a", "d", "b", "c"])
        let current = q.playEntryNext(q.keys[0])
        #expect(!current)
        let gone = q.playEntryNext("gone")
        #expect(!gone)
    }

    @Test func songsAboutToBeDeletedLeaveWhereverTheyAre() {
        var q = queue(["a", "b", "a", "c"], current: 2)
        _ = q.removeSongs(["a"])
        #expect(q.trackIds == ["b", "c"])
        #expect(q.currentItem?.trackId == "c")
    }

    @Test func deletingTheLastSongOnPlaysTheQueueOut() {
        var q = queue(["a", "b", "c"], current: 2)
        #expect(q.removeSongs(["c"])?.ended == true)
        var middle = queue(["a", "b", "c"], current: 1)
        #expect(middle.removeSongs(["b"])?.ended == false)
        var other = queue(["a", "b", "c"], current: 2)
        #expect(other.removeSongs(["a"])?.ended == false)
    }

    @Test func theOrderCarriesOverToTheOtherDeck() {
        var q = queue(["a", "b", "c", "d", "e", "f"])
        q.setPlayOrder([4, 0, 2, 5, 1, 3])
        var copy = q
        #expect(copy.order == [4, 0, 2, 5, 1, 3])
        copy.add([item("g")], at: 6)
        #expect(copy.order.last == 6)
    }

    @Test func clearingEmptiesTheOrder() {
        var q = queue(["a", "b", "c"])
        q.clear()
        #expect(q.order.isEmpty)
    }
}

@Suite struct StoresTest {
    @Test func halfTheSongCountsAsAPlay() {
        #expect(countsAsPlay(playedMs: 90_000, durationMs: 180_000))
        #expect(!countsAsPlay(playedMs: 89_000, durationMs: 180_000))
    }

    @Test func fourMinutesCountsForLongSongs() {
        #expect(countsAsPlay(playedMs: 240_000, durationMs: 1_200_000))
        #expect(!countsAsPlay(playedMs: 239_000, durationMs: 1_200_000))
    }

    @Test func shortClipsNeverCount() { #expect(!countsAsPlay(playedMs: 29_000, durationMs: 29_000)) }

    @Test func queueRoundTripsWithShuffleOrder() {
        let snapshot = QueueSnapshot(trackIds: ["device:1", "device:2", "device:3"], shuffleOrder: [2, 0, 1], index: 1, positionMs: 42_000,
                                     repeatMode: 2, shuffle: true)
        let (rows, state) = snapshot.toRows(now: 0)
        #expect(queueFromRows(rows, state) == snapshot)
    }

    @Test func emptyQueueRestoresAsNothing() { #expect(queueFromRows([], nil) == nil) }

    @Test func aSavedQueueReadsBackHeldInsideItself() {
        let saved = QueueSnapshot(trackIds: ["device:1", "device:2"], shuffleOrder: [], index: 7, positionMs: -5, repeatMode: 0, shuffle: false)
        let read = savedQueueRead(encodeQueue(saved))
        #expect(read?.index == 1)
        #expect(read?.positionMs == 0)
        #expect(savedQueueRead(encodeQueue(QueueSnapshot.empty)) == nil)
        #expect(savedQueueRead("not a queue") == nil)
    }

    @Test func relinkKeyIgnoresCaseAndAccentsButNotLength() {
        let a = relinkKey(albumArtist: "Beyoncé", album: "Lemonade", disc: 1, track: 3, title: "Hold Up", durationMs: 221_400)
        let b = relinkKey(albumArtist: "beyonce", album: "lemonade", disc: 1, track: 3, title: "hold up", durationMs: 221_900)
        #expect(a == b)
        #expect(a != relinkKey(albumArtist: "Beyoncé", album: "Lemonade", disc: 1, track: 3, title: "Hold Up", durationMs: 230_000))
    }
}

@Suite struct QueueRestoreTest {
    @Test func picksUpAtTheSavedSongAndPlace() {
        let point = restorePoint([true, true, true, true], savedIndex: 2, positionMs: 17_192)
        #expect(point.index == 2 && point.positionMs == 17_192)
    }

    @Test func songsGoneBeforeItMoveItForward() {
        let point = restorePoint([false, true, true], savedIndex: 2, positionMs: 17_192)
        #expect(point.index == 1 && point.positionMs == 17_192)
    }

    @Test func whenTheSavedSongIsGoneItStartsFromTheTop() {
        let point = restorePoint([true, false, true], savedIndex: 1, positionMs: 17_192)
        #expect(point.index == 0 && point.positionMs == 0)
    }

    @Test func aSavedPlaceOutsideTheQueueStartsFromTheTop() {
        let point = restorePoint([true, true], savedIndex: 5, positionMs: 17_192)
        #expect(point.index == 0 && point.positionMs == 0)
    }

    @Test func theSavedShuffleLeavesOutSongsThatAreGone() {
        #expect(restoredShuffle([2, 0, 3, 1], [true, false, true, true]) == [1, 0, 2])
    }

    @Test func aShuffleThatDoesNotFitIsDropped() {
        #expect(restoredShuffle([], [true, true]) == nil)
        #expect(restoredShuffle([0, 0], [true, true]) == nil)
    }
}

/// Each server keeps its own queue: a switch puts the one in use away for its server and brings
/// back the one the next server left, and a save asked for before the switch never lands over
/// the queue handed over.
@Suite struct QueueHandOverTest {
    final class MemoryText: KeyedText, @unchecked Sendable {
        private let lock = NSLock()
        private var values: [String: String] = [:]
        func text(_ key: String) -> String? { lock.withLock { values[key] } }
        func setText(_ text: String?, for key: String) { lock.withLock { values[key] = text } }
    }

    /// The saved queue, slow to write, as a database can be.
    final class SlowRows: QueueRows, @unchecked Sendable {
        private let lock = NSLock()
        private var stored: QueueSnapshot?
        var saved: QueueSnapshot? {
            get { lock.withLock { stored } }
            set { lock.withLock { stored = newValue } }
        }
        func read() async -> QueueSnapshot? { saved.flatMap { $0.trackIds.isEmpty ? nil : $0 } }
        func write(_ snapshot: QueueSnapshot) async {
            try? await Task.sleep(for: .milliseconds(20))
            saved = snapshot
        }
    }

    func queue(_ ids: String..., index: Int = 0, positionMs: Int = 0) -> QueueSnapshot {
        QueueSnapshot(trackIds: ids, shuffleOrder: [], index: index, positionMs: positionMs, repeatMode: 0, shuffle: false)
    }

    @Test func aSwitchAndBackBringsEachServersQueueBack() async {
        let rows = SlowRows()
        let store = QueueStore(rows: rows, parked: ParkedQueues(MemoryText()))
        rows.saved = queue("home-1", "home-2", index: 1, positionMs: 42_000)
        #expect(await store.handOver(from: "home", left: queue("home-1", "home-2", index: 1, positionMs: 43_000), to: "work", keepWhenNone: false))
        #expect(await store.load() == nil, "work had none: the queue is empty")
        store.save(queue("work-1"))
        #expect(await store.handOver(from: "work", left: nil, to: "home", keepWhenNone: false))
        #expect(await store.load() == queue("home-1", "home-2", index: 1, positionMs: 43_000))
        #expect(await store.handOver(from: "home", left: nil, to: "work", keepWhenNone: false))
        #expect(await store.load() == queue("work-1"), "work's queue as saved")
    }

    @Test func aSaveAskedBeforeTheSwitchLandsBeforeIt() async {
        let rows = SlowRows()
        let store = QueueStore(rows: rows, parked: ParkedQueues(MemoryText()))
        store.save(queue("home-1"))
        store.save(queue("home-1", "home-2"))
        _ = await store.handOver(from: "home", left: nil, to: "work", keepWhenNone: false)
        #expect(await store.load() == nil, "the old queue is not written over the new one")
        _ = await store.handOver(from: "work", left: nil, to: "home", keepWhenNone: false)
        #expect(await store.load() == queue("home-1", "home-2"))
    }

    @Test func signingInFromThePhoneKeepsItsQueueUnlessTheServerLeftOne() async {
        let rows = SlowRows()
        let store = QueueStore(rows: rows, parked: ParkedQueues(MemoryText()))
        rows.saved = queue("phone-1")
        #expect(await !store.handOver(from: "phone", left: nil, to: "home", keepWhenNone: true))
        #expect(await store.load() == queue("phone-1"))
        _ = await store.handOver(from: "home", left: queue("home-1"), to: "phone", keepWhenNone: false)
        store.save(queue("phone-2"))
        #expect(await store.handOver(from: "phone", left: nil, to: "home", keepWhenNone: true))
        #expect(await store.load() == queue("home-1"))
        _ = await store.handOver(from: "home", left: nil, to: "phone", keepWhenNone: false)
        #expect(await store.load() == queue("phone-2"), "the phone's own queue waited too")
    }

    @Test func aRemovedServersQueueIsForgotten() async {
        let rows = SlowRows()
        let store = QueueStore(rows: rows, parked: ParkedQueues(MemoryText()))
        _ = await store.handOver(from: "home", left: queue("home-1"), to: "work", keepWhenNone: false)
        await store.forget("home")
        _ = await store.handOver(from: "work", left: nil, to: "home", keepWhenNone: false)
        #expect(await store.load() == nil)
    }

    @Test func aQueueIsKeptWholeAsText() {
        let shuffled = QueueSnapshot(trackIds: ["a", "b", "c"], shuffleOrder: [2, 0, 1], index: 1, positionMs: 5_000, repeatMode: 2, shuffle: true)
        #expect(decodeQueue(encodeQueue(shuffled)) == shuffled)
        #expect(decodeQueue("not a queue") == nil)
        #expect(decodeQueue(#"{"trackIds":["a"],"later":true}"#)?.trackIds == ["a"])
    }
}
