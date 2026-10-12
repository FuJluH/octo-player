import OctoKit
import SwiftUI

/// A control pressed in: it shrinks to `scale` over the press time, after the motion scale.
struct PressScale: ButtonStyle {
    var scale = OctoPress.scale
    @Environment(\.motionScale) private var motion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? motion.scale(scale) : 1)
            .animation(.octoTween(OctoDuration.press, scale: motion), value: configuration.isPressed)
    }
}

/// A large surface held down, like a row or a card: it gives a little, to 0.985, over half the
/// squeeze time, and springs back.
struct SqueezeStyle: ButtonStyle {
    @Environment(\.motionScale) private var motion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? motion.scale(OctoPress.largeScale) : 1)
            .animation(.octoTween(OctoDuration.squeeze / 2, scale: motion), value: configuration.isPressed)
    }
}

/// A button's words, with an optional icon 8 points before them. While `loading` the words
/// keep their room, so the width never jumps, and a spinner turns in their place.
struct ButtonLabel: View {
    let text: String
    var icon: OctoIcon?
    var size: ButtonSize = .large
    var loading = false
    var color: Color = .white

    var body: some View {
        ZStack {
            HStack(spacing: 8) {
                if let icon { IconView(icon, size: CGFloat(size.iconSize), color: color) }
                Text(text)
                    .font(.octo(CGFloat(size.fontSize), .semibold, .footnote))
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .opacity(loading ? 0 : 1)
            if loading { Spinner(size: CGFloat(size.iconSize), color: color) }
        }
        .padding(.horizontal, CGFloat(size.padding))
    }
}

/// The filled button: a glass capsule in the accent's darker fill, white words. Large by
/// default (50 tall, 40 dense). Disabled it shows at half strength and cannot be tapped; it
/// cannot be tapped while loading either. `bright` fills it with the accent itself, dark words
/// on it, for the one main button of a sheet.
struct AccentButton: View {
    let text: String
    var icon: OctoIcon?
    var size: ButtonSize = .large
    var dense = false
    var tonal = false
    var bright = false
    var enabled = true
    var loading = false
    var fillWidth = false
    let action: () -> Void

    init(_ text: String, icon: OctoIcon? = nil, size: ButtonSize = .large, dense: Bool = false, tonal: Bool = false,
         bright: Bool = false, enabled: Bool = true, loading: Bool = false, fillWidth: Bool = false, action: @escaping () -> Void) {
        self.text = text
        self.icon = icon
        self.size = size
        self.dense = dense
        self.tonal = tonal
        self.bright = bright
        self.enabled = enabled
        self.loading = loading
        self.fillWidth = fillWidth
        self.action = action
    }

    var body: some View {
        let fill = bright ? OctoPalette.accent : tonal ? OctoPalette.accentTonal : OctoPalette.accentFill
        Button(action: action) {
            ButtonLabel(text: text, icon: icon, size: size, loading: loading, color: Color(contentColorFor(fill)))
                .frame(maxWidth: fillWidth ? .infinity : nil)
                .frame(height: CGFloat(dense ? size.dense : size.height))
                .contentShape(Capsule())
        }
        .buttonStyle(PressScale())
        .octoGlass(Capsule(), film: Color(fill), interactive: true)
        .opacity(enabled ? 1 : OctoInkColor.disabled)
        .disabled(!enabled || loading)
    }
}

/// The quieter button: lit glass with white words. `tint` lays a fifth of a color into its film.
struct GlazeButton: View {
    let text: String
    var icon: OctoIcon?
    var size: ButtonSize = .large
    var dense = false
    var tint: Color?
    var enabled = true
    var loading = false
    var fillWidth = false
    let action: () -> Void

