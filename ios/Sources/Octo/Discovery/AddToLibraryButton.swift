import OctoKit
import SwiftUI

/// Where a heart would be for a song not in the library: a plus that asks the server to download
/// the song into the library (the download arrow is kept for saving to the phone). A ring around
/// the plus shows the song on its way and turns into a check once it is in the library. A failed
/// one shows an alert: a tap tries again, a long press says why. A family member whose songs are
/// saved rather than added gets a heart that saves the song instead.
struct AddToLibraryButton: View {
    let song: Song
    var size: CGFloat = 44
    var iconSize: CGFloat = 24
    /// The color of its plus and heart: white, or the player's dark words over a light background.
    var ink: Color = .white

    var body: some View {
        AddButton(song: song, size: size, iconSize: iconSize, ink: ink)
    }
}

private struct AddButton: View {
    let song: Song
    let size: CGFloat
    let iconSize: CGFloat
    let ink: Color
    @Environment(\.titleIcons) private var titleIcons
    @Environment(Downloads.self) private var downloads
    @Environment(Router.self) private var router
    @Environment(Accounts.self) private var accounts
    @Environment(\.octoReduceMotion) private var calm
    @State private var release: (@Sendable () -> Void)?

    var body: some View {
        if accounts.family.outside.addLabel != nil {
            saveHeart
        } else {
            addButton
        }
    }

    /// How strongly the plus and the empty heart show: the player's title row's quiet step, else
    /// 60%.
    private var quiet: Double { titleIcons?.alpha ?? 0.6 }

    /// For a family member whose songs are saved rather than added: a heart that saves the song or
    /// takes it off Saved.
    private var saveHeart: some View {
        let id = song.id.hasPrefix("find:") ? song.id : findId(song.id)
        let saved = accounts.family.isSaved(id)
        return Button { accounts.family.toggleSaved(id, title: song.title) } label: {
            IconView(saved ? .liked : .like, size: iconSize, color: saved ? ink : ink.opacity(quiet))
                .iconGlow(saved)
                .frame(width: size, height: size)
                .contentShape(Rectangle())
        }
        .buttonStyle(NoPress())
        .accessibilityLabel("Save")
        .accessibilityValue(saved ? "Saved" : "Not saved")
    }

    @ViewBuilder
    private var addButton: some View {
        let phase = downloads.phase(song.id)
        let onItsWay = phase.state == .requested
        let follows = onItsWay && downloads.keepsLog
        let failed = isFailed(phase)
        let enabled = phase == .none || failed || follows
        Button {
            if follows {
                router.showServerDownloads(songId: song.id)
            } else {
                ask()
            }
        } label: {
            ZStack {
                switch phase {
                case .none:
                    Image(systemName: "plus")
                        .font(.system(size: iconSize * 0.84, weight: .regular))
                        .foregroundStyle(ink.opacity(quiet))
                case .failed:
                    DownloadAlert().frame(width: iconSize, height: iconSize)
                default:
                    DownloadRing(phase: phase, calm: calm).frame(width: iconSize, height: iconSize)
                }
            }
            .frame(width: size, height: size)
            .contentShape(Rectangle())
        }
        .buttonStyle(NoPress())
        .disabled(!enabled)
        .id(song.id)
        // Only a failed one has a long press: it says why, in place of the tap.
        .highPriorityGesture(LongPressGesture().onEnded { _ in explain() }, including: failed ? .all : .subviews)
        .accessibilityLabel("Add to your library")
        .accessibilityValue(phase.spoken)
        .accessibilityActions {
            if failed {
                Button("Try again") { ask() }
                Button("Why") { explain() }
            } else if follows {
                Button("Follow it") { router.showServerDownloads(songId: song.id) }
            }
        }
        .onAppear { release = downloads.showing(song.id) }
        .onDisappear {
            release?()
            release = nil
        }
        .onChange(of: song.id) { _, id in
            release?()
            release = downloads.showing(id)
        }
    }

