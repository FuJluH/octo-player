import AVFoundation
import Foundation
import Observation
import OctoKit

/// One of the phone's settings suites, as somewhere small values are kept by name.
final class DefaultsValues: KeptValues, @unchecked Sendable {
    private let defaults: UserDefaults

    init(suite: String) {
        defaults = UserDefaults(suiteName: suite) ?? .standard
    }

    func string(_ key: String) -> String? { defaults.string(forKey: key) }
    func bool(_ key: String) -> Bool? { defaults.object(forKey: key) as? Bool }
    func int(_ key: String) -> Int? { (defaults.object(forKey: key) as? NSNumber)?.intValue }
    func set(_ key: String, _ value: Any) { defaults.set(value, forKey: key) }
    func remove(_ key: String) { defaults.removeObject(forKey: key) }
    func all() -> [String: Any] { defaults.dictionaryRepresentation() }
}

/// Each song's own lyrics timing, kept in the "lyrics" settings suite as `offset:<song id>` and
/// only for songs whose timing was moved. The output's timing and the look live in the app's
/// settings; this is the part set from the player's lyrics menu.
@MainActor
@Observable
final class LyricsSongTiming {
    static let shared = LyricsSongTiming()

    private(set) var offsets: [String: Int] = [:]
    @ObservationIgnored private let values = DefaultsValues(suite: "lyrics")

    private init() {
        for (name, value) in values.all() where name.hasPrefix(SONG_OFFSET_PREFIX) {
            if let number = (value as? NSNumber)?.intValue { offsets[String(name.dropFirst(SONG_OFFSET_PREFIX.count))] = number }
        }
    }

    /// The song's own timing, 0 when it was never moved.
    func offset(_ trackId: String) -> Int { offsets[trackId] ?? 0 }

    /// Moves the song's timing some steps; back at 0 it is no longer kept.
    func step(_ trackId: String, _ steps: Int) { set(trackId, stepTiming(offset(trackId), steps)) }

    func reset(_ trackId: String) { set(trackId, 0) }

    /// Puts one song's timing back, as from a backup, held to the song limit.
    func set(_ trackId: String, _ ms: Int) {
        let held = min(max(ms, -TIMING_LIMIT_MS), TIMING_LIMIT_MS)
        if held == 0 {
            values.remove(SONG_OFFSET_PREFIX + trackId)
            offsets[trackId] = nil
        } else {
            values.set(SONG_OFFSET_PREFIX + trackId, held)
            offsets[trackId] = held
        }
    }
}

/// The lyrics timing of the output playing now, from the app's settings: its own, one it was
/// kept under before (earbuds once named by their address), or else its automatic one.
@MainActor
enum LyricsOutput {
    /// The output the sound goes to now.
    static var current: AudioOutput { SoundStore.live?.output ?? .phoneSpeaker }

    static var timing: (ms: Int, automatic: Bool) { outputTimingIn(AppSettings.shared.outputTimings, current) }

    /// Moves the output's timing some steps from where it is now, kept under its key alone.
    static func step(_ steps: Int) {
        let output = current
        AppSettings.shared.setOutputTiming(output.key, LyricsOutputTiming.step(timing.ms, steps: steps))
        for key in output.formerKeys { AppSettings.shared.resetOutputTiming(key) }
    }

    /// Back to the automatic timing, under every key the output has had.
    static func reset() {
        let output = current
        for key in [output.key] + output.formerKeys { AppSettings.shared.resetOutputTiming(key) }
    }

    /// The output's timing for the views: the kept one plus the screen's own lead, which starts
    /// every output a couple of frames early so the words are on the glass when the song gets
    /// there.
    static func viewOffset(refreshHz: Double) -> Int { timing.ms + screenLeadMs(refreshHz) }
}
