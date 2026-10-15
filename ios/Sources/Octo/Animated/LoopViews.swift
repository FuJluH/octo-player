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

/// An album's tall loop filling the top two thirds of the player as `FullScreenLook` places it:
/// wider than the screen at its own shape, centered, from just above the top edge, its lower part
/// dissolving with a long soft melt into the player's own background (the wash, or whichever
/// background is chosen), so the title and the upper controls sit on the melting art. Where the
/// art under the words would leave them under 4.5:1, a soft band of the background's base color
/// comes in behind them, just enough. Its still shows first when it has one. While lyrics show,
/// the loop fades away and holds, leaving the background the lyrics are drawn for. `covers`
/// hears whether the loop or its still now shows.
struct PlayerBackdrop: View {
    let clip: AnimatedClip
    let albumId: String?
    /// Where the title row starts, in points from the top of the player; nil until laid out.
    var titleTop: CGFloat?
    /// The words' color (dark or white) and the background's base color under the loop.
    var darkInk = false
    var base: UInt32 = 0xFF00_0000
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
    /// A small copy of the loop's first frame (else its still), for the words' contrast.
    @State private var sample: CGImage?

    /// The block of words over the art: from the title row's top, this far down (the title, the
    /// artist, the progress line and its times).
    private static let wordsHeight: CGFloat = 110

    private var play: LoopPlay {
        loopPlay(seen: shown && !held && !lyricsOpen && scenePhase == .active, powerSave: stage.lowPower, reduceMotion: calm)
    }

    private var covered: Bool { playing || poster != nil }

    /// How tall the loop is for each point of width: its own shape, 3:4 when it names none.
    private var shape: CGFloat {
        clip.width > 0 && clip.height > 0 ? CGFloat(clip.height) / CGFloat(clip.width) : 4.0 / 3.0
    }

    /// How much of the loop shows at `y` (points from the screen's top), as its melt has it.
    private static func shown(_ y: CGFloat, melt: ClosedRange<CGFloat>) -> CGFloat {
        if y <= melt.lowerBound { return 1 }
        if y >= melt.upperBound { return 0 }
        return 1 - CGFloat(FullScreenLook.melt(Double((y - melt.lowerBound) / (melt.upperBound - melt.lowerBound))))
    }

    /// How strong a band of the base color behind the words must be for them to read at 4.5:1
    /// over the melting art: 0 when they already do.
    private func scrim(loopTop: CGFloat, loopHeight: CGFloat, melt: ClosedRange<CGFloat>) -> Double {
        guard let sample, let top = titleTop else { return 0 }
        let ink: UInt32 = darkInk ? DarkInkArgb : 0xFFFF_FFFF
        var needed = 0.0
        // Each row of the block, as the art over the background leaves it.
        for step in 0...10 {
            let y = top + Self.wordsHeight * CGFloat(step) / 10
            let alpha = Self.shown(y, melt: melt)
            guard alpha > 0.02, y < loopTop + loopHeight,
                  let art = loopRowColor(sample, share: (y - loopTop) / loopHeight) else { continue }
            let under = OctoKit.overlay(art, Float(alpha), base)
            if contrastRatio(ink, under) >= PlayerContrast { continue }
            var low = 0.0, high = 1.0
            for _ in 0..<16 {
                let mid = (low + high) / 2
                if contrastRatio(ink, OctoKit.overlay(base, Float(mid), under)) >= PlayerContrast { high = mid } else { low = mid }
            }
            needed = max(needed, high)
        }
        return needed
    }

    var body: some View {
        let play = play
        GeometryReader { box in
            let place = FullScreenLook.place(width: Double(box.size.width), height: Double(box.size.height), shape: Double(shape))
            let loopWidth = CGFloat(place.width)
            let loopHeight = CGFloat(place.height)
            let loopTop = CGFloat(place.top)
            let melt = CGFloat(place.meltFrom)...CGFloat(place.meltTo)
            let pixels = loopPixels(.tall, points: CGSize(width: loopWidth, height: loopHeight), scale: scale)
            let scrim = scrim(loopTop: loopTop, loopHeight: loopHeight, melt: melt)
            ZStack(alignment: .top) {
                LoopVideo(source: file, run: loopRun(play, shown: shown, owns: stage.owner == id), poster: poster,
                          fade: (melt.lowerBound - loopTop)...(melt.upperBound - loopTop)) { now in
                    playing = now
                }
                // Wider than the screen, centered, its top where the look puts it.
                .frame(width: loopWidth, height: loopHeight)
                .frame(width: box.size.width, alignment: .center)
                .offset(y: loopTop)
                if scrim > 0, let top = titleTop {
                    LinearGradient(stops: [
                        .init(color: Color(argb: base).opacity(0), location: 0),
                        .init(color: Color(argb: base).opacity(scrim), location: 0.3),
                        .init(color: Color(argb: base).opacity(scrim), location: 0.75),
                        .init(color: Color(argb: base).opacity(0), location: 1),
                    ], startPoint: .top, endPoint: .bottom)
                    .frame(height: Self.wordsHeight + 80)
                    .offset(y: top - 40)
                }
            }
            .frame(width: box.size.width, height: box.size.height, alignment: .top)
            .clipped()
            .opacity(lyricsOpen ? 0 : 1)
            .task(id: "\(clip.video)|\(Int(pixels.width))x\(Int(pixels.height))|\(play == .stillOnly)") {
                file = nil
                let fetcher = loopFetcher(for: clip, client: session.client)
                let still = await LoopSource.shared.poster(clip, albumId: albumId, shape: .tall, fetcher: fetcher)
                guard !Task.isCancelled else { return }
                poster = still
                sample = still.flatMap { loopSample($0.cgImage) }
                // The status bar reads on the top 50 pt.
                let band = 50 / max(loopHeight, 1)
                if let still, let look = loopLook(still.cgImage, topShare: band) { looked(look) }
                guard play != .stillOnly, !Task.isCancelled else { return }
                file = await LoopSource.shared.file(clip, albumId: albumId, shape: .tall, pixels: pixels, fetcher: fetcher)
                if let file, let look = await LoopSource.shared.look(file, topShare: band), !Task.isCancelled { looked(look) }
                if let file, let frame = await LoopSource.shared.firstFrame(file), !Task.isCancelled { sample = frame }
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