    init(_ text: String, icon: OctoIcon? = nil, size: ButtonSize = .large, dense: Bool = false, tint: Color? = nil,
         enabled: Bool = true, loading: Bool = false, fillWidth: Bool = false, action: @escaping () -> Void) {
        self.text = text
        self.icon = icon
        self.size = size
        self.dense = dense
        self.tint = tint
        self.enabled = enabled
        self.loading = loading
        self.fillWidth = fillWidth
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            ButtonLabel(text: text, icon: icon, size: size, loading: loading)
                .frame(maxWidth: fillWidth ? .infinity : nil)
                .frame(height: CGFloat(dense ? size.dense : size.height))
                .contentShape(Capsule())
        }
        .buttonStyle(PressScale())
        .octoGlass(Capsule(), film: tint.map { $0.opacity(0.2) } ?? OctoColor.glazeFilm, interactive: true)
        .opacity(enabled ? 1 : OctoInkColor.disabled)
        .disabled(!enabled || loading)
    }
}

/// A small text button for a lesser action beside a title, like "See all" or "Clear all": no
/// border and no fill.
struct QuietButton: View {
    let text: String
    let action: () -> Void

    init(_ text: String, action: @escaping () -> Void) {
        self.text = text
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.octoLabel)
                .foregroundStyle(OctoColor.textSecondary)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .contentShape(Capsule())
        }
        .buttonStyle(QuietPress())
    }
}

/// The platform's press highlight, kept to a capsule.
private struct QuietPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Capsule().fill(Color.white.opacity(configuration.isPressed ? 0.10 : 0)))
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// A chrome button pressed: its glass pops to 1.05 while its icon dips to 0.96.
private struct ChromePress: ButtonStyle {
    var lone: Bool
    var active: Bool
    @Environment(\.motionScale) private var motion

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        configuration.label
            .scaleEffect(pressed ? motion.scale(OctoPress.scale) : 1)
            .background {
                if !lone {
                    if active {
                        GlazeSelected(shape: Capsule())
                    } else if pressed {
                        Circle().fill(Color.white.opacity(0.10))
                    }
                }
            }
            .scaleEffect(pressed && lone ? motion.scale(OctoPress.pop) : 1)
            .animation(.octoTween(OctoDuration.press, scale: motion), value: pressed)
    }
}

/// A round chrome button: 38 by 38 alone, 38 by 30 inside a group, with an 18 point icon.
/// Alone it wears its own glass and shadow; `active` adds the darker pill inside.
struct ChromeButton: View {
    let icon: OctoIcon
    let label: String
    var active = false
    var inGroup = false
    var accent: IconAccent?
    let action: () -> Void
    @State private var plays = 0

    init(_ icon: OctoIcon, label: String, active: Bool = false, inGroup: Bool = false, accent: IconAccent? = nil,
         action: @escaping () -> Void) {
        self.icon = icon
        self.label = label
        self.active = active
        self.inGroup = inGroup
        self.accent = accent
        self.action = action
    }

    var body: some View {
        Button {
            plays += 1
            action()
        } label: {
            IconView(icon, size: 18, color: .white)
                .iconAccent(accent, trigger: plays)
                .frame(width: inGroup ? 30 : 38, height: 38)
                .background {
                    if active && !inGroup { GlazeSelected(shape: Capsule()).padding(3) }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(ChromePress(lone: !inGroup, active: active && inGroup))
        .modifier(LoneChrome(lone: !inGroup))
        .accessibilityLabel(label)
    }
}

private struct LoneChrome: ViewModifier {
    let lone: Bool

    func body(content: Content) -> some View {
        if lone {
            content.octoGlass(Capsule(), interactive: true).chromeShadow()
        } else {
            content
        }
    }
}

/// A row of chrome buttons in one glass capsule, at least 38 tall, the buttons 4 points from its
/// ends and 4 apart.
struct ChromeGroup<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 4) { content }
            .padding(.horizontal, 4)
            .frame(minHeight: 38)
            .octoGlass(Capsule())
            .chromeShadow()
    }
}

/// A lone round control over content: floating glass, 56 points by default with a 22 point
/// icon (20 below 56). Pressed, the glass pops and the icon dips.
struct GlazedIconButton: View {
    let icon: OctoIcon
    let label: String
    var size: CGFloat = 56
    let action: () -> Void

