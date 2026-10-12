import Foundation

/// The OpenSubsonic extension an Octo server lists when it hands out songs' transition profiles
/// (getTransitionProfile). It is listed only while the server makes them.
public let octoTransitions = "octoTransitions"

/// A beat grid as the server sends it: beats fall on firstBeatMs + n * beatMs and bars start on
/// downbeatMs + n * 4 * beatMs, in song time.
public struct ProfileTempo: Codable, Sendable, Equatable {
    public var bpm: Double = 0
    public var trusted: Bool = false
    public var beatMs: Double = 0
    public var firstBeatMs: Double = 0
    public var downbeatMs: Double = 0
    public var confidence: Double = 0
    public var consistency: Double = 0
    public var steady: Bool = false

    enum CodingKeys: String, CodingKey { case bpm, trusted, beatMs, firstBeatMs, downbeatMs, confidence, consistency, steady }

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bpm = c.looseDouble(.bpm) ?? 0
        trusted = c.bool(.trusted) ?? false
        beatMs = c.looseDouble(.beatMs) ?? 0
        firstBeatMs = c.looseDouble(.firstBeatMs) ?? 0
        downbeatMs = c.looseDouble(.downbeatMs) ?? 0
        confidence = c.looseDouble(.confidence) ?? 0
        consistency = c.looseDouble(.consistency) ?? 0
        steady = c.bool(.steady) ?? false
    }
}

/// One end of a song: its level every `hopMs` from `startMs` (`levels`, base64 of one byte a hop,
/// half-dB steps above -100 dBFS), and its features. A time the song does not have is left out.
public struct ProfileSection: Codable, Sendable, Equatable {
    public var startMs: Int = 0
    public var hopMs: Int = 0
    public var levels: String = ""
    public var bodyDb: Double = -100
    public var gateDb: Double = -60
    public var soundStartMs: Int?
    public var soundEndMs: Int?
    public var outroStartMs: Int?
    public var introEndMs: Int?
    public var boundariesMs: [Int] = []
    public var tempo: ProfileTempo?

    enum CodingKeys: String, CodingKey {
        case startMs, hopMs, levels, bodyDb, gateDb, soundStartMs, soundEndMs, outroStartMs, introEndMs, boundariesMs, tempo
    }

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        startMs = c.int(.startMs) ?? 0
        hopMs = c.int(.hopMs) ?? 0
        levels = c.string(.levels) ?? ""
        bodyDb = c.looseDouble(.bodyDb) ?? -100
        gateDb = c.looseDouble(.gateDb) ?? -60
        soundStartMs = c.int(.soundStartMs)
        soundEndMs = c.int(.soundEndMs)
        outroStartMs = c.int(.outroStartMs)
        introEndMs = c.int(.introEndMs)
        boundariesMs = (try? c.decodeIfPresent([Int].self, forKey: .boundariesMs)) ?? []
        tempo = try? c.decodeIfPresent(ProfileTempo.self, forKey: .tempo)
    }
}

/// The server's answer for one song. When `ready`, the profile follows: its analysis `version`,
/// the song's length, the whole song's level and tempo, and its first 30 s and last 60 s. When
/// not, `version` is the one the server makes now, when it says.
public struct TransitionProfileAnswer: Codable, Sendable, Equatable {
    public var id: String = ""
    public var ready: Bool = false
    public var version: Int = 0
    public var durationMs: Int = 0
    public var bodyDb: Double?
    public var tempo: ProfileTempo?
    public var head: ProfileSection?
    public var tail: ProfileSection?

    enum CodingKeys: String, CodingKey { case id, ready, version, durationMs, bodyDb, tempo, head, tail }

    public init(id: String = "", ready: Bool = false, version: Int = 0) {
        self.id = id
        self.ready = ready
        self.version = version
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.string(.id) ?? ""
        ready = c.bool(.ready) ?? false
        version = c.int(.version) ?? 0
        durationMs = c.int(.durationMs) ?? 0
        bodyDb = c.looseDouble(.bodyDb)
        tempo = try? c.decodeIfPresent(ProfileTempo.self, forKey: .tempo)
        head = try? c.decodeIfPresent(ProfileSection.self, forKey: .head)
        tail = try? c.decodeIfPresent(ProfileSection.self, forKey: .tail)
    }

    /// A profile as JSON, as the server writes it.
    public static func parse(_ text: String) throws -> TransitionProfileAnswer {
        try JSONDecoder().decode(TransitionProfileAnswer.self, from: Data(text.utf8))
    }
}

extension KeyedDecodingContainer {
    func looseDouble(_ key: Key) -> Double? {
        if let d = try? decodeIfPresent(Double.self, forKey: key) { return d }
        if let s = try? decodeIfPresent(String.self, forKey: key) { return Double(s) }
        return nil
    }
}

/// The version of the server's analysis these players read. A profile of any other version is
/// ignored and the player scouts as before.
public let profileVersion = 1

/// Levels come as whole steps of this many dB above `silentDb`.
public let levelStepDb: Float = 0.5

/// The level a sent byte stands for.
public func levelOfCode(_ code: Int) -> Float { silentDb + Float(code) * levelStepDb }

/// One end of a song from its profile: its level every hopMs from startMs, and its features.
public struct SectionProfile: Sendable {
    public let startMs: Int
    public let hopMs: Int
    public let levels: [Float]
    public let features: SectionFeatures

    /// The section as the planner takes it.
    public func analysis() -> SectionAnalysis {
        SectionAnalysis.fromFeatures(
            SectionEnvelope(startMs: startMs, hopMs: hopMs, db: levels, lowDb: levels,
                            onset: [Float](repeating: 0, count: levels.count), lowOnset: [Float](repeating: 0, count: levels.count)),
            features)
    }
}

