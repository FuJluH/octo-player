import AVFoundation
import Foundation
import Observation
import OctoKit

/// Where a song's lyrics come from, and the listener's choices about them. Sources are asked in
/// the other apps' order: the listener's pick, the server, then lrclib. The first synced lyrics
/// win; plain ones are kept while the rest are asked for synced. On an Octo server that keeps
/// lyrics choices for every app (octoLyrics), the choice lives on the server.
@MainActor
@Observable
final class LyricsStore {
    enum Answer: Equatable {
        case found(StructuredLyrics, source: String)
        case none
        case hidden
        case failed
    }

    /// How the words are drawn.
    enum Look: String, CaseIterable {
        case flowing, classic, plain

        var title: String {
            switch self {
            case .flowing: "Flowing"
            case .classic: "Classic"
            case .plain: "Plain"
            }
        }
    }

    private(set) var answers: [String: Answer] = [:]
    var look: Look {
        didSet { UserDefaults.standard.set(look.rawValue, forKey: "lyrics.look") }
    }
    /// Whether lrclib may be asked.
    var online: Bool {
        didSet { UserDefaults.standard.set(online, forKey: "lyrics.online") }
    }

    @ObservationIgnored private let session: Session
    @ObservationIgnored private var asking: [String: Task<Answer, Never>] = [:]
    private var songOffsets: [String: Int]
    private var outputOffsets: [String: Int]
    private var picks: [String: String]
    private var hidden: Set<String>

    init(session: Session) {
        self.session = session
        let defaults = UserDefaults.standard
        look = Look(rawValue: defaults.string(forKey: "lyrics.look") ?? "") ?? .flowing
        online = defaults.object(forKey: "lyrics.online") as? Bool ?? true
        songOffsets = defaults.dictionary(forKey: "lyrics.songOffsets") as? [String: Int] ?? [:]
        outputOffsets = defaults.dictionary(forKey: "lyrics.outputOffsets") as? [String: Int] ?? [:]
        picks = defaults.dictionary(forKey: "lyrics.picks") as? [String: String] ?? [:]
        hidden = Set(defaults.stringArray(forKey: "lyrics.hidden") ?? [])
    }

    /// The server keeps choices for every app.
    var serverKeepsChoices: Bool { session.profile?.has("octoLyrics") ?? false }

    func answer(for song: Song) async -> Answer {
        if let known = answers[song.id], known != .failed { return known }
        if let running = asking[song.id] { return await running.value }
        let task = Task { await search(song) }
        asking[song.id] = task
        let found = await task.value
        asking[song.id] = nil
        answers[song.id] = found
        return found
    }

    func retry(_ song: Song) async -> Answer {
        answers[song.id] = nil
        return await answer(for: song)
    }

    private func search(_ song: Song) async -> Answer {
        if !serverKeepsChoices, hidden.contains(song.id) { return .hidden }
        let userAgent = session.client?.userAgent ?? "Octo (iOS)"
        if !serverKeepsChoices, let pick = picks[song.id], pick.hasPrefix("lrclib:"),
           let found = try? await LrcLib.copy(pick, userAgent: userAgent) {
            return .found(found, source: "lrclib")
        }
        var plain: Answer?
        var reached = true
        if let client = session.client {
            do {
                if let found = try await client.lyrics(songId: song.id), !found.line.isEmpty {
                    if found.synced || serverKeepsChoices { return .found(found, source: "server") }
                    plain = .found(found, source: "server")
                }
            } catch OctoError.notFound {
            } catch {
                reached = false
            }
        }
        if online, !song.title.isEmpty, !song.byline.isEmpty {
            do {
                if let found = try await LrcLib.find(title: song.title, artist: song.artist ?? song.byline, album: song.album,
                                                     duration: song.duration > 0 ? song.duration : nil, userAgent: userAgent),
                   !found.line.isEmpty {
                    if found.synced || plain == nil { return .found(found, source: "lrclib") }
                }
            } catch {
                reached = false
            }
        }
        return plain ?? (reached ? .none : .failed)
    }

    // MARK: Choosing

