import OctoKit
import SwiftUI
import UIKit

/// The radius a SwiftUI blur takes for a blur of `radius` points measured the platform way.
func platformBlur(_ radius: CGFloat) -> CGFloat { CGFloat(blurSigmaFor(Float(radius))) }

/// The player's background as the settings choose it, drawn over the base color at `show`:
/// the drifting wash, the still blurred artwork, a flat color, or the classic mesh. `dolly`
/// runs from 0 to 1 as the player comes in and back as it goes, and scales the wash and the
/// still artwork from 90% to full size.
struct PlayerBackground: View {
    let prefs: BackgroundPrefs
    let colors: PlayerColors
    let cover: WashCover?
    let coverId: String?
    /// Live background on.
    let live: Bool
    /// Octo's or the phone's Reduce motion.
    let calm: Bool
    let playing: Bool
    let bpm: Int?
    let entrance: PlayerEntrance
    let focused: Bool
    /// An album's animated art plays in the player: the background holds still under it, so the
    /// phone draws one moving thing, not two.
    var rests = false
    /// How much brighter than usual the background is drawn: brighter under a Full screen loop.
    var gain: Double = 1
    @State private var motion = PlayerMotion.shared

    var body: some View {
        ZStack {
            Color(argb: colors.base)
                .animation(.octoTween(fixed: 600), value: colors.base)
            layer
                // The wash draws its own gain; the other backgrounds are lifted to about the same.
                .brightness(prefs.mode == .immersive && WashGPU.shared != nil ? 0 : (gain - 1) * 0.4)
                .opacity(Double(colors.show))
                .animation(.timingCurve(0.65, 0, 0.35, 1, duration: 0.5), value: colors.show)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var layer: some View {
        switch prefs.mode {
        case .immersive:
            if WashGPU.shared != nil {
                ImmersiveWash(inputs: WashInputs(cover: cover, bpm: paceBpm(bpm, useBpm: prefs.useBpm), fpsLimit: prefs.fps,
                                                 speed: Float(prefs.speed) / 100, moving: live && !calm && !rests, focused: focused,
                                                 closing: entrance.closing, gain: Float(gain)))
            } else {
                // A phone whose graphics cannot run the wash shows the still artwork in its place.
                StillArtwork(cover: cover, dolly: entrance.dolly)
            }
        case .artwork:
            StillArtwork(cover: cover, dolly: entrance.dolly)
        case .color:
            Color(argb: colors.dominant.map { prepareColor($0, prefs.tuning) } ?? colors.base)
                .animation(.timingCurve(0.65, 0, 0.35, 1, duration: 0.5), value: colors.dominant)
        case .classic:
            if live && WashGPU.shared != nil {
                ClassicMesh(colors: colors.mesh, playing: playing && !rests, moving: motion.moving)
            } else {
                BlurredCover(coverId: coverId)
                    .opacity(0.6)
            }
        }
    }
}

/// The prepared cover filling the player, blurred 80 points with sharp edges, at 1.12 times the
/// dolly's scale so its edge never shows on the way in. A new cover fades in on the wash's
/// timing: the first at once, 300 ms when skipping through, otherwise 500 ms.
private struct StillArtwork: View {
    let cover: WashCover?
    let dolly: Double
    @State private var lastChange: Int?
    /// The cover drawn, swapped in with the fade worked out for that very change.
    @State private var shown: WashCover?

    var body: some View {
        GeometryReader { box in
            ZStack {
                if let shown, let image = shown.image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .scaledToFill()
                        .frame(width: box.size.width, height: box.size.height)
                        .clipped()
                        .blur(radius: platformBlur(80), opaque: true)
                        .id(shown.key)
                        .transition(.opacity)
                }
            }
            .scaleEffect(1.12 * CGFloat(dollyScale(Float(dolly))))
            .frame(width: box.size.width, height: box.size.height)
        }
        .onChange(of: cover?.key, initial: true) { _, _ in
            let now = Int(Date().timeIntervalSince1970 * 1000)
            let fadeMs = coverFadeMs(lastChange, now)
            lastChange = now
            if fadeMs == 0 {
                shown = cover
            } else {
                withAnimation(.timingCurve(0.65, 0, 0.35, 1, duration: Double(fadeMs) / 1000)) { shown = cover }
            }
        }
    }
}

/// The song's own artwork, center-cropped over the player and blurred 80 points.
private struct BlurredCover: View {
    let coverId: String?
    @Environment(Session.self) private var session
    @State private var image: UIImage?

    var body: some View {
        GeometryReader { box in
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: box.size.width, height: box.size.height)
                    .clipped()
                    .blur(radius: platformBlur(80), opaque: true)
                    .transition(.opacity)
            }
        }
        .task(id: coverId) {
            guard let coverId else {
                image = nil
                return
            }
            let loaded = await Covers.shared.image(coverId, size: WashSize, client: session.client)
            withAnimation(.easeOut(duration: 0.3)) { image = loaded }
        }
    }
}

/// The dolly: in over 800 ms after 20 ms, quick then settling; out over 500 ms, slow then quick.
enum PlayerDolly {
    static let open = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.8).delay(0.02)
    static let close = Animation.timingCurve(0.64, 0, 0.78, 0, duration: 0.5)
}
