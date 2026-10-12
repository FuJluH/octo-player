import Foundation

/// The queue as the player holds it: the songs in queue order, the play order used under
/// shuffle, repeat and shuffle, and the song on now. Navigation follows the usual player rules:
/// the next song after the last is the first under repeat all and none otherwise; repeat one
/// plays the same song again when it ends, but skipping moves on as if repeat were off.
///
/// The play order is a permutation of the queue's positions. Only a queue built from nothing is
/// shuffled at random; songs put in later take their place by the rules in ShuffleQueue.
public struct PlayQueue: Sendable, Equatable {
    public private(set) var items: [QueueItem] = []
    /// Queue positions in the order they play under shuffle.
    public private(set) var order: [Int] = []
    public var shuffle = false
    public var repeatMode: RepeatMode = .off
    /// The song on now; 0 when the queue is empty.
    public private(set) var current = 0
    /// The next queue entry id to give out.
    private var nextEntry = 0

    public init() {}

    public var isEmpty: Bool { items.isEmpty }
    public var count: Int { items.count }
    public var currentItem: QueueItem? { items.indices.contains(current) ? items[current] : nil }
    public var trackIds: [String] { items.map(\.trackId) }
    public var entryIds: [String?] { items.map(\.entryId) }

    // MARK: Navigation

    private func rank(of index: Int) -> Int? { order.firstIndex(of: index) }

    /// The position that plays after `index` under these rules, or nil when none does.
    public func nextIndex(after index: Int, repeatMode: RepeatMode, shuffle: Bool) -> Int? {
        guard items.indices.contains(index) else { return nil }
        if repeatMode == .one { return index }
        if shuffle {
            guard let at = rank(of: index) else { return nil }
            if at + 1 < order.count { return order[at + 1] }
            return repeatMode == .all ? order.first : nil
        }
        if index + 1 < items.count { return index + 1 }
        return repeatMode == .all ? 0 : nil
    }

    /// The position that plays before `index` under these rules, or nil when none does.
    public func previousIndex(before index: Int, repeatMode: RepeatMode, shuffle: Bool) -> Int? {
        guard items.indices.contains(index) else { return nil }
        if repeatMode == .one { return index }
        if shuffle {
            guard let at = rank(of: index) else { return nil }
            if at > 0 { return order[at - 1] }
            return repeatMode == .all ? order.last : nil
        }
        if index > 0 { return index - 1 }
        return repeatMode == .all ? items.count - 1 : nil
    }

    /// What plays when the song on now ends by itself.
    public var nextOnEnd: Int? { nextIndex(after: current, repeatMode: repeatMode, shuffle: shuffle) }

    /// What a skip forward or back moves to: repeat one counts as off.
    public var nextForSkip: Int? { nextIndex(after: current, repeatMode: repeatMode == .one ? .off : repeatMode, shuffle: shuffle) }
    public var previousForSkip: Int? {
        previousIndex(before: current, repeatMode: repeatMode == .one ? .off : repeatMode, shuffle: shuffle)
    }

    /// The first position in play order.
    public var firstIndex: Int? { items.isEmpty ? nil : (shuffle ? order.first : 0) }

    /// The queue positions after the current song, in the order they will play.
    public func upcoming() -> [Int] {
        var out: [Int] = []
        var i = current
        while out.count < items.count {
            guard let next = nextIndex(after: i, repeatMode: .off, shuffle: shuffle) else { break }
            out.append(next)
            i = next
        }
        return out
    }

    /// The play order in use right now, shuffle included.
    public func playOrder() -> [Int] {
        guard let first = firstIndex else { return [] }
        var out = [first]
        var i = first
        while out.count < items.count, let next = nextIndex(after: i, repeatMode: .off, shuffle: shuffle) {
            out.append(next)
            i = next
        }
        return out
    }

    // MARK: Changes

    /// Each song gets a queue entry id as it goes in, unless it has one.
    private mutating func stamped(_ items: [QueueItem]) -> [QueueItem] {
        items.map { item in
            if item.entryId != nil { return item }
            defer { nextEntry += 1 }
            return item.withEntry("q:\(nextEntry)")
        }
    }

