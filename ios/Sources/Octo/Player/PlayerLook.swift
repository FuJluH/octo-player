import CoreGraphics
import Observation
import OctoKit
import SwiftUI
import UIKit

/// The colors the player paints behind a song: four for the moving background, a base under
/// everything, the artwork's main color as it came, and the color for the player's words and
/// icons (white, or dark over a light background), with how much of the background shows over
/// the base so those words read.
struct PlayerColors: Equatable {
    /// `0xFFRRGGBB` each.
    var mesh: [UInt32]
    var base: UInt32
    var dominant: UInt32?
    var dark = false
    var show: Float = 1
    /// How strongly the quieter icons beside the name show: 70%, more over a background close to
    /// the words' limit, as far as 4.5:1 needs.
    var quiet: Float = PlayerTitleRow.iconAlpha

    /// Before artwork loads, or for music without any: quiet shades of the app's own accent.
    static let quiet = PlayerColors(artwork: .quiet)

    init(artwork: ArtworkColors) {
        mesh = artwork.mesh.map { 0xFF00_0000 | $0 }
        base = 0xFF00_0000 | artwork.base
        dominant = artwork.dominant.map { 0xFF00_0000 | $0 }
    }

    /// The color for every word and icon in the player.
    var content: Color { dark ? Color(argb: DarkInkArgb) : .white }

    /// The words' color decided from what is drawn behind them, and the background dimmed as far
    /// as they need. Until that is known, white words over the background as it is. The quieter
    /// icons are as strong as reading over the background's hardest part needs: its brightest
    /// under white words, its darkest under dark ones.
    func over(_ range: WashRange?) -> PlayerColors {
        var colors = self
        let ink = range.map { inkOver($0, base) } ?? WashInk(dark: false, show: 1)
        colors.dark = ink.dark
        colors.show = ink.show
        let under = quietIconsUnder(range, base: base, dark: ink.dark, show: ink.show)
        colors.quiet = quietAlpha(under, ink: ink.dark ? DarkInkArgb : 0xFFFF_FFFF, soft: PlayerTitleRow.iconAlpha)
        return colors
    }
}

extension Color {
    /// A color from `0xAARRGGBB`.
    init(argb: UInt32) {
        self.init(.sRGB, red: Double((argb >> 16) & 0xFF) / 255, green: Double((argb >> 8) & 0xFF) / 255,
                  blue: Double(argb & 0xFF) / 255, opacity: Double((argb >> 24) & 0xFF) / 255)
    }
}

/// Secondary words in the player (times, the album's name, the volume's speakers): the dark ink
/// at 60% over a light background, otherwise the app's muted words.
func mutedInk(_ ink: Color, dark: Bool) -> Color { dark ? ink.opacity(0.6) : OctoColor.textMuted }

/// The artist's name and the explicit mark: the dark ink at 75% over a light background,
/// otherwise the accent.
func accentInk(_ ink: Color, dark: Bool) -> Color { dark ? ink.opacity(0.75) : OctoColor.accent }

extension BackgroundPrefs {
    /// How the cover is prepared for this background.
    var tuning: WashTuning { WashTuning(contrast: contrast, saturation: Float(saturation) / 100, brightnessCap: Float(brightnessCap) / 100) }
}

/// A cover made ready for the background: the 512 square the wash and the blurred artwork draw
/// from, its pixels, and its darkest and brightest patches, which the words' color follows.
final class WashCover: @unchecked Sendable {
    let key: String
    /// Nil only when the picture could not be made.
    let image: CGImage?
    /// `0xFFRRGGBB`, row by row.
    let pixels: [UInt32]
    let range: WashRange

    init(key: String, pixels: [UInt32]) {
        self.key = key
        self.pixels = pixels
        image = WashCover.picture(pixels, WashSize)
        range = washRange(pixels, WashSize)
    }

    /// Two covers mixed as the wash mixes them, `mix` of the new over the old, for a fade that
    /// starts while another is under way.
    static func mixed(_ old: WashCover, _ new: WashCover, _ mix: Float) -> WashCover {
        let t = min(max(mix, 0), 1)
        let pixels = zip(old.pixels, new.pixels).map { a, b in overlay(b, t, a) }
        return WashCover(key: "\(old.key)+\(new.key)@\(t)", pixels: pixels)
    }

