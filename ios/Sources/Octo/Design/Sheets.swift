import OctoKit
import SwiftUI

/// The glass sheet's measures.
enum GlassSheetMeasures {
    /// The share of the screen a sheet may take.
    static let heightShare: CGFloat = 0.7
    static let corner: CGFloat = 28
    /// Pulled down this far, the sheet closes when let go.
    static let closeDistance: CGFloat = 96
    /// Or flicked down this fast, in points a second.
    static let closeSpeed: CGFloat = 1_200
}

/// A panel rising from the bottom over a dimmed screen. Tapping the dim closes it; so does
/// pulling its handle down, the panel following the finger. At most 70% of the screen tall
/// (`tall` lets it grow to the status bar); lines taller than that scroll under the handle.
/// The shell draws one for each sheet a page opens with `glassSheet`; it can also be placed
/// directly, last inside a full-screen stack.
struct GlassSheetFrame<Content: View>: View {
    let visible: Bool
    var tall = false
    var scrolls = true
    let onDismiss: () -> Void
    var onGone: () -> Void = {}
    @ViewBuilder let content: Content
    @State private var shown = false
    @State private var panelHeight: CGFloat = 0
    @State private var pull: CGFloat = 0
    @Environment(\.motionScale) private var motion

    var body: some View {
        GeometryReader { box in
            let screen = box.size.height + box.safeAreaInsets.top + box.safeAreaInsets.bottom
            let most = tall ? box.size.height + box.safeAreaInsets.bottom : screen * GlassSheetMeasures.heightShare
            ZStack(alignment: .bottom) {
                Color.black.opacity(0.45)
                    .opacity(shown ? 1 : 0)
                    .animation(.octoTween(OctoDuration.card, scale: motion), value: shown)
                    .contentShape(Rectangle())
                    .onTapGesture { if visible { onDismiss() } }
                    // The screen's left edge still goes back, closing the sheet.
                    .gesture(DragGesture(minimumDistance: 20).onEnded { drag in
                        if visible, drag.startLocation.x < 24, drag.translation.width > 60 { onDismiss() }
                    })
                    .accessibilityLabel("Close")
                    .accessibilityAddTraits(.isButton)
                panel(most: most, bottomInset: box.safeAreaInsets.bottom)
                    .offset(y: shown ? pull : max(panelHeight, 1) + 40)
            }
            .ignoresSafeArea(.container)
        }
        .onChange(of: visible) { _, now in now ? appear() : leave() }
    }

    private func panel(most: CGFloat, bottomInset: CGFloat) -> some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: GlassSheetMeasures.corner, topTrailingRadius: GlassSheetMeasures.corner,
                                           style: .continuous)
        return VStack(spacing: 0) {
            handle
            Group {
                if scrolls {
                    HuggingScroll { VStack(spacing: 0) { content } }
                } else {
                    content
                }
            }
            .frame(maxWidth: .infinity)
            Color.clear.frame(height: bottomInset)
        }
        .frame(maxWidth: .infinity)
        .frame(maxHeight: most, alignment: .top)
        .background {
            shape.fill(OctoColor.sheetFill)
                .overlay(alignment: .top) { Color.white.opacity(0.10).frame(height: 1).clipShape(shape) }
                .shadow(color: .black.opacity(0.4), radius: shadowRadius(32))
        }
        .clipShape(shape)
        // Taps on the sheet never reach the dim.
        .contentShape(shape)
        .onTapGesture {}
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
            let first = panelHeight == 0
            panelHeight = height
            // Its lines measure themselves a moment later; it rises once they have.
            if first && visible {
                Task {
                    try? await Task.sleep(for: .milliseconds(20))
                    appear()
                }
            }
        }
        .accessibilityAddTraits(.isModal)
    }

    /// The handle: a short bar in a full-width strip. Pulling it moves the sheet with the
    /// finger, never above its rest; let go far enough down or fast enough, the sheet closes.
    private var handle: some View {
        Capsule()
            .fill(OctoColor.textMuted)
            .frame(width: 36, height: 4)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { drag in pull = max(0, drag.translation.height) }
                    .onEnded { drag in
                        if pull > GlassSheetMeasures.closeDistance || drag.velocity.height > GlassSheetMeasures.closeSpeed {
                            onDismiss()
                        } else {
                            withAnimation(.octoSpring(0.8, 400)) { pull = 0 }
                        }
                    }
            )
            .accessibilityLabel("Close")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onDismiss() }
    }

    private func appear() {
        guard panelHeight > 0, !shown else { return }
        pull = 0
        withAnimation(.octoSpring(0.85, 400)) { shown = true }
    }

    private func leave() {
        withAnimation(.octoTween(OctoDuration.card, OctoEasing.easeIn, scale: motion)) {
            shown = false
        } completion: {
            pull = 0
            if !visible { onGone() }
        }
    }
}
