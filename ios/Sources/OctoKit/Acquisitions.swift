import Foundation

/// The OpenSubsonic extension an Octo server lists when it can say how the downloads it was
/// asked for are going. Version 2 adds each download's log, clearing finished ones, and Find
/// songs. Version 3 lets a picked copy that is not better than the library's ask first and
/// replace it anyway.
public let octoAcquisitions = "octoAcquisitions"

/// The version of octoAcquisitions whose pickFoundSong takes `anyway` and may answer with the
/// question to ask.
public let octoReplaceAnywayVersion = 3

/// Where one download on the server has got to.
public enum AcquisitionStage: String, Sendable {
    case queued, searching, downloading, verifying, importing, done, failed
    /// A stage this app does not know yet, from a newer server.
    case unknown = ""

    public static func of(_ text: String?) -> AcquisitionStage {
        let wire = (text ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        return AcquisitionStage(rawValue: wire).flatMap { $0 == .unknown ? nil : $0 } ?? .unknown
    }
}

/// One song the server is downloading for the signed-in user. Any field can be missing, and
/// finished ones stay listed for a while.
public struct Acquisition: Decodable, Sendable, Equatable {
    /// The id that was starred.
    public var id: String
    public var artist: String
    public var title: String
    public var album: String?
    /// As the server says it; `stage` is what it means.
    public var state: String
    public var progress: Double?
    public var bytesDone: Int?
    public var bytesTotal: Int?
    public var source: String?
    public var startedAt: String?
    public var updatedAt: String?
    /// Why it failed, in words.
    public var error: String?
    /// The song's id in the library once it is there.
    public var libraryId: String?
    /// How many downloads are ahead of a queued one.
    public var ahead: Int?
    public var note: String?
    public var key: String?
    public var kind: String?
    public var quality: String?
    public var coverArt: String?
    /// The peer the copy comes from, and how many lines its log has.
    public var peer: String?
    public var logLines: Int = 0
    /// The log, oldest first; only getAcquisition sends it.
    public var event: [AcquisitionEvent] = []

    enum CodingKeys: String, CodingKey {
        case id, artist, title, album, state, progress, bytesDone, bytesTotal, source, startedAt, updatedAt, error
        case libraryId, ahead, note, key, kind, quality, coverArt, peer, logLines, event
    }

    public init(id: String = "", artist: String = "", title: String = "", album: String? = nil, state: String = "",
                progress: Double? = nil, bytesDone: Int? = nil, bytesTotal: Int? = nil, source: String? = nil,
                startedAt: String? = nil, updatedAt: String? = nil, error: String? = nil, libraryId: String? = nil,
                ahead: Int? = nil, note: String? = nil, key: String? = nil, kind: String? = nil, quality: String? = nil,
                coverArt: String? = nil) {
        self.id = id
        self.artist = artist
        self.title = title
        self.album = album
        self.state = state
        self.progress = progress
        self.bytesDone = bytesDone
        self.bytesTotal = bytesTotal
        self.source = source
        self.startedAt = startedAt
        self.updatedAt = updatedAt
        self.error = error
        self.libraryId = libraryId
        self.ahead = ahead
        self.note = note
        self.key = key
        self.kind = kind
        self.quality = quality
        self.coverArt = coverArt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.string(.id) ?? ""
        artist = c.string(.artist) ?? ""
        title = c.string(.title) ?? ""
        album = c.string(.album)
        state = c.string(.state) ?? ""
        progress = (try? c.decodeIfPresent(Double.self, forKey: .progress)) ?? nil
        bytesDone = c.int(.bytesDone)
        bytesTotal = c.int(.bytesTotal)
        source = c.string(.source)
        startedAt = c.string(.startedAt)
        updatedAt = c.string(.updatedAt)
        error = c.string(.error)
        libraryId = c.string(.libraryId)
        ahead = c.int(.ahead)
        note = c.string(.note)
        key = c.string(.key)
        kind = c.string(.kind)
        quality = c.string(.quality)
        coverArt = c.string(.coverArt)
        peer = c.string(.peer)
        logLines = c.int(.logLines) ?? 0
        event = (try? c.decodeIfPresent([AcquisitionEvent].self, forKey: .event)) ?? []
    }

    public var stage: AcquisitionStage { .of(state) }

    /// How far along, kept between 0 and 1, or nil when unknown.
    public var fraction: Double? {
        if let progress, progress.isFinite { return min(1, max(0, progress)) }
        if let bytesDone, let bytesTotal, bytesTotal > 0 { return min(1, max(0, Double(bytesDone) / Double(bytesTotal))) }
        return nil
    }
}

struct AcquisitionsBody: Decodable {
    let acquisition: [Acquisition]
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        acquisition = (try? c.decodeIfPresent([Acquisition].self, forKey: AnyKey("acquisition"))) ?? []
    }
}

extension SubsonicClient {
    /// Every download the server is doing for this person, or did lately.
    public func acquisitions() async throws -> [Acquisition] {
        let body: AcquisitionsBody = try await get("getAcquisitions", key: "acquisitions")
        return body.acquisition
    }
}
