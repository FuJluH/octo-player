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

/// An album's tall loop at the top of the player, at the screen's width and its own shape, clean
/// to the top edge, its lower part dissolving softly into the player's own background (the wash,
/// or whichever background is chosen) so it is gone just above the title. Its still shows first
/// when it has one. While lyrics show, the loop fades away and holds, leaving the background the
/// lyrics are drawn for. `covers` hears whether the loop or its still now shows.
struct PlayerBackdrop: View {
    let clip: AnimatedClip
    let albumId: String?
    /// Where the title row starts, in points from the top of the player; nil until laid out.
    var titleTop: CGFloat?
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

    /// How much of the screen's height the loop dissolves over, and how far above the title it
    /// is gone, in points.
    private static let fadeShare: CGFloat = 0.18
    private static let clearOfTitle: CGFloat = 6

    private var play: LoopPlay {
        loopPlay(seen: shown && !held && !lyricsOpen && scenePhase == .active, powerSave: stage.lowPower, reduceMotion: calm)
    }

    private var covered: Bool { playing || poster != nil }

    /// How tall the loop is for each point of width: its own shape, 3:4 when it names none.
    private var shape: CGFloat {
        clip.width > 0 && clip.height > 0 ? CGFloat(clip.height) / CGFloat(clip.width) : 4.0 / 3.0
    }

    /// Where the loop dissolves: over about 18% of the screen, gone just above the title (about
    /// 58% of the screen before the title is laid out), never past the loop's own bottom.
    private func fade(width: CGFloat, height: CGFloat) -> ClosedRange<CGFloat> {
        let loop = (width * shape).rounded()
        let end = min(loop, (titleTop ?? 0.58 * height) - Self.clearOfTitle)
        let start = max(end - Self.fadeShare * height, 0)
        return start...max(end, start + 1)
    }

    var body: some View {
        let play = play
        GeometryReader { box in
            let loopHeight = (box.size.width * shape).rounded()
            let pixels = loopPixels(.tall, points: CGSize(width: box.size.width, height: loopHeight), scale: scale)
            LoopVideo(source: file, run: loopRun(play, shown: shown, owns: stage.owner == id), poster: poster,
                      fade: fade(width: box.size.width, height: box.size.height)) { now in
                playing = now
            }
            // The screen's width exactly, the loop's own shape, from the top edge.
            .frame(width: box.size.width, height: loopHeight)
            .frame(maxHeight: .infinity, alignment: .top)
            .opacity(lyricsOpen ? 0 : 1)
            .task(id: "\(clip.video)|\(Int(pixels.width))x\(Int(pixels.height))|\(play == .stillOnly)") {
                file = nil
                let fetcher = loopFetcher(for: clip, client: session.client)
                let still = await LoopSource.shared.poster(clip, albumId: albumId, shape: .tall, fetcher: fetcher)
                guard !Task.isCancelled else { return }
                poster = still
                // The status bar reads on the top 50 pt.
                let band = 50 / max(loopHeight, 1)
                if let still, let look = loopLook(still.cgImage, topShare: band) { looked(look) }
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
