import OctoKit
import SwiftUI
import UIKit

/// How the app looks: the artwork's colors glowing behind the pages, how strongly and where,
/// the player's background, playlist covers, and how much moves.
struct AppearanceSettingsPage: View {
    var highlight: String?
    @State private var settings = AppSettings.shared

    var body: some View {
        let prefs = settings.player
        let ambient = prefs.ambient
        SettingsPageFrame(title: SettingsPage.appearance.title, highlight: highlight) {
            AmbientPreview(strength: ambient.strength).padding(.horizontal, 16)
            SettingsGroup {
                ChoiceRow(SettingsIndex.ambient, value: ambient.strength.label, question: SettingsQuestion(
                    SettingsIndex.ambient.title, AmbientStrength.allCases, current: ambient.strength,
                    answer: { SettingsAnswer($0.label, $0.detail) }, pick: settings.setAmbientStrength))
            }
            if ambient.strength != .off {
                SettingsGroup(title: "Where it shows", icon: SettingsIcon.layout) {
                    ToggleRow(SettingsIndex.ambientHome, isOn: ambient.home) { settings.setAmbientArea(.home, $0) }
                    ToggleRow(SettingsIndex.ambientLibrary, isOn: ambient.library) { settings.setAmbientArea(.library, $0) }
                    ToggleRow(SettingsIndex.ambientSearch, isOn: ambient.search) { settings.setAmbientArea(.search, $0) }
                    ToggleRow(SettingsIndex.ambientSettings, isOn: ambient.settings) { settings.setAmbientArea(.settings, $0) }
                    ToggleRow(SettingsIndex.ambientBar, isOn: ambient.bar, helper: "A trace of the song's color in its glass.",
                              onChange: settings.setAmbientBar)
                    ToggleRow(SettingsIndex.ambientPageArtwork, isOn: ambient.pageArtwork,
                              helper: "The glow follows the page's album or artist, not the song.", onChange: settings.setAmbientPageArtwork)
                }
            }
            playerBackground(prefs)
            SettingsGroup(title: "Playlists", icon: SettingsIcon.playlists) {
                ChoiceRow(SettingsIndex.playlistCovers, value: settings.playlistCovers.label, question: SettingsQuestion(
                    SettingsIndex.playlistCovers.title, PlaylistCoverStyle.allCases, current: settings.playlistCovers,
                    answer: { SettingsAnswer($0.label, $0.help) }, pick: settings.setPlaylistCovers))
            }
            SettingsGroup(title: "Motion", icon: SettingsIcon.sparkle) {
                ToggleRow(SettingsIndex.reduceMotion, isOn: prefs.reduceMotion,
                          helper: "Backgrounds and lyrics hold still. On by itself when the phone's animations are off.",
                          onChange: settings.setReduceMotion)
            }
        }
    }

    /// The full player's background: what it is, whether it moves, and how the artwork is
    /// prepared for it.
    private func playerBackground(_ prefs: PlayerPrefs) -> some View {
        let background = prefs.background
        let moves = background.mode.canMove
        return SettingsGroup(title: "Player", icon: SettingsIcon.playback) {
            ChoiceRow(SettingsIndex.playerBackground, value: background.mode.label, question: SettingsQuestion(
                SettingsIndex.playerBackground.title, BackgroundMode.allCases, current: background.mode,
                answer: { SettingsAnswer($0.label, $0.detail) }, pick: { mode in settings.setBackground { $0.mode = mode } }))
            ToggleRow(SettingsIndex.liveBackground, isOn: prefs.liveBackground && moves,
                      helper: moves ? nil : "This background stays still.", enabled: moves, onChange: settings.setLiveBackground)
            if background.prepared {
                percentSlider(SettingsIndex.backgroundBrightnessCap, background.brightnessCap, BackgroundPrefs.brightnessCapRange, step: 5) { value in
                    settings.setBackground { $0.brightnessCap = value }
                }
                percentSlider(SettingsIndex.backgroundSaturation, background.saturation, BackgroundPrefs.saturationRange, step: 10) { value in
                    settings.setBackground { $0.saturation = value }
                }
                contrastSlider(background.contrast)
            }
            if background.mode == .immersive {
                percentSlider(SettingsIndex.backgroundSpeed, background.speed, BackgroundPrefs.speedRange, step: 5) { value in
                    settings.setBackground { $0.speed = value }
                }
                ToggleRow(SettingsIndex.backgroundUseBpm, isOn: background.useBpm, helper: "Drifts with the song's tempo, when it's known.") { on in
                    settings.setBackground { $0.useBpm = on }
                }
                ChoiceRow(SettingsIndex.backgroundFps, value: "\(background.fps) fps", question: SettingsQuestion(
                    SettingsIndex.backgroundFps.title, BackgroundPrefs.fpsChoices, current: background.fps,
                    answer: { SettingsAnswer("\($0) fps", $0 == 30 ? "Easiest on the battery." : nil) },
                    pick: { fps in settings.setBackground { $0.fps = fps } }))
            }
        }
    }

