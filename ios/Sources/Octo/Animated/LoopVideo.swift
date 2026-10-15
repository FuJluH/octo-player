import AVFoundation
import Observation
import OctoKit
import os
import SwiftUI
import UIKit

/// What a loop's player is to do: not be there, hold the frame it is on, or play.
enum LoopRun: Equatable {
    case none
    case held
    case playing
}

/// The one loop allowed to play at a time, and whether the phone is saving power. A loop that
/// wants to play claims the stage; one that loses it lets its player go, so two never decode at
/// once.
@MainActor
@Observable
final class LoopStage {
    static let shared = LoopStage()

    private(set) var owner: UUID?
    /// Low Power Mode is on.
    private(set) var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    @ObservationIgnored private var watch: NSObjectProtocol?

    private init() {
        watch = NotificationCenter.default.addObserver(forName: Notification.Name.NSProcessInfoPowerStateDidChange, object: nil,
                                                       queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled }
        }
    }

    func claim(_ id: UUID) {
        if owner != id { owner = id }
    }

    func release(_ id: UUID) {
        if owner == id { owner = nil }
    }
}

/// How a loop fills the whole player: drawn at the top at the view's width and its own height,
/// fading out between `fadeStart` and `fadeEnd` (points from the top), over the same loop
/// stretched across everything and blurred deep.
struct LoopBackdropFit: Equatable {
    var height: CGFloat
    var fadeStart: CGFloat
    var fadeEnd: CGFloat
}

/// A loop drawn by the system's video layer: muted, no controls, scaled to fill its frame, its
/// still (when it has one) under it until the first frame is ready, then crossfading in over
/// `loopFadeMs`. It never touches the music's audio session.
struct LoopVideo: UIViewRepresentable {
    /// The file (or stream) to play; nil for none.
    var source: URL?
    var run: LoopRun
    var poster: UIImage? = nil
    var radius: CGFloat = 0
    /// Filling the player behind the controls, in place of filling the view.
    var backdrop: LoopBackdropFit? = nil
    /// Blurred behind words that need the room, such as lyrics.
    var blurred = false
    /// Told when the loop's frames show, and when they go.
    var showing: ((Bool) -> Void)? = nil

    func makeUIView(context: Context) -> LoopVideoView { LoopVideoView() }

    func updateUIView(_ view: LoopVideoView, context: Context) {
        view.showing = showing
        view.set(radius: radius)
        view.set(backdrop: backdrop)
        view.set(poster: poster)
        view.set(blurred: blurred)
        view.update(source: run == .none ? nil : source, run: run)
    }

    static func dismantleUIView(_ view: LoopVideoView, coordinator: ()) {
        view.update(source: nil, run: .none, fade: false)
    }
}

/// The view under `LoopVideo`. Each loop it plays has its own player and layers, so a new one
/// can fade in over the one fading out. As a backdrop it draws the loop twice from one player:
/// sharp at the top, fading out, and behind it stretched and blurred as the color the rest of
/// the player sits on.
final class LoopVideoView: UIView {
    /// The blurred copy behind, shown only as a backdrop.
    private let backHost = UIView()
    private let backPoster = CALayer()
    private let backBlur = UIVisualEffectView(effect: UIBlurEffect(style: .regular))
    /// The loop itself, with its still under it.
    private let frontHost = UIView()
    private let posterLayer = CALayer()
    private let fadeMask = CAGradientLayer()
    /// The blur over everything while words need the room.
    private let blur = UIVisualEffectView(effect: nil)
    private var blurred = false
    private var fit: LoopBackdropFit?
    private var take: Take?
    private var posterImage: UIImage?
    var showing: ((Bool) -> Void)?

    /// One loop: its player, the looper that keeps it going, and the layers it is drawn in.
    private final class Take {
        let source: URL
        let player: AVQueuePlayer
        let looper: AVPlayerLooper
        let layer: AVPlayerLayer
        let back: AVPlayerLayer?
        var ready: NSKeyValueObservation?
        var counted: NSKeyValueObservation?
        var shown = false

