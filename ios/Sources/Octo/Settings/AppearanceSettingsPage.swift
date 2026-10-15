import OctoKit
import SwiftUI
import UIKit

/// How the app looks: the accent, the artwork's colors glowing behind the pages, how strongly and
/// where, Home's sections, the player's background, playlist covers, and how much moves.
struct AppearanceSettingsPage: View {
    var highlight: String?
    @State private var settings = AppSettings.shared

    var body: some View {
        let prefs = settings.player
        let ambient = prefs.ambient
        SettingsPageFrame(title: SettingsPage.appearance.title, highlight: highlight) {
            SettingsGroup {
                AccentPickerRow()
                GlassTintRow()
            }
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
            SettingsGroup(title: "Home", icon: SettingsIcon.home) {
                LinkRow(SettingsIndex.homeSections, helper: homeSectionsSummary(settings.homeSections), to: Route.homeSections)
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

    /// The full player's background: what it is, whether it moves, how the artwork is prepared
    /// for it, and how an album's animated art shows.
    private func playerBackground(_ prefs: PlayerPrefs) -> some View {
        let background = prefs.background
        let moves = background.mode.canMove
        return SettingsGroup(title: "Player", icon: SettingsIcon.playback) {
            ChoiceRow(SettingsIndex.playerBackground, value: background.mode.label, question: SettingsQuestion(
                SettingsIndex.playerBackground.title, BackgroundMode.allCases, current: background.mode,
                answer: { SettingsAnswer($0.label, $0.detail) }, pick: { mode in settings.setBackground { $0.mode = mode } }))
            ChoiceRow(SettingsIndex.animatedArt, value: settings.animatedArt.label, question: SettingsQuestion(
                SettingsIndex.animatedArt.title, AnimatedArtSetting.allCases, current: settings.animatedArt,
                answer: { SettingsAnswer($0.label, $0.detail) }, pick: settings.setAnimatedArt))
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
