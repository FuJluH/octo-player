import OctoKit
import SwiftUI
import UIKit

/// The Sound page's own type and ink, beyond the shared ones.
enum SoundStyle {
    /// Buttons, tabs and quiet actions: 13.5 semibold.
    static let label = Font.system(size: 13.5, weight: .semibold)
    /// The accent button's fill: the accent taken nearly halfway to black.
    static var accentFill: Color { OctoColor.accent.mix(with: .black, by: 0.45) }
    /// The darker pill that marks the chosen item inside glass.
    static let pill = Color.black.opacity(0.72)
    /// The springs the sliders move on.
    static let bouncy = Animation.interpolatingSpring(mass: 1, stiffness: 200, damping: 14.142)
    static let settled = Animation.interpolatingSpring(mass: 1, stiffness: 200, damping: 28.284)

    /// A blur measured in screen pixels of a phone at three times scale, as a radius in points.
    static func pixelBlur(_ pixels: CGFloat) -> CGFloat { (pixels * 0.57735 + 0.5) / 3 }
}

// MARK: Surfaces

extension View {
    /// The solid card a settings group sits on: a step up from the page, with a faint rim, a
    /// light line along its top inside edge, a dark contour and a small shadow.
    func soundRaisedPanel(radius: CGFloat = 20) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return background {
            shape.fill(OctoColor.surfaceRaised)
                .overlay(shape.strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
                .overlay(shape.stroke(Color.white.opacity(0.06), lineWidth: 1).offset(y: 1).clipShape(shape))
                .background(shape.inset(by: -0.5).fill(Color.black.opacity(0.40)))
                .shadow(color: .black.opacity(0.20), radius: 1, y: 1)
                .shadow(color: .black.opacity(0.12), radius: 3, y: 2)
        }
    }
}

/// A titled card with lines.
struct SoundCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.octoSection).foregroundStyle(OctoColor.textPrimary)
            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .soundRaisedPanel()
        .padding(.horizontal, 20)
    }
}

/// A card with a switch beside its title.
struct SoundSwitchCard<Content: View>: View {
    let title: String
    @Binding var isOn: Bool
    var enabled = true
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.octoSection)
                    .foregroundStyle(OctoColor.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityAddTraits(.isHeader)
                Toggle(title, isOn: $isOn).labelsHidden().tint(OctoColor.accent).disabled(!enabled)
            }
            .padding(.horizontal, 4)
            content
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .soundRaisedPanel()
        .padding(.horizontal, 20)
    }
}

// MARK: Lines

/// A setting with a line about it and a switch at the end.
struct SoundSwitchLine: View {
    let label: String
    let detail: String
    @Binding var isOn: Bool
    var enabled = true

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 0) {
                Text(label).font(.octoBodySmall).foregroundStyle(enabled ? OctoColor.textPrimary : OctoColor.textMuted)
                Text(detail).font(.octoCaption).foregroundStyle(OctoColor.textMuted)
            }
            .padding(.trailing, 12)
        }
        .tint(OctoColor.accent)
        .disabled(!enabled)
        .padding(.vertical, 4)
    }
}

/// A setting and its current choice; tapping it opens the options.
struct SoundChoiceLine: View {
    let label: String
    let value: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(label).font(.octoBodySmall).foregroundStyle(OctoColor.textPrimary)
                    Text(value).font(.octoCaption).foregroundStyle(OctoColor.textMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 12)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(OctoColor.textMuted)
                    .frame(width: 20, height: 20)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(SoundRowPressStyle())
    }
}

/// A thin line between the parts of a card, one physical pixel tall.
struct SoundHairline: View {
    @Environment(\.displayScale) private var scale

    var body: some View {
        Rectangle()
            .fill(OctoColor.textPrimary.opacity(0.08))
            .frame(maxWidth: .infinity)
            .frame(height: 1 / max(scale, 1))
    }
}

/// A quiet action in words, with no button around it. `spotAction` hears where the finger
/// tapped, in screen points (none when asked another way).
struct SoundTextAction: View {
    let text: String
    let spotAction: (CGPoint?) -> Void

    init(_ text: String, action: @escaping () -> Void) {
        self.text = text
        spotAction = { _ in action() }
    }

    init(_ text: String, spotAction: @escaping (CGPoint?) -> Void) {
        self.text = text
        self.spotAction = spotAction
    }

