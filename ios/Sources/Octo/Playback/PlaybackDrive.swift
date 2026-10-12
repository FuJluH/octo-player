#if DEBUG
import Foundation
import OctoKit
import SwiftUI

/// Drive steps for the player's states (see `Drive`):
///
/// - `crossfade:on`, `crossfade:off`, `crossfade:SECONDS` turns crossfade on at that length
/// - `automix:on`, `automix:off` turns crossfade on with smart transitions on or off;
///   `filters:on|off`, `matchtempo:on|off`
/// - `blend` jumps to 30 s before the end of the song, to hear the next one come in
/// - `radio` starts radio from the song on now; `radio:TEXT` from the first song a search finds
/// - `sleep:MINUTES`, `sleep:end`, `sleep:songs:N`, `sleep:extend:MINUTES`, `sleep:off`
/// - `resume-offer` shows the Resume card with a sample offer; `resume-check` asks the server
/// - `autoplay:end` leaves only the song on now and jumps near its end, so Autoplay adds songs
/// - `seek:SECONDS`, `next`, `previous`, `play`, `shuffle:on|off`, `repeat:off|all|one`
/// - `speed:VALUE`, `pitch:SEMITONES`, `keeppitch:on|off`, `skipsilence:on|off`
/// - `startafter:NAME` (Instant, Short, Steady, Safe, Long as kept)
/// - `shuffle-library` shuffles the whole library
/// - `playstate` shows a line with what the player is doing
@MainActor
enum PlaybackDrive {
    static func install(player: Player, router: Router, overlays: Overlays) {
        Drive.steps.append { name, value in
            await step(name, value, player: player, router: router, overlays: overlays)
        }
    }

    private static func step(_ name: String, _ value: String, player: Player, router: Router, overlays: Overlays) async -> Bool {
        let settings = AppSettings.shared
        switch name {
        case "crossfade":
            if value == "off" {
                settings.setCrossfade(false)
            } else {
                settings.setCrossfade(true)
                if let seconds = Int(value) { settings.setCrossfadeSeconds(seconds) }
            }
        case "automix":
            settings.setCrossfade(value != "off" || settings.player.crossfade)
            settings.setSmartTransitions(value != "off")
        case "filters": settings.setFilterSweeps(value != "off")
        case "matchtempo": settings.setMatchTempo(value != "off")
        case "blend":
            if player.duration > 40 { player.seek(to: player.duration - 30) }
        case "radio":
            if value.isEmpty {
                if let song = player.current { await player.startRadio(from: song) }
            } else if let client = player.session.client, let found = try? await client.search(value), let first = found.song.first {
                await player.startRadio(from: first)
            }
        case "sleep":
            let parts = value.split(separator: ":").map(String.init)
            switch parts.first {
            case "off": player.cancelSleep()
            case "end": player.sleepAtEndOfSong()
            case "songs": player.sleepAfterSongs(Int(parts.last ?? "") ?? 2)
            case "extend": player.extendSleep(minutes: Int(parts.last ?? "") ?? 5)
            default: player.startSleep(minutes: Int(value) ?? 15)
            }
            router.show(sleepSummary(player.sleepState))
        case "resume-offer":
            player.serverQueue.showSample(ResumeOffer(
                device: "Feishin", title: player.current?.title ?? "Paranoid Android",
                artist: player.current?.byline ?? "Radiohead",
                remote: RemoteQueue(songs: player.queue, index: 0, positionMs: 30_000,
                                    changedAt: Int(Date().timeIntervalSince1970 * 1000), changedBy: "Feishin")))
            let id = UUID()
            overlays.showSheet(id, tall: false, scrolls: false, content: AnyView(
                VStack { ResumeCard().environment(player) }.padding(.vertical, 20)
            )) { overlays.hideSheet(id) }
        case "resume-check": player.serverQueue.arrived()
        case "autoplay":
            settings.setAutoplay(value != "off")
            if value == "end" {
                player.clearUpcoming()
                player.setRepeat(.off)
                if player.duration > 40 { player.seek(to: player.duration - 25) }
            }
        case "seek": player.seek(to: Double(value) ?? 0)
        case "next": player.next()
        case "previous": player.previous()
        case "play": player.resume()
        case "shuffle":
            if player.shuffled != (value != "off") { player.toggleShuffle() }
        case "repeat":
            player.setRepeat(value == "one" ? .one : value == "all" ? .all : .off)
        case "speed": settings.setSpeed(Float(value) ?? 1)
        case "pitch": settings.setPitchSemitones(Int(value.replacingOccurrences(of: "+", with: "")) ?? 0)
        case "keeppitch": settings.setKeepPitch(value != "off")
        case "skipsilence": settings.setSkipSilence(value != "off")
        case "startafter": settings.setStartAfter(StartAfter(rawValue: value) ?? .short)
        case "shuffle-library": await player.shuffleLibrary()
        case "playstate":
            let quality = player.quality.map { "\($0.label) \($0.full)" } ?? "no badge"
            let fade = settings.player.crossfade ? "crossfade \(settings.player.crossfadeSeconds) s" : "no crossfade"
            router.show("\(player.isPlaying ? "Playing" : "Paused") \(player.index + 1) of \(player.queue.count), \(fade), \(sleepSummary(player.sleepState)), \(quality)")
        default:
            return false
        }
        return true
    }
}
#endif
