import Foundation

/// The version of octoAcquisitions that adds each download's log, clearing finished downloads, and
/// Find songs.
public let octoDownloadLogVersion = 2

/// The OpenSubsonic extension for acting on the library's files; version 2 lists the higher
/// quality copies asked for (getUpgrades).
public let octoLibraryActions = "octoLibraryActions"

/// What a download is for, as the server names it.
public enum AcquisitionKind {
    /// A heart, a play or an album walk.
    public static let download = "download"
    /// A higher quality copy of a song already in the library.
    public static let upgrade = "upgrade"
    /// The one copy someone picked from Find songs.
    public static let pick = "pick"
}

/// What one line of a download's log is about. A kind this app does not know yet is drawn as a
/// plain line.
public enum LogKind: String, Sendable, CaseIterable {
    case queued, search, found, `try`, transfer, check, tags, cover, lyrics, library, done, failed, note
    case unknown = ""

    public static func of(_ text: String?) -> LogKind {
        let wire = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return allCases.first { $0 != .unknown && $0.rawValue == wire } ?? .unknown
    }
}

/// One copy a source offered: in a download's log, and in Find songs. Any figure can be missing.
/// `rank` is the server's order of preference among the copies it would try (1 is first), nil for
/// one it would pass over, and `note` says why it would.
public struct FoundCandidate: Decodable, Sendable, Equatable, Hashable {
    /// "Soulseek" or "Lidarr".
    public var source: String
    /// Soulseek: the peer sharing it. Lidarr: the indexer.
    public var peer: String?
    /// The file's own name, or a Lidarr release's title.
    public var file: String?
    public var folder: String?
    public var title: String?
    public var album: String?
    public var format: String?
    /// "FLAC 16-bit 44.1 kHz", "MP3 320 kbps".
    public var quality: String?
    public var bitRate: Int?
    public var bitDepth: Int?
    public var sampleRate: Int?
    public var size: Int64?
    /// In seconds.
    public var length: Int?
    public var queueLength: Int?
    public var freeSlot: Bool?
    /// Bytes a second.
    public var speed: Int?
    public var rank: Int?
    public var note: String?
    /// Its place on a Find songs list, which a server older than copy ids takes back for a pick.
    public var index: Int?
    /// Its own id on a Find songs list, which picking it sends back.
    public var id: String?
    /// How it stands against the library's copy, with the words to show.
    public var vsYours: String?
    public var vsYoursText: String?

    enum CodingKeys: String, CodingKey {
        case source, peer, file, folder, title, album, format, quality, bitRate, bitDepth, sampleRate, size, length
        case queueLength, freeSlot, speed, rank, note, index, id, vsYours, vsYoursText
    }

    public init(source: String = "", peer: String? = nil, file: String? = nil, folder: String? = nil, title: String? = nil,
                album: String? = nil, format: String? = nil, quality: String? = nil, size: Int64? = nil, length: Int? = nil,
                queueLength: Int? = nil, freeSlot: Bool? = nil, speed: Int? = nil, rank: Int? = nil, note: String? = nil,
                index: Int? = nil, id: String? = nil, vsYours: String? = nil, vsYoursText: String? = nil) {
        self.source = source
        self.peer = peer
        self.file = file
        self.folder = folder
        self.title = title
        self.album = album
        self.format = format
        self.quality = quality
        self.size = size
        self.length = length
        self.queueLength = queueLength
        self.freeSlot = freeSlot
        self.speed = speed
        self.rank = rank
        self.note = note
        self.index = index
        self.id = id
        self.vsYours = vsYours
        self.vsYoursText = vsYoursText
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        source = c.string(.source) ?? ""
        peer = c.string(.peer)
        file = c.string(.file)
        folder = c.string(.folder)
        title = c.string(.title)
        album = c.string(.album)
        format = c.string(.format)
        quality = c.string(.quality)
        bitRate = c.int(.bitRate)
        bitDepth = c.int(.bitDepth)
        sampleRate = c.int(.sampleRate)
        size = c.int(.size).map(Int64.init)
        length = c.int(.length)
        queueLength = c.int(.queueLength)
        freeSlot = c.bool(.freeSlot)
        speed = c.int(.speed)
        rank = c.int(.rank)
        note = c.string(.note)
        index = c.int(.index)
        id = c.string(.id)
        vsYours = c.string(.vsYours)
        vsYoursText = c.string(.vsYoursText)
    }
}