    var body: some View {
        Text(text)
            .font(SoundStyle.label)
            .foregroundStyle(OctoColor.accent)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .onTapGesture(coordinateSpace: .global) { spotAction($0) }
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { spotAction(nil) }
    }
}

/// No press effect at all.
struct SoundStillStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label }
}

/// A row that lights faintly while pressed.
struct SoundRowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Color.white.opacity(configuration.isPressed ? 0.06 : 0), in: RoundedRectangle(cornerRadius: 8))
    }
}

/// A glass button of the large size: 50 tall, 24 to each side, its words in the label style.
/// The accent one is filled with the accent.
struct SoundGlassButtonStyle: ButtonStyle {
    var accent = false
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(SoundStyle.label)
            .foregroundStyle(OctoColor.textPrimary)
            .lineLimit(1)
            .padding(.horizontal, 24)
            .frame(height: 50)
            .glassEffect(accent ? .regular.tint(SoundStyle.accentFill).interactive() : Glass.octo.interactive(), in: .capsule)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(enabled ? 1 : 0.5)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

// MARK: Choices

/// A few choices in one glass strip, the chosen one in the darker pill that glides between them.
struct SoundSegmented: View {
    let options: [String]
    let selected: Int
    let onSelect: (Int) -> Void
    @Environment(\.accessibilityReduceMotion) private var still

    var body: some View {
        GeometryReader { box in
            let cell = options.isEmpty ? 0 : max(0, box.size.width - 8) / CGFloat(options.count)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(SoundStyle.pill)
                    .frame(width: cell, height: max(0, box.size.height - 8))
                    .offset(x: CGFloat(selected) * cell)
                    .animation(still ? nil : .timingCurve(0.65, 0.05, 0.36, 1, duration: 0.3), value: selected)
                HStack(spacing: 0) {
                    ForEach(options.indices, id: \.self) { index in
                        let chosen = index == selected
                        Button { onSelect(index) } label: {
                            Text(options[index])
                                .font(SoundStyle.label)
                                .foregroundStyle(chosen ? OctoColor.accent : OctoColor.textPrimary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .padding(.horizontal, 4)
                                .frame(width: cell, height: max(0, box.size.height - 8))
                                .contentShape(Rectangle())
                                .animation(.easeOut(duration: 0.2), value: chosen)
                        }
                        .buttonStyle(SoundStillStyle())
                        .accessibilityAddTraits(chosen ? [.isSelected] : [])
                    }
                }
            }
            .padding(4)
        }
        .frame(height: 40)
        .glassEffect(Glass.octo, in: .capsule)
        .overlay(Capsule().strokeBorder(OctoColor.accent.opacity(0.25), lineWidth: 0.5))
    }
}

/// The presets in one glass strip that scrolls sideways. The chosen one sits in the darker
/// pill; a long press on one of the listener's own asks to delete it, with the spot the finger
/// held, in screen points (none when asked another way).
struct SoundPresetBar: View {
    let choices: [PresetChoice]
    let selected: String
    let onPick: (PresetChoice) -> Void
    let onLongPress: (PresetChoice, CGPoint?) -> Void
    @State private var position: String?
    /// The preset just held down, so the release that follows does not also pick it.
    @State private var heldDown: (key: String, at: Date)?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 0) {
                ForEach(choices, id: \.key) { choice in item(choice) }
            }
            .scrollTargetLayout()
            .padding(.horizontal, 4)
        }
        .scrollPosition(id: $position, anchor: .leading)
        .frame(height: 44)
        .clipShape(Capsule())
        .glassEffect(Glass.octo, in: .capsule)
        .onAppear {
            // Opens with the chosen preset in view; it does not follow it later.
            if !choices.isEmpty { position = choices[PresetChoice.firstShown(choices, label: selected)].key }
        }
    }

    private func item(_ choice: PresetChoice) -> some View {
        let chosen = choice.name == selected
        return Button {
            if let held = heldDown, held.key == choice.key, Date().timeIntervalSince(held.at) < 2 {
                heldDown = nil
                return
            }
            onPick(choice)
        } label: {
            Text(choice.name)
                .font(SoundStyle.label)
                .foregroundStyle(chosen ? OctoColor.accent : OctoColor.textPrimary)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 14)
                .frame(maxHeight: .infinity)
                .background { if chosen { Capsule().fill(SoundStyle.pill) } }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
        }
        .buttonStyle(SoundStillStyle())
        // Only the listener's own presets have a long press; on a built-in one a long hold is a tap.
        .gesture(SoundLongPress(enabled: choice.own) { spot in
            heldDown = (choice.key, Date())
            onLongPress(choice, spot)
        })
        .accessibilityAddTraits(chosen ? [.isSelected] : [])
        .accessibilityActions {
            if choice.own {
                Button("Delete") { onLongPress(choice, nil) }
            }
        }
    }
}

