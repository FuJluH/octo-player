#if DEBUG
import Foundation
import OctoKit
import os

/// Drive steps for animated art (see `Drive`):
///
/// - `animated:standin` gives every album Apple's Short n' Sweet loops, square and tall, straight
///   from Apple, for checking the screens before a server offers any; `animated:standin-square`
///   only the square one; `animated:standin-off` takes them away
/// - `animated:square`, `animated:full_screen`, `animated:off` sets the Animated art setting
/// - `animated:stream:on|off` plays each clip's HLS playlist as it is instead of its one file
/// - `animated:forget` empties the shelf of recently shown loops, so the next shows from its still
/// - `animated:queue:TEXT` puts the library songs a search for TEXT in the player, paused at once,
///   so nothing is heard
@MainActor
enum AnimatedDrive {
    static let squareClip = AnimatedClip(
        video: "https://mvod.itunes.apple.com/itunes-assets/HLSVideo221/v4/f9/e7/bc/f9e7bc17-b0db-3d1b-a4c7-27f666b33b0a/P899578198_default.m3u8",
        width: 3840, height: 3840)
    static let tallClip = AnimatedClip(
        video: "https://mvod.itunes.apple.com/itunes-assets/HLSVideo221/v4/28/23/22/282322aa-5758-a88a-3915-1abf28500982/P899565453_default.m3u8",
        width: 2048, height: 2732)

    static func install(player: Player, session: Session) {
        Drive.steps.append { name, value in
            guard name == "animated" else { return false }
            await step(value, player: player, session: session)
            return true
        }
    }

    private static func step(_ value: String, player: Player, session: Session) async {
        let log = Logger(subsystem: "app.winters.octo", category: "loops")
        let (what, detail) = value.firstIndex(of: ":").map { (String(value[..<$0]), String(value[value.index(after: $0)...])) } ?? (value, "")
        switch what {
        case "standin": AnimatedArtStore.shared.standIn = AnimatedArt(square: squareClip, tall: tallClip)
        case "standin-square": AnimatedArtStore.shared.standIn = AnimatedArt(square: squareClip)
        case "standin-off": AnimatedArtStore.shared.standIn = nil
        case "square", "full_screen", "off": AppSettings.shared.setAnimatedArt(AnimatedArtSetting.from(key: what))
        case "stream": await LoopSource.shared.setStreamsDirectly(detail != "off")
        case "forget":
            let shelf = LoopSource.shared.shelf
            try? FileManager.default.removeItem(at: shelf.dir)
            try? FileManager.default.createDirectory(at: shelf.dir, withIntermediateDirectories: true)
        case "queue":
            guard let client = session.client, let found = try? await client.search(detail) else { return }
            let songs = found.song.filter { !$0.isExternal }
            guard !songs.isEmpty else { return }
            player.play(songs, from: 0)
            // Paused the moment the songs are in place, before a sound comes out.
            for _ in 0..<500 {
                if player.current?.title == songs[0].title || player.isPlaying { break }
                try? await Task.sleep(for: .milliseconds(10))
            }
            player.pause()
            log.notice("queued paused \(player.current?.title ?? "-", privacy: .public)")
        default: break
        }
    }
}
#endif
