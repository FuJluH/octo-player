import OctoKit
import SwiftUI

/// How songs play: blending, speed, skipping silence, Autoplay and how radio is tuned, music
/// coming back when headphones connect, and what happens when casting ends.
struct PlaybackSettingsPage: View {
    var highlight: String?
    @State private var settings = AppSettings.shared
    @State private var navigator = SettingsNavigator.shared
    @State private var speedOpen = false

    var body: some View {
        let prefs = settings.player
        SettingsPageFrame(title: SettingsPage.playback.title, highlight: highlight) {
            SettingsGroup {
                ToggleRow(SettingsIndex.crossfade, isOn: prefs.crossfade, helper: "Albums played in order stay gapless.", onChange: settings.setCrossfade)
                if prefs.crossfade {
                    crossfadeLength(prefs.crossfadeSeconds)
                    ToggleRow(SettingsIndex.smartTransitions, isOn: prefs.smartTransitions,
                              helper: "Each blend starts where the two songs meet best, on the beat when it can. Off blends at the end of each song.",
                              onChange: settings.setSmartTransitions)
                    if prefs.smartTransitions {
                        ToggleRow(SettingsIndex.filterSweeps, isOn: prefs.filterSweeps,
                                  helper: "The song ending loses its highs and bass as the next one comes in.", onChange: settings.setFilterSweeps)
                        ToggleRow(SettingsIndex.matchTempo, isOn: prefs.matchTempo,
                                  helper: "Songs with a close tempo blend in step. The next song settles back to its own speed after.",
                                  onChange: settings.setMatchTempo)
                    }
                }
                PopoverRow(SettingsIndex.speed, value: SettingsWords.paceLabel(prefs), isPresented: $speedOpen) {
                    PaceCard().frame(width: 320)
                }
                ToggleRow(SettingsIndex.skipSilence, isOn: prefs.skipSilence, onChange: settings.setSkipSilence)
                ToggleRow(SettingsIndex.autoplay, isOn: prefs.autoplay, helper: "When the queue ends, similar songs keep playing.",
                          onChange: settings.setAutoplay)
            }
            SettingsGroup(title: "Radio", icon: SettingsIcon.radio) {
                ChoiceRow(SettingsIndex.radioDiscovery, value: prefs.radioDiscovery.label, question: SettingsQuestion(
                    SettingsIndex.radioDiscovery.title, RadioDiscovery.allCases, current: prefs.radioDiscovery,
                    answer: { SettingsAnswer($0.label, $0.detail) }, pick: settings.setRadioDiscovery))
                ChoiceRow(SettingsIndex.radioAdventure, value: prefs.radioAdventure.label, question: SettingsQuestion(
                    SettingsIndex.radioAdventure.title, RadioAdventure.allCases, current: prefs.radioAdventure,
                    answer: { SettingsAnswer($0.label, $0.detail) }, pick: settings.setRadioAdventure))
                ChoiceRow(SettingsIndex.radioVariety, value: prefs.radioVariety.label, question: SettingsQuestion(
                    SettingsIndex.radioVariety.title, RadioVariety.allCases, current: prefs.radioVariety,
                    answer: { SettingsAnswer($0.label, $0.detail) }, pick: settings.setRadioVariety))
                ToggleRow(SettingsIndex.radioFavorites, isOn: prefs.radioFavorites,
                          helper: "Songs you hearted or rated 4 or 5 stars come around more often.", onChange: settings.setRadioFavorites)
            }
            SettingsGroup(title: "Headphones", icon: SettingsIcon.headphones,
                          footer: prefs.resumeWired || prefs.resumeBluetooth ? "Only while Octo is open or paused in the background." : nil) {
                ToggleRow(SettingsIndex.resumeWired, isOn: prefs.resumeWired, helper: "If unplugging paused it in the last 30 minutes.",
                          onChange: settings.setResumeWired)
                ToggleRow(SettingsIndex.resumeBluetooth, isOn: prefs.resumeBluetooth, helper: "If losing them paused it in the last 30 minutes.",
                          onChange: settings.setResumeBluetooth)
                if prefs.resumeWired || prefs.resumeBluetooth {
                    ToggleRow(SettingsIndex.resumeAlways, isOn: prefs.resumeAlways, helper: "However or whenever the music was paused.",
                              onChange: settings.setResumeAlways)
                }
            }
            SettingsGroup(title: "Casting", icon: SettingsIcon.cast) {
                ToggleRow(SettingsIndex.castKeepPlaying, isOn: prefs.castKeepPlaying,
                          helper: "When a TV or speaker drops out, the music carries on here.", onChange: settings.setCastKeepPlaying)
            }
        }
        .onChange(of: navigator.popup, initial: true) { _, popup in
            if popup == SettingsIndex.speed.id {
                navigator.popup = nil
                speedOpen = true
            }
        }
    }

    /// The longest a blend may be, from 2 to 16 seconds, saved as it changes.
    private func crossfadeLength(_ seconds: Int) -> some View {
        let range = PlayerPrefs.crossfadeSecondsRange
        let span = Double(range.upperBound - range.lowerBound)
        return SliderRow(SettingsIndex.crossfadeLength, value: "\(seconds) s",
                         fraction: Double(seconds - range.lowerBound) / span) { fraction in
            let picked = range.lowerBound + Int((fraction * span + 0.5).rounded(.down))
            if picked != seconds { settings.setCrossfadeSeconds(picked) }
        }
    }
}