/// A long press that tells where the finger held, in screen points.
struct SoundLongPress: UIGestureRecognizerRepresentable {
    let enabled: Bool
    let onPress: (CGPoint) -> Void

    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        let press = UILongPressGestureRecognizer()
        press.minimumPressDuration = 0.5
        press.isEnabled = enabled
        return press
    }

    func updateUIGestureRecognizer(_ recognizer: UILongPressGestureRecognizer, context: Context) {
        recognizer.isEnabled = enabled
    }

    func handleUIGestureRecognizerAction(_ recognizer: UILongPressGestureRecognizer, context: Context) {
        if recognizer.state == .began { onPress(context.converter.location(in: .global)) }
    }
}

/// A button that works only while it is held down, its glass lifting under the finger.
struct SoundHoldButton: View {
    let text: String
    let enabled: Bool
    let onHold: (Bool) -> Void
    @GestureState private var pressing = false
    @State private var held = false

    var body: some View {
        Text(text)
            .font(SoundStyle.label)
            .foregroundStyle(OctoColor.textPrimary)
            .padding(.horizontal, 24)
            .frame(height: 48)
            .glassEffect(held ? .regular.tint(OctoColor.accent.opacity(0.07)).interactive() : Glass.octo.interactive(), in: .capsule)
            .opacity(enabled || held ? 1 : 0.6)
            .contentShape(Capsule())
            // The press is followed for as long as it lasts, even as the page changes under it.
            .gesture(DragGesture(minimumDistance: 0).updating($pressing) { _, state, _ in state = true })
            .onChange(of: pressing) { _, down in
                if down {
                    guard enabled else { return }
                    held = true
                    onHold(true)
                } else if held {
                    held = false
                    onHold(false)
                }
            }
            .accessibilityElement()
            .accessibilityLabel(text)
            .accessibilityAddTraits(.isButton)
    }
}

// MARK: Sliders

/// A labelled value on the white line slider, with its reading beside it. The value moves in
/// `step`s and is sent all along the drag.
struct SoundValueSlider: View {
    let label: String
    let value: Double
    let range: ClosedRange<Double>
    let reading: String
    var step = 0.5
    var enabled = true
    var toFraction: ((Double) -> Double)?
    var fromFraction: ((Double) -> Double)?
    let onChange: (Double) -> Void

    var body: some View {
        HStack(spacing: 0) {
            Text(label)
                .font(.octoBodySmall)
                .foregroundStyle(OctoColor.textSecondary)
                .frame(width: 76, alignment: .leading)
            SoundLineSlider(fraction: min(1, max(0, place(value)))) { fraction in
                guard enabled else { return }
                let clean = SoundSliders.value(fraction: fraction, step: step, range: range, fromFraction: valueAt)
                if clean != value { onChange(clean) }
            }
            .allowsHitTesting(enabled)
            .accessibilityElement()
            .accessibilityLabel(label)
            .accessibilityValue(reading)
            .accessibilityAdjustableAction { direction in
                direction == .increment ? more() : less()
            }
            .accessibilityAction(named: "More") { more() }
            .accessibilityAction(named: "Less") { less() }
            Text(reading)
                .font(.octoBodySmall.monospacedDigit())
                .foregroundStyle(OctoColor.textPrimary)
                .lineLimit(1)
                .frame(width: 64, alignment: .leading)
                .padding(.leading, 12)
                .accessibilityHidden(true)
        }
        .opacity(enabled ? 1 : 0.5)
    }

    private func place(_ value: Double) -> Double { toFraction?(value) ?? SoundSliders.linearFraction(value, range: range) }
    private func valueAt(_ fraction: Double) -> Double { fromFraction?(fraction) ?? SoundSliders.linearValue(fraction, range: range) }
    private func more() { onChange(min(range.upperBound, value + step)) }
    private func less() { onChange(max(range.lowerBound, value - step)) }
}

