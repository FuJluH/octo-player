import CoreGraphics
import Observation
import OctoKit
import SwiftUI
import UIKit

/// Where the artwork's glow shows and how strongly, as Settings, Appearance keeps it.
@MainActor
@Observable
final class AmbientSettings {
    private let store: AppSettings

    init(store: AppSettings = .shared) { self.store = store }

    var prefs: AmbientPrefs { store.player.ambient }

    func setStrength(_ strength: AmbientStrength) { store.setAmbientStrength(strength) }

    /// The Settings summary: "No glow", "Subtle glow" or "Rich glow".
    var summary: String {
        switch prefs.strength {
        case .off: "No glow"
        case .subtle: "Subtle glow"
        case .rich: "Rich glow"
        }
    }
}

/// The artwork each open album or artist page shows, by its route, so the glow behind the page
/// on top can follow it.
@MainActor
@Observable
final class PageArtworks {
    private(set) var artworks: [Route: String] = [:]

    func artwork(for route: Route?) -> String? { route.flatMap { artworks[$0] } }

    func set(_ route: Route, _ artwork: String?) {
        if let artwork { artworks[route] = artwork } else { artworks[route] = nil }
    }

    func remove(_ route: Route, if artwork: String?) {
        if artworks[route] == artwork { artworks[route] = nil }
    }
}

extension View {
    /// An album or artist page's own cover, for the glow behind it while it is shown.
    func pageArtwork(_ route: Route, _ artwork: String?) -> some View {
        modifier(PageArtworkMark(route: route, artwork: artwork))
    }
}

private struct PageArtworkMark: ViewModifier {
    let route: Route
    let artwork: String?
    @Environment(PageArtworks.self) private var pages

    func body(content: Content) -> some View {
        content
            .onAppear { pages.set(route, artwork) }
            .onChange(of: artwork) { old, new in
                pages.remove(route, if: old)
                pages.set(route, new)
            }
            .onDisappear { pages.remove(route, if: artwork) }
    }
}

/// The colors picked out of each artwork, the same for the player and the glow: the last 32
/// kept. Quiet shades of the accent stand in for no artwork, or one with no usable color.
@MainActor
@Observable
final class ArtworkColorStore {
    private(set) var colors: [String: ArtworkColors] = [:]
    /// Covers whose colors could not be read, and when: Quiet stands in for them, uncached, and
    /// they are read again when asked for after a while.
    private var failed: [String: Date] = [:]
    @ObservationIgnored private var order: [String] = []
    @ObservationIgnored private var loading: Set<String> = []
    @ObservationIgnored private let session: Session

    private static let retryAfter: TimeInterval = 30

    init(session: Session) { self.session = session }

    /// The colors for a cover, once they are known; nil while they are being read.
    func colors(for coverId: String?) -> ArtworkColors? {
        guard let coverId else { return .quiet }
        if let known = colors[coverId] { return known }
        if let when = failed[coverId], Date().timeIntervalSince(when) < Self.retryAfter { return .quiet }
        guard session.client != nil else { return .quiet }
        load(coverId)
        return nil
    }

    private func load(_ coverId: String) {
        guard !loading.contains(coverId) else { return }
        let client = session.client
        loading.insert(coverId)
        Task {
            let image = await Covers.shared.image(coverId, size: artworkSampleSize, client: client)
            let found = await Task.detached(priority: .utility) { image.flatMap(Self.extract) }.value
            loading.remove(coverId)
            if let found {
                failed[coverId] = nil
                keep(coverId, found)
            } else {
                failed[coverId] = Date()
            }
        }
    }

    private func keep(_ coverId: String, _ found: ArtworkColors) {
        colors[coverId] = found
        order.removeAll { $0 == coverId }
        order.append(coverId)
        while order.count > 32 { colors[order.removeFirst()] = nil }
    }

    /// Reads a cover at 128 pixels, cuts it down to about 112 by 112, and picks its colors.
    nonisolated private static func extract(_ image: UIImage) -> ArtworkColors? {
        guard let source = image.cgImage else { return nil }
        let side = artworkSampleSize
        guard let large = pixels(of: source, width: side, height: side, smooth: true) else { return nil }
        let sample = paletteSampleSize(width: side, height: side)
        var small = [UInt32](repeating: 0, count: sample.width * sample.height)
        for y in 0..<sample.height {
            for x in 0..<sample.width {
                let sx = min(side - 1, x * side / sample.width)
                let sy = min(side - 1, y * side / sample.height)
                small[y * sample.width + x] = large[sy * side + sx]
            }
        }
        return ArtworkColors.from(pixels: small)
    }

