import Observation
import SwiftUI
import UIKit

/// Where the message pill is in its window, so every other touch passes through to the app.
@MainActor
@Observable
final class ToastSpot {
    @ObservationIgnored var frame: CGRect?
}

/// The message line's own window, just above the app's, so a message shows over the system
/// sheets, popovers, menus and questions the app opens. It takes a touch only on the pill
/// itself, and the status bar follows the app under it.
@MainActor
final class ToastWindow {
    private static var shared: ToastWindow?
    private let window: ToastPassWindow

    private init(scene: UIWindowScene, below: UIWindow, router: Router) {
        let spot = ToastSpot()
        let host = ToastController(rootView: AnyView(
            ToastHost()
                .environment(router)
                .environment(spot)
                .preferredColorScheme(.dark)
        ))
        host.below = below
        host.view.backgroundColor = .clear
        window = ToastPassWindow(windowScene: scene)
        window.spot = spot
        window.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.normal.rawValue + 0.5)
        window.backgroundColor = .clear
        window.rootViewController = host
        window.isHidden = false
    }

    /// Puts the window up once, over the window `below` of the app.
    static func install(over below: UIWindow, router: Router) {
        guard shared == nil, let scene = below.windowScene else { return }
        shared = ToastWindow(scene: scene, below: below, router: router)
    }
}

/// Lets every touch through but those on the message pill.
private final class ToastPassWindow: UIWindow {
    weak var spot: ToastSpot?

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let frame = spot?.frame, frame.contains(point) else { return nil }
        return super.hitTest(point, with: event)
    }
}

/// Hosts the message line, leaving the status bar's look to whatever the app shows under it.
private final class ToastController: UIHostingController<AnyView> {
    weak var below: UIWindow?

    /// The app's front screen: its root, or what it presents on top.
    private var front: UIViewController? {
        var top = below?.rootViewController
        while let next = top?.presentedViewController, !next.isBeingDismissed { top = next }
        return top
    }

    override var childForStatusBarStyle: UIViewController? { front }
    override var childForStatusBarHidden: UIViewController? { front }
}

/// Puts the message line's window up once the shell is in a window.
struct ToastWindowProbe: UIViewRepresentable {
    let router: Router

    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.router = router
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: ProbeView, context: Context) {}

    final class ProbeView: UIView {
        var router: Router?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard let window, let router else { return }
            ToastWindow.install(over: window, router: router)
        }
    }
}