    static func picture(_ pixels: [UInt32], _ side: Int) -> CGImage? {
        var bytes = [UInt8](repeating: 255, count: side * side * 4)
        for (i, p) in pixels.enumerated() {
            bytes[i * 4] = UInt8((p >> 16) & 0xFF)
            bytes[i * 4 + 1] = UInt8((p >> 8) & 0xFF)
            bytes[i * 4 + 2] = UInt8(p & 0xFF)
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: side * 4,
                       space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}

/// Prepares covers for the background off the main thread, and keeps the last few so going back
/// a song is instant. The background and the words' color ask for the same one.
@MainActor
final class WashArtwork {
    static let shared = WashArtwork()

    private var cache: [String: WashCover] = [:]
    private var order: [String] = []
    private var making: [String: Task<WashCover, Never>] = [:]
    /// The cover being made: one at a time, so the next waits for it and may find it made.
    private var last: Task<WashCover, Never>?

    /// The cover for a song's artwork with these adjustments. A song with no artwork gets a soft
    /// blend of its colors instead.
    func prepare(_ coverId: String?, colors: PlayerColors, tuning: WashTuning, client: SubsonicClient?) async -> WashCover {
        let key = "\(coverId ?? "none:\(colors.mesh)")|\(tuning.contrast)|\(tuning.saturation)|\(tuning.brightnessCap)"
        if let known = cache[key] { return known }
        if let running = making[key] { return await running.value }
        let before = last
        let task = Task<WashCover, Never> {
            _ = await before?.value
            var source: CGImage?
            if let coverId { source = await Covers.shared.image(coverId, size: WashSize, client: client)?.cgImage }
            let mesh = colors.mesh
            return await Task.detached(priority: .userInitiated) {
                let pixels = source.flatMap { WashArtwork.processed($0, tuning) } ?? WashArtwork.blend(mesh, tuning)
                return WashCover(key: key, pixels: pixels)
            }.value
        }
        making[key] = task
        last = task
        let cover = await task.value
        making[key] = nil
        cache[key] = cover
        order.removeAll { $0 == key }
        order.append(key)
        while order.count > 4 { cache[order.removeFirst()] = nil }
        return cover
    }

    /// Cropped to its middle square and brought to 512, then contrast and saturation through a
    /// color matrix, then the brightness cap pixel by pixel.
    nonisolated static func processed(_ source: CGImage, _ tuning: WashTuning) -> [UInt32]? {
        let side = WashSize
        let short = min(source.width, source.height)
        let crop = CGRect(x: (source.width - short) / 2, y: (source.height - short) / 2, width: short, height: short)
        guard let square = source.cropping(to: crop), let pixels = draw(side, { $0.draw(square, in: CGRect(x: 0, y: 0, width: side, height: side)) })
        else { return nil }
        let matrix = washColorMatrix(tuning)
        return pixels.map { capBrightness(applyColorMatrix($0, matrix), tuning.brightnessCap) }
    }

    /// For music without artwork: its colors, blended corner to corner, then adjusted as a cover
    /// would be.
    nonisolated static func blend(_ mesh: [UInt32], _ tuning: WashTuning) -> [UInt32] {
        let side = WashSize
        let colors = mesh.map { CGColor(srgbRed: CGFloat(($0 >> 16) & 0xFF) / 255, green: CGFloat(($0 >> 8) & 0xFF) / 255,
                                        blue: CGFloat($0 & 0xFF) / 255, alpha: 1) }
        let pixels = draw(side) { context in
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: nil) else { return }
            // Drawn bottom-up, so top left to bottom right on the square as read.
            context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: side), end: CGPoint(x: side, y: 0), options: [])
        }
        guard let pixels else { return [UInt32](repeating: 0xFF00_0000, count: side * side) }
        let matrix = washColorMatrix(tuning)
        return pixels.map { capBrightness(applyColorMatrix($0, matrix), tuning.brightnessCap) }
    }

    /// Draws into a `side` square and reads its pixels back, top row first, as `0xFFRRGGBB`.
    nonisolated private static func draw(_ side: Int, _ paint: (CGContext) -> Void) -> [UInt32]? {
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        let drawn: Bool = bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
            else { return false }
            context.interpolationQuality = .high
            paint(context)
            return true
        }
        guard drawn else { return nil }
        return (0..<(side * side)).map { i in
            0xFF00_0000 | UInt32(bytes[i * 4]) << 16 | UInt32(bytes[i * 4 + 1]) << 8 | UInt32(bytes[i * 4 + 2])
        }
    }
}

/// The darkest and brightest the background drawn in `mode` gets: the prepared cover's range,
/// as the wash's last pass leaves it; the adjusted main color for a flat fill; the mesh's four
/// colors for the classic one (at 60% over the base when it cannot move, as the blurred artwork
/// then shows). Nil while the cover is still being made.
func drawnRange(_ mode: BackgroundMode, _ colors: PlayerColors, _ prefs: BackgroundPrefs, _ cover: WashRange?, live: Bool) -> WashRange? {
    switch mode {
    case .immersive: return cover?.scaled(FinalGain)
    case .artwork: return cover
    case .color: return WashRange.of(colors.dominant.map { prepareColor($0, prefs.tuning) } ?? colors.base)
    case .classic: return live ? WashRange.of(colors.mesh) : WashRange.of(colors.mesh.map { overlay($0, 0.6, colors.base) })
    }
}

/// What the player's background and words follow: the song's artwork colors, the prepared
/// cover, and the words' color, worked out again when the artwork or the background settings
/// change. Colors follow the artwork, not the song, so an album plays through without the
/// background flickering; a newer request replaces an older one.
@MainActor
@Observable
final class PlayerLook {
    /// One for the app's life, so a player opened again starts on the colors it closed with.
    static let shared = PlayerLook()

    private(set) var colors = PlayerColors.quiet
    private(set) var cover: WashCover?
    @ObservationIgnored private var running: Task<Void, Never>?
    @ObservationIgnored private var asked: String?

    func follow(coverId: String?, prefs: BackgroundPrefs, live: Bool, artwork: ArtworkColors?, client: SubsonicClient?) {
        let key = "\(coverId ?? "-")|\(prefs.mode.rawValue)|\(prefs.tuning)|\(live)|\(artwork.map { "\($0.mesh)" } ?? "?")"
        guard key != asked else { return }
        asked = key
        running?.cancel()
        guard let artwork else { return }
        let base = PlayerColors(artwork: artwork)
        running = Task {
            var prepared: WashCover?
            if prefs.mode == .immersive || prefs.mode == .artwork {
                prepared = await WashArtwork.shared.prepare(coverId, colors: base, tuning: prefs.tuning, client: client)
                guard !Task.isCancelled else { return }
                cover = prepared
            }
            colors = base.over(drawnRange(prefs.mode, base, prefs, prepared?.range, live: live))
        }
    }
}
