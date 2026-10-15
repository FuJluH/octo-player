import Foundation

// A station keeps going: once its songs play, more of them are added as the queue runs low, for
// as long as it plays.

/// A station is topped up once fewer songs than this come after the one playing.
public let stationTopUpAt = 20
/// How many songs a top-up asks the server for.
public let stationBatch = 25
/// How many of the station's songs already queued the server is told about, so it sends others.
public let stationAfter = 100

/// The ids of Octo's stations start with this; any other server list, like a Made for you list,
/// is fixed.
public let stationIdPrefix = "or"

/// The extension a server lists when it sends more of a station's songs.
public let octoStations = "octoStations"

/// Whether the server sends more of a station's songs, going by the extensions it listed.
public func offersStationSongs(_ extensions: some Sequence<String>) -> Bool {
    extensions.contains { $0 == octoStations || $0.hasPrefix(octoStations + ":") }
}

/// What a server list plays under: one of Octo's stations as a station that keeps going, any
/// other list (a Made for you list, a mix) as a list with its name. A list Octo says is of
/// another kind than a station (`octoGroup`) is never one.
public func serverListSource(id: String, name: String, octoGroup: String? = nil) -> QueueSource {
    if id.hasPrefix(stationIdPrefix), !id.contains(":"), octoGroup == nil || octoGroup == "station" {
        return .station(id: id, name: name)
    }
    return .played(name.isEmpty ? nil : name)
}

/// The station to top up now, or nil: only while fewer than `stationTopUpAt` songs come after
/// the one playing (`current`), and then the last station among the songs from the one playing
/// to the end of the queue. Songs the listener queued after a station leave it going: the new
/// songs go after theirs.
public func stationToTopUp(_ sources: [QueueSource], current: Int) -> QueueSource? {
    guard sources.indices.contains(current), sources.count - current - 1 < stationTopUpAt else { return nil }
    return sources[current...].last(where: \.isStation)
}

extension QueueSource {
    /// Whether the song came from one of the server's stations.
    public var isStation: Bool {
        if case .station = self { return true }
        return false
    }
}

/// The station to top up in a queue as it plays, with the queue entry the new songs would follow
/// in play order (shuffle included), or nil. Never while repeat is on, which plays the queue again
/// instead.
public func stationTopUp(_ queue: PlayQueue) -> (station: QueueSource, tail: String)? {
    guard queue.repeatMode == .off, queue.items.indices.contains(queue.current) else { return nil }
    let order = [queue.current] + queue.upcoming()
    guard let station = stationToTopUp(order.map { queue.items[$0].source }, current: 0),
          let last = order.last, let tail = queue.items[last].entryId else { return nil }
    return (station, tail)
}

/// The ids of a station's songs in the queue, in queue order: the last `stationAfter` of them.
public func stationSongsQueued(_ items: [QueueItem], station: QueueSource) -> [String] {
    Array(items.filter { $0.source == station }.map(\.trackId).suffix(stationAfter))
}

/// One top-up's songs, as the server sent them: the station's own id and name, then its songs.
public struct StationSongs: Decodable, Sendable {
    public var id: String
    public var name: String
    public var entry: [Song]

    enum CodingKeys: String, CodingKey { case id, name, entry }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.id(.id)) ?? ""
        name = c.string(.name) ?? ""
        entry = (try? c.decodeIfPresent([Song].self, forKey: .entry)) ?? []
    }
}

extension SubsonicClient {
    /// More of a station's songs: `count` of them, none of those in `after` (the server's ids of
    /// its songs already queued).
    public func stationSongs(id: String, count: Int = stationBatch, after: [String]) async throws -> StationSongs {
        try await get("getStationSongs", [("id", id), ("count", "\(count)")] + after.map { ("after", $0) }, key: "stationSongs")
    }
}

/// What a tap on a station card on Home does: an internet radio station added to the server plays
/// its stream; any other opens its songs, and its play button plays them.
public enum StationTap: Sendable, Equatable {
    case playStream(String)
    case openList
}

public func stationTap(_ station: Station) -> StationTap {
    let stream = (station.streamUrl ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    return stream.isEmpty ? .openList : .playStream(stream)
}

/// Whether a station card carries a play button: only one whose tap opens its songs.
public func stationHasPlayButton(_ station: Station) -> Bool { stationTap(station) == .openList }