    /// A percentage along a range, in steps, saved only when it changes.
    private func percentSlider(_ entry: SettingEntry, _ value: Int, _ range: ClosedRange<Int>, step: Int,
                               onChange: @escaping (Int) -> Void) -> some View {
        let span = Double(range.upperBound - range.lowerBound)
        return SliderRow(entry, value: "\(value)%", fraction: Double(value - range.lowerBound) / span) { fraction in
            let picked = range.lowerBound + Int((fraction * span / Double(step) + 0.5).rounded(.down)) * step
            if picked != value { onChange(picked.held(to: range)) }
        }
    }

    /// The contrast factor, in steps of 0.05.
    private func contrastSlider(_ value: Float) -> some View {
        let range = BackgroundPrefs.contrastRange
        let steps = Int(((range.upperBound - range.lowerBound) / 0.05 + 0.5).rounded(.down))
        let at = Int(((value - range.lowerBound) / 0.05 + 0.5).rounded(.down))
        return SliderRow(SettingsIndex.backgroundContrast, value: String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), value),
                         fraction: Double(at) / Double(steps)) { fraction in
            let picked = Int((fraction * Double(steps) + 0.5).rounded(.down))
            if picked != at {
                let contrast = Float(Int(((range.lowerBound + Float(picked) * 0.05) * 100 + 0.5).rounded(.down))) / 100
                settings.setBackground { $0.contrast = contrast }
            }
        }
    }
}

/// A strip showing the glow at a strength, with the song on now written over it the way a
/// page's words sit on it. Its colors come from the song's artwork; without one, quiet shades of
/// the app's accent. It never drifts.
struct AmbientPreview: View {
    let strength: AmbientStrength
    @Environment(Player.self) private var player
    @Environment(Session.self) private var session
    @State private var colors: [Color] = AmbientColor.quiet.map(Self.color)

    var body: some View {
        let song = player.current
        ZStack(alignment: .leading) {
            OctoColor.background
            LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                .opacity(strength.glowAlpha)
                .animation(.easeInOut(duration: 0.8), value: strength)
            VStack(alignment: .leading, spacing: 0) {
                Text(song?.title ?? "Nothing playing").font(.octoBodySmall).foregroundStyle(OctoColor.textPrimary).lineLimit(1)
                Text(song.map { $0.artist ?? "" } ?? "The glow takes its colors from the song on now.")
                    .font(.octoCaption)
                    .foregroundStyle(OctoColor.textSecondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 16)
        }
        .frame(height: 72)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .task(id: song?.coverArt) {
            guard let id = song?.coverArt, let client = session.client,
                  let image = await Covers.shared.image(id, size: 64, client: client),
                  let mesh = Self.meshColors(image)
            else {
                withAnimation(.easeInOut(duration: 0.8)) { colors = AmbientColor.quiet.map(Self.color) }
                return
            }
            withAnimation(.easeInOut(duration: 0.8)) { colors = mesh.map { Self.color(AmbientColor.safe($0)) } }
        }
    }

    nonisolated static func color(_ argb: UInt32) -> Color {
        Color(hex: argb & 0xFFFFFF)
    }

    /// Four colors from the artwork: the average of each quarter.
    nonisolated static func meshColors(_ image: UIImage) -> [UInt32]? {
        guard let cg = image.cgImage else { return nil }
        var pixels = [UInt8](repeating: 0, count: 2 * 2 * 4)
        guard let context = CGContext(data: &pixels, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 8,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.interpolationQuality = .medium
        context.draw(cg, in: CGRect(x: 0, y: 0, width: 2, height: 2))
        return (0..<4).map { i in
            let r = UInt32(pixels[i * 4]), g = UInt32(pixels[i * 4 + 1]), b = UInt32(pixels[i * 4 + 2])
            return 0xFF00_0000 | (r << 16) | (g << 8) | b
        }
    }
}
