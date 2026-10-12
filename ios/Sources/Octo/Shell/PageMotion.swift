import ObjectiveC
import OctoKit
import SwiftUI
import UIKit

/// How pages move. Going deeper slides the new page in from 32% of the width to the right as the
/// old one drifts 12% to the left, the new one fading in a touch late and the old one fading
/// out: 380 ms on the default curve. Going back runs it the other way, so where a page came from
/// says where back leads. A swipe in from the left edge takes the page back with the finger,
/// evenly, so the page sits where the finger has taken it. With Reduce motion the pages only
/// cross-fade.
enum PageMotion {
    static let arrive: CGFloat = 0.32
    static let leave: CGFloat = 0.12
    static let slideMs = 380
    static let fadeOutMs = 140
    static let fadeInMs = 180
    static let fadeInDelayMs = 40
}

extension View {
    /// Gives the stack this view sits in Octo's page motion. `rootBack`, when given, is what a
    /// swipe in from the left edge does at the stack's first page.
    func pageMotion(rootBack: (() -> Void)? = nil) -> some View {
        background(PageMotionInstaller(rootBack: rootBack).allowsHitTesting(false).accessibilityHidden(true))
    }
}

private struct PageMotionInstaller: UIViewRepresentable {
    let rootBack: (() -> Void)?
    @Environment(\.motionScale) private var motion
    @Environment(\.accessibilityReduceMotion) private var systemCalm

    func makeUIView(context: Context) -> Probe {
        let probe = Probe()
        probe.isUserInteractionEnabled = false
        return probe
    }

    func updateUIView(_ probe: Probe, context: Context) {
        probe.still = motion.still || systemCalm
        probe.rootBack = rootBack
        probe.install()
    }

    final class Probe: UIView {
        var still = false
        var rootBack: (() -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            install()
        }

        func install() {
            guard window != nil else { return }
            var responder: UIResponder? = self
            while let current = responder, !(current is UINavigationController) { responder = current.next }
            guard let navigation = responder as? UINavigationController else { return }
            let delegate = PageMotionDelegate.install(on: navigation)
            delegate.still = still
            delegate.rootBack = rootBack
        }
    }
}

/// Stands in front of the stack's own delegate: it hands every message on, and adds Octo's page
/// motion and the edge swipe that drives it.
@MainActor
final class PageMotionDelegate: NSObject, UINavigationControllerDelegate, UIGestureRecognizerDelegate {
    private static var key: UInt8 = 0

    nonisolated(unsafe) weak var original: UINavigationControllerDelegate?
    weak var navigation: UINavigationController?
    var still = false
    /// What the edge swipe does at the first page, if anything.
    var rootBack: (() -> Void)?
    private var interaction: EdgeBack?
    private var swipingAtRoot = false
    private var edge: UIScreenEdgePanGestureRecognizer?

