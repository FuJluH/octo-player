import OctoKit
import SwiftUI
import UIKit

/// The time card's two pages.
enum TimePage: Equatable { case sleep, speed }

/// The sleep timer and the speed, one card of two pages in a popover. Opened from the sleep
/// button it starts on the timer, with the speed a page further; opened from the speed mark it
/// starts on the speed, with no way back. A new page slides in from the side it is going; with
/// Reduce motion it fades.
struct TimeCard: View {
    let start: TimePage
    let dismiss: () -> Void
    @State private var page: TimePage
    @State private var deeper = true
    @State private var height: CGFloat = 0
    @Environment(\.octoReduceMotion) private var calm

    init(start: TimePage, opening: TimePage? = nil, dismiss: @escaping () -> Void) {
        self.start = start
        self.dismiss = dismiss
        _page = State(initialValue: opening ?? start)
    }

    /// The card is at most 60% of the screen's height; a taller page scrolls inside it.
    private var room: CGFloat {
        let screen = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.screen.bounds.height }.first ?? 800
        return screen * 0.6
    }

    var body: some View {
        let room = room
        ScrollView(.vertical) {
            ZStack(alignment: .topLeading) {
                switch page {
                case .sleep:
                    SleepPage(dismiss: dismiss) { go(.speed, deeper: true) }
                        .transition(slide)
                case .speed:
                    SpeedPage(back: start == .sleep ? { go(.sleep, deeper: false) } : nil)
                        .transition(slide)
                }
            }
            .clipped()
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        }
        .scrollDisabled(height <= room)
        .scrollBounceBehavior(.basedOnSize)
        .frame(width: 320, height: height > 0 ? min(height, room) : nil)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sleep timer and speed")
        .accessibilityAction(.escape) { back() }
    }

    /// Back from the speed, opened from the timer, goes to the timer; otherwise the card closes.
    private func back() {
        if page == .speed && start == .sleep {
            go(.sleep, deeper: false)
        } else {
            dismiss()
        }
    }

    private var slide: AnyTransition {
        calm ? .opacity : .push(from: deeper ? .trailing : .leading)
    }

    private func go(_ next: TimePage, deeper: Bool) {
        self.deeper = deeper
        withAnimation(calm ? .easeOut(duration: 0.15) : .octo(OctoSprings.calm)) { page = next }
    }
}

// MARK: Sleep timer

private struct SleepPage: View {
    let dismiss: () -> Void
    let openSpeed: () -> Void
    @Environment(Player.self) private var player
    @State private var settings = AppSettings.shared
    @State private var custom = false
    @State private var minutes = ""

    var body: some View {
        let state = player.sleepState
        VStack(alignment: .leading, spacing: 0) {
            Text("Sleep timer").font(.octoBody).foregroundStyle(.white)
                .accessibilityAddTraits(.isHeader)
            if state != .off {
                HStack(spacing: 12) {
                    if case .counting(let left) = state {
                        // The timer ticks on each whole second, and ten times a second over its last
                        // 30 seconds.
                        Text(asClock((left + 999) / 1000))
                            .font(.octo(32, .black).monospacedDigit())
                            .tracking(octoDisplayTracking)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text(sleepSummary(state))
                            .font(.octoBody)
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    GlazeButton("Cancel") {
                        player.cancelSleep()
                        dismiss()
                    }
                }
                .padding(.top, 12)
                if case .counting = state {
                    HStack(spacing: 10) {
                        ForEach(sleepExtensions, id: \.self) { more in
                            GlazeButton("+\(more) min") { player.extendSleep(minutes: more) }
                        }
                    }
                    .padding(.top, 12)
                }
            }
            FlowRow(spacing: 10) {
                ForEach(sleepMinutes, id: \.self) { length in
                    GlazeButton(length == 60 ? "1 hour" : "\(length) min") {
                        player.startSleep(minutes: length)
                        dismiss()
                    }
                }
                GlazeButton("Custom") { custom = true }
            }
            .padding(.top, 20)
            Text("Stop after")
                .font(.octoLabel)
                .foregroundStyle(OctoColor.accent)
                .padding(.top, 16)
            FlowRow(spacing: 10) {
                ForEach(sleepSongCounts, id: \.self) { count in
                    GlazeButton(count == 1 ? "This song" : "\(count) songs") {
                        player.sleepAfterSongs(count)
                        dismiss()
                    }
                }
            }
            .padding(.top, 10)
            if custom {
                customField.padding(.top, 16)
            }
            speedLine.padding(.top, 16)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 10)
        .frame(width: 320, alignment: .leading)
    }

    private var chosen: Int? {
        guard let value = Int(minutes), (1...maxSleepMinutes).contains(value) else { return nil }
        return value
    }

    private var customField: some View {
        HStack(spacing: 10) {
            GlassInput(placeholder: "Minutes, 1 to 720", text: $minutes, submitLabel: .done, onSubmit: startCustom,
                       leading: { EmptyView() }, trailing: { EmptyView() }, focusOnAppear: true)
                .keyboardType(.numbersAndPunctuation)
                .onChange(of: minutes) { _, typed in
                    let digits = String(typed.filter(\.isNumber).prefix(3))
                    if digits != typed { minutes = digits }
                }
            AccentButton("Start", enabled: chosen != nil, action: startCustom)
        }
    }

    private func startCustom() {
        guard let chosen else { return }
        player.startSleep(minutes: chosen)
        dismiss()
    }

    private var speedLine: some View {
        let speed = settings.player.speed
        return Button(action: openSpeed) {
            HStack(spacing: 0) {
                Text("Playback speed").font(.octo(14, .regular)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(Pace.speedLabel(speed))
                    .font(.octo(14, .regular).monospacedDigit())
                    .foregroundStyle(speed == 1 ? OctoColor.textMuted : .white)
                IconView(.chevron, size: 20, color: OctoColor.textMuted)
                    .padding(.leading, 6)
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPress())
    }
}

/// A full-width line that dims a little under the finger.
private struct RowPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                if configuration.isPressed { Rectangle().fill(Color.white.opacity(0.06)) }
            }
    }
}

