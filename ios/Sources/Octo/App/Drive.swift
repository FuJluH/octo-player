#if DEBUG
import Foundation
import OctoKit

/// Steps named in the OCTO_DRIVE launch variable, run one after another once the app has
/// started, to bring it to a given state from outside. Steps are separated by ";":
///
/// - `wait:SECONDS`
/// - `tab:home`, `tab:search`, `tab:library`, `tab:settings`
/// - `player` opens the full player, `close` closes it, `lyrics` opens its lyrics
/// - `list:NAME` plays the server playlist with that name
/// - `found:TEXT` plays the songs not in the library that a search for TEXT finds
/// - `search:TEXT` plays the library songs a search for TEXT finds
/// - `pause`
/// - `sound`, `sound:graphic`, `sound:parametric`, `sound:preset:NAME`, `sound:editor`,
///   `sound:save`, `sound:own:NAME`, `sound:delete:NAME`, `sound:card:NAME`, `sound:eq:on|off`,
///   `sound:each:on|off`
///   open the Sound page in that state (see `SoundDrive`)
/// - `settings:PAGE`, `settings:PAGE@ROW`, `settings-search:TEXT`, `popup:ROW`, `whatsnew`,
///   `settings-state:NAME`: see `SettingsNavigator.drive`
@MainActor
enum Drive {
    static func run(session: Session, player: Player, router: Router) async {
        guard let script = ProcessInfo.processInfo.environment["OCTO_DRIVE"], !script.isEmpty else { return }
        for _ in 0..<40 where session.client == nil { try? await Task.sleep(for: .milliseconds(250)) }
        try? await Task.sleep(for: .seconds(1))
        for step in script.split(separator: ";").map({ $0.trimmingCharacters(in: .whitespaces) }) where !step.isEmpty {
            let (name, value) = split(step)
            switch name {
            case "wait": try? await Task.sleep(for: .seconds(Double(value) ?? 1))
            case "tab": if let tab = AppTab(rawValue: value) { router.drive = .tab(tab) }
            case "player": router.drive = .openPlayer
            case "close": router.drive = .closePlayer
            case "lyrics": router.drive = .lyrics
            case "pause": player.pause()
            case "sound": SoundDrive.run(value, router: router)
            case "settings", "settings-search", "popup", "whatsnew", "settings-state": await SettingsNavigator.shared.drive(name, value, router: router)
            case "list":
                guard let client = session.client,
                      let list = try? await client.playlists().first(where: { $0.name.caseInsensitiveCompare(value) == .orderedSame }),
                      let full = try? await client.playlist(list.id)
                else { continue }
                player.play(full.entry, from: 0)
            case "found", "search":
                guard let client = session.client, let found = try? await client.search(value) else { continue }
                let songs = found.song.filter { name == "found" ? $0.isExternal : !$0.isExternal }
                if !songs.isEmpty { player.play(songs, from: 0) }
            default:
                for handle in steps where await handle(name, value) { break }
            }
            try? await Task.sleep(for: .milliseconds(400))
        }
    }

    /// More steps, added by parts of the app: each answers whether it took the step.
    static var steps: [@MainActor (_ name: String, _ value: String) async -> Bool] = []

    private static func split(_ step: String) -> (String, String) {
        guard let colon = step.firstIndex(of: ":") else { return (step, "") }
        return (String(step[..<colon]), String(step[step.index(after: colon)...]))
    }
}
#endif
