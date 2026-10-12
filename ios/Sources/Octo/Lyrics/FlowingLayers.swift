import CoreImage
import OctoKit
import QuartzCore
import SwiftUI
import UIKit

/// The flowing lines drawn with Core Animation. Each line shown is a layer holding a picture of
/// the line, drawn again only when the engine says what the line shows changed; every frame only
/// moves, scales and fades the layers, which the GPU does without redrawing anything. A line's
/// blur is a blurred copy of its picture, made off the main thread for a few fixed strengths and
/// kept until the line changes.
struct FlowingLayers: UIViewRepresentable {
    let model: FlowingModel
    let ink: Color
    let calm: Bool
    let tap: (Int) -> Void
    let hold: (Int) -> Void
    let press: (Int, Bool) -> Void
    let dragStart: () -> Void
    let dragBy: (Double) -> Void
    let dragEnd: () -> Void

    func makeUIView(context: Context) -> FlowingLayerView {
        let view = FlowingLayerView(model: model)
        model.surface = view
        return view
    }

    func updateUIView(_ view: FlowingLayerView, context: Context) {
        view.ink = UIColor(ink)
        view.calm = calm
        view.tap = tap
        view.hold = hold
        view.press = press
        view.dragStart = dragStart
        view.dragBy = dragBy
        view.dragEnd = dragEnd
        if model.surface !== view { model.surface = view }
    }
}

@MainActor
final class FlowingLayerView: UIView {
    let model: FlowingModel
    var ink = UIColor.white {
        didSet { if ink != oldValue { forgetPictures() } }
    }
    var calm = false {
        didSet { if calm != oldValue { forgetPictures() } }
    }
    var tap: (Int) -> Void = { _ in }
    var hold: (Int) -> Void = { _ in }
    var press: (Int, Bool) -> Void = { _, _ in }
    var dragStart: () -> Void = {}
    var dragBy: (Double) -> Void = { _ in }
    var dragEnd: () -> Void = {}

    private var lines: [Int: LineLayer] = [:]
    private var pressed: Int?
    private var lastDrag: CGFloat = 0
    private var shownRange = LineRange.empty