/// What the server worked out about a song from its whole file: the start and the end the
/// planner reads, and the whole song's level and tempo, as a live tap that heard all of it would
/// give. The end is already measured against the whole song's level, so the planner takes it
/// without a level from the live tap.
public final class TransitionProfile: Sendable {
    public let durationMs: Int
    public let bodyDb: Double?
    public let tempo: Tempo?
    public let head: SectionProfile
    public let tail: SectionProfile

    init(durationMs: Int, bodyDb: Double?, tempo: Tempo?, head: SectionProfile, tail: SectionProfile) {
        self.durationMs = durationMs
        self.bodyDb = bodyDb
        self.tempo = tempo
        self.head = head
        self.tail = tail
    }

    public func headAnalysis() -> SectionAnalysis { head.analysis() }

    public func tailAnalysis() -> SectionAnalysis { tail.analysis() }

    /// The whole song's tempo when it is trusted.
    public var tempoPrior: Double? { tempo?.confident == true ? tempo?.bpm : nil }

    /// The profile in a server's answer, or nil when it is not ready, of a version these players
    /// cannot read, or not whole.
    public static func of(_ answer: TransitionProfileAnswer) -> TransitionProfile? {
        guard answer.ready, answer.version == profileVersion, answer.durationMs > 0 else { return nil }
        guard let head = answer.head.flatMap(sectionOf), let tail = answer.tail.flatMap(sectionOf) else { return nil }
        return TransitionProfile(durationMs: answer.durationMs, bodyDb: answer.bodyDb, tempo: answer.tempo.flatMap(tempoOf),
                                 head: head, tail: tail)
    }

    private static func sectionOf(_ section: ProfileSection) -> SectionProfile? {
        guard section.hopMs > 0, let bytes = decodeBase64(section.levels) else { return nil }
        let levels = bytes.map { levelOfCode(Int($0)) }
        let features = SectionFeatures(
            bodyDb: section.bodyDb, gateDb: section.gateDb, soundStartMs: section.soundStartMs, soundEndMs: section.soundEndMs,
            outroStartMs: section.outroStartMs, boundariesMs: section.boundariesMs, tempo: section.tempo.flatMap(tempoOf),
            introEndMs: section.introEndMs)
        return SectionProfile(startMs: section.startMs, hopMs: section.hopMs, levels: levels, features: features)
    }

    private static func tempoOf(_ t: ProfileTempo) -> Tempo? {
        guard t.bpm > 0, t.beatMs > 0 else { return nil }
        return Tempo(bpm: t.bpm, confidence: t.confidence, consistency: t.consistency, beatMs: t.beatMs,
                     firstBeatMs: t.firstBeatMs, downbeatMs: t.downbeatMs, steady: t.steady)
    }

    /// Standard base64, the closing padding optional.
    private static func decodeBase64(_ text: String) -> [UInt8]? {
        var padded = text
        switch text.count % 4 {
        case 0: break
        case 2: padded += "=="
        case 3: padded += "="
        default: return nil
        }
        return Data(base64Encoded: padded).map { [UInt8]($0) }
    }
}

/// How long a "not ready" answer is believed before the song is asked about again: the server
/// makes profiles in the background, one song at a time.
public let profileRetryMs = 60_000

/// How many songs' profiles are kept.
private let profilesKept = 64

/// The transition profiles of the songs about to blend, asked of the server once and kept.
/// `fetch` asks the server for one song by its id there, and gives nil when this server hands
/// out no profiles or could not be asked.
public final class TransitionProfiles: @unchecked Sendable {
    private let fetch: @Sendable (String) async throws -> TransitionProfileAnswer?
    private let now: @Sendable () -> Int
    private let lock = NSLock()
    /// Most recently used last.
    private var ready: [String: TransitionProfile] = [:]
    private var order: [String] = []
    /// When each song was last found to have no profile yet.
    private var missing: [String: Int] = [:]

    public init(fetch: @escaping @Sendable (String) async throws -> TransitionProfileAnswer?,
                now: @escaping @Sendable () -> Int = { Int(Date().timeIntervalSince1970 * 1000) }) {
        self.fetch = fetch
        self.now = now
    }

    /// The song's profile when it is already here.
    public func cached(_ id: String) -> TransitionProfile? {
        lock.withLock { touch(id) }
    }

    /// The song's profile, asking the server unless it has lately said there is none. Nil when
    /// there is none to have.
    public func profile(_ id: String) async -> TransitionProfile? {
        let known: TransitionProfile?? = lock.withLock {
            if let found = touch(id) { return .some(found) }
            if let at = missing[id], now() - at < profileRetryMs { return .some(nil) }
            return nil
        }
        if let known { return known }
        let answer: TransitionProfileAnswer?
        do {
            answer = try await fetch(id)
        } catch {
            answer = nil
        }
        if Task.isCancelled { return nil }
        let profile = answer.flatMap(TransitionProfile.of)
        lock.withLock {
            if let profile {
                ready[id] = profile
                order.removeAll { $0 == id }
                order.append(id)
                if order.count > profilesKept { ready[order.removeFirst()] = nil }
                missing[id] = nil
            } else {
                missing[id] = now()
                if missing.count > profilesKept * 4 { missing.removeAll() }
            }
        }
        return profile
    }

    /// Forgets everything, as when the server changes.
    public func clear() {
        lock.withLock {
            ready.removeAll()
            order.removeAll()
            missing.removeAll()
        }
    }

    private func touch(_ id: String) -> TransitionProfile? {
        guard let found = ready[id] else { return nil }
        order.removeAll { $0 == id }
        order.append(id)
        return found
    }
}
