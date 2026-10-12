#if DEBUG
import Foundation
import OctoIntents
import OctoKit
import OctoSystem
import WidgetKit

/// Drive steps for the widgets, their links, Siri and the quick actions (see `Drive`):
///
/// - `widget:write` puts the music as it is on the widgets' shelf now; `widget:sample` puts a
///   sample song there (playing, no cover); `widget:paused` the same song paused;
///   `widget:empty` "Nothing playing"; `widget:read` shows what the shelf holds
/// - `link:open`, `link:player`, `link:play`, `link:pause`, `link:next`, `link:previous`,
///   `link:quick:Liked`, `link:quick:RecentlyAdded`, `link:quick:AlbumMix`, `link:quick:Resume`
///   open the app with the link a widget uses
/// - `intent:play`, `intent:pause`, `intent:next`, `intent:previous`, `intent:resume`,
///   `intent:liked`, `intent:recent`, `intent:mix`, `intent:music`, `intent:music:TEXT`,
///   `intent:item:TEXT`, `intent:radio:TEXT` run an App Intent as Siri or a widget button would
///   (`item` and `radio` take the first library item a search for TEXT finds)
/// - `voice:TEXT`, `voice-album:TEXT`, `voice-artist:TEXT`, `voice-playlist:NAME`,
///   `voice-station:TEXT`, `voice-resume`, `voice-current` play a Siri media request
/// - `shortcut:shuffle_all`, `shortcut:liked`, `shortcut:recently_added`, `shortcut:resume` run a
///   Home Screen quick action
/// - `siri-names` shows how many library names Siri is given
@MainActor
enum SystemDrive {
    static func install(router: Router) {
        Drive.steps.append { name, value in
            await step(name, value, router: router)
        }
    }

    private static func step(_ name: String, _ value: String, router: Router) async -> Bool {
        guard let actions = SystemActions.shared else { return false }
        switch name {
        case "widget":
            await widget(value, router: router)
        case "link":
            guard let command = link(value) else { return true }
            SystemEntries.shared?.open(command.url)
        case "intent":
            await intent(value, actions: actions, router: router)
        case "voice":
            report(await actions.voice(voiceAsk(VoiceRequest(name: value))), router: router)
        case "voice-album":
            report(await actions.voice(voiceAsk(VoiceRequest(name: value, kind: .album))), router: router)
        case "voice-artist":
            report(await actions.voice(voiceAsk(VoiceRequest(name: value, kind: .artist))), router: router)
        case "voice-playlist":
            report(await actions.voice(voiceAsk(VoiceRequest(name: value, kind: .playlist))), router: router)
        case "voice-station":
            report(await actions.voice(voiceAsk(VoiceRequest(name: value, kind: .station))), router: router)
        case "voice-resume":
            report(await actions.voice(voiceAsk(VoiceRequest(resume: true))), router: router)
        case "voice-current":
            report(await actions.voice(voiceAsk(VoiceRequest(current: true))), router: router)
        case "shortcut":
            guard let shortcut = LauncherShortcut(rawValue: value) else { return true }
            await SystemEntries.shared?.run(shortcut)
        case "siri-names":
            let names = await actions.suggestions()
            router.show("Siri knows \(names.count) names: \(names.prefix(3).map(\.title).joined(separator: ", "))")
        default:
            return false
        }
        return true
    }

    private static func widget(_ value: String, router: Router) async {
        let shelf = WidgetShelf.shared()
        let sample = WidgetPlayback(title: "Hold On, We're Going Home", artist: "Drake", isPlaying: true)
        switch value {
        case "write": SystemHooks.updates?.rewrite()
        case "sample": _ = try? shelf?.write(sample, cover: .none)
        case "paused":
            var paused = sample
            paused.isPlaying = false
            _ = try? shelf?.write(paused, cover: .none)
        case "empty": _ = try? shelf?.write(nil, cover: .none)
        default: break
        }
        if value != "write" { WidgetCenter.shared.reloadTimelines(ofKind: WidgetKind.nowPlaying) }
        guard let shelf else {
            router.show("No shared folder: this build has no App Group")
            return
        }
        guard let shelved = shelf.read() else {
            router.show("The widgets' shelf is empty")
            return
        }
        let face = nowPlayingFace(shelved.playback, .large)
        let cover = shelf.coverURL(shelved) == nil ? "no cover" : "a cover"
        router.show("\(face.title), \(face.artist ?? "no artist"), \(face.playing ? "playing" : "paused"), \(cover)")
    }

    private static func link(_ value: String) -> OctoLink? {
        switch value {
        case "open": return .open
        case "player": return .player
        default: return WidgetCommand(encoded: value).map(OctoLink.command)
        }
    }

    private static func intent(_ value: String, actions: SystemActions, router: Router) async {
        let (kind, text) = value.firstIndex(of: ":").map { (String(value[..<$0]), String(value[value.index(after: $0)...])) } ?? (value, "")
        do {
            switch kind {
            case "play": _ = try await PlayIntent().perform()
            case "pause": _ = try await PauseIntent().perform()
            case "next": _ = try await NextIntent().perform()
            case "previous": _ = try await PreviousIntent().perform()
            case "resume": _ = try await ResumeIntent().perform()
            case "liked": _ = try await PlayLikedIntent().perform()
            case "recent": _ = try await PlayRecentlyAddedIntent().perform()
            case "mix": _ = try await PlayAlbumMixIntent().perform()
            case "music": _ = try await PlayMusicIntent(text: text.isEmpty ? nil : text).perform()
            case "item", "radio":
                guard let found = await actions.find(text).first else {
                    router.show("Nothing called \(text)")
                    return
                }
                let item = MusicItemEntity(found)
                if kind == "item" {
                    _ = try await PlayItemIntent(item: item).perform()
                } else {
                    _ = try await StartRadioIntent(item: item).perform()
                }
            default: return
            }
        } catch {
            router.show((error as? CustomLocalizedStringResourceConvertible).map { String(localized: $0.localizedStringResource) } ?? "\(error)")
        }
    }

    private static func report(_ words: String?, router: Router) {
        if let words { router.show(words) }
    }
}
#endif
