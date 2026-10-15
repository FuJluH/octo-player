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
        let run = loopRun(play, shown: shown, owns: stage.owner == id)
        LoopVideo(source: file, run: run, radius: radius)
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

/// An album's tall loop at the top of the player, at the screen's width and its own shape, under
/// the status bar, fading out softly just above the title. Below that the player is the loop's
/// own colors: the same loop stretched and blurred deep, shaded into the clip's color (else the
/// cover's) so the words read on it, and further while lyrics show. Its still shows first when
/// it has one. `covers` hears whether the loop or its still now fills the player.
struct PlayerBackdrop: View {
    let clip: AnimatedClip
    let albumId: String?
    /// The shade, `0xFFRRGGBB`.
    let color: UInt32
    /// Where the title row starts, in points from the top of the player; nil until laid out.
    var titleTop: CGFloat?
    var shown: Bool
    var held: Bool
    var lyricsOpen: Bool
    var covers: (Bool) -> Void
    /// Hears whether the top of what is drawn (the still, then the loop) is light, for the status
    /// bar's color.
    var lightTop: (Bool) -> Void = { _ in }
    @Environment(Session.self) private var session
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.octoReduceMotion) private var calm
    @Environment(\.displayScale) private var scale
    @State private var stage = LoopStage.shared
    @State private var id = UUID()
    @State private var file: URL?
    @State private var poster: UIImage?
    @State private var playing = false

    /// How long the loop takes to fade out, and how far above the title it is gone, in points.
    private static let fadeLength: CGFloat = 125
    private static let clearOfTitle: CGFloat = 14

    private var play: LoopPlay {
        loopPlay(seen: shown && !held && scenePhase == .active, powerSave: stage.lowPower, reduceMotion: calm)
    }

    private var covered: Bool { playing || poster != nil }

    /// The loop's place: the width of the screen at the clip's own shape (3:4 when it names
    /// none), fading so it is gone just above the title, or at its own bottom when the screen is
    /// taller than that.
    private func fit(_ size: CGSize) -> LoopBackdropFit {
        let shape = clip.width > 0 && clip.height > 0 ? CGFloat(clip.height) / CGFloat(clip.width) : 4.0 / 3.0
        let height = (size.width * shape).rounded()
        let gone = max(min(height, (titleTop ?? height) - Self.clearOfTitle), Self.fadeLength)
        return LoopBackdropFit(height: height, fadeStart: max(gone - Self.fadeLength, 0), fadeEnd: gone)
    }

    var body: some View {
        let play = play
        GeometryReader { box in
            let full = CGSize(width: box.size.width + 2, height: box.size.height + 2)
            let fit = fit(full)
            let pixels = loopPixels(.tall, points: CGSize(width: full.width, height: fit.height), scale: scale)
            ZStack {
                LoopVideo(source: file, run: loopRun(play, shown: shown, owns: stage.owner == id), poster: poster,
                          backdrop: fit, blurred: lyricsOpen) { now in
                    playing = now
                }
                shade(fit, height: full.height)
                    .opacity(covered ? 1 : 0)
            }
            // A point past every edge, so no line of the screen shows past the loop.
            .frame(width: full.width, height: full.height)
            .position(x: box.size.width / 2, y: box.size.height / 2)
            .task(id: "\(clip.video)|\(Int(pixels.width))x\(Int(pixels.height))|\(play == .stillOnly)") {
                file = nil
                let fetcher = loopFetcher(for: clip, client: session.client)
                let still = await LoopSource.shared.poster(clip, albumId: albumId, shape: .tall, fetcher: fetcher)
                guard !Task.isCancelled else { return }
                poster = still
                // The status bar reads on the top 50 pt.
                let band = 50 / max(fit.height, 1)
                if let still, let light = loopTopIsLight(still.cgImage, share: band) { lightTop(light) }
                guard play != .stillOnly, !Task.isCancelled else { return }
                file = await LoopSource.shared.file(clip, albumId: albumId, shape: .tall, pixels: pixels, fetcher: fetcher)
                if let file, let light = await LoopSource.shared.topIsLight(file, share: band), !Task.isCancelled { lightTop(light) }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .animation(.easeInOut(duration: Double(loopFadeMs) / 1000), value: covered)
        .animation(.easeInOut(duration: 0.35), value: lyricsOpen)
        .onChange(of: play == .play, initial: true) { _, plays in
            if plays { stage.claim(id) }
        }
        .onChange(of: covered, initial: true) { _, now in covers(now) }
        .onDisappear {
            stage.release(id)
            covers(false)
        }
    }

    /// The shade: coming in as the loop fades out, so the blurred color under the controls is
    /// mostly the shade, and over everything while lyrics show. The top of the loop is left clean.
    private func shade(_ fit: LoopBackdropFit, height: CGFloat) -> some View {
        let tint = Color(argb: color)
        let points = max(height, 1)
        let start = fit.fadeStart / points
        let end = fit.fadeEnd / points
        return ZStack {
            // Eased in with the loop's fade, then steady under the controls.
            LinearGradient(stops: [
                .init(color: tint.opacity(0), location: start),
                .init(color: tint.opacity(0.12), location: start + (end - start) * 0.4),
                .init(color: tint.opacity(0.42), location: start + (end - start) * 0.75),
                .init(color: tint.opacity(0.62), location: end),
                .init(color: tint.opacity(0.66), location: 1),
            ], startPoint: .top, endPoint: .bottom)
            tint.opacity(lyricsOpen ? 0.78 : 0)
        }
    }
}

/// The colors the player's words take over a full-screen loop shaded into `color`: dark words
/// over a light shade, white ones otherwise, the quiet icons as strong as reading needs.
func backdropColors(_ base: PlayerColors, over color: UInt32) -> PlayerColors {
    var colors = base
    let ink = loopShadeInk(color)
    colors.dark = ink.dark
    let quiet = quietAlpha(color, ink: ink.dark ? DarkInkArgb : 0xFFFF_FFFF, soft: PlayerTitleRow.iconAlpha)
    // The dark heart and More at least at 70% over the shade.
    colors.quiet = ink.dark ? max(quiet, 0.70) : quiet
    return colors
}