// MARK: Speed and pitch

/// Speed and pitch: the speed large over its line, with the common speeds under it to jump to,
/// whether voices keep their pitch, and the pitch in semitones. Every change is heard at once and
/// kept for every song.
struct SpeedPage: View {
    let back: (() -> Void)?
    @State private var settings = AppSettings.shared

    private static let common: [Float] = [0.75, 1, 1.25, 1.5]

    var body: some View {
        let prefs = settings.player
        VStack(alignment: .leading, spacing: 0) {
            if let back {
                PopoverBack(title: "Sleep timer", onBack: back).padding(.top, 6)
                SoundHairline().padding(.horizontal, 14).padding(.vertical, 4)
            }
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    Text("Speed").font(.octoBody).foregroundStyle(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if prefs.speed != 1 || !prefs.keepPitch || prefs.pitchSemitones != 0 {
                        GlazeButton("Reset", dense: true) { settings.resetPace() }
                    }
                }
                .frame(height: 48)
                Text(Pace.speedLabel(prefs.speed))
                    .font(.octo(32, .black).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.top, 8)
                OctoSlider(value: Double(Pace.speedFraction(prefs.speed)), onChange: { fraction in
                    let speed = Pace.speedAt(Float(fraction))
                    if speed != settings.player.speed { settings.setSpeed(speed) }
                }, live: true, color: .white, trackColor: .white.opacity(0.24), valueLabel: { Pace.speedLabel(Pace.speedAt(Float($0))) })
                .accessibilityLabel("Playback speed")
                commonSpeeds(prefs.speed)
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Keep pitch").font(.octo(14, .regular)).foregroundStyle(.white)
                        Text(prefs.keepPitch ? "Voices sound as usual at any speed." : "Pitch rises and falls with the speed, like a record.")
                            .font(.octoCaption)
                            .foregroundStyle(OctoColor.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    OctoSwitch(isOn: Binding(get: { settings.player.keepPitch }, set: { settings.setKeepPitch($0) }), label: "Keep pitch")
                }
                .padding(.vertical, 4)
                .padding(.top, 16)
                HStack(spacing: 12) {
                    Text("Pitch").font(.octo(14, .regular)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(Pace.semitonesLabel(prefs.pitchSemitones))
                        .font(.octo(14, .regular).monospacedDigit())
                        .foregroundStyle(prefs.pitchSemitones == 0 ? OctoColor.textMuted : .white)
                }
                .padding(.top, 12)
                OctoSlider(value: Double(Pace.semitonesFraction(prefs.pitchSemitones)), onChange: { fraction in
                    let semitones = Pace.semitonesAt(Float(fraction))
                    if semitones != settings.player.pitchSemitones { settings.setPitchSemitones(semitones) }
                }, live: true, color: .white, trackColor: .white.opacity(0.24),
                valueLabel: { Pace.semitonesLabel(Pace.semitonesAt(Float($0))) })
                .accessibilityLabel("Pitch")
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 18)
        }
        .frame(width: 320, alignment: .leading)
    }

    /// The common speeds, each under its place on the line and kept inside it.
    private func commonSpeeds(_ speed: Float) -> some View {
        GeometryReader { box in
            let width = box.size.width
            ZStack(alignment: .topLeading) {
                ForEach(Self.common, id: \.self) { mark in
                    Button { settings.setSpeed(mark) } label: {
                        Text(Pace.speedLabel(mark))
                            .font(.octoCaption.monospacedDigit())
                            .foregroundStyle(mark == speed ? Color.white : OctoColor.textMuted)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .fixedSize()
                    }
                    .buttonStyle(NoPress())
                    .alignmentGuide(.leading) { label in
                        let center = width * CGFloat(Pace.speedFraction(mark))
                        let left = min(max(center - label.width / 2, 0), max(0, width - label.width))
                        return -left
                    }
                }
            }
        }
        .frame(height: 24)
    }
}