        init(source: URL, player: AVQueuePlayer, looper: AVPlayerLooper, layer: AVPlayerLayer, back: AVPlayerLayer?) {
            self.source = source
            self.player = player
            self.looper = looper
            self.layer = layer
            self.back = back
        }

        func end() {
            ready?.invalidate()
            counted?.invalidate()
            player.pause()
            looper.disableLooping()
            player.removeAllItems()
            layer.player = nil
            back?.player = nil
            layer.removeFromSuperlayer()
            back?.removeFromSuperlayer()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        accessibilityElementsHidden = true
        backgroundColor = .clear
        layer.masksToBounds = true
        layer.cornerCurve = .continuous
        for host in [backHost, frontHost] {
            host.isUserInteractionEnabled = false
            host.backgroundColor = .clear
            addSubview(host)
        }
        backHost.isHidden = true
        backHost.clipsToBounds = true
        backPoster.contentsGravity = .resizeAspectFill
        backPoster.opacity = 0
        backHost.layer.addSublayer(backPoster)
        backHost.addSubview(backBlur)
        posterLayer.contentsGravity = .resizeAspectFill
        posterLayer.opacity = 0
        frontHost.layer.addSublayer(posterLayer)
        // Eased in and out: the sharp loop gives way to its blurred copy slowly, then steadily,
        // then slowly again, so no line shows where the blur begins or ends.
        fadeMask.colors = [1.0, 1.0, 0.94, 0.72, 0.38, 0.1, 0.0].map { UIColor.black.withAlphaComponent($0).cgColor }
        blur.isUserInteractionEnabled = false
        addSubview(blur)
    }

    required init?(coder: NSCoder) { nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        backHost.frame = bounds
        backBlur.frame = backHost.bounds
        // The blurred copy a little larger than the view, so its soft edges never show.
        let spill = backHost.bounds.insetBy(dx: -40, dy: -40)
        backPoster.frame = spill
        take?.back?.frame = spill
        if let fit {
            frontHost.frame = CGRect(x: 0, y: 0, width: bounds.width, height: fit.height)
            let height = max(fit.height, 1)
            let start = min(max(fit.fadeStart / height, 0), 1)
            let end = min(max(fit.fadeEnd / height, start), 1)
            let span = end - start
            fadeMask.locations = [0, start, start + span * 0.2, start + span * 0.45, start + span * 0.7, start + span * 0.88, end]
                .map { NSNumber(value: Double($0)) }
            fadeMask.frame = frontHost.bounds
            frontHost.layer.mask = fadeMask
        } else {
            frontHost.frame = bounds
            frontHost.layer.mask = nil
        }
        posterLayer.frame = frontHost.bounds
        take?.layer.frame = frontHost.bounds
        CATransaction.commit()
        blur.frame = bounds
    }

    func set(radius: CGFloat) {
        guard layer.cornerRadius != radius else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.cornerRadius = radius
        CATransaction.commit()
    }

    func set(backdrop: LoopBackdropFit?) {
        guard backdrop != fit else { return }
        fit = backdrop
        backHost.isHidden = backdrop == nil
        setNeedsLayout()
    }

    /// Blurs the loop and its still, or clears them, over 0.35 s.
    func set(blurred: Bool) {
        guard blurred != self.blurred else { return }
        self.blurred = blurred
        UIView.animate(withDuration: 0.35, delay: 0, options: [.curveEaseInOut, .beginFromCurrentState]) {
            self.blur.effect = blurred ? UIBlurEffect(style: .regular) : nil
        }
    }

    /// The still under the loop, faded in once it arrives.
    func set(poster: UIImage?) {
        guard poster !== posterImage else { return }
        posterImage = poster
        let target: Float = poster == nil ? 0 : 1
        for still in [posterLayer, backPoster] {
            still.contents = poster?.cgImage
            if still.opacity != target { fade(still, to: target, seconds: 0.3) }
        }
    }