/// One line of a download's log: when, what kind of step, the words, an optional second line, and
/// the copies a search offered when the step is about them.
public struct AcquisitionEvent: Decodable, Sendable, Equatable {
    public var at: String?
    public var kind: String
    public var text: String
    public var detail: String?
    public var candidate: [FoundCandidate]

    enum CodingKeys: String, CodingKey { case at, kind, text, detail, candidate }

    public init(at: String? = nil, kind: String = "", text: String = "", detail: String? = nil, candidate: [FoundCandidate] = []) {
        self.at = at
        self.kind = kind
        self.text = text
        self.detail = detail
        self.candidate = candidate
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        at = c.string(.at)
        kind = c.string(.kind) ?? ""
        text = c.string(.text) ?? ""
        detail = c.string(.detail)
        candidate = (try? c.decodeIfPresent([FoundCandidate].self, forKey: .candidate)) ?? []
    }

    public var logKind: LogKind { .of(kind) }
}

/// The song a Find songs search looks for, with the library's copy when there is one.
public struct FoundSong: Decodable, Sendable, Equatable {
    public var artist: String
    public var title: String
    public var album: String?
    public var duration: Int?
    public var coverArt: String?
    public var libraryId: String?
    public var format: String?
    public var quality: String?
    public var size: Int64?
    /// When the library's copy looks like another take of the song, a line saying so.
    public var take: String?
    public var takeKind: String?

    enum CodingKeys: String, CodingKey { case artist, title, album, duration, coverArt, libraryId, format, quality, size, take, takeKind }

    public init(artist: String = "", title: String = "", album: String? = nil, coverArt: String? = nil, libraryId: String? = nil,
                quality: String? = nil, size: Int64? = nil, take: String? = nil) {
        self.artist = artist
        self.title = title
        self.album = album
        self.coverArt = coverArt
        self.libraryId = libraryId
        self.quality = quality
        self.size = size
        self.take = take
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        artist = c.string(.artist) ?? ""
        title = c.string(.title) ?? ""
        album = c.string(.album)
        duration = c.int(.duration)
        coverArt = c.string(.coverArt)
        libraryId = c.string(.libraryId)
        format = c.string(.format)
        quality = c.string(.quality)
        size = c.int(.size).map(Int64.init)
        take = c.string(.take)
        takeKind = c.string(.takeKind)
    }
}

/// How one source's look went: searching, done, failed or off.
public struct FindSourceState: Decodable, Sendable, Equatable, Hashable {
    public var name: String
    public var state: String
    public var text: String?

    enum CodingKeys: String, CodingKey { case name, state, text }

    public init(name: String, state: String, text: String? = nil) {
        self.name = name
        self.state = state
        self.text = text
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = c.string(.name) ?? ""
        state = c.string(.state) ?? ""
        text = c.string(.text)
    }
}

public let findSearching = "searching"
public let findDone = "done"
public let findFailed = "failed"
public let findOff = "off"

/// A Find songs search as it stands: searching until every source answers.
public struct FoundSongs: Decodable, Sendable, Equatable {
    public var id: String
    public var state: String
    public var error: String?
    public var startedAt: String?
    public var song: FoundSong
    public var source: [FindSourceState]
    public var candidate: [FoundCandidate]

    enum CodingKeys: String, CodingKey { case id, state, error, startedAt, song, source, candidate }

    public init(id: String = "", state: String = "", error: String? = nil, song: FoundSong = FoundSong(),
                source: [FindSourceState] = [], candidate: [FoundCandidate] = []) {
        self.id = id
        self.state = state
        self.error = error
        self.song = song
        self.source = source
        self.candidate = candidate
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.string(.id) ?? ""
        state = c.string(.state) ?? ""
        error = c.string(.error)
        startedAt = c.string(.startedAt)
        song = (try? c.decodeIfPresent(FoundSong.self, forKey: .song)) ?? FoundSong()
        source = (try? c.decodeIfPresent([FindSourceState].self, forKey: .source)) ?? []
        candidate = (try? c.decodeIfPresent([FoundCandidate].self, forKey: .candidate)) ?? []
    }

