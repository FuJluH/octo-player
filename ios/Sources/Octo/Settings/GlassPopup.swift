import OctoKit
import SwiftUI
import UIKit

/// One popup asked for: its title (what VoiceOver calls it), the control it opens beside, how
/// wide it is, a heading that stays put, and the body, which scrolls when it is taller than the
/// popup may be.
struct PopupRequest {
    var title: String
    var anchor: CGRect?
    var width: PopupWidth
    var padding: CGFloat
    var header: AnyView?
    var body: AnyView
}

/// Shows glass popups over everything, the floating bar included, in a window of their own
/// above the app's. One at a time; a tap outside the card closes it.
@MainActor
final class GlassPopupHost {
    static let shared = GlassPopupHost()

    private var window: UIWindow?
    private var closing: (() -> Void)?
    private var onClose: (() -> Void)?
    private var token = 0
    /// Whose popup is showing.
    private var owner: UUID?

    private init() {}

    var isShowing: Bool { window != nil }

    func show(_ request: PopupRequest, owner: UUID, onClose: @escaping () -> Void) {
        removeNow()
        self.owner = owner
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
            ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
        else { return }
        let insets = scene.windows.first(where: \.isKeyWindow)?.safeAreaInsets ?? scene.windows.first?.safeAreaInsets ?? .zero
        token += 1
        let mine = token
        let model = PopupModel()
        let overlay = PopupOverlay(request: request, insets: insets, screen: scene.screen.bounds.size, model: model) { [weak self] in
            self?.close(owner: owner)
        }
        let host = UIHostingController(rootView: overlay.preferredColorScheme(.dark).tint(OctoColor.accent))
        host.view.backgroundColor = .clear
        host.view.accessibilityViewIsModal = true
        let window = UIWindow(windowScene: scene)
        window.windowLevel = .normal + 1
        window.backgroundColor = .clear
        window.rootViewController = host
        window.isHidden = false
        self.window = window
        self.onClose = onClose
        closing = { [weak self] in
            model.shown = false
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(180))
                guard let self, self.token == mine else { return }
                self.removeNow()
            }
        }
        UIAccessibility.post(notification: .screenChanged, argument: host.view)
    }

    /// Shrinks the popup away, then lets it go, when it is `owner`'s.
    func close(owner: UUID) {
        guard owner == self.owner, let closing else { return }
        self.closing = nil
        let done = onClose
        onClose = nil
        closing()
        done?()
    }

    private func removeNow() {
        window?.isHidden = true
        window = nil
        closing = nil
        owner = nil
        if let done = onClose {
            onClose = nil
            done()
        }
    }
}

@MainActor
@Observable
final class PopupModel {
    var shown = false
    var size: CGSize?
    var keepAbove: Bool?
}

/// The popup's layer: a clear sheet that closes it on a tap, and the glass card placed beside
/// the control that opened it.
private struct PopupOverlay: View {
    let request: PopupRequest
    let insets: UIEdgeInsets
    let screen: CGSize
    @State var model: PopupModel
    let close: () -> Void
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    private var reduceMotion: Bool { systemReduceMotion || AppSettings.shared.player.reduceMotion }

    var body: some View {
        let maxWidth = min(PopupPlacement.maxWidth, screen.width - 2 * PopupPlacement.margin)
        let room = screen.height - insets.top - insets.bottom - 2 * PopupPlacement.margin
        let maxHeight = min(screen.height * PopupPlacement.heightShare, room)
        let spot = model.size.map { size in
            PopupPlacement.place(
                anchor: request.anchor.map { PopupRect(left: $0.minX, top: $0.minY, right: $0.maxX, bottom: $0.maxY) },
                width: size.width, height: size.height, screenWidth: screen.width, screenHeight: screen.height,
                gap: PopupPlacement.gap, top: insets.top, bottom: insets.bottom, keepAbove: model.keepAbove)
        }
        ZStack(alignment: .topLeading) {
            Color.black.opacity(0.001)
                .contentShape(Rectangle())
                .onTapGesture(perform: close)
                .accessibilityHidden(true)
            PopupCard(request: request, maxWidth: maxWidth, maxHeight: maxHeight)
                .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
                    model.size = size
                    if model.keepAbove == nil, let spot = placed(size) { model.keepAbove = spot.above }
                }
                .scaleEffect(model.shown || reduceMotion ? 1 : 0.92,
                             anchor: UnitPoint(x: spot?.origin.x ?? 0.5, y: spot?.origin.y ?? 0.5))
                .opacity(model.shown ? 1 : 0)
                .offset(x: spot?.x ?? 0, y: spot?.y ?? 0)
                .accessibilityElement(children: .contain)
                .accessibilityLabel(request.title)
                .accessibilityAddTraits(.isModal)
                .accessibilityAction(.escape, close)
        }
        .frame(width: screen.width, height: screen.height, alignment: .topLeading)
        .ignoresSafeArea()
        .onChange(of: spot != nil) { _, placed in
            guard placed, !model.shown else { return }
            withAnimation(reduceMotion ? .easeOut(duration: 0.08) : .timingCurve(0.2, 0.8, 0.2, 1, duration: 0.16)) { model.shown = true }
        }
        .animation(.easeIn(duration: 0.16), value: model.shown)
    }

    private func placed(_ size: CGSize) -> PopupSpot? {
        PopupPlacement.place(
            anchor: request.anchor.map { PopupRect(left: $0.minX, top: $0.minY, right: $0.maxX, bottom: $0.maxY) },
            width: size.width, height: size.height, screenWidth: screen.width, screenHeight: screen.height,
            gap: PopupPlacement.gap, top: insets.top, bottom: insets.bottom)
    }
}

/// The frosted card: its heading, then the body, scrolling with a "more below" mark when it is
/// taller than the card may be.
private struct PopupCard: View {
    let request: PopupRequest
    let maxWidth: CGFloat
    let maxHeight: CGFloat

    var body: some View {
        GlassPopupCard(width: request.width, maxWidth: maxWidth, maxHeight: maxHeight) {
            VStack(alignment: .leading, spacing: 0) {
                request.header
                HuggingScroll { request.body }
            }
            .padding(request.padding)
        }
    }
}

extension View {
    /// Opens a glass popup beside this view while `isPresented` is true.
    func glassPopup(isPresented: Binding<Bool>, request: @escaping () -> PopupRequest) -> some View {
        modifier(GlassPopupAnchor(isPresented: isPresented, request: request))
    }
}

/// Keeps the view's place on screen, and opens and closes the popup as asked.
private struct GlassPopupAnchor: ViewModifier {
    @Binding var isPresented: Bool
    let request: () -> PopupRequest
    @State private var frame: CGRect?
    @State private var id = UUID()

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame = $0 }
            .onChange(of: isPresented) { _, open in open ? show() : GlassPopupHost.shared.close(owner: id) }
            .onAppear { if isPresented { show() } }
            .onDisappear { GlassPopupHost.shared.close(owner: id) }
    }

    private func show() {
        var asked = request()
        asked.anchor = frame
        GlassPopupHost.shared.show(asked, owner: id) { isPresented = false }
    }
}
