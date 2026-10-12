import Foundation

/// The queue as saved: songs in queue order, where playback was, and the shuffle order so
/// shuffle picks up exactly where it left off. `items` keeps what is known of each song, so a
/// queue can come back before the library has been read.
public struct QueueSnapshot: Sendable, Equatable, Codable {
    public var trackIds: [String]
    /// Queue positions in shuffle order; empty when unknown.
    public var shuffleOrder: [Int]
    public var index: Int
    public var positionMs: Int
    public var repeatMode: Int
    public var shuffle: Bool
    public var items: [QueueItem]?

    public init(trackIds: [String], shuffleOrder: [Int], index: Int, positionMs: Int, repeatMode: Int, shuffle: Bool,
                items: [QueueItem]? = nil) {
        self.trackIds = trackIds
        self.shuffleOrder = shuffleOrder
        self.index = index
        self.positionMs = positionMs
        self.repeatMode = repeatMode
        self.shuffle = shuffle
        self.items = items
    }

    public static let empty = QueueSnapshot(trackIds: [], shuffleOrder: [], index: 0, positionMs: 0, repeatMode: 0, shuffle: false)

    enum CodingKeys: String, CodingKey { case trackIds, shuffleOrder, index, positionMs, repeatMode, shuffle, items }

    /// Unknown keys are ignored and missing ones take their defaults.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        trackIds = try c.decode([String].self, forKey: .trackIds)
        shuffleOrder = (try? c.decodeIfPresent([Int].self, forKey: .shuffleOrder)) ?? []
        index = (try? c.decodeIfPresent(Int.self, forKey: .index)) ?? 0
        positionMs = (try? c.decodeIfPresent(Int.self, forKey: .positionMs)) ?? 0
        repeatMode = (try? c.decodeIfPresent(Int.self, forKey: .repeatMode)) ?? 0
        shuffle = (try? c.decodeIfPresent(Bool.self, forKey: .shuffle)) ?? false
        items = try? c.decodeIfPresent([QueueItem].self, forKey: .items)
    }
}

/// One saved song of the queue: its place in the queue, its id, and its place in the shuffle.
public struct QueueRow: Sendable, Equatable, Codable {
    public var position: Int
    public var trackId: String
    public var shuffledPosition: Int
}

/// Where playback was when the queue was saved.
public struct QueueState: Sendable, Equatable, Codable {
    public var currentIndex: Int
    public var positionMs: Int
    public var repeatMode: Int
    public var shuffle: Bool
    public var savedAt: Int
}

extension QueueSnapshot {
    public func toRows(now: Int) -> ([QueueRow], QueueState) {
        var shuffledAt = Array(0..<trackIds.count)
        if shuffleOrder.count == trackIds.count {
            for (rank, position) in shuffleOrder.enumerated() where shuffledAt.indices.contains(position) { shuffledAt[position] = rank }
        }
        let rows = trackIds.enumerated().map { QueueRow(position: $0.offset, trackId: $0.element, shuffledPosition: shuffledAt[$0.offset]) }
        return (rows, QueueState(currentIndex: index, positionMs: positionMs, repeatMode: repeatMode, shuffle: shuffle, savedAt: now))
    }
}

public func queueFromRows(_ rows: [QueueRow], _ state: QueueState?) -> QueueSnapshot? {
    guard !rows.isEmpty, let state else { return nil }
    let ordered = rows.sorted { $0.position < $1.position }
    return QueueSnapshot(
        trackIds: ordered.map(\.trackId),
        shuffleOrder: ordered.sorted { $0.shuffledPosition < $1.shuffledPosition }.map(\.position),
        index: min(max(state.currentIndex, 0), ordered.count - 1),
        positionMs: max(0, state.positionMs),
        repeatMode: state.repeatMode,
        shuffle: state.shuffle)
}

/// Where a saved queue picks up once the songs gone from the library are dropped: `found` says
/// which saved songs are still here, in saved order. The saved song at the place it was, or
/// when that song is gone, the first song from its start.
public func restorePoint(_ found: [Bool], savedIndex: Int, positionMs: Int) -> (index: Int, positionMs: Int) {
    guard found.indices.contains(savedIndex), found[savedIndex] else { return (0, 0) }
    return (found[0..<savedIndex].filter { $0 }.count, max(0, positionMs))
}