    private func ask() {
        let phase = downloads.phase(song.id)
        guard phase == .none || isFailed(phase) else { return }
        Task { _ = await downloads.request(song) }
    }

    private func explain() {
        if case .failed(let reason) = downloads.phase(song.id) { router.show("Could not download: \(reason)") }
    }

    private func isFailed(_ phase: DownloadPhase) -> Bool {
        if case .failed = phase { return true }
        return false
    }
}

/// A button with no press look of its own.
struct NoPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label }
}

/// A song on its way into the library: a thin ring around a small plus, turning while it waits,
/// filling as it downloads, full and pulsing while the song is added, then a check once it is in
/// the library. With reduced motion nothing turns, pulses or draws in; only the states change.
struct DownloadRing: View {
    let phase: DownloadPhase
    let calm: Bool

    /// The fill never goes back, even when an answer does.
    @State private var fillFrom = 0.0
    @State private var fillTo = 0.0
    @State private var fillAt = Date.distantPast
    /// When the song arrived while shown; nil when it was already in, or is not.
    @State private var doneAt: Date?
    @State private var doneFirst: Bool?
    @State private var tick = 0

    private static let turnSeconds = 1.6
    private static let fillSeconds = 1.2
    private static let pulseSeconds = 0.9
    private static let drawSeconds = 0.3
    private static let glowRise = 0.3
    private static let glowHold = 0.5
    private static let glowFade = 0.7

    private var waiting: Bool {
        if phase == .queued { return true }
        if case .downloading(nil) = phase { return true }
        return false
    }

    var body: some View {
        let moving = !calm && (waiting || phase == .adding)
        let settling = Date() < settledAt
        TimelineView(.animation(paused: !(moving || settling))) { context in
            Canvas { canvas, size in draw(canvas, size, at: context.date) }
        }
        .onAppear {
            if doneFirst == nil {
                doneFirst = phase == .done
                if phase == .done { fillTo = 1; fillFrom = 1 }
            }
            fill(animated: false)
        }
        .onChange(of: phase) { old, new in
            fill(animated: !calm)
            if new == .done, old != .done {
                doneAt = calm ? nil : Date()
            } else if new != .done {
                doneAt = nil
            }
            tick += 1
        }
        .task(id: tick) {
            let wait = settledAt.timeIntervalSinceNow
            if wait > 0 {
                try? await Task.sleep(for: .seconds(wait + 0.05))
                tick += 1
            }
        }
    }

    /// When every tween in flight has finished.
    private var settledAt: Date {
        let fillEnd = fillAt.addingTimeInterval(Self.fillSeconds)
        let doneEnd = doneAt?.addingTimeInterval(Self.glowRise + Self.glowHold + Self.glowFade) ?? .distantPast
        return max(fillEnd, doneEnd)
    }

    private func fill(animated: Bool) {
        let target: Double = switch phase {
        case .adding, .done: 1
        case .downloading(let progress): progress ?? 0
        default: 0
        }
        let current = fillValue(at: Date())
        let goal = max(target, fillTo)
        guard goal != fillTo else { return }
        if animated {
            fillFrom = current
            fillAt = Date()
        } else {
            fillFrom = goal
            fillAt = .distantPast
        }
        fillTo = goal
    }

    private func fillValue(at date: Date) -> Double {
        let t = date.timeIntervalSince(fillAt) / Self.fillSeconds
        if t >= 1 { return fillTo }
        return fillFrom + (fillTo - fillFrom) * Easing.linearOutSlowIn(max(0, t))
    }

