import Foundation

/// How the sound settings are kept: one set for each output key ("all" holds the shared one),
/// and whether each output keeps its own. Stored as the other apps store them, a JSON map
/// under "profiles" and a flag under "per_output", so a backup moves between them.
public enum SoundProfiles {
    /// The stored map, or an empty one when it is missing or cannot be read.
    public static func decode(_ json: String?) -> [String: SoundSettings] {
        guard let data = json?.data(using: .utf8),
              let map = try? JSONDecoder().decode([String: SoundSettings].self, from: data)
        else { return [:] }
        return map
    }

    public static func encode(_ saved: [String: SoundSettings]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(saved) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    /// The sets from a backup put back: those it names replace the ones of the same key, the
    /// others stay.
    public static func restoring(_ profiles: [String: SoundSettings], into saved: [String: SoundSettings]) -> [String: SoundSettings] {
        saved.merging(profiles) { _, restored in restored }
    }
}

/// The listener's own equalizer presets, listed after the built-in ones and shared by every
/// output. Stored as a JSON list of names and ten gains under "presets".
public enum UserPresetRules {
    /// The saved presets; entries without exactly ten gains are left out.
    public static func decode(_ json: String?) -> [EqPreset] {
        guard let data = json?.data(using: .utf8), let list = try? JSONDecoder().decode([StoredPreset].self, from: data) else { return [] }
        return list.filter { $0.gains.count == graphicBands.count }.map { EqPreset(name: $0.name, gains: $0.gains) }
    }

    public static func encode(_ presets: [EqPreset]) -> String {
        guard let data = try? JSONEncoder().encode(presets.map { StoredPreset(name: $0.name, gains: $0.gains) }) else { return "[]" }
        return String(decoding: data, as: UTF8.self)
    }

    /// A curve saved under a name: one saved before under the same name in any case is
    /// replaced, and the new one goes to the end. Nothing changes for an empty name or a curve
    /// that is not ten gains.
    public static func saving(_ name: String, gains: [Double], to list: [EqPreset]) -> [EqPreset] {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, gains.count == graphicBands.count else { return list }
        return list.filter { $0.name.caseInsensitiveCompare(clean) != .orderedSame } + [EqPreset(name: clean, gains: gains)]
    }

    /// Takes away the preset with exactly this name.
    public static func deleting(_ name: String, from list: [EqPreset]) -> [EqPreset] {
        list.filter { $0.name != name }
    }

    /// Presets from a backup added: each with a name and ten gains replaces one of the same
    /// trimmed name in any case, and goes in with its name trimmed.
    public static func restoring(_ presets: [EqPreset], into list: [EqPreset]) -> [EqPreset] {
        let clean = presets.filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.gains.count == graphicBands.count }
        guard !clean.isEmpty else { return list }
        let names = Set(clean.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        let others = list.filter { !names.contains($0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) }
        return others + clean.map { EqPreset(name: $0.name.trimmingCharacters(in: .whitespacesAndNewlines), gains: $0.gains) }
    }

    /// Whether a curve can be saved under this name: anything but empty, "Custom", or the
    /// name of a built-in preset, in any case.
    public static func canSaveAs(_ name: String) -> Bool {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !clean.isEmpty && clean.caseInsensitiveCompare(SoundEdits.custom) != .orderedSame
            && !eqPresets.contains { $0.name.caseInsensitiveCompare(clean) == .orderedSame }
    }

    private struct StoredPreset: Codable {
        var name: String
        var gains: [Double]
    }
}

/// The lines a backup's sound part adds to what the backup says it holds.
public enum SoundBackupWords {
    public static func lines(perOutput: Bool, profiles: [String: SoundSettings]?, presets: [EqPreset]) -> [String] {
        var lines: [String] = []
        if let profiles {
            let outputs = profiles.keys.filter { $0 != AudioOutput.shared }.count
            if perOutput && outputs > 0 {
                lines.append(SettingsSummaries.count(outputs, one: "output with its own sound", many: "outputs with their own sound"))
            }
        }
        if !presets.isEmpty {
            lines.append(SettingsSummaries.count(presets.count, one: "equalizer preset", many: "equalizer presets"))
        }
        return lines
    }
}

/// The Sound page's entries in the settings search: title, line, and the words that find them.
public struct SoundSearchEntry: Sendable, Equatable {
    public let id: String
    public let title: String
    public let summary: String
    public let keywords: [String]

    public static let all: [SoundSearchEntry] = [
        SoundSearchEntry(id: "sound_per_output", title: "Sound for each output", summary: "Headphones and speakers keep their own sound",
                         keywords: ["bluetooth", "speaker", "device", "output"]),
        SoundSearchEntry(id: "sound_equalizer", title: "Equalizer", summary: "Shape the sound, with presets",
                         keywords: ["eq", "bass", "treble", "presets", "bands", "filters"]),
        SoundSearchEntry(id: "sound_loudness", title: "Loudness", summary: "Even out the volume between songs",
                         keywords: ["volume", "levelling", "leveling", "normalize", "replaygain", "preamp"]),
        SoundSearchEntry(id: "sound_balance", title: "Balance", summary: "Left and right",
                         keywords: ["left", "right", "channel", "mono"]),
        SoundSearchEntry(id: "sound_correction", title: "Headphone correction", summary: "A correction for the headphones in use",
                         keywords: ["headphones", "correction", "profile", "tuning"]),
        SoundSearchEntry(id: "sound_crossfeed", title: "Crossfeed", summary: "Blends a little of each side into the other on headphones",
                         keywords: ["headphones", "stereo", "speakers", "fatigue", "blend", "chu moy", "meier", "binaural"]),
    ]
}