/// A row like a choice row that opens its own card in a popover beside it instead of a list.
struct PopoverRow<Card: View>: View {
    let entry: SettingEntry?
    let value: String
    @Binding var isPresented: Bool
    let card: () -> Card

    init(_ entry: SettingEntry?, value: String, isPresented: Binding<Bool>, @ViewBuilder card: @escaping () -> Card) {
        self.entry = entry
        self.value = value
        _isPresented = isPresented
        self.card = card
    }

    var body: some View {
        Button { isPresented = true } label: {
            RowFrame(entry: entry) {
                TitleValueLayout {
                    Text(entry?.title ?? "")
                        .font(.octoBody)
                        .foregroundStyle(OctoColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .layoutValue(key: RowShare.self, value: 1)
                    Text(value)
                        .font(.octoBodySmall)
                        .foregroundStyle(OctoColor.textSecondary)
                        .multilineTextAlignment(.trailing)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .layoutValue(key: RowShare.self, value: 0.8)
                    Image(systemName: SettingsIcon.chevron)
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 18, height: 18)
                        .foregroundStyle(OctoColor.textMuted)
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(SettingsRowPress())
        .accessibilityLabel(entry?.title ?? "")
        .accessibilityValue(value)
        .glassPopover(isPresented: $isPresented, content: card)
    }
}

/// Speed and pitch, kept for every song: a slider from half to double speed that settles on the
/// common speeds, whether voices keep their pitch, and a pitch shift. Every change is heard at once.
struct PaceCard: View {
    @State private var settings = AppSettings.shared

    var body: some View {
        let prefs = settings.player
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Speed").font(.octoBody).foregroundStyle(OctoColor.textPrimary).frame(maxWidth: .infinity, alignment: .leading)
                if !prefs.paceIsDefault {
                    Button("Reset") { settings.resetPace() }
                        .buttonStyle(.glass)
                        .font(.octoBodySmall)
                }
            }
            .frame(height: 48)
            Text(Pace.speedLabel(prefs.speed))
                .font(.octoDisplay.monospacedDigit())
                .tracking(-0.5)
                .foregroundStyle(OctoColor.textPrimary)
                .padding(.top, 8)
            GlowSlider(fraction: Double(Pace.speedFraction(prefs.speed)), label: "Playback speed",
                       valueText: Pace.speedLabel(prefs.speed), step: 0.05 / 1.5) { fraction in
                let picked = Pace.speedAt(Float(fraction))
                if picked != prefs.speed { settings.setSpeed(picked) }
            }
            DetentLabels(speed: prefs.speed) { settings.setSpeed($0) }

            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Keep pitch").font(.octoBodySmall).foregroundStyle(OctoColor.textPrimary)
                    Text(prefs.keepPitch ? "Voices sound as usual at any speed." : "Pitch rises and falls with the speed, like a record.")
                        .font(.octoCaption)
                        .foregroundStyle(OctoColor.textMuted)
                }
                .padding(.trailing, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                Toggle("Keep pitch", isOn: Binding(get: { prefs.keepPitch }, set: { settings.setKeepPitch($0) }))
                    .labelsHidden()
                    .tint(OctoColor.accent)
            }
            .padding(.vertical, 4)
            .padding(.top, 16)

            HStack {
                Text("Pitch").font(.octoBodySmall).foregroundStyle(OctoColor.textPrimary).frame(maxWidth: .infinity, alignment: .leading)
                Text(Pace.semitonesLabel(prefs.pitchSemitones))
                    .font(.octoBodySmall.monospacedDigit())
                    .foregroundStyle(prefs.pitchSemitones == 0 ? OctoColor.textMuted : OctoColor.textPrimary)
            }
            .padding(.top, 12)
            GlowSlider(fraction: Double(Pace.semitonesFraction(prefs.pitchSemitones)), label: "Pitch",
                       valueText: Pace.semitonesLabel(prefs.pitchSemitones), step: 1.0 / 12) { fraction in
                let picked = Pace.semitonesAt(Float(fraction))
                if picked != prefs.pitchSemitones { settings.setPitchSemitones(picked) }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 18)
    }
}

/// The common speeds under the slider, each where it falls on the line. A tap goes straight to one.
private struct DetentLabels: View {
    let speed: Float
    let pick: (Float) -> Void

    var body: some View {
        GeometryReader { box in
            ForEach(Pace.speedDetents, id: \.self) { detent in
                let label = Pace.speedLabel(detent)
                Button { pick(detent) } label: {
                    Text(label)
                        .font(.octoCaption.monospacedDigit())
                        .foregroundStyle(detent == speed ? OctoColor.textPrimary : OctoColor.textMuted)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .fixedSize()
                }
                .buttonStyle(.plain)
                .position(x: center(detent, width: box.size.width, label: label), y: box.size.height / 2)
            }
        }
        .frame(height: 24)
    }

    /// Centered where the speed falls on the line, kept inside the width.
    private func center(_ detent: Float, width: CGFloat, label: String) -> CGFloat {
        let half = CGFloat(label.count) * 3.6 + 6
        let x = CGFloat(Pace.speedFraction(detent)) * width
        return min(max(x, half), width - half)
    }
}
