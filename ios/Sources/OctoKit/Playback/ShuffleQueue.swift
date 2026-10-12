import Foundation

// A shuffled queue is two lists: the songs in queue order, and `order`, the queue positions in
// the order they play. These keep the second in step with the first as songs come and go, so a
// song put in never lands at a random spot.

/// Songs put in at queue positions `at` until `at + count` play, in queue order, after the
/// first `rank` entries of the shuffled order. Every song already at `at` or later moves along
/// by `count`.
public func insertIntoShuffle(_ order: [Int], at: Int, count: Int, rank: Int) -> [Int] {
    let shifted = order.map { $0 >= at ? $0 + count : $0 }
    let place = min(max(rank, 0), shifted.count)
    return Array(shifted[0..<place]) + Array(at..<(at + count)) + Array(shifted[place...])
}

/// How many songs of the shuffled order play before songs put in at queue position `at` of a
/// queue `size` long, while `current` is on:
/// - "Play next" (`playNext`): right after the song that is on;
/// - at the end of the queue ("Add to queue"): after all of them;
/// - right after the song that is on in the queue: right after it;
/// - just before a song Autoplay added: just before it, so the listener's own songs play first;
/// - anywhere else: right after the song before them in the queue.
public func shuffleRankFor(_ order: [Int], at: Int, size: Int, current: Int, playNext: Bool = false, beforeAutoplay: Bool = false) -> Int {
    func after(_ position: Int) -> Int { order.firstIndex(of: position).map { $0 + 1 } ?? order.count }
    if playNext && current >= 0 { return after(current) }
    if at >= size { return order.count }
    if current >= 0 && at == current + 1 { return after(current) }
    if beforeAutoplay { return order.firstIndex(of: at) ?? order.count }
    if at == 0 { return 0 }
    return after(at - 1)
}

/// Where songs the listener adds at queue position `at` go. Added at the end, they go before the
/// first Autoplay song still to come (`upcoming` is the queue positions after the current song,
/// in play order), so the listener's own songs play before Autoplay's. Anywhere else, at `at`.
public func ownSongsAt(_ at: Int, upcoming: [Int], autoplay: [Bool]) -> Int {
    if at < autoplay.count { return at }
    return upcoming.first { autoplay.indices.contains($0) && autoplay[$0] } ?? at
}

/// The shuffled order once queue positions `from` until `to` are taken out: the rest keep
/// playing in the same order.
public func removeFromShuffle(_ order: [Int], from: Int, to: Int) -> [Int] {
    let count = to - from
    return order.filter { $0 < from || $0 >= to }.map { $0 >= to ? $0 - count : $0 }
}

/// The shuffled order once queue positions `from` until `to` move to start at `newFrom`: each
/// song keeps its place in the play order.
public func moveInShuffle(_ order: [Int], from: Int, to: Int, newFrom: Int) -> [Int] {
    let size = order.count
    let moved = Array(from..<to)
    let rest = (0..<size).filter { $0 < from || $0 >= to }
    let queue = Array(rest[0..<newFrom]) + moved + Array(rest[newFrom...])
    // Where each old queue position ends up.
    var newPosition = [Int](repeating: 0, count: size)
    for (position, old) in queue.enumerated() { newPosition[old] = position }
    return order.map { newPosition[$0] }
}
