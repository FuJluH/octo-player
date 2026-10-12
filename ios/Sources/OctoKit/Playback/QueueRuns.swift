import Foundation

// The queue arithmetic behind undo, on plain keys and positions.

/// Where songs go back for an undo. `before` is the queue's keys before the edit and `now` its
/// keys since. Each run is a queue position and the old positions of the songs that go there,
/// lowest first; putting them back in that order puts every song at its old position. Nil when
/// the queue has changed some other way since, so an undo never scrambles it.
public func putBackRuns(_ before: [String], _ now: [String]) -> [(at: Int, old: [Int])]? {
    var runs: [(at: Int, old: [Int])] = []
    var kept = 0
    for (i, key) in before.enumerated() {
        if kept < now.count && now[kept] == key {
            kept += 1
        } else if let last = runs.last, last.old.last == i - 1 {
            runs[runs.count - 1].old.append(i)
        } else {
            runs.append((at: i, old: [i]))
        }
    }
    return kept == now.count && !runs.isEmpty ? runs : nil
}

/// Queue positions to take out, as runs from the last to the first, so taking out one never
/// moves the next.
public func removalRuns(_ positions: some Collection<Int>) -> [ClosedRange<Int>] {
    var runs: [ClosedRange<Int>] = []
    for p in Set(positions).sorted() {
        if let last = runs.last, last.upperBound == p - 1 {
            runs[runs.count - 1] = last.lowerBound...p
        } else {
            runs.append(p...p)
        }
    }
    return runs.reversed()
}

/// Where these songs sit in the queue, by the queue's song ids, every time each one is there.
public func queuePositionsOf(_ queueTrackIds: [String], _ songs: Set<String>) -> [Int] {
    queueTrackIds.indices.filter { songs.contains(queueTrackIds[$0]) }
}

/// Where songs put in the queue together are now, to take them back out. They went in at
/// `insertedAt`, but the queue may have changed since: the run of those songs nearest that place
/// is taken to be them. Nil when the run is not in the queue any more.
public func findInserted(_ queue: [String], _ inserted: [String], insertedAt: Int) -> Int? {
    if inserted.isEmpty || inserted.count > queue.count { return nil }
    return (0...(queue.count - inserted.count))
        .filter { start in inserted.indices.allSatisfy { queue[start + $0] == inserted[$0] } }
        .min { abs($0 - insertedAt) < abs($1 - insertedAt) }
}