    init(model: FlowingModel) {
        self.model = model
        super.init(frame: .zero)
        isOpaque = false
        backgroundColor = .clear
        clipsToBounds = true
        isAccessibilityElement = false

        let tapper = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
        let holder = UILongPressGestureRecognizer(target: self, action: #selector(held(_:)))
        holder.minimumPressDuration = 0.5
        holder.allowableMovement = 10
        tapper.require(toFail: holder)
        let panner = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
        addGestureRecognizer(tapper)
        addGestureRecognizer(holder)
        addGestureRecognizer(panner)
    }

    required init?(coder: NSCoder) { fatalError("not from a storyboard") }

    // MARK: Drawing

    /// Places every line shown for this frame, drawing again only the lines that changed.
    func render() {
        guard let layout = model.layout else { return }
        let engine = model.engine
        let range = engine.shown
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        for (index, layer) in lines where range.isEmpty || !range.contains(index) {
            layer.removeFromSuperlayer()
            lines[index] = nil
        }
        guard !range.isEmpty else { return }
        let width = bounds.width
        for index in range.first...range.last where engine.states.indices.contains(index) {
            let state = engine.states[index]
            let box = layout.lines[index]
            let line = model.lines[index]
            let height = line.isInterlude ? layout.spec.interludeFull : box.height
            let layer: LineLayer
            if let known = lines[index] {
                layer = known
            } else {
                layer = LineLayer()
                self.layer.addSublayer(layer)
                lines[index] = layer
            }
            layer.bounds = CGRect(x: 0, y: 0, width: width, height: height)
            if layer.drawnVersion != state.drawVersion || layer.drawnSize != layer.bounds.size {
                draw(layer, index: index, layout: layout, size: layer.bounds.size, version: state.drawVersion)
            }
            layer.show(blur: blurBucket(shownBlur(state.blur)), scale: window?.screen.scale ?? 3)
            layer.transform = FlowingPlacement.transform(engine, state, box, nodeHeight: height)
            layer.opacity = Float(min(max(state.opacity, 0), 1))
        }
        if range != shownRange {
            shownRange = range
            accessibilityElements = nil
        }
    }

    /// The line's picture, with room around it for its blur.
    private func draw(_ layer: LineLayer, index: Int, layout: LyricsLayout, size: CGSize, version: Int) {
        let pad = LineLayer.pad
        let format = UIGraphicsImageRendererFormat()
        format.scale = window?.screen.scale ?? 3
        format.opaque = false
        let canvas = CGSize(width: size.width + pad * 2, height: size.height + pad * 2)
        let painter = LyricPainter(engine: model.engine, layout: layout, index: index, ink: ink, calm: calm)
        let picture = UIGraphicsImageRenderer(size: canvas, format: format).image { context in
            context.cgContext.translateBy(x: pad, y: pad)
            painter.draw(context.cgContext)
        }
        layer.setPicture(picture.cgImage, version: version, size: size)
    }

    /// A blur rounded to the strengths kept, in points; 0 is sharp.
    private func blurBucket(_ blur: Double) -> Int {
        let radius = blur <= 0 ? 0 : blur * 0.57735 + 0.5
        return Int(radius.rounded())
    }

    private func forgetPictures() {
        for layer in lines.values { layer.drawnVersion = -1 }
    }

    // MARK: Touch

    /// The line under a point, by where each line is drawn this frame.
    private func line(at point: CGPoint) -> Int? {
        guard let layout = model.layout else { return nil }
        let engine = model.engine
        let range = engine.shown
        guard !range.isEmpty else { return nil }
        for index in range.first...range.last where engine.states.indices.contains(index) {
            let state = engine.states[index]
            let box = layout.lines[index]
            let height = model.lines[index].isInterlude ? layout.spec.interludeFull : box.height
            let transform = CATransform3DGetAffineTransform(FlowingPlacement.transform(engine, state, box, nodeHeight: height))
            if CGRect(x: 0, y: 0, width: bounds.width, height: height).applying(transform).contains(point) { return index }
        }
        return nil
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        if let point = touches.first?.location(in: self), let index = line(at: point) {
            pressed = index
            press(index, true)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        letGo()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        letGo()
    }

    private func letGo() {
        if let pressed { press(pressed, false) }
        pressed = nil
    }

    @objc private func tapped(_ recognizer: UITapGestureRecognizer) {
        if let index = line(at: recognizer.location(in: self)) { tap(index) }
    }

    @objc private func held(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began, let index = line(at: recognizer.location(in: self)) else { return }
        hold(index)
    }

    /// A vertical drag anywhere scrolls by hand. There is no fling: the lyrics follow the song
    /// again a moment after the finger lifts.
    @objc private func panned(_ recognizer: UIPanGestureRecognizer) {
        let y = recognizer.translation(in: self).y
        switch recognizer.state {
        case .began:
            // The scroll starts from here: the movement before the drag was seen is left out.
            letGo()
            dragStart()
            lastDrag = y
        case .changed:
            dragBy(Double(y - lastDrag))
            lastDrag = y
        default:
            lastDrag = 0
            dragEnd()
        }
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
        let speed = pan.velocity(in: self)
        return abs(speed.y) > abs(speed.x)
    }

    // MARK: VoiceOver

    override var accessibilityElements: [Any]? {
        get {
            if let made = super.accessibilityElements { return made }
            let made = spokenLines()
            super.accessibilityElements = made
            return made
        }
        set { super.accessibilityElements = newValue }
    }

    private func spokenLines() -> [Any] {
        guard let layout = model.layout else { return [] }
        let engine = model.engine
        let range = engine.shown
        guard !range.isEmpty else { return [] }
        var elements: [Any] = []
        for index in range.first...range.last where engine.states.indices.contains(index) {
            let line = model.lines[index]
            let element = LineElement(accessibilityContainer: self)
            element.index = index
            element.view = self
            element.accessibilityLabel = line.isInterlude ? "Instrumental"
                : [line.text, line.translation].compactMap { $0 }.joined(separator: ". ")
            let state = engine.states[index]
            let box = layout.lines[index]
            let height = line.isInterlude ? layout.spec.interludeFull : box.height
            let transform = CATransform3DGetAffineTransform(FlowingPlacement.transform(engine, state, box, nodeHeight: height))
            element.accessibilityFrameInContainerSpace = CGRect(x: 0, y: 0, width: bounds.width, height: height).applying(transform)
            if !line.isCredit {
                element.accessibilityTraits = .button
                let time = asClock(max(Int((line.start * 1000).rounded()), 0) / 1000)
                element.accessibilityCustomActions = [UIAccessibilityCustomAction(name: "Play from \(time)") { [weak self] _ in
                    self?.tap(index)
                    return true
                }]
            }
            elements.append(element)
        }
        return elements
    }

    fileprivate final class LineElement: UIAccessibilityElement {
        var index = 0
        weak var view: FlowingLayerView?

        override func accessibilityActivate() -> Bool {
            view?.tap(index)
            return true
        }
    }
}

/// One line on screen: its picture, and blurred copies of it made as they are needed. Used on
/// the main thread only.
final class LineLayer: CALayer, @unchecked Sendable {
    /// The room kept around a line's picture for its blur to spread into.
    static let pad: CGFloat = 28

    var drawnVersion = -1
    private(set) var drawnSize = CGSize.zero
    private let picture = CALayer()
    private var sharp: CGImage?
    private var blurred: [Int: CGImage] = [:]
    private var making = Set<Int>()
    private var shownBlur = -1

    override init() {
        super.init()
        anchorPoint = .zero
        position = .zero
        masksToBounds = false
        picture.contentsGravity = .resize
        addSublayer(picture)
    }

    override init(layer: Any) { super.init(layer: layer) }

    required init?(coder: NSCoder) { fatalError("not from a storyboard") }

    @MainActor func setPicture(_ image: CGImage?, version: Int, size: CGSize) {
        drawnVersion = version
        drawnSize = size
        sharp = image
        blurred = [:]
        making = []
        shownBlur = -1
        picture.frame = CGRect(x: -Self.pad, y: -Self.pad, width: size.width + Self.pad * 2, height: size.height + Self.pad * 2)
    }

    /// Shows the picture at this blur: the copy at that strength once it is made, the nearest
    /// sharper one until then.
    @MainActor func show(blur: Int, scale: CGFloat) {
        guard let sharp else { return }
        if blur <= 0 {
            if shownBlur != 0 {
                picture.contents = sharp
                shownBlur = 0
            }
            return
        }
        if let ready = blurred[blur] {
            if shownBlur != blur {
                picture.contents = ready
                shownBlur = blur
            }
            return
        }
        if shownBlur < 0 {
            picture.contents = blurred.filter { $0.key < blur }.max { $0.key < $1.key }?.value ?? sharp
            shownBlur = 0
        }
        guard !making.contains(blur) else { return }
        making.insert(blur)
        let version = drawnVersion
        let source = sharp
        BlurMaker.shared.make(source, radiusPixels: CGFloat(blur) * scale) { [weak self] image in
            guard let self, self.drawnVersion == version, let image else { return }
            self.blurred[blur] = image
            self.making.remove(blur)
        }
    }
}

/// Makes blurred copies of line pictures on a queue of its own.
final class BlurMaker: @unchecked Sendable {
    static let shared = BlurMaker()
    private let queue = DispatchQueue(label: "app.winters.octo.lyrics.blur", qos: .userInitiated)
    private let context = CIContext(options: [.cacheIntermediates: false])

    func make(_ image: CGImage, radiusPixels: CGFloat, done: @escaping @MainActor (CGImage?) -> Void) {
        nonisolated(unsafe) let source = image
        queue.async { [context] in
            let input = CIImage(cgImage: source)
            let output = input.clampedToExtent().applyingGaussianBlur(sigma: Double(radiusPixels)).cropped(to: input.extent)
            nonisolated(unsafe) let made = context.createCGImage(output, from: input.extent)
            DispatchQueue.main.async { MainActor.assumeIsolated { done(made) } }
        }
    }
}

/// Where a line goes on a frame: moved, scaled and turned about its own text's start edge.
enum FlowingPlacement {
    @MainActor
    static func transform(_ engine: LyricEngine, _ st: LineState, _ box: LineBox, nodeHeight: CGFloat) -> CATransform3D {
        let look = engine.look
        let inactive = look.fraction(.inactiveScale)
        var scale = inactive + (1 - inactive) * st.grown.value()
        scale *= 1 - (1 - PRESSED_SCALE) * st.press
        let y = st.y.value() + engine.scrollOffset
        let pivot = CGPoint(x: box.pivotX, y: nodeHeight / 2)
        var translateX = 0.0
        var yaw = 0.0
        if look.arc && onScreen(y, height: st.height, viewHeight: engine.viewHeight) {
            let pose = arcPose(centre: y + st.height / 2, viewHeight: engine.viewHeight, side: st.line.alignRight ? -1 : 1)
            translateX = pose.translationX
            yaw = pose.rotationY
            scale *= pose.scale
        }
        var t = CATransform3DMakeTranslation(-pivot.x, -pivot.y, 0)
        t = CATransform3DConcat(t, CATransform3DMakeScale(scale, scale, 1))
        if yaw != 0 {
            t = CATransform3DConcat(t, CATransform3DMakeRotation(yaw, 0, 1, 0))
            var perspective = CATransform3DIdentity
            perspective.m34 = -1 / CGFloat(ARC_PERSPECTIVE)
            t = CATransform3DConcat(t, perspective)
        }
        return CATransform3DConcat(t, CATransform3DMakeTranslation(pivot.x + translateX, pivot.y + y, 0))
    }
}