/// A line that glows along its filled part. It thickens and shows a thumb while dragged; the
/// line follows the finger smoothly while the value moves in steps. A tap jumps to that point.
struct SoundLineSlider: View {
    let fraction: Double
    let onSeek: (Double) -> Void
    @State private var dragging = false
    @State private var dragFraction = 0.0

    var body: some View {
        GeometryReader { box in
            let width = max(box.size.width, 1)
            SoundLineDrawing(fraction: dragging ? dragFraction : fraction, held: dragging ? 1 : 0)
                .animation(SoundStyle.bouncy, value: dragging)
                .contentShape(Rectangle())
                .gesture(SpatialTapGesture().onEnded { tap in onSeek(min(1, max(0, tap.location.x / width))) })
                .gesture(SoundPan(shouldBegin: { _, moved in abs(moved.x) > abs(moved.y) }) { phase, location, _ in
                    let spot = min(1, max(0, location.x / width))
                    switch phase {
                    case .began:
                        dragging = true
                        dragFraction = spot
                    case .changed:
                        dragFraction = spot
                        onSeek(spot)
                    case .ended:
                        onSeek(dragFraction)
                        dragging = false
                    case .cancelled:
                        dragging = false
                    }
                })
        }
        .frame(height: 48)
    }
}

/// The line slider's drawing, with how far it is held (0 at rest, 1 dragging) as the part that
/// animates.
private struct SoundLineDrawing: View, Animatable {
    var fraction: Double
    var held: Double

    nonisolated var animatableData: Double {
        get { held }
        set { held = newValue }
    }

    var body: some View {
        Canvas { context, size in
            let y = size.height / 2
            let thickness = 3.5 + 4.5 * held
            let thumb = 9 * max(0, held)
            let blur = 12 + 12 * min(1, max(0, held))
            let glow = 0.4 + 0.4 * min(1, max(0, held))
            let end = size.width * fraction
            let style = StrokeStyle(lineWidth: thickness, lineCap: .round)
            context.stroke(line(0, size.width, y), with: .color(.white.opacity(0.24)), style: style)
            if end > 0 {
                for spread in [2.5, 1, 0.3] {
                    context.drawLayer { layer in
                        layer.addFilter(.blur(radius: SoundStyle.pixelBlur(blur * spread)))
                        layer.stroke(line(0, end, y), with: .color(.white.opacity(glow / 3)), style: style)
                    }
                }
                context.stroke(line(0, end, y), with: .color(.white), style: style)
            }
            if thumb > 0 {
                context.fill(Path(ellipseIn: CGRect(x: end - thumb, y: y - thumb, width: thumb * 2, height: thumb * 2)), with: .color(.white))
            }
        }
    }

    private func line(_ from: CGFloat, _ to: CGFloat, _ y: CGFloat) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: from, y: y))
        path.addLine(to: CGPoint(x: to, y: y))
        return path
    }
}

/// Left and right balance: a line that glows from the center out to the chosen side, with a
/// small mark at the center it snaps back to.
struct SoundBalanceSlider: View {
    let value: Double
    let onChange: (Double) -> Void
    @State private var dragging = false
    @State private var dragValue = 0.0
    @State private var ticks = 0

    var body: some View {
        HStack(spacing: 0) {
            Text("L").font(.octoCaption).foregroundStyle(OctoColor.textMuted)
            GeometryReader { box in
                let width = max(box.size.width, 1)
                SoundBalanceDrawing(value: dragging ? dragValue : value, held: dragging ? 1 : 0)
                    .animation(SoundStyle.bouncy, value: dragging)
                    .contentShape(Rectangle())
                    .gesture(SpatialTapGesture(count: 2).onEnded { _ in onChange(0) })
                    .gesture(SoundPan(shouldBegin: { _, moved in abs(moved.x) > abs(moved.y) }) { phase, location, _ in
                        switch phase {
                        case .began:
                            dragging = true
                            dragValue = value
                            follow(location.x, width)
                        case .changed:
                            follow(location.x, width)
                        case .ended, .cancelled:
                            dragging = false
                        }
                    })
            }
            .frame(height: 48)
            .padding(.horizontal, 12)
            .accessibilityElement()
            .accessibilityLabel("Balance")
            .accessibilityValue(SoundEdits.readBalance(value))
            .accessibilityAdjustableAction { direction in
                direction == .increment ? onChange(min(1, value + 0.1)) : onChange(max(-1, value - 0.1))
            }
            .accessibilityAction(named: "More to the left") { onChange(max(-1, value - 0.1)) }
            .accessibilityAction(named: "More to the right") { onChange(min(1, value + 0.1)) }
            .accessibilityAction(named: "Center") { onChange(0) }
            Text("R").font(.octoCaption).foregroundStyle(OctoColor.textMuted)
        }
        .sensoryFeedback(.selection, trigger: ticks)
    }