    /// A new queue: shuffled at random, playing from `startIndex`.
    public mutating func setItems(_ newItems: [QueueItem], startIndex: Int, using random: inout some RandomNumberGenerator) {
        items = stamped(newItems)
        order = Array(0..<items.count).shuffled(using: &random)
        current = items.isEmpty ? 0 : min(max(startIndex, 0), items.count - 1)
    }

    public mutating func setItems(_ newItems: [QueueItem], startIndex: Int) {
        var random = SystemRandomNumberGenerator()
        setItems(newItems, startIndex: startIndex, using: &random)
    }

    /// Sets the play order for shuffle, as saved or as it was before an edit.
    public mutating func setPlayOrder(_ newOrder: [Int]) {
        if newOrder.count == items.count && newOrder.sorted() == Array(0..<items.count) { order = newOrder }
    }

    /// Songs go in at `index`. Songs the listener adds at the end go before any Autoplay songs
    /// still to come, since those only fill in once the listener's own run out. Under shuffle,
    /// added songs take their place in the play order by the rules in ShuffleQueue instead of a
    /// random one. `playNext` puts them right after the song that is on in the play order too.
    public mutating func add(_ newItems: [QueueItem], at index: Int, playNext: Bool = false) {
        guard !newItems.isEmpty else { return }
        let size = items.count
        if size == 0 {
            var random = SystemRandomNumberGenerator()
            setItems(newItems, startIndex: 0, using: &random)
            return
        }
        let adding = newItems.allSatisfy { $0.source == .autoplay }
        let autoplay = items.map { $0.source == .autoplay }
        let at = adding || playNext ? min(max(index, 0), size) : ownSongsAt(min(max(index, 0), size), upcoming: upcoming(), autoplay: autoplay)
        let beforeAutoplay = !adding && autoplay.indices.contains(at) && autoplay[at]
        let rank = shuffleRankFor(order, at: at, size: size, current: current, playNext: playNext, beforeAutoplay: beforeAutoplay)
        items.insert(contentsOf: stamped(newItems), at: at)
        order = insertIntoShuffle(order, at: at, count: newItems.count, rank: rank)
        if current >= at { current += newItems.count }
    }

    /// "Play next": the songs go right after the song that is on, in the queue and, under
    /// shuffle, in the play order too.
    public mutating func addNext(_ newItems: [QueueItem]) {
        add(newItems, at: min(current + 1, items.count), playNext: true)
    }

    /// Puts songs back exactly where they were, entry ids and all, for an undo. `runs` are queue
    /// positions and the songs that go there, lowest first; `order` is the play order once they
    /// are all back.
    public mutating func putBack(_ runs: [(at: Int, items: [QueueItem])], order newOrder: [Int]) {
        for run in runs {
            let at = min(max(run.at, 0), items.count)
            let rank = shuffleRankFor(order, at: at, size: items.count, current: -1)
            items.insert(contentsOf: run.items, at: at)
            order = insertIntoShuffle(order, at: at, count: run.items.count, rank: rank)
            if !items.isEmpty && current >= at && items.count > run.items.count { current += run.items.count }
        }
        setPlayOrder(newOrder)
    }

    /// Takes out the songs at queue positions `from` until `to`. When the song on now goes, the
    /// one that would have played after it (that is still here) is on, from its start; answers
    /// whether that happened, and whether nothing was left to play.
    @discardableResult
    public mutating func remove(from: Int, to: Int) -> (currentRemoved: Bool, ended: Bool) {
        let from = max(0, from), to = min(items.count, to)
        guard from < to else { return (false, false) }
        let removedCurrent = current >= from && current < to
        var successor: Int?
        if removedCurrent {
            var i = current
            var seen = 0
            while seen < items.count, let next = nextIndex(after: i, repeatMode: repeatMode, shuffle: shuffle) {
                if next < from || next >= to { successor = next; break }
                i = next
                seen += 1
            }
        }
        items.removeSubrange(from..<to)
        order = removeFromShuffle(order, from: from, to: to)
        let count = to - from
        if removedCurrent {
            if let successor {
                current = successor >= to ? successor - count : successor
                return (true, false)
            }
            current = firstIndex ?? 0
            return (true, true)
        }
        if current >= to { current -= count }
        return (false, false)
    }