    public var searching: Bool { state == findSearching }
}

/// The states a pick answers with. From octoAcquisitions 3, a library song's pick sent with
/// anyway=false never fetches: `pickReady` for a better copy of the right song, `pickConfirm` for
/// one that needs the person's word, with the whole question in `detail`.
public let pickQueued = "queued"
public let pickSkipped = "skipped"
public let pickReady = "ready"
public let pickConfirm = "confirm"

/// One side of a pick's comparison: its quality in short words, its length in seconds and what
/// take it is. Any of them can be missing.
public struct PickSide: Decodable, Sendable, Equatable {
    public var quality: String?
    public var length: Int?
    public var take: String?

    enum CodingKeys: String, CodingKey { case quality, length, take }

    public init(quality: String? = nil, length: Int? = nil, take: String? = nil) {
        self.quality = quality
        self.length = length
        self.take = take
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        quality = c.string(.quality)
        length = c.int(.length)
        take = c.string(.take)
    }
}

/// The library's copy beside the picked one.
public struct PickCompare: Decodable, Sendable, Equatable {
    public var yours: PickSide?
    public var copy: PickSide?

    public init(yours: PickSide? = nil, copy: PickSide? = nil) {
        self.yours = yours
        self.copy = copy
    }
}

/// What picking a copy did: queued, with the downloads row to follow when there is one, skipped
/// with the server's words why, or a question to confirm first.
public struct PickResult: Decodable, Sendable, Equatable {
    public var state: String
    public var detail: String?
    public var key: String?
    public var compare: PickCompare?

    enum CodingKeys: String, CodingKey { case state, detail, key, compare }

    public init(_ state: String, _ detail: String? = nil, _ key: String? = nil, _ compare: PickCompare? = nil) {
        self.state = state
        self.detail = detail
        self.key = key
        self.compare = compare
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        state = c.string(.state) ?? ""
        detail = c.string(.detail)
        key = c.string(.key)
        compare = try? c.decodeIfPresent(PickCompare.self, forKey: .compare)
    }

    public var queued: Bool { state == pickQueued }
    public var ready: Bool { state == pickReady }
    public var confirm: Bool { state == pickConfirm }
}

/// Where a higher quality copy asked for has got to.
public enum UpgradeStage: String, Sendable {
    /// Waiting for its turn in the server's queue.
    case queued
    /// Held while the source is out; it carries on once it is back.
    case waiting
    /// Being searched for, downloaded or checked.
    case working
    /// Done: the copy passed and took the original's place.
    case upgraded
    /// No copy of it could be found; the original stays.
    case notFound
    /// Only rehearsed; nothing changed.
    case rehearsed
    /// Not done, and never will be as asked.
    case skipped
    /// It tried and could not; the original stays.
    case failed
    /// A state this app does not know yet, from a newer server.
    case unknown = ""

    public static func of(_ text: String?) -> UpgradeStage {
        let wire = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return UpgradeStage(rawValue: wire).flatMap { $0 == .unknown ? nil : $0 } ?? .unknown
    }

    /// Whether the server is still on it, so it is worth asking again.
    public var pending: Bool { self == .queued || self == .waiting || self == .working }
}

/// A higher quality copy the signed-in user asked for, and how it is going.
public struct Upgrade: Decodable, Sendable, Equatable {
    /// The song's id in the library, which stays the same after the swap.
    public var id: String
    public var title: String
    public var artist: String
    public var album: String?
    public var state: String
    /// The server's own words about how it went.
    public var detail: String?
    public var progress: Double?
    public var updatedAt: String?
    /// The download fetching the replacement, by its key, once there is one.
    public var acquisition: String?
    /// The copy picked in Find songs, in words, when one was.
    public var picked: String?

    enum CodingKeys: String, CodingKey { case id, title, artist, album, state, detail, progress, updatedAt, acquisition, picked }

