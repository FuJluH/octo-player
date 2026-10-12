#if DEBUG
import Foundation
import OctoKit

/// The Sound page's steps for the OCTO_DRIVE launch variable. Each step changes the stored
/// settings of the output playing now, then opens the page:
///
/// - `sound` opens the Sound page as it is
/// - `sound:graphic` and `sound:parametric` open it in that mode
/// - `sound:preset:NAME` opens it with that preset (built-in or own) applied
/// - `sound:editor` opens the parametric filter editor, with a filter in it
/// - `sound:save` opens the "Save as preset" card
/// - `sound:own:NAME` saves the ten bands as an own preset and marks the curve as it
/// - `sound:delete:NAME` asks to delete that own preset
/// - `sound:card:loudness`, `sound:card:balance`, `sound:card:correction` scroll to that card
/// - `sound:eq:on`, `sound:eq:off`, `sound:each:on`, `sound:each:off` set those switches
@MainActor
enum SoundDrive {
    static func run(_ value: String, router: Router) {
        guard let store = SoundStore.live else { return }
        let parts = value.split(separator: ":", maxSplits: 1).map(String.init)
        let what = parts.first ?? ""
        let rest = parts.count > 1 ? parts[1] : ""
        switch what {
        case "graphic":
            store.update { SoundEdits.withMode($0, .graphic) }
        case "parametric":
            store.update { SoundEdits.withMode($0, .parametric) }
        case "preset":
            if let preset = eqPresets.first(where: { $0.name.caseInsensitiveCompare(rest) == .orderedSame })
                ?? store.presets.first(where: { $0.name.caseInsensitiveCompare(rest) == .orderedSame }) {
                store.update { SoundEdits.withPreset($0, preset) }
            }
        case "editor":
            store.update { settings in
                var s = SoundEdits.withMode(settings, .parametric)
                if s.filters.isEmpty { s = SoundEdits.withNewFilter(s) }
                s.eqEnabled = true
                return s
            }
            store.pageRequest = .editor
        case "save":
            store.update { SoundEdits.withMode($0, .graphic) }
            store.pageRequest = .savePreset
        case "own":
            let name = rest.isEmpty ? "Mine" : rest
            store.savePreset(name, gains: store.current.graphicGains)
            store.update { settings in
                var s = SoundEdits.withMode(settings, .graphic)
                s.preset = name
                return s
            }
        case "delete":
            store.pageRequest = .deletePreset(rest.isEmpty ? "Mine" : rest)
        case "card":
            store.pageRequest = .card(rest)
        case "eq":
            store.update { settings in
                var s = settings
                s.eqEnabled = rest != "off"
                return s
            }
        case "each":
            store.setPerOutput(rest != "off")
        default:
            break
        }
        if store.pagesShown == 0 { router.go(.sound) }
    }
}
#endif