    /// Plays `source`, holds it, or lets it go. Another source fades the old loop out as the new
    /// one comes in.
    func update(source: URL?, run: LoopRun, fade: Bool = true) {
        if let take, take.source != source || run == .none {
            letGo(fade: fade)
        }
        guard let source, run != .none else { return }
        if take == nil {
            // Held with nothing on screen yet: the still stays, nothing is loaded.
            guard run == .playing else { return }
            start(source)
        }
        guard let take else { return }
        if run == .playing {
            if take.player.timeControlStatus != .playing { take.player.play() }
        } else if take.player.timeControlStatus != .paused {
            take.player.pause()
        }
    }

    private func start(_ source: URL) {
        let player = AVQueuePlayer()
        // A silent picture: never heard, never on another screen, never keeping the phone awake,
        // and it leaves the audio session alone.
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        player.allowsExternalPlayback = false
        player.audiovisualBackgroundPlaybackPolicy = .pauses
        let item = AVPlayerItem(asset: AVURLAsset(url: source))
        let looper = AVPlayerLooper(player: player, templateItem: item)
        let layer = AVPlayerLayer(player: player)
        // The blurred copy only as a backdrop; a cover draws the loop once.
        let back = fit == nil ? nil : AVPlayerLayer(player: player)
        for drawn in [layer] + [back].compactMap({ $0 }) {
            drawn.videoGravity = .resizeAspectFill
            drawn.opacity = 0
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.frame = frontHost.bounds
        frontHost.layer.addSublayer(layer)
        if let back {
            back.frame = backHost.bounds.insetBy(dx: -40, dy: -40)
            backHost.layer.insertSublayer(back, above: backPoster)
        }
        CATransaction.commit()
        let take = Take(source: source, player: player, looper: looper, layer: layer, back: back)
        let id = ObjectIdentifier(take)
        take.ready = Self.watchReady(layer) { [weak self] in
            Task { @MainActor in self?.reveal(id) }
        }
        #if DEBUG
        take.counted = Self.watchLoops(looper, source: source)
        #endif
        self.take = take
    }

    /// The first frame is drawn: the loop crossfades in over the still or the cover.
    private func reveal(_ id: ObjectIdentifier) {
        guard let take, ObjectIdentifier(take) == id, !take.shown, take.layer.isReadyForDisplay else { return }
        take.shown = true
        for drawn in [take.layer] + [take.back].compactMap({ $0 }) { fade(drawn, to: 1, seconds: Double(loopFadeMs) / 1000) }
        showing?(true)
    }

    private func letGo(fade: Bool) {
        guard let old = take else { return }
        take = nil
        if old.shown { showing?(false) }
        guard fade, old.shown else {
            old.end()
            return
        }
        CATransaction.begin()
        CATransaction.setCompletionBlock { old.end() }
        for drawn in [old.layer] + [old.back].compactMap({ $0 }) { self.fade(drawn, to: 0, seconds: Double(loopFadeMs) / 1000) }
        CATransaction.commit()
    }

    private func fade(_ target: CALayer, to opacity: Float, seconds: Double) {
        let from = target.presentation()?.opacity ?? target.opacity
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = from
        animation.toValue = opacity
        animation.duration = seconds
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        target.opacity = opacity
        target.add(animation, forKey: "fade")
    }

    nonisolated private static func watchReady(_ layer: AVPlayerLayer, _ ready: @escaping @Sendable () -> Void) -> NSKeyValueObservation {
        layer.observe(\.isReadyForDisplay, options: [.initial, .new]) { layer, _ in
            if layer.isReadyForDisplay { ready() }
        }
    }

    #if DEBUG
    /// Logs each time the loop comes round and when the looper gives up, for checking on a device.
    nonisolated private static func watchLoops(_ looper: AVPlayerLooper, source: URL) -> NSKeyValueObservation {
        let log = Logger(subsystem: "app.winters.octo", category: "loops")
        let name = source.isFileURL ? "file \(source.lastPathComponent)" : "stream \(source.lastPathComponent)"
        log.notice("loop start \(name, privacy: .public)")
        return looper.observe(\.loopCount, options: [.new]) { looper, _ in
            let status = looper.status == .failed ? "failed \(looper.error?.localizedDescription ?? "")" : "\(looper.status.rawValue)"
            log.notice("loop \(looper.loopCount) status \(status, privacy: .public) \(name, privacy: .public)")
        }
    }
    #endif
}
