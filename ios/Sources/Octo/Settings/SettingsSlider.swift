import SwiftUI
import UIKit

/// The settings slider: a recessed track, an accent fill, and a white jewel of a thumb with an
/// accent dot in it, which grows a ring and a glow while dragged. A tap jumps to that point; a
/// drag sends the value all along and again on release. Set from elsewhere, the fill slides to
/// the new value in 80 ms.
struct JewelSlider: View {
    let fraction: Double
    let label: String
    let valueText: String
    /// How far one swipe up or down moves it, for VoiceOver.
    var step: Double = 0.05
    let onSeek: (Double) -> Void

    @State private var dragging: Double?
    @State private var shown: Double = 0

    var body: some View {
        GeometryReader { box in
            let thumb: CGFloat = dragging == nil ? 14 : 16
            let radius = thumb / 2
            let width = box.size.width
            let at = dragging ?? shown
            let x = radius + (width - 2 * radius) * CGFloat(min(max(at, 0), 1))
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(LinearGradient(colors: [.white.opacity(0.10), .white.opacity(0.14)], startPoint: .top, endPoint: .bottom))
                    .overlay(Capsule().stroke(Color.black.opacity(0.25), lineWidth: 0.5).offset(y: 0.5).mask(Capsule()))
                    .frame(height: 4)
                Capsule()
                    .fill(LinearGradient(colors: [OctoColor.accent, OctoColor.accent.mix(with: .black, by: 0.22)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: max(0, x), height: 4)
                Circle()
                    .fill(OctoColor.accent.opacity(0.25))
                    .frame(width: thumb + 12, height: thumb + 12)
                    .opacity(dragging == nil ? 0 : 1)
                    .offset(x: x - radius - 6)
                Circle()
                    .fill(.white)
                    .overlay(Circle().fill(OctoColor.accent).scaleEffect(dragging == nil ? 0.35 : 0.42))
                    .shadow(color: .black.opacity(0.3), radius: 1.5, y: 1)
                    .shadow(color: OctoColor.accent.opacity(dragging == nil ? 0 : 0.5), radius: 6)
                    .frame(width: thumb, height: thumb)
                    .offset(x: x - radius)
            }
            .frame(width: width, height: box.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let f = Double(min(max((drag.location.x - radius) / max(width - 2 * radius, 1), 0), 1))
                        dragging = f
                        onSeek(f)
                    }
                    .onEnded { drag in
                        let f = Double(min(max((drag.location.x - radius) / max(width - 2 * radius, 1), 0), 1))
                        onSeek(f)
                        // The fill settles on the saved value, which moves in steps.
                        shown = f
                        dragging = nil
                        withAnimation(.linear(duration: 0.08)) { shown = fraction }
                    }
            )
            .animation(.easeOut(duration: 0.15), value: dragging == nil)
        }
        .frame(height: 48)
        .onAppear { shown = fraction }
        .onChange(of: fraction) { _, new in
            guard dragging == nil else { return }
            withAnimation(.linear(duration: 0.08)) { shown = new }
        }
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue(valueText)
        .accessibilityAdjustableAction { direction in
            let next = direction == .increment ? fraction + step : fraction - step
            onSeek(min(max(next, 0), 1))
        }
    }
}

/// Octo's glowing line, for speed and pitch: the filled part lit, a thumb while dragged. It
/// sends its value all along the drag, so changes are heard as the finger moves.
struct GlowSlider: View {
    let fraction: Double
    let label: String
    let valueText: String
    var step: Double = 0.05
    let onSeek: (Double) -> Void

    @State private var dragging: Double?

    var body: some View {
        GeometryReader { box in
            let width = box.size.width
            let at = min(max(dragging ?? fraction, 0), 1)
            let held = dragging != nil
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.24)).frame(height: held ? 8 : 3.5)
                Capsule()
                    .fill(Color.white)
                    .frame(width: max(0, width * at), height: held ? 8 : 3.5)
                    .shadow(color: .white.opacity(held ? 0.6 : 0.35), radius: held ? 8 : 4)
                if held {
                    Circle().fill(.white).frame(width: 18, height: 18).offset(x: width * at - 9)
                }
            }
            .frame(width: width, height: box.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let f = Double(min(max(drag.location.x / max(width, 1), 0), 1))
                        dragging = f
                        onSeek(f)
                    }
                    .onEnded { drag in
                        onSeek(Double(min(max(drag.location.x / max(width, 1), 0), 1)))
                        dragging = nil
                    }
            )
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: held)
        }
        .frame(height: 48)
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue(valueText)
        .accessibilityAdjustableAction { direction in
            onSeek(min(max(direction == .increment ? fraction + step : fraction - step, 0), 1))
        }
    }
}