    /// A spot on the line as a balance, with a tick as it lands on the center.
    private func follow(_ x: CGFloat, _ width: CGFloat) {
        let snapped = SoundSliders.balance(x: x, width: width)
        if snapped == 0 && dragValue != 0 { ticks += 1 }
        dragValue = snapped
        onChange(snapped)
    }
}

private struct SoundBalanceDrawing: View, Animatable {
    var value: Double
    var held: Double

    nonisolated var animatableData: Double {
        get { held }
        set { held = newValue }
    }

    var body: some View {
        Canvas { context, size in
            let y = size.height / 2
            let thickness = 3.5 + 4.5 * held
            let thumb = 4 + 5 * held
            let glow = 0.4 + 0.4 * min(1, max(0, held))
            let center = size.width / 2
            let end = center + value * center
            let style = StrokeStyle(lineWidth: thickness, lineCap: .round)
            var track = Path()
            track.move(to: CGPoint(x: 0, y: y))
            track.addLine(to: CGPoint(x: size.width, y: y))
            context.stroke(track, with: .color(.white.opacity(0.24)), style: style)
            if end != center {
                var fill = Path()
                fill.move(to: CGPoint(x: center, y: y))
                fill.addLine(to: CGPoint(x: end, y: y))
                for spread in [2.5, 1, 0.3] {
                    context.drawLayer { layer in
                        layer.addFilter(.blur(radius: SoundStyle.pixelBlur(12 * spread)))
                        layer.stroke(fill, with: .color(.white.opacity(glow / 3)), style: style)
                    }
                }
                context.stroke(fill, with: .color(.white), style: style)
            }
            var mark = Path()
            mark.move(to: CGPoint(x: center, y: y - 7))
            mark.addLine(to: CGPoint(x: center, y: y + 7))
            context.stroke(mark, with: .color(.white.opacity(0.5)), lineWidth: 1)
            context.fill(Path(ellipseIn: CGRect(x: end - thumb, y: y - thumb, width: thumb * 2, height: thumb * 2)), with: .color(.white))
        }
    }
}

// MARK: Gestures

/// A drag that is taken only when `shouldBegin` says so, from where it started and how far it
/// has moved; otherwise the page scrolls as usual.
struct SoundPan: UIGestureRecognizerRepresentable {
    enum Phase { case began, changed, ended, cancelled }

    let shouldBegin: (_ start: CGPoint, _ moved: CGPoint) -> Bool
    let onPan: (_ phase: Phase, _ location: CGPoint, _ moved: CGPoint) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator(converter: converter)
    }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.delegate = context.coordinator
        pan.maximumNumberOfTouches = 1
        context.coordinator.shouldBegin = shouldBegin
        return pan
    }

    func updateUIGestureRecognizer(_ recognizer: UIPanGestureRecognizer, context: Context) {
        context.coordinator.shouldBegin = shouldBegin
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        let location = context.converter.localLocation
        let moved = context.converter.localTranslation ?? .zero
        switch recognizer.state {
        case .began: onPan(.began, location, moved)
        case .changed: onPan(.changed, location, moved)
        case .ended: onPan(.ended, location, moved)
        case .cancelled, .failed: onPan(.cancelled, location, moved)
        default: break
        }
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        let converter: CoordinateSpaceConverter
        var shouldBegin: ((CGPoint, CGPoint) -> Bool)?

        init(converter: CoordinateSpaceConverter) {
            self.converter = converter
        }

        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            let location = converter.localLocation
            let moved = converter.localTranslation ?? .zero
            return shouldBegin?(CGPoint(x: location.x - moved.x, y: location.y - moved.y), moved) ?? true
        }

        /// The page's scrolling waits to see whether this drag is taken.
        func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
            other.view is UIScrollView && other is UIPanGestureRecognizer
        }
    }
}
