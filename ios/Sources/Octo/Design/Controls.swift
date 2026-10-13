import OctoKit
import SwiftUI

/// Octo's on/off switch: the accent, glowing faintly, when on; a faint recessed pill when off.
/// The thumb slides on the default curve and squashes toward where it is going while held.
struct OctoSwitch: View {
    @Binding var isOn: Bool
    var size: SwitchSize = .standard
    var enabled = true
    var label: String?

    var body: some View {
        Button { isOn.toggle() } label: { EmptyView() }
            .buttonStyle(SwitchFace(isOn: isOn, size: size, enabled: enabled))
            .disabled(!enabled)
            .opacity(enabled ? 1 : OctoInkColor.disabled)
            .accessibilityLabel(label ?? "")
            .accessibilityValue(isOn ? "On" : "Off")
            .accessibilityAddTraits(.isToggle)
    }
}

/// The switch's track and thumb, the thumb stretching while the switch is held.
private struct SwitchFace: ButtonStyle {
    let isOn: Bool
    let size: SwitchSize
    let enabled: Bool
    @Environment(\.motionScale) private var motion

    func makeBody(configuration: Configuration) -> some View {
        let width = CGFloat(size.width)
        let height = CGFloat(size.height)
        let thumbSide = CGFloat(size.thumb)
        let on: Double = isOn ? 1 : 0
        let stretch: Double = configuration.isPressed && enabled ? motion.distance : 0
        let thumb = switchThumb(track: Double(width), thumb: Double(thumbSide), padding: SwitchSize.padding,
                                position: on, stretch: stretch)
        return ZStack(alignment: .leading) {
            Capsule().fill(Color.white.opacity(0.18)).opacity(1 - on)
            Capsule().fill(OctoColor.accent).opacity(on)
            // Recessed while off: a shade along the top inside edge.
            Capsule()
                .stroke(Color.black.opacity(0.22 * (1 - on)), lineWidth: 1)
                .blur(radius: shadowRadius(1.5))
                .offset(y: 0.5)
                .clipShape(Capsule())
            Capsule().strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
            Capsule()
                .fill(Color.white)
                .frame(width: CGFloat(thumb.width), height: thumbSide)
                .shadow(color: .black.opacity(0.18), radius: 0, y: 0.5)
                .shadow(color: .black.opacity(0.12), radius: 0, y: 1)
                .offset(x: CGFloat(thumb.x))
        }
        .frame(width: width, height: height)
        .background {
            Capsule().fill(OctoColor.accent).blur(radius: shadowRadius(5)).offset(y: 1).opacity(0.30 * on)
        }
        .shadow(color: .white.opacity(0.05), radius: 0, y: 0.5)
        .contentShape(Capsule())
        .animation(.octoTween(OctoDuration.card, scale: motion), value: isOn)
        .animation(.octoTween(OctoDuration.press, scale: motion), value: configuration.isPressed)
    }
}

/// A few choices in one glass tray, the chosen one in the darker pill that glides between them
/// over 300 ms on the Smooth curve. The pill is lit faintly in the accent from the side it came
/// from, and the tabs it passes flash a little accent. With Reduce motion it jumps.
struct GlazeTabs<Tab: View>: View {
    let count: Int
    let selected: Int
    let onSelect: (Int) -> Void
    var height: CGFloat = 40
    var enabled: (Int) -> Bool = { _ in true }
    @ViewBuilder let tab: (Int, Bool) -> Tab
    @Environment(\.motionScale) private var motion
    @State private var pill: Double = -1
    @State private var way: Double = 1
    @State private var moving = false

    var body: some View {
        GeometryReader { box in
            let cell = count > 0 ? (box.size.width - 8) / CGFloat(count) : 0
            ZStack(alignment: .leading) {
                PillLayer(pill: pill < 0 ? Double(selected) : pill, selected: selected, way: way, moving: moving,
                          cell: cell, count: count)
                HStack(spacing: 0) {
                    ForEach(0..<count, id: \.self) { index in
                        Button { if enabled(index) { onSelect(index) } } label: {
                            tab(index, index == selected)
                                .padding(.horizontal, 4)
                                .frame(width: cell, height: box.size.height - 8)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(index == selected ? [.isSelected, .isButton] : .isButton)
                    }
                }
            }
            .padding(4)
        }
        .frame(height: height)
        .background {
            // Recessed: a shade from the top inside edge, and a hairline of accent round the rim.
            Capsule().stroke(Color.black.opacity(0.15), lineWidth: 1.6).blur(radius: shadowRadius(2)).offset(y: 3).clipShape(Capsule())
        }
        .overlay { Capsule().strokeBorder(OctoColor.accent.opacity(0.25), lineWidth: 0.5) }
        .octoGlass(Capsule())
        .shadow(color: .black.opacity(0.20), radius: shadowRadius(10), y: 2)
        .onAppear { pill = Double(selected) }
        .onChange(of: selected) { old, new in
            way = new > old ? 1 : -1
            if motion.still {
                pill = Double(new)
                return
            }
            moving = true
            withAnimation(.octoTween(OctoDuration.neutral, OctoEasing.smooth, scale: motion)) {
                pill = Double(new)
            } completion: {
                moving = false
            }
        }
    }
}

/// The pill and the passing flashes, drawn from the pill's place as it animates.
private struct PillLayer: View, Animatable {
    var pill: Double
    let selected: Int
    let way: Double
    let moving: Bool
    let cell: CGFloat
    let count: Int