/// The saved shuffle order with the songs that are gone left out, so the rest still play in the
/// order they would have.
public func restoredShuffle(_ order: [Int], _ found: [Bool]) -> [Int]? {
    guard order.count == found.count, order.sorted() == Array(found.indices) else { return nil }
    var newIndex = [Int](repeating: -1, count: found.count)
    var kept = 0
    for (i, here) in found.enumerated() where here {
        newIndex[i] = kept
        kept += 1
    }
    return order.filter { found[$0] }.map { newIndex[$0] }
}

/// The saved queue in use as it is read back: nothing when it holds no songs; the current song
/// held inside the queue and the place never below 0.
public func savedQueueRead(_ text: String) -> QueueSnapshot? {
    guard var queue = decodeQueue(text), !queue.trackIds.isEmpty else { return nil }
    queue.index = min(max(queue.index, 0), queue.trackIds.count - 1)
    queue.positionMs = max(0, queue.positionMs)
    return queue
}

/// The queue as text, for keeping another account's queue.
public func encodeQueue(_ queue: QueueSnapshot) -> String {
    (try? JSONEncoder().encode(queue)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
}

public func decodeQueue(_ text: String) -> QueueSnapshot? {
    try? JSONDecoder().decode(QueueSnapshot.self, from: Data(text.utf8))
}

/// Where the queue in use is saved.
public protocol QueueRows: Sendable {
    func read() async -> QueueSnapshot?
    func write(_ snapshot: QueueSnapshot) async
}

/// Small text values kept by key, such as the app's settings.
public protocol KeyedText: Sendable {
    func text(_ key: String) -> String?
    func setText(_ text: String?, for key: String)
}

/// The queues of accounts not in use, one per account, under `queue@<account>`.
public struct ParkedQueues: Sendable {
    private let data: KeyedText

    public init(_ data: KeyedText) { self.data = data }

    /// Takes the queue waiting for an account, which then waits no more.
    public func take(_ account: String) -> QueueSnapshot? {
        let found = data.text(keyOf(account)).flatMap(decodeQueue)
        data.setText(nil, for: keyOf(account))
        return found
    }

    public func put(_ account: String, _ queue: QueueSnapshot?) {
        if let queue, !queue.trackIds.isEmpty {
            data.setText(encodeQueue(queue), for: keyOf(account))
        } else {
            data.setText(nil, for: keyOf(account))
        }
    }

    private func keyOf(_ account: String) -> String { "queue@\(account)" }
}


/// The queue in use is the saved queue; each other account's waits in `parked` until its server
/// is in use again. Every read and write runs one at a time in the order asked, so a save asked
/// for before a hand-over lands before it, never over the queue handed over.
public final class QueueStore: @unchecked Sendable {
    private let rows: QueueRows
    private let parked: ParkedQueues
    private let lock = NSLock()
    private var tail: Task<Void, Never>?

    public init(rows: QueueRows, parked: ParkedQueues) {
        self.rows = rows
        self.parked = parked
    }

    /// Saving runs in turn and finishes even if the asker goes away.
    public func save(_ snapshot: QueueSnapshot) {
        let rows = rows
        _ = chain { await rows.write(snapshot) }
    }

    public func load() async -> QueueSnapshot? {
        let rows = rows
        return await chain { await rows.read() }.value
    }

    /// Another account's queue becomes the one in use. The queue of `from` (as it was left, else
    /// as saved) waits for it, and the one `to` left comes back. With nothing waiting for `to`,
    /// the queue is emptied, unless `keepWhenNone`, when it stays as it is and nothing waits.
    /// Answers whether the queue in use changed.
    public func handOver(from: String, left: QueueSnapshot?, to: String, keepWhenNone: Bool) async -> Bool {
        let rows = rows, parked = parked
        return await chain { () -> Bool in
            let coming = parked.take(to)
            if coming == nil && keepWhenNone { return false }
            let leaving: QueueSnapshot? = if let left { left } else { await rows.read() }
            parked.put(from, leaving)
            await rows.write(coming ?? .empty)
            return true
        }.value
    }

    /// Forgets the queue kept for a server taken off the list.
    public func forget(_ account: String) async {
        let parked = parked
        await chain { parked.put(account, nil) }.value
    }

    /// Waits until every save asked for so far has landed.
    public func settle() async {
        await chain {}.value
    }

    /// Runs `block` after everything asked before it.
    private func chain<T: Sendable>(_ block: @escaping @Sendable () async -> T) -> Task<T, Never> {
        lock.lock()
        defer { lock.unlock() }
        let previous = tail
        let task = Task { () -> T in
            await previous?.value
            return await block()
        }
        tail = Task { _ = await task.value }
        return task
    }
}