    nonisolated private static func pixels(of image: CGImage, width: Int, height: Int, smooth: Bool) -> [UInt32]? {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn: Bool = bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = smooth ? .high : .none
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        return (0..<(width * height)).map { i in
            0xFF00_0000 | UInt32(bytes[i * 4]) << 16 | UInt32(bytes[i * 4 + 1]) << 8 | UInt32(bytes[i * 4 + 2])
        }
    }
}

/// The glow's drift time, one for every page, so the pools carry on from where they stopped
/// and a page opened over another shows them where they were. It moves at a fifth of the
/// player's pace, ten steps a second, only while music plays, the app is in view, the player
/// does not cover the pages and Reduce motion is off.
@MainActor
@Observable
final class AmbientDrift {
    private(set) var time = 0.0

    /// Moves time on until the task running it ends.
    func run() async {
        var last = Date()
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(AmbientTiming.frameMs))
            let now = Date()
            time += now.timeIntervalSince(last) * AmbientTiming.pace
            last = now
        }
    }
}

/// The glow behind every page: the artwork's colors, faint and dark, above the plain
/// background and under the page.
struct AmbientBackdrop: View {
    let page: AmbientPage?
    let route: Route?
    let awake: Bool
    @Environment(AmbientSettings.self) private var settings
    @Environment(PageArtworks.self) private var pages
    @Environment(ArtworkColorStore.self) private var store
    @Environment(Player.self) private var player
    @State private var held: ArtworkColors?