    nonisolated var animatableData: Double {
        get { pill }
        set { pill = newValue }
    }

    var body: some View {
        Canvas { context, size in
            guard cell > 0 else { return }
            let left = CGFloat(pill) * cell
            let rect = CGRect(x: left, y: 0, width: cell, height: size.height)
            let shape = Path(roundedRect: rect, cornerRadius: size.height / 2)
            context.fill(shape, with: .color(OctoColor.glazeSelected))
            let travel = min(1, max(0, abs(pill - Double(selected)) * 2))
            let lit = OctoColor.accent.opacity(0.10 + 0.12 * travel)
            let from = way > 0 ? left : left + cell
            let to = way > 0 ? left + cell * 0.7 : left + cell * 0.3
            context.fill(shape, with: .linearGradient(Gradient(colors: [lit, .clear]),
                                                     startPoint: CGPoint(x: from, y: 0), endPoint: CGPoint(x: to, y: 0)))
            guard moving else { return }
            for index in 0..<count {
                let tint = gearShiftTint(index, pill: pill, selected: selected)
                if tint > 0 {
                    let cellRect = CGRect(x: CGFloat(index) * cell, y: 0, width: cell, height: size.height)
                    context.fill(Path(roundedRect: cellRect, cornerRadius: size.height / 2), with: .color(OctoColor.accent.opacity(tint)))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// A few word choices in glass tabs filling the width: the chosen label in the accent, the
/// others white.
struct Segmented: View {
    let options: [String]
    @Binding var selected: Int

    var body: some View {
        GlazeTabs(count: options.count, selected: selected, onSelect: { selected = $0 }) { index, chosen in
            Text(options[index])
                .font(.octoLabel)
                .foregroundStyle(chosen ? OctoColor.accent : .white)
                .lineLimit(1)
                .animation(.octo(OctoSprings.state), value: chosen)
        }
        .frame(maxWidth: .infinity)
    }
}

/// A text field sunk into the surface: a dark inner shadow from the top left, a faint highlight
/// from the bottom right, both deeper while typing. Its accent fill strengthens from a tenth to
/// 15% while typing, and a thin accent ring fades in round it.
struct GlassInput<Leading: View, Trailing: View>: View {
    let placeholder: String
    @Binding var text: String
    var secure = false
    var submitLabel: SubmitLabel = .done
    var onSubmit: () -> Void = {}
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing
    /// Takes the focus, and so opens the keyboard, as it appears.
    var focusOnAppear = false
    /// Whether the field has the focus, kept in step both ways, so the field before it can hand
    /// the focus on.
    var focus: Binding<Bool>?
    @FocusState private var focused: Bool
    @Environment(\.motionScale) private var motion

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        let depth: Double = focused ? 1 : 0
        HStack(spacing: 8) {
            leading
            ZStack(alignment: .leading) {
                if text.isEmpty {
                    Text(placeholder).font(.octoBody).foregroundStyle(OctoColor.textMuted).lineLimit(1)
                        .accessibilityHidden(true)
                }
                Group {
                    if secure {
                        SecureField(placeholder, text: $text)
                    } else {
                        TextField(placeholder, text: $text)
                    }
                }
                .labelsHidden()
                .font(.octoBody)
                .foregroundStyle(.white)
                .tint(OctoColor.accent)
                .focused($focused)
                .submitLabel(submitLabel)
                .onSubmit(onSubmit)
                .textFieldStyle(.plain)
            }
            trailing
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .background(shape.fill(OctoColor.accent.opacity(0.10 + 0.05 * depth)))
        .overlay {
            // Sunk in: dark from the top left, light from the bottom right.
            ZStack {
                shape.stroke(Color.black.opacity(0.5 + 0.1 * depth), lineWidth: 4 + depth)
                    .blur(radius: shadowRadius(7 + 2 * depth))
                    .offset(x: 2 + depth / 2, y: 2 + depth / 2)
                shape.stroke(Color.white.opacity(0.10 + 0.05 * depth), lineWidth: 4 + depth)
                    .blur(radius: shadowRadius(7 + 2 * depth))
                    .offset(x: -2 - depth / 2, y: -2 - depth / 2)
            }
            .clipShape(shape)
            .allowsHitTesting(false)
        }
        .overlay { shape.strokeBorder(OctoColor.accent.opacity(0.10), lineWidth: 1) }
        .overlay {
            shape.inset(by: -0.75).stroke(OctoColor.accent.opacity(0.60), lineWidth: 1.5).opacity(depth)
                .allowsHitTesting(false)
        }
        .animation(.octoTween(OctoDuration.card, OctoEasing.overshoot, scale: motion), value: focused)
        .contentShape(shape)
        .onTapGesture { focused = true }
        .onAppear { if focusOnAppear { focused = true } }
        .onChange(of: focused) { _, now in if let focus, focus.wrappedValue != now { focus.wrappedValue = now } }
        .onChange(of: focus?.wrappedValue) { _, wanted in if let wanted, wanted != focused { focused = wanted } }
    }
}

extension GlassInput where Leading == EmptyView, Trailing == EmptyView {
    init(_ placeholder: String, text: Binding<String>, secure: Bool = false, submitLabel: SubmitLabel = .done,
         focus: Binding<Bool>? = nil, onSubmit: @escaping () -> Void = {}) {
        self.init(placeholder: placeholder, text: text, secure: secure, submitLabel: submitLabel, onSubmit: onSubmit,
                  leading: { EmptyView() }, trailing: { EmptyView() }, focus: focus)
    }
}

/// How a line slider is drawn: the glowing line for song progress and volume, or the jewel
/// settings slider.
enum SliderLook { case glow, jewel }

/// A line slider. Glow: the played part lit, thickening and showing a thumb while dragged.
/// Jewel: a recessed track, an accent fill, a white jewel thumb with an accent dot, a ring and a
/// glow while dragged, and the value in a bubble above. A tap seeks; a drag shows its own value
/// and sends it when the finger lifts, unless `live`; a drag taken away sends nothing. `steps`
/// snaps to that many steps. A drag that goes up or down first is not the line's: it sends
/// nothing and is handed to `passedDrag` when one is set.
struct OctoSlider: View {
    let value: Double
    let onChange: (Double) -> Void
    var look: SliderLook = .glow
    var live = false
    var color: Color = .white
    var trackColor: Color = .white.opacity(0.24)
    var fill: Color = OctoColor.accent
    var steps = 0
    var valueLabel: ((Double) -> String)?
    @State private var dragging = false
    @State private var dragValue = 0.0
    @State private var shown = 0.0
    @State private var line = 0.0
    @State private var glow = 0.0
    @State private var thumb = 0.0
    @State private var ring = 0.0
    @State private var bubble = 0.0
    /// The finger went up or down first: the line lets the drag go and sends nothing.
    @State private var passed = false
    @GestureState private var touching = false
    @Environment(\.motionScale) private var motion
    @Environment(\.passedDrag) private var passedDrag

    /// How far the finger moves before a drag is told from a tap, and its way decided.
    private static let slop: CGFloat = 8

    var body: some View {
        GeometryReader { box in
            let width = max(1, box.size.width)
            let current = dragging ? dragValue : (look == .jewel ? shown : min(1, max(0, value)))
            Group {
                switch look {
                case .glow:
                    GlowLine(fraction: current, line: line, glow: glow, color: color, trackColor: trackColor)
                case .jewel:
                    JewelLine(fraction: current, thumb: thumb, ring: ring, bubble: bubble, fill: fill, steps: steps,
                              label: valueLabel?(current))
                }
            }
            .frame(width: width, height: box.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($touching) { _, state, _ in state = true }
                    .onChanged { drag in
                        if passed {
                            passedDrag?.moved(drag.translation)
                            return
                        }
                        if !dragging {
                            switch dragAxis(drag.translation.width, drag.translation.height, slop: Self.slop) {
                            case .undecided: return
                            case .vertical:
                                passed = true
                                passedDrag?.moved(drag.translation)
                                return
                            case .horizontal: held(true)
                            }
                        }
                        let f = snapToSteps(drag.location.x / width, steps)
                        dragValue = f
                        if live { onChange(f) }
                    }
                    .onEnded { drag in
                        if passed {
                            passed = false
                            passedDrag?.ended(drag.translation, drag.velocity)
                            return
                        }
                        let f = snapToSteps(drag.location.x / width, steps)
                        held(false)
                        onChange(f)
                        shown = f
                    }
            )
        }
        .frame(height: 48)
        .onAppear { shown = min(1, max(0, value)) }
        .onChange(of: value) { _, new in
            if dragging { return }
            withAnimation(.linear(duration: motion.seconds(80))) { shown = min(1, max(0, new)) }
        }
        .onChange(of: touching) { _, now in
            // A drag taken away by something else sends nothing.
            guard !now else { return }
            if dragging { held(false) }
            if passed {
                passed = false
                passedDrag?.cancelled()
            }
        }
        .accessibilityElement()
        .accessibilityValue(valueLabel?(value) ?? "\(Int((value * 100).rounded())) percent")
        .accessibilityAdjustableAction { direction in
            let step = steps > 0 ? 1 / Double(steps) : 0.05
            switch direction {
            case .increment: onChange(min(1, value + step))
            case .decrement: onChange(max(0, value - step))
            @unknown default: break
            }
        }
    }

    private func held(_ on: Bool) {
        dragging = on
        let target: Double = on ? 1 : 0
        withAnimation(.octoSpring(0.5, 200)) { line = target }
        withAnimation(.octoSpring(1, 200)) { glow = target }
        withAnimation(.octoTween(OctoDuration.hover, scale: motion)) { thumb = target }
        withAnimation(.octoTween(OctoDuration.card, scale: motion)) { ring = target }
        withAnimation(.octoTween(OctoDuration.swap, scale: motion)) { bubble = target }
    }
}

/// The glowing line: 3.5 thick, 8 while held, with a thumb of radius 9 while held (`line`), and
/// three soft passes of glow that widen and brighten while held (`glow`).
private struct GlowLine: View, Animatable {
    let fraction: Double
    var line: Double
    var glow: Double
    let color: Color
    let trackColor: Color

    nonisolated var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(line, glow) }
        set {
            line = newValue.first
            glow = newValue.second
        }
    }

    var body: some View {
        Canvas { context, size in
            let y = size.height / 2
            let stroke = 3.5 + (8 - 3.5) * line
            // The ends sit in by half the thickest line, so the round caps are drawn whole.
            let cap: CGFloat = 4
            let start = cap
            let finish = max(cap, size.width - cap)
            let end = start + (finish - start) * fraction
            var track = Path()
            track.move(to: CGPoint(x: start, y: y))
            track.addLine(to: CGPoint(x: finish, y: y))
            context.stroke(track, with: .color(trackColor), style: StrokeStyle(lineWidth: stroke, lineCap: .round))
            guard fraction > 0 else { return }
            var lit = Path()
            lit.move(to: CGPoint(x: start, y: y))
            lit.addLine(to: CGPoint(x: end, y: y))
            // Glow radius 12 at rest and 24 held, in pixels; alpha 0.4 at rest and 0.8 held.
            let radius = (12 + 12 * glow) / 3
            let alpha = 0.4 + 0.4 * glow
            for spread in [2.5, 1.0, 0.3] {
                var pass = context
                pass.addFilter(.blur(radius: radius * spread))
                pass.stroke(lit, with: .color(color.opacity(alpha / 3)), style: StrokeStyle(lineWidth: stroke, lineCap: .round))
            }
            context.stroke(lit, with: .color(color), style: StrokeStyle(lineWidth: stroke, lineCap: .round))
            let thumb = 9 * max(0, line)
            if thumb > 0 {
                context.fill(Path(ellipseIn: CGRect(x: end - thumb, y: y - thumb, width: thumb * 2, height: thumb * 2)), with: .color(color))
            }
        }
    }
}

/// The jewel slider: the recessed track, the accent fill, ticks for its steps, the thumb, and
/// while dragged its ring, glow and value bubble.
private struct JewelLine: View, Animatable {
    let fraction: Double
    var thumb: Double
    var ring: Double
    var bubble: Double
    let fill: Color
    let steps: Int
    let label: String?

    nonisolated var animatableData: AnimatablePair<AnimatablePair<Double, Double>, Double> {
        get { AnimatablePair(AnimatablePair(thumb, ring), bubble) }
        set {
            thumb = newValue.first.first
            ring = newValue.first.second
            bubble = newValue.second
        }
    }

    var body: some View {
        Canvas { context, size in
            let y = size.height / 2
            let track: CGFloat = 4
            let radius = CGFloat(14 + 2 * thumb) / 2
            let start = radius
            let end = size.width - radius
            let x = start + (end - start) * fraction
            let top = y - track / 2
            let trackShape = Path(roundedRect: CGRect(x: 0, y: top, width: size.width, height: track), cornerRadius: track / 2)
            context.fill(trackShape, with: .linearGradient(Gradient(colors: [.white.opacity(0.10), .white.opacity(0.14)]),
                                                          startPoint: CGPoint(x: 0, y: top), endPoint: CGPoint(x: 0, y: top + track)))
            context.fill(Path(roundedRect: CGRect(x: 0, y: top, width: size.width, height: 1), cornerRadius: 0.5), with: .color(.black.opacity(0.25)))
            if x > 0 {
                context.fill(Path(roundedRect: CGRect(x: 0, y: top, width: x, height: track), cornerRadius: track / 2),
                             with: .linearGradient(Gradient(colors: [fill, fill.mix(with: .black, by: 0.22)]),
                                                   startPoint: CGPoint(x: 0, y: top), endPoint: CGPoint(x: 0, y: top + track)))
            }
            if (1...40).contains(steps) {
                for i in 1..<steps {
                    let tx = start + (end - start) * CGFloat(i) / CGFloat(steps)
                    let color: Color = tx <= x ? .black.opacity(0.30) : .white.opacity(0.30)
                    context.fill(Path(ellipseIn: CGRect(x: tx - 1, y: y - 1, width: 2, height: 2)), with: .color(color))
                }
            }
            if ring > 0 {
                let glow = radius + 18
                context.fill(Path(ellipseIn: CGRect(x: x - glow, y: y - glow, width: glow * 2, height: glow * 2)),
                             with: .radialGradient(Gradient(colors: [fill.opacity(0.35 * ring), .clear]), center: CGPoint(x: x, y: y),
                                                   startRadius: 0, endRadius: glow))
                let edge = radius + 2
                context.stroke(Path(ellipseIn: CGRect(x: x - edge, y: y - edge, width: edge * 2, height: edge * 2)),
                               with: .color(fill.opacity(0.45 * ring)), lineWidth: 4)
            }
            context.fill(Path(ellipseIn: CGRect(x: x - radius - 0.5, y: y + 1 - radius - 0.5, width: radius * 2 + 1, height: radius * 2 + 1)),
                         with: .color(.black.opacity(0.35)))
            context.fill(Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)),
                         with: .radialGradient(Gradient(colors: [.white, Color(hex: 0xE4E6E8)]),
                                               center: CGPoint(x: x - radius * 0.35, y: y - radius * 0.35), startRadius: 0, endRadius: radius * 1.6))
            let dot = radius * CGFloat(0.35 + 0.07 * thumb)
            context.fill(Path(ellipseIn: CGRect(x: x - dot, y: y - dot, width: dot * 2, height: dot * 2)), with: .color(fill))
            if bubble > 0, let label {
                let text = context.resolve(Text(label).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white))
                let measured = text.measure(in: CGSize(width: 200, height: 40))
                let w = measured.width + 12
                let h = measured.height + 6
                let arrow: CGFloat = 4
                let bottom = y - radius - 14 + arrow
                let left = min(max(0, x - w / 2), max(0, size.width - w))
                let shade = Color.black.opacity(0.85 * bubble)
                context.fill(Path(roundedRect: CGRect(x: left, y: bottom - arrow - h, width: w, height: h), cornerRadius: 8), with: .color(shade))
                var tip = Path()
                tip.move(to: CGPoint(x: x - arrow, y: bottom - arrow))
                tip.addLine(to: CGPoint(x: x + arrow, y: bottom - arrow))
                tip.addLine(to: CGPoint(x: x, y: bottom))
                tip.closeSubpath()
                context.fill(tip, with: .color(shade))
                var faded = context
                faded.opacity = bubble
                faded.draw(text, at: CGPoint(x: left + 6, y: bottom - arrow - h + 3), anchor: .topLeading)
            }
        }
    }
}

/// Where a drag a control lets go of goes on: an upright drag that starts on a line slider, for
/// the page around it to take (the player pulls down to close with it).
struct PassedDrag {
    let moved: @MainActor (CGSize) -> Void
    let ended: @MainActor (_ translation: CGSize, _ velocity: CGSize) -> Void
    let cancelled: @MainActor () -> Void
}

extension EnvironmentValues {
    @Entry var passedDrag: PassedDrag? = nil
}
