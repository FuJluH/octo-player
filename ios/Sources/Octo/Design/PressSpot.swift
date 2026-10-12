import Observation
import OctoKit
import SwiftUI
import UIKit

/// The last thing pressed anywhere in the app, so a menu or a small glass card can open beside
/// it: a long-pressed row, or the button tapped. Every touch is noted as it lands, before any
/// tap or long press runs. A control marked with `pressAnchor()` is its own anchor (a wide row
/// is narrowed to the finger); an unmarked press keeps just the finger's point.
@MainActor
@Observable
final class PressSpots {
    @ObservationIgnored private var marked: [UUID: CGRect] = [:]
    @ObservationIgnored private var choiceMarked: [UUID: CGRect] = [:]
    @ObservationIgnored private var memory = PressMemory()
    @ObservationIgnored private var choiceMemory = PressMemory()
    @ObservationIgnored private var windowWidth: CGFloat = 0

    func mark(_ id: UUID, _ frame: CGRect?, choice: Bool) {
        if choice {
            choiceMarked[id] = frame
        } else {
            marked[id] = frame
        }
    }

    /// A finger landed at `point` in a window `width` wide.
    func landed(at point: CGPoint, windowWidth width: CGFloat) {
        windowWidth = width
        let now = ProcessInfo.processInfo.systemUptime
        if let frame = smallest(containing: point, in: marked) {
            memory.pressed(menuAnchor(bounds: PopupRect(frame), fingerX: point.x, fingerY: point.y, windowWidth: width), at: now)
        } else {
            memory.pressed(PopupRect(left: point.x, top: point.y, right: point.x, bottom: point.y), at: now)
        }
        if let frame = smallest(containing: point, in: choiceMarked) {
            choiceMemory.pressed(PopupRect(frame), at: now)
        }
    }

    /// What was pressed in the last two seconds, if anything.
    func recent() -> CGRect? { memory.recent(at: ProcessInfo.processInfo.systemUptime)?.cgRect }

    /// The control marked as asking a question that was pressed in the last two seconds; it is
    /// used once.
    func takeRecentChoice() -> CGRect? {
        let found = choiceMemory.recent(at: ProcessInfo.processInfo.systemUptime)?.cgRect
        choiceMemory.forget()
        return found
    }

    private func smallest(containing point: CGPoint, in frames: [UUID: CGRect]) -> CGRect? {
        frames.values.filter { $0.contains(point) }.min { $0.width * $0.height < $1.width * $1.height }
    }
}

extension PopupRect {
    init(_ rect: CGRect) { self.init(left: rect.minX, top: rect.minY, right: rect.maxX, bottom: rect.maxY) }
    var cgRect: CGRect { CGRect(x: left, y: top, width: width, height: height) }
}

extension View {
    /// Marks this control as what a menu or card it opens should float beside.
    func pressAnchor() -> some View { modifier(PressAnchor(choice: false)) }

    /// Marks a control that asks a question, so the answers pop up beside it rather than in the
    /// middle of the screen.
    func choiceAnchor() -> some View { modifier(PressAnchor(choice: true)) }

    /// Notes every touch in the window, for `PressSpots`. Put once on the app's root.
    func recordsPresses(_ spots: PressSpots) -> some View {
        background(PressRecorderView(spots: spots).allowsHitTesting(false))
    }
}

private struct PressAnchor: ViewModifier {
    let choice: Bool
    @Environment(PressSpots.self) private var spots
    @State private var id = UUID()

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { spots.mark(id, $0, choice: choice) }
            .onDisappear { spots.mark(id, nil, choice: choice) }
    }
}

/// Puts a touch watcher on the window that never takes a touch for itself.
private struct PressRecorderView: UIViewRepresentable {
    let spots: PressSpots

    func makeUIView(context: Context) -> RecorderHost {
        let view = RecorderHost()
        view.spots = spots
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: RecorderHost, context: Context) { view.spots = spots }

    final class RecorderHost: UIView {
        weak var spots: PressSpots?
        private var recorder: PressRecognizer?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard let window, recorder?.view !== window else { return }
            let recognizer = PressRecognizer { [weak self] point, width in self?.spots?.landed(at: point, windowWidth: width) }
            window.addGestureRecognizer(recognizer)
            recorder = recognizer
        }
    }
}

/// Fails at once on every touch, after noting where it landed, so it never gets in the way.
private final class PressRecognizer: UIGestureRecognizer, UIGestureRecognizerDelegate {
    private let landed: (CGPoint, CGFloat) -> Void

    init(landed: @escaping (CGPoint, CGFloat) -> Void) {
        self.landed = landed
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        delegate = self
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        if let touch = touches.first, let view {
            landed(touch.location(in: view), view.bounds.width)
        }
        state = .failed
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
}