    private func draw(_ canvas: GraphicsContext, _ size: CGSize, at date: Date) {
        let stroke: CGFloat = 2
        let side = min(size.width, size.height)
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = side / 2 - stroke / 2
        let t = date.timeIntervalSinceReferenceDate

        // How far the check has drawn in, and how bright its glow is.
        var morph = 0.0
        var glow = 0.0
        if phase == .done {
            if let doneAt {
                let since = date.timeIntervalSince(doneAt)
                morph = Easing.fastOutSlowIn(min(1, max(0, since / Self.drawSeconds)))
                if since < Self.glowRise {
                    glow = Easing.fastOutSlowIn(since / Self.glowRise)
                } else if since < Self.glowRise + Self.glowHold {
                    glow = 1
                } else {
                    glow = 1 - Easing.fastOutSlowIn(min(1, (since - Self.glowRise - Self.glowHold) / Self.glowFade))
                }
            } else {
                morph = 1
            }
        }

        let fade = 1 - morph
        if fade > 0 {
            let ring = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
            canvas.stroke(ring, with: .color(.white.opacity(0.2 * fade)), lineWidth: stroke)

            var arc = Path()
            var alpha = 1.0
            if waiting {
                let turn = calm ? 0 : (t.truncatingRemainder(dividingBy: Self.turnSeconds) / Self.turnSeconds) * 360
                arc.addArc(center: center, radius: radius, startAngle: .degrees(turn - 90), endAngle: .degrees(turn), clockwise: false)
            } else {
                let fill = fillValue(at: date)
                if fill > 0 {
                    arc.addArc(center: center, radius: radius, startAngle: .degrees(-90), endAngle: .degrees(-90 + 360 * fill), clockwise: false)
                }
                if phase == .adding, !calm {
                    var p = t.truncatingRemainder(dividingBy: Self.pulseSeconds * 2) / Self.pulseSeconds
                    if p > 1 { p = 2 - p }
                    alpha = 1 - 0.55 * Easing.fastOutSlowIn(p)
                }
            }
            canvas.stroke(arc, with: .color(.white.opacity(fade * alpha)), style: StrokeStyle(lineWidth: stroke, lineCap: .round))

            let arm = side * 0.18
            var plus = Path()
            plus.move(to: CGPoint(x: center.x - arm, y: center.y))
            plus.addLine(to: CGPoint(x: center.x + arm, y: center.y))
            plus.move(to: CGPoint(x: center.x, y: center.y - arm))
            plus.addLine(to: CGPoint(x: center.x, y: center.y + arm))
            canvas.stroke(plus, with: .color(.white.opacity(fade)), style: StrokeStyle(lineWidth: stroke, lineCap: .round))
        }

        if morph > 0 {
            var check = Path()
            check.move(to: CGPoint(x: size.width * 0.24, y: size.height * 0.52))
            check.addLine(to: CGPoint(x: size.width * 0.42, y: size.height * 0.70))
            check.addLine(to: CGPoint(x: size.width * 0.78, y: size.height * 0.33))
            let drawn = check.trimmedPath(from: 0, to: morph)
            let style = StrokeStyle(lineWidth: stroke, lineCap: .round, lineJoin: .round)
            if glow > 0 {
                var wide = canvas
                wide.addFilter(.blur(radius: 10))
                wide.opacity = 0.6 * glow
                wide.stroke(drawn, with: .color(.white), style: style)
                var near = canvas
                near.addFilter(.blur(radius: 3))
                near.opacity = 0.7 * glow
                near.stroke(drawn, with: .color(.white), style: style)
            }
            canvas.stroke(drawn, with: .color(.white), style: style)
        }
    }
}

/// A download that failed: a white circle with an exclamation mark.
struct DownloadAlert: View {
    var body: some View {
        Canvas { canvas, size in
            let stroke: CGFloat = 2
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) * 0.42 - stroke / 2
            canvas.stroke(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
                          with: .color(.white), lineWidth: stroke)
            var bar = Path()
            bar.move(to: CGPoint(x: center.x, y: center.y - radius * 0.5))
            bar.addLine(to: CGPoint(x: center.x, y: center.y + radius * 0.1))
            canvas.stroke(bar, with: .color(.white), style: StrokeStyle(lineWidth: stroke, lineCap: .round))
            let dot = stroke * 0.7
            canvas.fill(Path(ellipseIn: CGRect(x: center.x - dot, y: center.y + radius * 0.48 - dot, width: dot * 2, height: dot * 2)),
                        with: .color(.white))
        }
    }
}
