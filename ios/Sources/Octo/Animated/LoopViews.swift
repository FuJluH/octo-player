import OctoKit
import SwiftUI
import UIKit

/// What a loop on screen does from where it is: `shown` while its place is on screen at all
/// (the player open and not closing, the page in front), `held` while it is there but should
/// stand still (the player pulled down, the cover still flying in). With the app in front and
/// nothing asking for less, it claims the stage and plays; a loop held keeps its frame; one not
/// shown, or with Reduce Motion on, lets its player go.
@MainActor
private func loopRun(_ play: LoopPlay, shown: Bool, owns: Bool) -> LoopRun {
    switch play {
    case .stillOnly: .none
    case .play: owns ? .playing : .none
    case .hold: shown && owns ? .held : .none
    }
}

/// An album's square loop over its cover, the same size and corners: the cover shows until the
/// loop's first frame is ready, then the loop crossfades in.
struct CoverLoop: View {
    let clip: AnimatedClip
    let albumId: String?
    let side: CGFloat
    var radius: CGFloat
    var shown: Bool
    var held = false
    @Environment(Session.self) private var session
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.octoReduceMotion) private var calm
    @Environment(\.displayScale) private var scale
    @State private var stage = LoopStage.shared
    @State private var id = UUID()
    @State private var file: URL?

    private var play: LoopPlay {
        loopPlay(seen: shown && !held && scenePhase == .active, powerSave: stage.lowPower, reduceMotion: calm)
    }

    /// The space the loop fills, in pixels, in steps of 64 so a small change in layout fetches
    /// nothing new.
    private var pixels: CGSize {
        let side = (loopPixels(.square, points: CGSize(width: self.side, height: self.side), scale: scale).width / 64).rounded(.up) * 64
        return CGSize(width: side, height: side)
    }

    var body: some View {
        let play = play
        LoopVideo(source: file, run: loopRun(play, shown: shown, owns: stage.owner == id), radius: radius)
            .frame(width: side, height: side)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .task(id: "\(clip.video)|\(Int(pixels.width))|\(play == .stillOnly)") {
                file = nil
                guard play != .stillOnly else { return }
                let fetcher = loopFetcher(for: clip, client: session.client)
                file = await LoopSource.shared.file(clip, albumId: albumId, shape: .square, pixels: pixels, fetcher: fetcher)
            }
            .onChange(of: play == .play, initial: true) { _, plays in
                if plays { stage.claim(id) }
            }
            .onDisappear { stage.release(id) }
    }
}

/// An album's tall loop filling the player behind the controls, scaled to cover the screen, its
/// still first when it has one. Shaded into the clip's color (else the cover's) under the
/// controls and along the top so the words read, and further while lyrics show. `covers` hears
/// whether the loop or its still now fills the player.
struct PlayerBackdrop: View {
    let clip: AnimatedClip
    let albumId: String?
    /// The shade, `0xFFRRGGBB`.
    let color: UInt32
    var shown: Bool
    var held: Bool
    var lyricsOpen: Bool
    var covers: (Bool) -> Void
    @Environment(Session.self) private var session
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.octoReduceMotion) private var calm
    @Environment(\.displayScale) private var scale
    @State private var stage = LoopStage.shared
    @State private var id = UUID()
    @State private var file: URL?
    @State private var poster: UIImage?
    @State private var playing = false

    private var play: LoopPlay {
        loopPlay(seen: shown && !held && scenePhase == .active, powerSave: stage.lowPower, reduceMotion: calm)
    }

    private var covered: Bool { playing || poster != nil }

    var body: some View {
        let play = play
        GeometryReader { box in
            let pixels = loopPixels(.tall, points: box.size, scale: scale)
            ZStack {
                LoopVideo(source: file, run: loopRun(play, shown: shown, owns: stage.owner == id), poster: poster) { now in
                    playing = now
                }
                shade(box.size.height)
                    .opacity(covered ? 1 : 0)
            }
            .frame(width: box.size.width, height: box.size.height)
            .task(id: "\(clip.video)|\(Int(pixels.width))x\(Int(pixels.height))|\(play == .stillOnly)") {
                file = nil
                let fetcher = loopFetcher(for: clip, client: session.client)
                let still = await LoopSource.shared.poster(clip, albumId: albumId, shape: .tall, fetcher: fetcher)
                guard !Task.isCancelled else { return }
                poster = still
                guard play != .stillOnly, !Task.isCancelled else { return }
                file = await LoopSource.shared.file(clip, albumId: albumId, shape: .tall, pixels: pixels, fetcher: fetcher)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .animation(.easeInOut(duration: Double(loopFadeMs) / 1000), value: covered)
        .animation(.easeInOut(duration: 0.36), value: lyricsOpen)
        .onChange(of: play == .play, initial: true) { _, plays in
            if plays { stage.claim(id) }
        }
        .onChange(of: covered, initial: true) { _, now in covers(now) }
        .onDisappear {
            stage.release(id)
            covers(false)
        }
    }

    /// The shade over the loop: the clip's color along the top under the album's name, rising
    /// from the bottom under the controls, and over everything while lyrics show.
    private func shade(_ height: CGFloat) -> some View {
        let tint = Color(argb: color)
        let top = min(180 / max(height, 1), 0.3)
        return ZStack {
            LinearGradient(stops: [
                .init(color: tint.opacity(0.55), location: 0),
                .init(color: tint.opacity(0), location: top),
            ], startPoint: .top, endPoint: .bottom)
            LinearGradient(stops: [
                .init(color: tint.opacity(0), location: 0.38),
                .init(color: tint.opacity(0.55), location: 0.52),
                .init(color: tint.opacity(0.86), location: 0.66),
                .init(color: tint.opacity(0.94), location: 1),
            ], startPoint: .top, endPoint: .bottom)
            tint.opacity(lyricsOpen ? 0.6 : 0)
        }
    }
}

/// The colors the player's words take over a full-screen loop shaded into `color`: dark words
/// over a light shade, white ones otherwise, the quiet icons as strong as reading needs.
func backdropColors(_ base: PlayerColors, over color: UInt32) -> PlayerColors {
    var colors = base
    let ink = inkOver(WashRange.of(color), color)
    colors.dark = ink.dark
    colors.quiet = quietAlpha(color, ink: ink.dark ? DarkInkArgb : 0xFFFF_FFFF, soft: PlayerTitleRow.iconAlpha)
    return colors
}
