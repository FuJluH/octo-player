import Observation
import OctoKit
import SwiftUI

/// The time card's two pages.
enum TimePage: Equatable { case sleep, speed }

/// The sleep timer as the player shows it, read from the player's own timer. A stop set from the
/// queue for one song further down is named by that song.
@MainActor
@Observable
final class PlayerSleep {
    static let shared = PlayerSleep()

    /// The song the music stops after, when the timer was set for it from the queue.
    private(set) var afterTitle: String?
    @ObservationIgnored private var afterSongs: Int?

    func state(_ player: Player, at now: Date = Date()) -> PlayerRule.Sleep {
        switch player.sleep {
        case nil:
            return .off
        case .at(let date):
            return .counting(remainingMs: max(0, Int((date.timeIntervalSince(now) * 1000).rounded(.up))))
        case .afterSongs(let count):
            if let afterTitle, afterSongs != nil, count > 1 { return .afterSong(title: afterTitle) }
            return count <= 1 ? .endOfSong : .songs(count)
        }
    }

    /// Counts down from now.
    func start(minutes: Int, _ player: Player) {
        clearNote()
        player.setSleep(.at(Date().addingTimeInterval(TimeInterval(minutes * 60))))
    }

    /// Stops after this many songs end, the one playing included.
    func stopAfter(songs: Int, _ player: Player) {
        clearNote()
        player.setSleep(.afterSongs(songs))
    }

    /// Stops after the song `ahead` places after the one playing, named `title`.
    func stopAfter(ahead: Int, title: String, _ player: Player) {
        if ahead <= 0 {
            stopAfter(songs: 1, player)
            return
        }
        afterTitle = title
        afterSongs = ahead + 1
        player.setSleep(.afterSongs(ahead + 1))
    }

    /// More time on a countdown.
    func add(minutes: Int, _ player: Player) {
        guard case .at(let date) = player.sleep else { return }
        player.setSleep(.at(date.addingTimeInterval(TimeInterval(minutes * 60))))
    }

    func cancel(_ player: Player) {
        clearNote()
        player.setSleep(nil)
    }

    private func clearNote() {
        afterTitle = nil
        afterSongs = nil
    }
}

/// The sleep timer and the speed, one glass card of two pages. Opened from the sleep button it
/// starts on the timer, with the speed a page further; opened from the speed mark it starts on
/// the speed, with no way back.
struct TimeCard: View {
    let pages: PopupPages<TimePage>
    let dismiss: () -> Void

    var body: some View {
        PopupPager(pages: pages) { page, canGoBack in
            switch page {
            case .sleep: SleepPage(dismiss: dismiss) { pages.open(.speed) }
            case .speed: SpeedPage(back: canGoBack ? { pages.back() } : nil)
            }
        }
    }
}

// MARK: Sleep timer

private struct SleepPage: View {
    let dismiss: () -> Void
    let openSpeed: () -> Void
    @Environment(Player.self) private var player
    @State private var sleep = PlayerSleep.shared
    @State private var settings = AppSettings.shared
    @State private var custom = false
    @State private var minutes = ""

    private static let lengths = [5, 15, 30, 45, 60]
    private static let extensions = [5, 10]
    private static let songCounts = [1, 2, 3, 5]
    private static let longest = 720

    var body: some View {
        let state = sleep.state(player)
        VStack(alignment: .leading, spacing: 0) {
            Text("Sleep timer").font(.octoBody).foregroundStyle(.white)
                .accessibilityAddTraits(.isHeader)
            if state != .off {
                HStack(spacing: 12) {
                    if case .counting = state {
                        CountdownClock()
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text(PlayerRule.sleepSummary(state))
                            .font(.octoBody)
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    GlazeButton("Cancel") {
                        sleep.cancel(player)
                        dismiss()
                    }
                }
                .padding(.top, 12)
                if case .counting = state {
                    HStack(spacing: 10) {
                        ForEach(Self.extensions, id: \.self) { more in
                            GlazeButton("+\(more) min") { sleep.add(minutes: more, player) }
                        }
                    }
                    .padding(.top, 12)
                }
            }
            FlowRow(spacing: 10) {
                ForEach(Self.lengths, id: \.self) { length in
                    GlazeButton(length == 60 ? "1 hour" : "\(length) min") {
                        sleep.start(minutes: length, player)
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
                ForEach(Self.songCounts, id: \.self) { count in
                    GlazeButton(count == 1 ? "This song" : "\(count) songs") {
                        sleep.stopAfter(songs: count, player)
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
        guard let value = Int(minutes), (1...Self.longest).contains(value) else { return nil }
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
        sleep.start(minutes: chosen, player)
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

/// The time left on a countdown, rounded up to the second: a second a tick, and ten ticks a
/// second over the last 30 seconds.
private struct CountdownClock: View {
    @Environment(Player.self) private var player

    var body: some View {
        let near = PlayerSleep.shared.state(player).remaining.map { $0 <= 30_000 } ?? false
        TimelineView(.periodic(from: .now, by: near ? 0.1 : 1)) { time in
            let left = PlayerSleep.shared.state(player, at: time.date).remaining ?? 0
            Text(asClock((left + 999) / 1000))
                .font(.octo(32, .black).monospacedDigit())
                .tracking(octoDisplayTracking)
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }
}

extension PlayerRule.Sleep {
    /// The time left on a countdown, in milliseconds.
    var remaining: Int? {
        if case .counting(let ms) = self { return ms }
        return nil
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
                GlassMenuBack(title: "Sleep timer", onBack: back).padding(6)
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