    /// Takes out runs of songs, last run first. The rest keep their play order.
    @discardableResult
    public mutating func removeRuns(_ runs: [ClosedRange<Int>]) -> (currentRemoved: Bool, ended: Bool) {
        var removed = false, ended = false
        for run in runs {
            let result = remove(from: run.lowerBound, to: run.upperBound + 1)
            removed = removed || result.currentRemoved
            ended = result.ended
        }
        return (removed, ended)
    }

    /// Moves queue positions `from` until `to` to start at `newIndex`; each song keeps its place
    /// in the play order, and the song on now stays on.
    public mutating func move(from: Int, to: Int, newIndex: Int) {
        guard from < to, from >= 0, to <= items.count else { return }
        let count = to - from
        let newIndex = min(max(newIndex, 0), items.count - count)
        guard newIndex != from else { return }
        let currentEntry = current
        let moved = Array(items[from..<to])
        items.removeSubrange(from..<to)
        items.insert(contentsOf: moved, at: newIndex)
        order = moveInShuffle(order, from: from, to: to, newFrom: newIndex)
        // Where the song on now went.
        if currentEntry >= from && currentEntry < to {
            current = newIndex + (currentEntry - from)
        } else {
            let afterRemoval = currentEntry >= to ? currentEntry - count : currentEntry
            current = afterRemoval >= newIndex ? afterRemoval + count : afterRemoval
        }
    }

    /// Moves the song on now.
    public mutating func setCurrent(_ index: Int) {
        guard items.indices.contains(index) else { return }
        current = index
    }

    /// Changes one song in place, keeping its entry.
    public mutating func update(at index: Int, _ change: (inout QueueItem) -> Void) {
        guard items.indices.contains(index) else { return }
        var item = items[index]
        let entry = item.entryId
        change(&item)
        item.entryId = entry
        items[index] = item
    }

    /// Empties the queue.
    public mutating func clear() {
        items = []
        order = []
        current = 0
    }

    /// Where the song with this entry sits, if it is in the queue.
    public func position(ofEntry entry: String) -> Int? { items.firstIndex { $0.entryId == entry } }

    /// The key each song is drawn under.
    public var keys: [String] { queueKeys(trackIds, entryIds) }

    /// The queue in the order it will play, starting with the current song.
    public func upNext() -> [QueueSlot] {
        upNextOrder(trackIds, current: current, entryIds: entryIds) { nextIndex(after: $0, repeatMode: .off, shuffle: shuffle) }
    }

    /// The songs already played, in the order they played, ending just before the current song.
    public func played() -> [QueueSlot] {
        playedOrder(trackIds, current: current, entryIds: entryIds) { previousIndex(before: $0, repeatMode: .off, shuffle: shuffle) }
    }
}

/// Where a song sits in the queue, and the key a list draws it under.
public struct QueueSlot: Sendable, Equatable, Hashable {
    public var index: Int
    public var key: String

    public init(_ index: Int, _ key: String) {
        self.index = index
        self.key = key
    }
}

/// The key each song in the queue is drawn under: its queue entry id, or, for a song without
/// one, its id and how many times it appears earlier in the queue, so the same song twice gets
/// two keys.
public func queueKeys(_ trackIds: [String], _ entryIds: [String?] = []) -> [String] {
    var seen: [String: Int] = [:]
    return trackIds.enumerated().map { i, id in
        let times = seen[id] ?? 0
        seen[id] = times + 1
        return (entryIds.indices.contains(i) ? entryIds[i] : nil) ?? "\(id)#\(times)"
    }
}

