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

    /// The space the loop is picked for, in pixels, in steps of 32 so a small change in layout
    /// fetches nothing new.
    private var pixels: CGSize {
        let side = (loopPixels(.square, points: CGSize(width: self.side, height: self.side), scale: scale).width / 32).rounded() * 32
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

/// An album's tall loop filling the player with the Full screen look (`LoopMelt`): at the top
/// at the screen's width and its own shape, clean to the top edge, going out of focus toward
/// its bottom and melting into a deep blur of itself under the title and the controls. Its still
/// shows first, drawn the same way, when it has one. A shade and a blur come over it while
/// lyrics show. `covers` hears whether the loop or its still now fills the player.
struct PlayerBackdrop: View {
    let clip: AnimatedClip
    let albumId: String?
    var shown: Bool
    var held: Bool
    var lyricsOpen: Bool
    var covers: (Bool) -> Void
    /// Hears how the top of what is drawn looks, for the status bar's color.
    var looked: (LoopLook) -> Void = { _ in }
    @Environment(Session.self) private var session
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.octoReduceMotion) private var calm
    @Environment(\.displayScale) private var scale
    @State private var stage = LoopStage.shared
    @State private var id = UUID()
    @State private var file: URL?
    @State private var poster: UIImage?
    @State private var playing = false
    @State private var melt: LoopMelt?
    @State private var meltKey = ""

    private var play: LoopPlay {
        loopPlay(seen: shown && !held && scenePhase == .active, powerSave: stage.lowPower, reduceMotion: calm)
    }

    private var covered: Bool { playing || poster != nil }

    /// How tall the loop is for each point of width: its own shape, 3:4 when it names none.
    private var shape: CGFloat {
        clip.width > 0 && clip.height > 0 ? CGFloat(clip.height) / CGFloat(clip.width) : 4.0 / 3.0
    }

    var body: some View {
        let play = play
        GeometryReader { box in
            let full = CGSize(width: box.size.width + 2, height: box.size.height + 2)
            // Drawn at twice the points at most: the loop's own version is about that sharp.
            let drawScale = min(scale, 2)
            let pixels = loopPixels(.tall, points: CGSize(width: full.width, height: full.width * shape), scale: scale)
            let key = "\(Int(full.width))x\(Int(full.height))|\(shape)|\(drawScale)"
            ZStack {
                LoopVideo(source: melt == nil ? nil : file, run: loopRun(play, shown: shown, owns: stage.owner == id), poster: poster,
                          melt: melt, blurred: lyricsOpen) { now in
                    playing = now
                }
                Color.black.opacity(lyricsOpen ? 0.45 : 0)
            }
            // A point past every edge, so no line of the screen shows past the loop.
            .frame(width: full.width, height: full.height)
            .position(x: box.size.width / 2, y: box.size.height / 2)
            .task(id: "\(clip.video)|\(key)|\(Int(pixels.width))|\(play == .stillOnly)") {
                if meltKey != key {
                    meltKey = key
                    melt = LoopMelt(screen: full, shape: shape, scale: drawScale)
                }
                file = nil
                let fetcher = loopFetcher(for: clip, client: session.client)
                let still = await LoopSource.shared.poster(clip, albumId: albumId, shape: .tall, fetcher: fetcher)
                guard !Task.isCancelled else { return }
                // The status bar reads on the top 50 pt.
                let band = 50 / max(full.width * shape, 1)
                if let still, let look = loopLook(still.cgImage, topShare: band) { looked(look) }
                if let still, let melt { poster = await Task.detached { melt.still(still) }.value } else { poster = nil }
                guard play != .stillOnly, !Task.isCancelled else { return }
                file = await LoopSource.shared.file(clip, albumId: albumId, shape: .tall, pixels: pixels, fetcher: fetcher)
                if let file, let look = await LoopSource.shared.look(file, topShare: band), !Task.isCancelled { looked(look) }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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
}

/// The colors the player's words take over the Full screen look: white, the quieter parts
/// added onto what is under them (see `PlayerInkScale.melt`), the heart and More at 70%.
func meltColors(_ base: PlayerColors) -> PlayerColors {
    var colors = base
    colors.dark = false
    colors.quiet = 0.70
    return colors
}