    /// The delegate on `navigation`, put there the first time and again if the stack replaced it.
    @discardableResult
    static func install(on navigation: UINavigationController) -> PageMotionDelegate {
        let delegate: PageMotionDelegate
        if let existing = objc_getAssociatedObject(navigation, &key) as? PageMotionDelegate {
            delegate = existing
        } else {
            delegate = PageMotionDelegate()
            delegate.navigation = navigation
            objc_setAssociatedObject(navigation, &key, delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            let edge = UIScreenEdgePanGestureRecognizer(target: delegate, action: #selector(edgeMoved(_:)))
            edge.edges = .left
            edge.delegate = delegate
            navigation.view.addGestureRecognizer(edge)
            delegate.edge = edge
            navigation.interactivePopGestureRecognizer?.isEnabled = false
        }
        if navigation.delegate !== delegate {
            delegate.original = navigation.delegate
            navigation.delegate = delegate
        }
        return delegate
    }

    // MARK: Handing messages on

    nonisolated override func responds(to selector: Selector!) -> Bool {
        super.responds(to: selector) || (original?.responds(to: selector) ?? false)
    }

    nonisolated override func forwardingTarget(for selector: Selector!) -> Any? {
        if let original, original.responds(to: selector) { return original }
        return super.forwardingTarget(for: selector)
    }

    func navigationController(_ navigationController: UINavigationController, willShow viewController: UIViewController, animated: Bool) {
        original?.navigationController?(navigationController, willShow: viewController, animated: animated)
    }

    func navigationController(_ navigationController: UINavigationController, didShow viewController: UIViewController, animated: Bool) {
        original?.navigationController?(navigationController, didShow: viewController, animated: animated)
    }

    // MARK: The motion

    func navigationController(_ navigationController: UINavigationController, animationControllerFor operation: UINavigationController.Operation,
                              from fromVC: UIViewController, to toVC: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        guard operation != .none else { return nil }
        return PageAnimator(forward: operation == .push, still: still)
    }

    func navigationController(_ navigationController: UINavigationController,
                              interactionControllerFor animationController: UIViewControllerAnimatedTransitioning) -> UIViewControllerInteractiveTransitioning? {
        interaction
    }

    // MARK: The edge swipe

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let navigation, navigation.transitionCoordinator == nil else { return false }
        // A page with something to close first (picked songs) closes that instead of leaving.
        if navigation.viewControllers.count > 1, let handler = BackHandler.current {
            handler.run()
            return false
        }
        return navigation.viewControllers.count > 1 || rootBack != nil
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        false
    }

    @objc private func edgeMoved(_ pan: UIScreenEdgePanGestureRecognizer) {
        guard let navigation, let view = navigation.view else { return }
        let width = max(1, view.bounds.width)
        let progress = min(1, max(0, pan.translation(in: view).x / width))
        if pan.state == .began {
            swipingAtRoot = navigation.viewControllers.count <= 1
        }
        if swipingAtRoot {
            // At the first page there is nothing to slide back to: far enough, the swipe acts.
            if pan.state == .ended, pan.translation(in: view).x > 60 { rootBack?() }
            return
        }
        switch pan.state {
        case .began:
            let back = EdgeBack(still: still)
            interaction = back
            navigation.popViewController(animated: true)
        case .changed:
            interaction?.update(progress)
        case .ended:
            let speed = pan.velocity(in: view).x
            if progress > 0.35 || speed > 600 { interaction?.finish() } else { interaction?.cancel() }
            interaction = nil
        default:
            interaction?.cancel()
            interaction = nil
        }
    }
}

/// Where each page is at `progress` (0 at the start of the move, 1 at its end), the move taking
/// the slide's whole time.
private struct PagePose {
    let forward: Bool
    let width: CGFloat

    func arriving(_ p: CGFloat) -> (x: CGFloat, alpha: CGFloat) {
        let side: CGFloat = forward ? 1 : -1
        let total = CGFloat(PageMotion.slideMs)
        let fade = min(1, max(0, (p * total - CGFloat(PageMotion.fadeInDelayMs)) / CGFloat(PageMotion.fadeInMs)))
        return (width * PageMotion.arrive * side * (1 - p), fade)
    }

    func leaving(_ p: CGFloat) -> (x: CGFloat, alpha: CGFloat) {
        let side: CGFloat = forward ? 1 : -1
        let total = CGFloat(PageMotion.slideMs)
        let fade = 1 - min(1, max(0, p * total / CGFloat(PageMotion.fadeOutMs)))
        return (-width * PageMotion.leave * side * p, fade)
    }
}

/// The move run by itself, after a tap on back or into a page.
@MainActor
private final class PageAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    let forward: Bool
    let still: Bool

    init(forward: Bool, still: Bool) {
        self.forward = forward
        self.still = still
    }

    func transitionDuration(using context: UIViewControllerContextTransitioning?) -> TimeInterval {
        still ? Double(PageMotion.fadeInMs / 2) / 1_000 : Double(PageMotion.slideMs) / 1_000
    }