/// The queue in the order it will play, starting with the current song. `next` gives the index
/// played after a given one, or nil when the queue runs out.
public func upNextOrder(_ trackIds: [String], current: Int, entryIds: [String?] = [], next: (Int) -> Int?) -> [QueueSlot] {
    walk(trackIds, from: current, entryIds, next)
}

/// The songs already played, in the order they played, ending just before the current song.
public func playedOrder(_ trackIds: [String], current: Int, entryIds: [String?] = [], previous: (Int) -> Int?) -> [QueueSlot] {
    guard trackIds.indices.contains(current), let before = previous(current) else { return [] }
    return walk(trackIds, from: before, entryIds, previous).reversed()
}

private func walk(_ trackIds: [String], from: Int, _ entryIds: [String?], _ step: (Int) -> Int?) -> [QueueSlot] {
    guard trackIds.indices.contains(from) else { return [] }
    let keys = queueKeys(trackIds, entryIds)
    var out: [QueueSlot] = []
    var i: Int? = from
    // Never longer than the queue, even if the order loops back.
    while let at = i, out.count < trackIds.count {
        out.append(QueueSlot(at, keys[at]))
        i = step(at)
    }
    return out
}

// MARK: Undoable edits

/// A queue edit that can be taken back: the queue as it was, its play order under shuffle, and
/// the entries left once the edit was made.
public struct QueueUndo: Sendable, Equatable {
    public let items: [QueueItem]
    public let order: [Int]
    public let kept: [String]
    /// The edit took out the song on now and left nothing to play after it.
    public let ended: Bool

    public init(items: [QueueItem], order: [Int], kept: [String], ended: Bool = false) {
        self.items = items
        self.order = order
        self.kept = kept
        self.ended = ended
    }
}

extension PlayQueue {
    private var entryKeys: [String] { items.map { $0.entryId ?? "" } }

    private mutating func edit(_ pick: (PlayQueue, [String]) -> [Int]) -> QueueUndo? {
        let keys = entryKeys
        let positions = pick(self, keys)
        guard !positions.isEmpty else { return nil }
        let before = items
        let order = self.order
        let result = removeRuns(removalRuns(positions))
        return QueueUndo(items: before, order: order, kept: entryKeys, ended: result.currentRemoved && result.ended)
    }

    /// Takes one song out by its key. Answers the undo, or nil when the song is no longer there.
    public mutating func removeEntry(_ key: String) -> QueueUndo? {
        edit { queue, _ in queue.keys.firstIndex(of: key).map { [$0] } ?? [] }
    }

    /// Takes out everything but the song that is on.
    public mutating func clearAllButCurrent() -> QueueUndo? {
        edit { queue, keys in keys.indices.filter { $0 != queue.current } }
    }

    /// Takes these songs out wherever they are, for files about to be deleted. When the song that
    /// is on goes, the next one plays.
    public mutating func removeSongs(_ trackIds: Set<String>) -> QueueUndo? {
        edit { queue, _ in queuePositionsOf(queue.trackIds, trackIds) }
    }

    /// Takes out the songs played before the one that is on.
    public mutating func removePlayed() -> QueueUndo? {
        edit { queue, _ in queue.played().map(\.index) }
    }

    /// Moves a song already in the queue to play right after the one that is on, shuffle or not.
    /// Answers whether it was there to move.
    public mutating func playEntryNext(_ key: String) -> Bool {
        guard let from = keys.firstIndex(of: key), from != current else { return false }
        let item = items[from]
        removeRuns([from...from])
        addNext([item])
        return true
    }

    /// Puts the songs back exactly where they were. Answers whether it could: not once the queue
    /// has changed some other way.
    public mutating func undo(_ undo: QueueUndo) -> Bool {
        guard let runs = putBackRuns(undo.items.map { $0.entryId ?? "" }, entryKeys), undo.kept == entryKeys else { return false }
        putBack(runs.map { (at: $0.at, items: $0.old.map { undo.items[$0] }) }, order: undo.order)
        return true
    }
}
