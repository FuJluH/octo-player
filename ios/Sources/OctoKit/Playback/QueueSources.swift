import Foundation

/// Where each song in the queue came from, so the queue can show the listener's own picks apart
/// from the list they were playing: "Next from you", then "Next from OK Computer".
public enum QueueSource: Sendable, Hashable {
    /// The listener put it in: Play next, Add to queue, or dropped in.
    case you
    /// Part of a list that was played: an album, a playlist, the songs, a radio. `name` is how
    /// the queue shows it, or nil for a list with no name worth showing.
    case played(String?)
    /// Added by Autoplay once the listener's own queue ran out.
    case autoplay
    /// One of the server's stations, which adds more of its songs as the queue runs low. `id`
    /// is never empty and has no colon; `name` is how the queue shows it.
    case station(id: String, name: String)

    /// A played list with no name.
    public static let none = QueueSource.played(nil)

    /// A source as a short word, for saving a queue: "you", "autoplay", "list", "list:<name>" or
    /// "station:<id>:<name>".
    public var encoded: String {
        switch self {
        case .you: "you"
        case .autoplay: "autoplay"
        case .played(let name): name.map { "list:\($0)" } ?? "list"
        case .station(let id, let name): "station:\(id):\(name)"
        }
    }
}

/// The heading over a run of songs to come from one source.
public func queueSourceTitle(_ source: QueueSource) -> String {
    switch source {
    case .you: "Next from you"
    case .autoplay: "Next from Autoplay"
    case .played(let name): name.map { "Next from \($0)" } ?? "Up next"
    case .station(_, let name): name.isEmpty ? "Up next" : "Next from \(name)"
    }
}

/// The songs to come cut into runs of one source each, in the order they play. Songs from one
/// source that are apart stay in runs of their own.
public func sourceRuns<T>(_ items: [T], sourceOf: (T) -> QueueSource) -> [(source: QueueSource, items: [T])] {
    var runs: [(source: QueueSource, items: [T])] = []
    for item in items {
        let source = sourceOf(item)
        if let last = runs.last, last.source == source {
            runs[runs.count - 1].items.append(item)
        } else {
            runs.append((source: source, items: [item]))
        }
    }
    return runs
}

/// The source a song takes once moved (or dropped) among the songs to come, between `before`
/// and `after` (nil at either end): inside a run it joins that run, so a song dragged in among
/// the listener's own becomes theirs; at the edge between two runs it keeps its own. It never
/// becomes Autoplay's, so a song of the listener's moved past Autoplay's stays theirs.
public func movedSource(_ own: QueueSource, before: QueueSource?, after: QueueSource?) -> QueueSource {
    let joined: QueueSource
    if let before, let after {
        joined = before == after ? before : own
    } else if let before {
        joined = before
    } else if let after {
        joined = after
    } else {
        joined = own
    }
    return joined == .autoplay && own != .autoplay ? own : joined
}

/// The source a saved word stands for; an unknown or missing one is a list with no name. A
/// station's id ends at the first colon after "station:", so its name may hold colons; a station
/// with no id is a list with no name.
public func queueSourceOf(_ word: String?) -> QueueSource {
    guard let word else { return .none }
    if word == "you" { return .you }
    if word == "autoplay" { return .autoplay }
    if word.hasPrefix("list:") {
        let name = String(word.dropFirst("list:".count))
        return .played(name.isEmpty ? nil : name)
    }
    if word.hasPrefix("station:") {
        let rest = word.dropFirst("station:".count)
        let id = rest.prefix { $0 != ":" }
        guard !id.isEmpty else { return .none }
        return .station(id: String(id), name: String(rest.dropFirst(id.count + 1)))
    }
    return .none
}
