import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The play queue a server keeps for the signed-in user, so another device can pick it up. The
/// older form names the current song by id; the index-based form gives its place in the list,
/// which works when a song is in the queue twice. Position is in milliseconds into the current
/// song; `changed` is when it was saved, and `changedBy` the name of the client that saved it.
public struct ServerPlayQueue: Decodable, Sendable {
    public var entry: [Song]
    public var current: String?
    public var currentIndex: Int?
    public var position: Int
    public var changed: String?
    public var changedBy: String?

    enum CodingKeys: String, CodingKey { case entry, current, currentIndex, position, changed, changedBy }

    public init(entry: [Song], current: String? = nil, currentIndex: Int? = nil, position: Int = 0, changed: String? = nil,
                changedBy: String? = nil) {
        self.entry = entry
        self.current = current
        self.currentIndex = currentIndex
        self.position = position
        self.changed = changed
        self.changedBy = changedBy
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        entry = (try? c.decodeIfPresent([Song].self, forKey: .entry)) ?? []
        current = c.string(.current)
        currentIndex = c.int(.currentIndex)
        position = c.int(.position) ?? 0
        changed = c.string(.changed)
        changedBy = c.string(.changedBy)
    }
}

/// The OpenSubsonic extension for saving the queue by place in the list.
public let indexBasedQueue = "indexBasedQueue"

/// What a queue save sends: every song id in order, and where playback is. In the index-based
/// form the current song is its place in the list; otherwise it is the song's id. An empty queue
/// sends no current song.
public func queueSaveParams(_ ids: [String], currentIndex: Int, positionMs: Int, indexBased: Bool) -> [(String, String)] {
    var params = ids.map { ("id", $0) }
    guard ids.indices.contains(currentIndex) else { return params }
    params.append(indexBased ? ("currentIndex", "\(currentIndex)") : ("current", ids[currentIndex]))
    params.append(("position", "\(max(0, positionMs))"))
    return params
}

/// The most songs saved on the server. A save is one address with every id in it, and proxies
/// in front of a server refuse addresses much longer than this makes (about 11 KB).
public let serverQueueMax = 400

/// How many songs before the current one a trimmed queue keeps.
private let keepBefore = 50

/// A queue as the server keeps it: server song ids in the order they will play, the current
/// one's place, and how far into it playback is.
public struct ServerQueue: Sendable, Equatable {
    public var ids: [String]
    public var index: Int
    public var positionMs: Int

    public init(_ ids: [String], _ index: Int, _ positionMs: Int) {
        self.ids = ids
        self.index = index
        self.positionMs = positionMs
    }

    /// A long queue cut down around the current song: a few before it, the rest after.
    public func trimmed(_ max: Int = serverQueueMax) -> ServerQueue {
        guard ids.count > max else { return self }
        let start = Swift.min(Swift.max(index - keepBefore, 0), ids.count - max)
        return ServerQueue(Array(ids[start..<(start + max)]), index - start, positionMs)
    }
}

/// A queue another device saved: its songs, the current one's place, the position in it, when
/// it was saved and by which app.
public struct RemoteQueue: Sendable {
    public var songs: [Song]
    public var index: Int
    public var positionMs: Int
    public var changedAt: Int?
    public var changedBy: String?

    public init(songs: [Song], index: Int, positionMs: Int, changedAt: Int?, changedBy: String?) {
        self.songs = songs
        self.index = index
        self.positionMs = positionMs
        self.changedAt = changedAt
        self.changedBy = changedBy
    }

    public var current: Song? { songs.indices.contains(index) ? songs[index] : nil }
}

/// The index-based form: the index held inside the list.
public func remoteQueueOf(byIndex queue: ServerPlayQueue) -> RemoteQueue {
    RemoteQueue(songs: queue.entry, index: min(max(queue.currentIndex ?? 0, 0), max(queue.entry.count - 1, 0)),
                positionMs: max(0, queue.position), changedAt: serverTime(queue.changed), changedBy: queue.changedBy)
}

/// The id-based form: a position only means something in the song it was saved for.
public func remoteQueueOf(byId queue: ServerPlayQueue) -> RemoteQueue {
    let index = queue.entry.firstIndex { $0.id == queue.current }
    return RemoteQueue(songs: queue.entry, index: index ?? 0, positionMs: index != nil ? max(0, queue.position) : 0,
                       changedAt: serverTime(queue.changed), changedBy: queue.changedBy)
}

/// A server's time as milliseconds since 1970, or nil when it cannot be read: an instant, else a
/// date and time with an offset.
public func serverTime(_ text: String?) -> Int? {
    guard var text, !text.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
    // Fractions finer than milliseconds are cut to three digits.
    if let dot = text.firstIndex(of: "."), let zone = text[dot...].firstIndex(where: { $0 == "Z" || $0 == "+" || $0 == "-" }) {
        let digits = text[text.index(after: dot)..<zone]
        if digits.count > 3 { text = String(text[...dot]) + digits.prefix(3) + text[zone...] }
    }
    let withFraction = ISO8601DateFormatter()
    withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let plain = ISO8601DateFormatter()
    plain.formatOptions = [.withInternetDateTime]
    guard let date = withFraction.date(from: text) ?? plain.date(from: text) else { return nil }
    return Int((date.timeIntervalSince1970 * 1000).rounded())
}

/// Whether to offer picking up a queue from the server: it has songs, it is not the one this
/// device saved last (known by the server's own time stamp for that save, so another device
/// running Octo still counts as another device), and it was saved after this device last saved
/// or answered an offer.
public func shouldOfferResume(_ remote: RemoteQueue?, lastSavedAt: Int, answeredUpTo: Int, ownStamp: Int?) -> Bool {
    guard let remote, remote.current != nil, let changedAt = remote.changedAt else { return false }
    if changedAt == ownStamp { return false }
    return changedAt > max(lastSavedAt, answeredUpTo)
}

/// The phone's queue as a queue for the server. Songs the server does not have are left out.
/// With shuffle on, the songs go in the order they will play, so the other device carries on
/// with the same songs next. When the current song is not on the server, the next one that is
/// takes its place, from its start. Nil when no song is on the server.
public func serverQueueOf(_ snapshot: QueueSnapshot, serverIdOf: (String) -> String?) -> ServerQueue? {
    let ids = snapshot.trackIds
    let shuffled = snapshot.shuffle && snapshot.shuffleOrder.count == ids.count && Set(snapshot.shuffleOrder) == Set(ids.indices)
    let order = shuffled ? snapshot.shuffleOrder : Array(ids.indices)
    // Each song on the server: its place in play order, and its server id.
    let kept = order.enumerated().compactMap { rank, position in serverIdOf(ids[position]).map { (rank, position, $0) } }
    guard !kept.isEmpty else { return nil }
    let serverIds = kept.map(\.2)
    if let exact = kept.firstIndex(where: { $0.1 == snapshot.index }) {
        return ServerQueue(serverIds, exact, max(0, snapshot.positionMs))
    }
    let currentRank = order.firstIndex(of: snapshot.index) ?? -1
    let next = kept.firstIndex { $0.0 > currentRank }
    return ServerQueue(serverIds, next ?? kept.count - 1, 0)
}

/// The name the app gives servers as its client. A queue saved under any other name came from
/// another app or device.
public let ourClientName = "Octo"