    init(_ icon: OctoIcon, label: String, size: CGFloat = 56, action: @escaping () -> Void) {
        self.icon = icon
        self.label = label
        self.size = size
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            IconView(icon, size: size >= 56 ? 22 : 20, color: .white)
                .frame(width: size, height: size)
                .contentShape(Circle())
        }
        .buttonStyle(ChromePress(lone: true, active: false))
        .floatingGlass(Circle(), interactive: true)
        .accessibilityLabel(label)
    }
}

/// The turning arc: 270 degrees, once every 900 ms, its stroke 12% of its size.
struct Spinner: View {
    var size: CGFloat = 18
    var color: Color = .white

    var body: some View {
        TimelineView(.animation) { time in
            let turn = time.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 0.9) / 0.9
            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(color, style: StrokeStyle(lineWidth: size * 0.12, lineCap: .round))
                .rotationEffect(.degrees(turn * 360))
                .padding(size * 0.06)
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Loading")
    }
}

/// The waiting spinner for a page loading: an accent arc that grows and shrinks as it turns.
struct LoadingSpinner: View {
    var size: CGFloat = 28
    var color: Color = OctoColor.accent

    var body: some View {
        TimelineView(.animation) { time in
            let t = time.date.timeIntervalSinceReferenceDate
            // One grow-and-shrink every 1.333 seconds, the whole arc turning meanwhile.
            let cycle = t.truncatingRemainder(dividingBy: 1.333) / 1.333
            let grow = OctoEasing.standard.at(min(1, cycle * 2))
            let shrink = OctoEasing.standard.at(max(0, cycle * 2 - 1))
            let head = 0.05 + 0.70 * grow
            let tail = 0.70 * shrink
            Circle()
                .trim(from: tail, to: max(tail + 0.02, head))
                .stroke(color, style: StrokeStyle(lineWidth: 4 * size / 40, lineCap: .round))
                .rotationEffect(.degrees(t.truncatingRemainder(dividingBy: 1.568) / 1.568 * 360 - 90))
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Loading")
    }
}

extension View {
    /// Plays an icon's small gesture each time `trigger` changes: 300 ms, strongest 45% of the
    /// way through, still with Reduce motion.
    func iconAccent<T: Equatable>(_ accent: IconAccent?, trigger: T) -> some View {
        modifier(IconAccentPlayer(accent: accent, trigger: trigger))
    }

    /// A glow behind an icon while `lit`: a wide soft copy and a close one, fading in and out
    /// over 300 ms.
    func iconGlow(_ lit: Bool, color: Color = .white) -> some View {
        modifier(IconGlow(lit: lit, color: color))
    }
}

private struct IconAccentPlayer<T: Equatable>: ViewModifier {
    let accent: IconAccent?
    let trigger: T
    @State private var started: Date?
    @Environment(\.motionScale) private var motion

    func body(content: Content) -> some View {
        if let accent {
            TimelineView(.animation(paused: started == nil)) { time in
                let length = max(0.001, motion.seconds(accentDuration))
                let progress = started.map { time.date.timeIntervalSince($0) / length } ?? 1
                let pose = accentPose(accent, progress, distance: motion.distance)
                content
                    .scaleEffect(pose.scale)
                    .rotationEffect(.degrees(pose.rotation))
                    .offset(x: pose.dx, y: pose.dy)
            }
            .onChange(of: trigger) {
                started = Date()
                Task {
                    try? await Task.sleep(for: .seconds(motion.seconds(accentDuration) + 0.05))
                    started = nil
                }
            }
        } else {
            content
        }
    }
}

private struct IconGlow: ViewModifier {
    let lit: Bool
    let color: Color
    @Environment(\.motionScale) private var motion

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    content.blur(radius: 10).opacity(0.6)
                    content.blur(radius: 3).opacity(0.7)
                }
                .foregroundStyle(color)
                .opacity(lit ? 1 : 0)
                .animation(.octoTween(OctoDuration.neutral, scale: motion), value: lit)
                .allowsHitTesting(false)
            }
    }
}
