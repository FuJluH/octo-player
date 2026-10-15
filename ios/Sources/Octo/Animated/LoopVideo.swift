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

/// A loop drawn by the system's video layer: muted, no controls, scaled to fill its frame, its
/// still (when it has one) under it until the first frame is ready, then crossfading in over
/// `loopFadeMs`. With a fade, its lower part dissolves into whatever is under it. It never
/// touches the music's audio session.
struct LoopVideo: UIViewRepresentable {
    /// The file (or stream) to play; nil for none.
    var source: URL?
    var run: LoopRun
    var poster: UIImage? = nil
    var radius: CGFloat = 0
    /// Where the loop dissolves, in points from its top: whole down to the first, gone at the
    /// second, eased by `FullScreenLook.melt` between.
    var fade: ClosedRange<CGFloat>? = nil
    /// Blurred behind words that need the room, such as lyrics.
    var blurred = false
    /// Told when the loop's frames show, and when they go.
    var showing: ((Bool) -> Void)? = nil

    func makeUIView(context: Context) -> LoopVideoView { LoopVideoView() }

    func updateUIView(_ view: LoopVideoView, context: Context) {
        view.showing = showing
        view.set(radius: radius)
        view.set(fade: fade)
        view.set(poster: poster)
        view.set(blurred: blurred)
        view.update(source: run == .none ? nil : source, run: run)
    }

    static func dismantleUIView(_ view: LoopVideoView, coordinator: ()) {
        view.update(source: nil, run: .none, fade: false)
    }
}

/// The view under `LoopVideo`. Each loop it plays has its own player and layer, so a new one can
/// fade in over the one fading out.
final class LoopVideoView: UIView {
    private let posterLayer = CALayer()
    /// The blur over everything while words need the room.
    private let blur = UIVisualEffectView(effect: nil)
    private var blurred = false
    private var take: Take?
    private var posterImage: UIImage?
    private var fade: ClosedRange<CGFloat>?
    private let fadeMask = CAGradientLayer()
    var showing: ((Bool) -> Void)?

    /// One loop: its player, the looper that keeps it going, and the layer it is drawn in.
    private final class Take {
        let source: URL
        let player: AVQueuePlayer
        let looper: AVPlayerLooper
        let layer: AVPlayerLayer
        var ready: NSKeyValueObservation?
        var counted: NSKeyValueObservation?
        var shown = false

        init(source: URL, player: AVQueuePlayer, looper: AVPlayerLooper, layer: AVPlayerLayer) {
            self.source = source
            self.player = player
            self.looper = looper
            self.layer = layer
        }

        func end() {
            ready?.invalidate()
            counted?.invalidate()
            player.pause()
            looper.disableLooping()
            player.removeAllItems()
            layer.player = nil
            layer.removeFromSuperlayer()
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
        posterLayer.contentsGravity = .resizeAspectFill
        posterLayer.opacity = 0
        layer.addSublayer(posterLayer)
        blur.isUserInteractionEnabled = false
        addSubview(blur)
    }

    required init?(coder: NSCoder) { nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        posterLayer.frame = bounds
        take?.layer.frame = bounds
        if let fade, bounds.height > 0 {
            // The melt from whole to nothing, sampled finely enough that no step shows.
            let steps = 16
            let start = fade.lowerBound / bounds.height
            let end = fade.upperBound / bounds.height
            var locations: [NSNumber] = [0]
            var colors: [CGColor] = [UIColor.black.cgColor]
            for i in 0...steps {
                let t = CGFloat(i) / CGFloat(steps)
                let gone = CGFloat(FullScreenLook.melt(Double(t)))
                locations.append(NSNumber(value: Double(start + (end - start) * t)))
                colors.append(UIColor.black.withAlphaComponent(1 - gone).cgColor)
            }
            locations.append(1)
            colors.append(UIColor.clear.cgColor)
            fadeMask.locations = locations
            fadeMask.colors = colors
            fadeMask.frame = bounds
            layer.mask = fadeMask
        } else {
            layer.mask = nil
        }
        CATransaction.commit()
        blur.frame = bounds
    }

    func set(fade: ClosedRange<CGFloat>?) {
        guard fade != self.fade else { return }
        self.fade = fade
        setNeedsLayout()
    }

    func set(radius: CGFloat) {
        guard layer.cornerRadius != radius else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.cornerRadius = radius
        CATransaction.commit()
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
        posterLayer.contents = poster?.cgImage
        let target: Float = poster == nil ? 0 : 1
        if posterLayer.opacity != target { fade(posterLayer, to: target, seconds: 0.3) }
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
            return
        }
        guard let take else { return }
        if run == .playing {
            if take.player.timeControlStatus != .playing { take.player.play() }
        } else if take.player.timeControlStatus != .paused {
            take.player.pause()
        }
    }

    private func start(_ source: URL) {
        let asset = AVURLAsset(url: source)
        let player = AVQueuePlayer()
        // A silent picture: never heard, never on another screen, never keeping the phone awake,
        // and it leaves the audio session alone.
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        player.allowsExternalPlayback = false
        player.audiovisualBackgroundPlaybackPolicy = .pauses
        let item = AVPlayerItem(asset: asset)
        let looper = AVPlayerLooper(player: player, templateItem: item)
        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspectFill
        layer.opacity = 0
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.frame = bounds
        // Under the blur, which is a view of its own above every layer drawn here.
        self.layer.insertSublayer(layer, below: blur.layer)
        CATransaction.commit()
        let take = Take(source: source, player: player, looper: looper, layer: layer)
        let id = ObjectIdentifier(take)
        take.ready = Self.watchReady(layer) { [weak self] in
            Task { @MainActor in self?.reveal(id) }
        }
        #if DEBUG
        take.counted = Self.watchLoops(looper, source: source)
        #endif
        self.take = take
        player.play()
    }

    /// The first frame is drawn: the loop crossfades in over the still or the cover.
    private func reveal(_ id: ObjectIdentifier) {
        guard let take, ObjectIdentifier(take) == id, !take.shown, take.layer.isReadyForDisplay else { return }
        take.shown = true
        fade(take.layer, to: 1, seconds: Double(loopFadeMs) / 1000)
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
        self.fade(old.layer, to: 0, seconds: Double(loopFadeMs) / 1000)
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