    var body: some View {
        let prefs = settings.prefs
        let source = ambientSource(prefs: prefs, page: page, pageArtwork: pages.artwork(for: route),
                                   hasTrack: player.current != nil, playingArtwork: player.current?.coverArt)
        let artwork: String?? = switch source {
        case .none: nil
        case .playing(let cover): .some(cover)
        case .page(let cover): .some(cover)
        }
        let found = artwork.flatMap { store.colors(for: $0) }
        // Kept through a turn to none, so the old colors fade out as they are.
        let colors = found ?? held
        let strength = source == .none || colors == nil ? 0 : ambientAlpha(prefs.strength)
        AmbientField(paint: AmbientPaint(colors: colors ?? .quiet, strength: strength), shown: awake)
            .animation(.octoTween(fixed: AmbientTiming.crossMs), value: AmbientPaint(colors: colors ?? .quiet, strength: strength))
            .onChange(of: found, initial: true) { _, new in if let new { held = new } }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// The glow's four colors and strength, as one value that can ease from one song to the next.
struct AmbientPaint: VectorArithmetic {
    var values: [Double]

    init(values: [Double]) { self.values = values }

    init(colors: ArtworkColors, strength: Double) {
        var out: [Double] = []
        for color in colors.mesh.prefix(4) {
            let safe = RGBA(argb: ambientColor(0xFF00_0000 | color))
            out += [safe.red, safe.green, safe.blue]
        }
        while out.count < 12 { out.append(0) }
        out.append(strength)
        values = out
    }

    var strength: Double { values.count > 12 ? values[12] : 0 }

    var colors: [(Double, Double, Double)] {
        (0..<4).map { i in (values[i * 3], values[i * 3 + 1], values[i * 3 + 2]) }
    }

    static var zero: AmbientPaint { AmbientPaint(values: Array(repeating: 0, count: 13)) }

    static func + (a: AmbientPaint, b: AmbientPaint) -> AmbientPaint { AmbientPaint(values: zip(a.padded, b.padded).map(+)) }
    static func - (a: AmbientPaint, b: AmbientPaint) -> AmbientPaint { AmbientPaint(values: zip(a.padded, b.padded).map(-)) }
    mutating func scale(by rhs: Double) { values = padded.map { $0 * rhs } }
    var magnitudeSquared: Double { padded.reduce(0) { $0 + $1 * $1 } }

    private var padded: [Double] { values.count >= 13 ? values : values + Array(repeating: 0, count: 13 - values.count) }
}

/// The color field itself: the player's drifting mesh, at a fifth of its pace and redrawn ten
/// times a second, faded toward the bottom so lists and the bar sit on its quietest part.
private struct AmbientField: View, Animatable {
    var paint: AmbientPaint
    /// Pages out of sight keep the time they were drawn at.
    let shown: Bool
    @Environment(AmbientDrift.self) private var drift
    @State private var still = 0.0

    nonisolated var animatableData: AmbientPaint {
        get { paint }
        set { paint = newValue }
    }

    var body: some View {
        if paint.strength > AmbientTiming.threshold {
            MeshImage(colors: paint.colors, time: shown ? drift.time : still)
                .opacity(paint.strength)
                .overlay {
                    LinearGradient(stops: [.init(color: .clear, location: 0.35),
                                           .init(color: OctoColor.background.opacity(0.4), location: 1)],
                                   startPoint: .top, endPoint: .bottom)
                }
                .onChange(of: shown, initial: true) { _, now in if !now { still = drift.time } }
        } else {
            Color.clear
        }
    }
}

/// The mesh drawn small and stretched smooth: a field this soft looks the same.
struct MeshImage: View {
    let colors: [(Double, Double, Double)]
    let time: Double

    var body: some View {
        GeometryReader { box in
            let width = max(1, box.size.width)
            let height = max(1, box.size.height)
            let columns = 24
            let rows = max(1, Int((Double(columns) * height / width).rounded()))
            if let image = Self.image(columns: columns, rows: rows, width: width, height: height, time: time, colors: colors) {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: width, height: height)
            }
        }
    }

    static func image(columns: Int, rows: Int, width: Double, height: Double, time: Double,
                      colors: [(Double, Double, Double)]) -> CGImage? {
        let bytes = MeshField.render(columns: columns, rows: rows, width: width, height: height, time: time, colors: colors)
        guard !bytes.isEmpty, let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: columns, height: rows, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: columns * 4,
                       space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}

/// A strip in Settings showing the glow at a strength, still, with the song on now written over
/// it the way a page's words sit on it.
struct AmbientPreview: View {
    let strength: AmbientStrength
    @Environment(ArtworkColorStore.self) private var store
    @Environment(Player.self) private var player

    var body: some View {
        // With no artwork the quiet colors show; artwork whose colors are still being read
        // shows the plain strip until they are.
        let cover = player.current?.coverArt
        let colors: ArtworkColors? = cover == nil ? .quiet : store.colors(for: cover)
        let paint = AmbientPaint(colors: colors ?? .quiet, strength: colors == nil ? 0 : ambientAlpha(strength))
        ZStack(alignment: .leading) {
            OctoColor.background
            AmbientPreviewField(paint: paint)
                .animation(.octoTween(fixed: AmbientTiming.crossMs), value: paint)
            VStack(alignment: .leading, spacing: 0) {
                Text(player.current?.title ?? "Nothing playing")
                    .font(.octoBodySmall).foregroundStyle(.white).lineLimit(1)
                Text(player.current != nil ? (player.current?.artist ?? "") : "The glow takes its colors from the song on now.")
                    .font(.octoCaption).foregroundStyle(OctoColor.textSecondary).lineLimit(1)
            }
            .padding(.horizontal, 16)
        }
        .frame(height: 72)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// The preview's glow: the pages' field held still, easing to a new strength or song as they
/// do, faded toward the bottom the same way.
private struct AmbientPreviewField: View, Animatable {
    var paint: AmbientPaint

    nonisolated var animatableData: AmbientPaint {
        get { paint }
        set { paint = newValue }
    }

    var body: some View {
        if paint.strength > AmbientTiming.threshold {
            MeshImage(colors: paint.colors, time: 0)
                .opacity(paint.strength)
                .overlay {
                    LinearGradient(stops: [.init(color: .clear, location: 0.35),
                                           .init(color: OctoColor.background.opacity(0.4), location: 1)],
                                   startPoint: .top, endPoint: .bottom)
                }
        } else {
            Color.clear
        }
    }
}

/// The bar's film: the plain dim, or with the bar tint on and a song loaded, a trace of the
/// song's main color laid over it. It changes over 800 ms.
struct BarFilm {
    @MainActor
    static func color(settings: AmbientSettings, store: ArtworkColorStore, player: Player) -> Color {
        let prefs = settings.prefs
        guard prefs.tintsBar, let song = player.current else { return OctoColor.glazeFilm }
        guard let colors = store.colors(for: song.coverArt), let first = colors.mesh.first else { return OctoColor.glazeFilm }
        return Color(barFilm(prefs: prefs, hasTrack: true, firstMeshColor: first))
    }
}