    public init(id: String = "", title: String = "", artist: String = "", album: String? = nil, state: String = "", detail: String? = nil,
                progress: Double? = nil, updatedAt: String? = nil, acquisition: String? = nil, picked: String? = nil) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.state = state
        self.detail = detail
        self.progress = progress
        self.updatedAt = updatedAt
        self.acquisition = acquisition
        self.picked = picked
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.string(.id) ?? ""
        title = c.string(.title) ?? ""
        artist = c.string(.artist) ?? ""
        album = c.string(.album)
        state = c.string(.state) ?? ""
        detail = c.string(.detail)
        progress = (try? c.decodeIfPresent(Double.self, forKey: .progress)) ?? nil
        updatedAt = c.string(.updatedAt)
        acquisition = c.string(.acquisition)
        picked = c.string(.picked)
    }

    public var stage: UpgradeStage { .of(state) }

    /// How far along, kept between 0 and 1, or nil when unknown.
    public var fraction: Double? {
        guard let progress, progress.isFinite else { return nil }
        return min(1, max(0, progress))
    }
}

/// What a library action did, in the server's words.
public struct LibraryActionResult: Decodable, Sendable, Equatable {
    public var id: String
    public var action: String
    public var state: String
    public var detail: String?

    enum CodingKeys: String, CodingKey { case id, action, state, detail }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.string(.id) ?? ""
        action = c.string(.action) ?? ""
        state = c.string(.state) ?? ""
        detail = c.string(.detail)
    }
}

/// Puts a replaced song's old copy back, by the song's id.
public let libraryActionRestore = "restore"

struct UpgradesBody: Decodable {
    let upgrade: [Upgrade]
    init(from decoder: Decoder) throws {
        if let list = try? [Upgrade](from: decoder) {
            upgrade = list
            return
        }
        let c = try decoder.container(keyedBy: AnyKey.self)
        upgrade = (try? c.decodeIfPresent([Upgrade].self, forKey: AnyKey("upgrade"))) ?? []
    }
}

struct ClearedBody: Decodable {
    let count: Int
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        count = c.int(AnyKey("count")) ?? 0
    }
}

extension SubsonicClient {
    /// One download with its whole log, by the key the list gives it. Only for servers that list
    /// octoAcquisitions at version 2.
    public func acquisition(key: String) async throws -> Acquisition {
        try await get("getAcquisition", [("key", key)], key: "acquisition")
    }

    /// Takes the finished downloads off the signed-in user's list, or only the one with this key,
    /// and answers how many it let go.
    @discardableResult
    public func clearAcquisitions(key: String? = nil) async throws -> Int {
        let body: ClearedBody = try await get("clearAcquisitions", key.map { [("key", $0)] } ?? [], key: "cleared")
        return body.count
    }

    /// Starts a search for one song on the user's download sources, answered at once while it runs.
    public func findSongs(id: String) async throws -> FoundSongs {
        try await get("findSongs", [("id", id)], key: "foundSongs")
    }

    /// A Find songs search as it stands, by the id findSongs answered.
    public func foundSongs(search: String) async throws -> FoundSongs {
        try await get("getFoundSongs", [("search", search)], key: "foundSongs")
    }

    /// Fetches exactly this copy from a Find songs list: by its id, or on a server older than copy
    /// ids, by its place on the list. `anyway` is sent only when not nil.
    public func pickFoundSong(search: String, copy: FoundCandidate, anyway: Bool? = nil) async throws -> PickResult {
        let which: (String, String)
        if let id = copy.id {
            which = ("copy", id)
        } else if let index = copy.index {
            which = ("candidate", String(index))
        } else {
            return PickResult(pickSkipped, "This copy cannot be picked. Search again.")
        }
        var params = [("search", search), which]
        if let anyway { params.append(("anyway", anyway ? "true" : "false")) }
        return try await get("pickFoundSong", params, key: "pick")
    }

    /// The higher quality copies the signed-in user asked for, and how each is going. Only for
    /// servers that list octoLibraryActions at version 2.
    public func upgradesAskedFor() async throws -> [Upgrade] {
        let body: UpgradesBody = try await get("getUpgrades", key: "upgrades")
        return body.upgrade
    }

    /// Puts back the copy a picked one replaced, by the library song's id.
    public func restoreReplacedCopy(id: String) async throws -> LibraryActionResult {
        try await get("libraryAction", [("id", id), ("action", libraryActionRestore)], key: "libraryAction")
    }
}
