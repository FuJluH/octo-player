import Foundation
import Observation
import OctoKit

/// Everything the Sound page shows and changes. Changes go to the output playing now.
///
/// There are two kinds of change. `change` (a switch, a tap, a preset) is saved at once. `preview`
/// (a drag or a slider) is shown at once and saved at most every 100 ms, and once more when the
/// finger lifts. Each edit sets values outright, so saving only the latest one loses nothing.
@MainActor
@Observable
final class SoundPageModel {
    let store: SoundStore

    /// The settings as a drag has left them, ahead of the saved ones, so the page follows the
    /// finger while writes are spaced out.
    private(set) var draft: SoundSettings?
    /// Why the last file could not be read or written, until the next try.
    private(set) var fileProblem: String?
    /// Whether the flat button is held, with the equalizer off for it.
    private(set) var heldFlat = false

    @ObservationIgnored private var pending: ((SoundSettings) -> SoundSettings)?
    @ObservationIgnored private var writing = false

    /// How often a drag saves while the finger moves.
    private static let saveEvery = Duration.milliseconds(100)

    init(store: SoundStore) {
        self.store = store
    }

    /// What the page shows: the draft while a drag is in flight, else what is saved.
    var settings: SoundSettings { draft ?? store.current }

    /// A change saved at once, like a switch or a tap.
    func change(_ edit: @escaping (SoundSettings) -> SoundSettings) {
        draft = draft.map(edit)
        store.update(edit)
    }

    /// A change from a moving finger: shown at once, saved at most every 100 ms.
    func preview(_ edit: @escaping (SoundSettings) -> SoundSettings) {
        draft = edit(draft ?? store.current)
        pending = edit
        guard !writing else { return }
        writing = true
        Task { await writeWhileMoving() }
    }

    /// The finger lifted: saves the last position now.
    func settle() {
        guard let edit = pending else { return }
        pending = nil
        store.update(edit)
    }

    private func writeWhileMoving() async {
        defer { writing = false }
        while true {
            if let edit = pending {
                pending = nil
                store.update(edit)
                try? await Task.sleep(for: Self.saveEvery)
                continue
            }
            // Keeps showing the draft until the saved settings catch up, so nothing flickers
            // back for a frame.
            let target = draft
            let clock = ContinuousClock()
            let deadline = clock.now + .seconds(1)
            while store.current != target, clock.now < deadline {
                try? await Task.sleep(for: .milliseconds(16))
            }
            if pending == nil {
                if draft == target { draft = nil }
                return
            }
        }
    }

    func setPerOutput(_ on: Bool) {
        store.setPerOutput(on)
    }

    func applyPreset(_ preset: EqPreset) {
        change { SoundEdits.withPreset($0, preset) }
    }

    /// Saves the ten bands under a name, and marks the curve as that preset.
    func savePreset(_ name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard UserPresetRules.canSaveAs(clean) else { return }
        store.savePreset(clean, gains: settings.graphicGains)
        change { settings in
            var s = settings
            s.preset = clean
            return s
        }
    }

    func deletePreset(_ name: String) {
        store.deletePreset(name)
        if settings.preset == name {
            change { settings in
                var s = settings
                s.preset = nil
                return s
            }
        }
    }

    /// While the flat button is held the equalizer is off, and it comes back on when the button
    /// is let go.
    func hearFlat(_ held: Bool) {
        if held && !heldFlat && settings.eqEnabled {
            heldFlat = true
            change { Self.withEqualizer($0, on: false) }
        } else if !held && heldFlat {
            heldFlat = false
            change { Self.withEqualizer($0, on: true) }
        }
    }

    /// Reads a correction file the listener picked. It switches the equalizer on, since a
    /// correction only plays through it.
    func importCorrection(_ url: URL) {
        Task {
            let correction = await Task.detached { SoundFiles.readCorrection(url) }.value
            guard let correction else {
                fileProblem = "That file has no filters Octo can read."
                return
            }
            fileProblem = nil
            change { settings in
                var s = settings
                s.eqEnabled = true
                s.correction = correction
                return s
            }
        }
    }

    func removeCorrection() {
        change { settings in
            var s = settings
            s.correction = nil
            return s
        }
    }

    /// Everything the equalizer applies, correction included, as a file another equalizer can
    /// load: the level and the filters, as if the equalizer were on.
    func curveFile() -> String {
        let on = Self.withEqualizer(settings, on: true)
        return ParametricEqFile.write(preampDb: on.effectivePreampDb(), filters: on.activeFilters())
    }

    func exportFinished(saved: Bool) {
        fileProblem = saved ? nil : "The file could not be saved."
    }

    /// The page is closing: a held button must not leave the equalizer off, and a drag still
    /// waiting is saved.
    func close() {
        if heldFlat { store.update { Self.withEqualizer($0, on: true) } }
        settle()
    }

    private static func withEqualizer(_ settings: SoundSettings, on: Bool) -> SoundSettings {
        var s = settings
        s.eqEnabled = on
        return s
    }
}