    /// Every copy to choose from: the server's when it keeps choices, else lrclib's.
    func candidates(for song: Song, title: String? = nil, artist: String? = nil) async throws -> [LyricsCandidate] {
        if serverKeepsChoices, let client = session.client {
            return try await client.lyricsCandidates(songId: song.id, title: title, artist: artist).candidate
        }
        let userAgent = session.client?.userAgent ?? "Octo (iOS)"
        var found = try await LrcLib.search(title: title ?? song.title, artist: artist ?? song.byline, userAgent: userAgent)
        if let pick = picks[song.id] {
            for i in found.indices where found[i].id == pick { found[i].chosen = true }
        }
        return found
    }

    func choose(_ candidate: LyricsCandidate, for song: Song) async throws {
        if serverKeepsChoices, let client = session.client {
            try await client.setLyricsChoice(songId: song.id, candidate: candidate.id)
        } else {
            picks[song.id] = candidate.id
            save()
        }
        if let lyrics = candidate.lyrics {
            answers[song.id] = .found(lyrics, source: candidate.source)
        } else {
            answers[song.id] = nil
            _ = await answer(for: song)
        }
    }

    func hide(_ song: Song) async throws {
        if serverKeepsChoices, let client = session.client {
            try await client.setLyricsChoice(songId: song.id, candidate: LyricsChoice.none)
        } else {
            hidden.insert(song.id)
            save()
        }
        answers[song.id] = .hidden
    }

    func show(_ song: Song) async throws {
        if serverKeepsChoices, let client = session.client {
            try await client.setLyricsChoice(songId: song.id, candidate: LyricsChoice.auto)
        } else {
            hidden.remove(song.id)
            picks[song.id] = nil
            save()
        }
        answers[song.id] = nil
        _ = await answer(for: song)
    }

    // MARK: Timing

    /// Lyrics move earlier or later by this much a step.
    static let step = 50
    static let songLimit = 10_000
    static let outputLimit = 2_000

    func songOffset(_ songId: String) -> Int { songOffsets[songId] ?? 0 }

    func moveSong(_ songId: String, steps: Int) {
        songOffsets[songId] = min(Self.songLimit, max(-Self.songLimit, songOffset(songId) + steps * Self.step))
        save()
    }

    /// The output in use (the phone's speaker, a pair of earbuds), as a key and a name.
    var output: (key: String, name: String) {
        let port = AVAudioSession.sharedInstance().currentRoute.outputs.first
        return (port.map { "\($0.portType.rawValue):\($0.uid)" } ?? "speaker", port?.portName ?? "This iPhone")
    }

    private var outputIsBluetooth: Bool {
        guard let type = AVAudioSession.sharedInstance().currentRoute.outputs.first?.portType else { return false }
        return [.bluetoothA2DP, .bluetoothHFP, .bluetoothLE].contains(type)
    }

    /// The output's timing, and whether it is the automatic one: words are mostly heard about
    /// 0.3 s late on the phone and a cable, 0.5 s over Bluetooth.
    var outputTiming: (ms: Int, automatic: Bool) {
        if let set = outputOffsets[output.key] { return (set, false) }
        return (outputIsBluetooth ? -500 : -300, true)
    }

    func moveOutput(steps: Int) {
        outputOffsets[output.key] = min(Self.outputLimit, max(-Self.outputLimit, outputTiming.ms + steps * Self.step))
        save()
    }

    func resetOutput() {
        outputOffsets[output.key] = nil
        save()
    }

    /// How much later than written the words are heard, in seconds: the song's and the
    /// output's together. The lyrics follow a clock this far behind the song.
    func totalOffset(_ songId: String) -> Double {
        Double(songOffset(songId) + outputTiming.ms) / 1000
    }

    private func save() {
        let defaults = UserDefaults.standard
        defaults.set(songOffsets, forKey: "lyrics.songOffsets")
        defaults.set(outputOffsets, forKey: "lyrics.outputOffsets")
        defaults.set(picks, forKey: "lyrics.picks")
        defaults.set(Array(hidden), forKey: "lyrics.hidden")
    }
}

extension LyricsStore.Answer {
    /// Where the lyrics came from, as the menu's heading says it.
    var heading: String {
        switch self {
        case .found(_, let source):
            switch source {
            case "server": "Lyrics from your server"
            case "lrclib": "Lyrics from LRCLIB"
            default: "Lyrics from \(source.capitalized)"
            }
        case .hidden: "Lyrics hidden for this song"
        case .none: "No lyrics found"
        case .failed: "Couldn't load lyrics"
        }
    }
}