    func animateTransition(using context: UIViewControllerContextTransitioning) {
        guard let from = context.view(forKey: .from), let to = context.view(forKey: .to),
              let toController = context.viewController(forKey: .to) else {
            context.completeTransition(!context.transitionWasCancelled)
            return
        }
        let container = context.containerView
        to.frame = context.finalFrame(for: toController)
        if forward { container.addSubview(to) } else { container.insertSubview(to, belowSubview: from) }
        let done = { (finished: Bool) in
            from.transform = .identity
            from.alpha = 1
            to.transform = .identity
            to.alpha = 1
            context.completeTransition(!context.transitionWasCancelled)
        }
        if still {
            // Nothing travels; the pages only cross, in half the time.
            to.alpha = 0
            let fadeIn = UIViewPropertyAnimator(duration: Double(PageMotion.fadeInMs / 2) / 1_000, curve: .easeInOut) { to.alpha = 1 }
            let fadeOut = UIViewPropertyAnimator(duration: Double(PageMotion.fadeOutMs / 2) / 1_000, curve: .easeInOut) { from.alpha = 0 }
            fadeIn.addCompletion { _ in done(true) }
            fadeOut.startAnimation()
            fadeIn.startAnimation()
            return
        }
        let pose = PagePose(forward: forward, width: container.bounds.width)
        let start = pose.arriving(0)
        to.transform = CGAffineTransform(translationX: start.x, y: 0)
        to.alpha = 0
        let curve = UICubicTimingParameters(controlPoint1: CGPoint(x: 0.2, y: 0.8), controlPoint2: CGPoint(x: 0.2, y: 1))
        let slide = UIViewPropertyAnimator(duration: Double(PageMotion.slideMs) / 1_000, timingParameters: curve)
        slide.addAnimations {
            to.transform = .identity
            from.transform = CGAffineTransform(translationX: pose.leaving(1).x, y: 0)
        }
        let fadeIn = UIViewPropertyAnimator(duration: Double(PageMotion.fadeInMs) / 1_000, timingParameters: curve)
        fadeIn.addAnimations { to.alpha = 1 }
        let fadeOut = UIViewPropertyAnimator(duration: Double(PageMotion.fadeOutMs) / 1_000, timingParameters: curve)
        fadeOut.addAnimations { from.alpha = 0 }
        slide.addCompletion { _ in done(true) }
        slide.startAnimation()
        fadeOut.startAnimation()
        fadeIn.startAnimation(afterDelay: Double(PageMotion.fadeInDelayMs) / 1_000)
    }
}

/// Back driven by the finger: the pages follow it evenly, then finish or go back when it lifts.
@MainActor
private final class EdgeBack: NSObject, UIViewControllerInteractiveTransitioning {
    let still: Bool
    private var context: UIViewControllerContextTransitioning?
    private var from: UIView?
    private var to: UIView?
    private var pose = PagePose(forward: false, width: 0)
    private var progress: CGFloat = 0
    private var ending: (finish: Bool, done: Bool)?

    init(still: Bool) { self.still = still }

    func startInteractiveTransition(_ context: UIViewControllerContextTransitioning) {
        self.context = context
        guard let from = context.view(forKey: .from), let to = context.view(forKey: .to),
              let toController = context.viewController(forKey: .to) else {
            context.completeTransition(false)
            return
        }
        self.from = from
        self.to = to
        to.frame = context.finalFrame(for: toController)
        context.containerView.insertSubview(to, belowSubview: from)
        pose = PagePose(forward: false, width: context.containerView.bounds.width)
        apply(0)
        if let ending { ending.finish ? finish() : cancel() }
    }

    func update(_ value: CGFloat) {
        guard ending == nil else { return }
        progress = value
        apply(value)
        context?.updateInteractiveTransition(value)
    }

    func finish() { end(true) }
    func cancel() { end(false) }

    private func apply(_ p: CGFloat) {
        guard let from, let to else { return }
        if still {
            to.transform = .identity
            from.transform = .identity
            to.alpha = p
            from.alpha = 1 - p
            return
        }
        let arriving = pose.arriving(p)
        let leaving = pose.leaving(p)
        to.transform = CGAffineTransform(translationX: arriving.x, y: 0)
        to.alpha = arriving.alpha
        from.transform = CGAffineTransform(translationX: leaving.x, y: 0)
        from.alpha = leaving.alpha
    }

    private func end(_ finish: Bool) {
        guard let context else {
            // The stack has not started the move yet; it ends this way as soon as it does.
            ending = (finish, false)
            return
        }
        guard ending?.done != true else { return }
        ending = (finish, true)
        if finish { context.finishInteractiveTransition() } else { context.cancelInteractiveTransition() }
        let target: CGFloat = finish ? 1 : 0
        let remaining = Double(abs(target - progress)) * Double(PageMotion.slideMs) / 1_000
        let animator = UIViewPropertyAnimator(duration: max(0.12, remaining), curve: .easeOut) { self.apply(target) }
        animator.addCompletion { _ in
            self.from?.transform = .identity
            self.from?.alpha = 1
            self.to?.transform = .identity
            self.to?.alpha = 1
            context.completeTransition(finish)
        }
        animator.startAnimation()
    }
}
