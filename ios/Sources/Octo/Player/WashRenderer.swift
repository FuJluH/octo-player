import Metal
import OctoKit
import QuartzCore
import SwiftUI
import UIKit

/// The GPU programs the player's moving backgrounds draw with, built once from their source.
final class WashGPU: @unchecked Sendable {
    let device: MTLDevice
    let queue: MTLCommandQueue
    let composite: MTLRenderPipelineState
    let blurAcross: MTLRenderPipelineState
    let blurDown: MTLRenderPipelineState
    let finalPass: MTLRenderPipelineState
    let mesh: MTLRenderPipelineState

    nonisolated(unsafe) private static var made: WashGPU??

    /// The programs, or nil on a phone that cannot run them.
    static var shared: WashGPU? {
        if let made { return made }
        let built = WashGPU()
        made = .some(built)
        return built
    }

    private init?() {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue(),
              let library = try? device.makeLibrary(source: WashGPU.source, options: nil),
              let vertex = library.makeFunction(name: "fullScreen")
        else { return nil }
        func pipeline(_ name: String, _ format: MTLPixelFormat) -> MTLRenderPipelineState? {
            guard let fragment = library.makeFunction(name: name) else { return nil }
            let description = MTLRenderPipelineDescriptor()
            description.vertexFunction = vertex
            description.fragmentFunction = fragment
            description.colorAttachments[0].pixelFormat = format
            return try? device.makeRenderPipelineState(descriptor: description)
        }
        guard let composite = pipeline("composite", .rgba16Float), let across = pipeline("blurAcross", .rgba16Float),
              let down = pipeline("blurDown", .rgba16Float), let final = pipeline("finalPass", .bgra8Unorm),
              let mesh = pipeline("mesh", .bgra8Unorm)
        else { return nil }
        self.device = device
        self.queue = queue
        self.composite = composite
        blurAcross = across
        blurDown = down
        finalPass = final
        self.mesh = mesh
    }

    /// A 512 square cover as a texture.
    func texture(_ cover: WashCover) -> MTLTexture? {
        let side = WashSize
        let description = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: side, height: side, mipmapped: false)
        description.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: description) else { return nil }
        var bytes = [UInt8](repeating: 255, count: side * side * 4)
        for (i, p) in cover.pixels.enumerated() {
            bytes[i * 4] = UInt8((p >> 16) & 0xFF)
            bytes[i * 4 + 1] = UInt8((p >> 8) & 0xFF)
            bytes[i * 4 + 2] = UInt8(p & 0xFF)
        }
        texture.replace(region: MTLRegionMake2D(0, 0, side, side), mipmapLevel: 0, withBytes: bytes, bytesPerRow: side * 4)
        return texture
    }

    func square() -> MTLTexture? {
        let description = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: WashSize, height: WashSize, mipmapped: false)
        description.usage = [.renderTarget, .shaderRead]
        description.storageMode = .private
        return device.makeTexture(descriptor: description)
    }

    // The wash's steps and the classic mesh: the
    // eight copies over a warp into the 512 square, the square blurred across and down with
    // mirrored edges, then turned and magnified over the screen, brightened, with fresh grain.
    private static let source = """
    #include <metal_stdlib>
    using namespace metal;

    struct Out { float4 position [[position]]; };

    vertex Out fullScreen(uint id [[vertex_id]]) {
        float2 corners[3] = { float2(-1.0, -1.0), float2(3.0, -1.0), float2(-1.0, 3.0) };
        Out out;
        out.position = float4(corners[id], 0.0, 1.0);
        return out;
    }

    struct Copies {
        float4 m[8];
        float4 o[8];
        float rotation;
        float warp;
        float fade;
        float pad;
    };

    constant float opacity[8] = { 1.0, 0.60, 0.30, 0.20, 0.85, 0.70, 0.55, 0.40 };

    float divider(float rest, float lag, float scale, float y, float rotation, float warp) {
        return rest + \(WarpAmplitude) * sin(warp + lag + y * 0.1 * rotation * scale * 10.0);
    }

    float warpX(float x, float y, float rotation, float warp) {
        float d0 = divider(\(WarpRest[0]), \(WarpPhaseSteps[0]), \(WarpScales[0]), y, rotation, warp);
        float d1 = divider(\(WarpRest[1]), \(WarpPhaseSteps[1]), \(WarpScales[1]), y, rotation, warp);
        float d2 = divider(\(WarpRest[2]), \(WarpPhaseSteps[2]), \(WarpScales[2]), y, rotation, warp);
        float band = \(WarpMinBand);
        d0 = clamp(d0, band, 1.0 - 3.0 * band);
        d1 = max(d1, d0 + band);
        d2 = min(max(d2, d1 + band), 1.0 - band);
        d1 = min(d1, d2 - band);
        d0 = min(d0, d1 - band);
        if (x < d0) return (x / d0) * 0.25;
        if (x < d1) return (1.0 + (x - d0) / (d1 - d0)) * 0.25;
        if (x < d2) return (2.0 + (x - d1) / (d2 - d1)) * 0.25;
        return (3.0 + (x - d2) / (1.0 - d2)) * 0.25;
    }

    fragment float4 composite(Out in [[stage_in]], texture2d<float> oldCover [[texture(0)]],
                              texture2d<float> newCover [[texture(1)]], constant Copies& u [[buffer(0)]]) {
        constexpr sampler s(address::repeat, filter::linear);
        float2 uv = in.position.xy / \(Float(WashSize));
        uv.x = warpX(uv.x, uv.y * \(Float(WashSize)), u.rotation, u.warp);
        float3 c = float3(0.0);
        for (int i = 0; i < 8; i++) {
            float4 m = u.m[i];
            float2 p = uv - 0.5 + u.o[i].xy;
            float2 q = float2(m.x * p.x + m.y * p.y, m.z * p.x + m.w * p.y) + 0.5;
            float3 cover = mix(oldCover.sample(s, q).rgb, newCover.sample(s, q).rgb, u.fade);
            c = mix(c, cover, opacity[i]);
        }
        return float4(c, 1.0);
    }

    float4 blurAlong(texture2d<float> source, float2 at, float2 step, float sigma) {
        constexpr sampler s(address::mirrored_repeat, filter::linear);
        int reach = int(ceil(sigma * 3.0));
        float3 sum = source.sample(s, at / \(Float(WashSize))).rgb;
        float total = 1.0;
        for (int k = 1; k <= reach; k += 2) {
            float w1 = exp(-float(k * k) / (2.0 * sigma * sigma));
            float w2 = exp(-float((k + 1) * (k + 1)) / (2.0 * sigma * sigma));
            float w = w1 + w2;
            float2 off = step * (float(k) + w2 / w);
            sum += (source.sample(s, (at + off) / \(Float(WashSize))).rgb + source.sample(s, (at - off) / \(Float(WashSize))).rgb) * w;
            total += 2.0 * w;
        }
        return float4(sum / total, 1.0);
    }

    fragment float4 blurAcross(Out in [[stage_in]], texture2d<float> source [[texture(0)]]) {
        return blurAlong(source, in.position.xy, float2(1.0, 0.0), \(WashBlurSigmaAcross));
    }

    fragment float4 blurDown(Out in [[stage_in]], texture2d<float> source [[texture(0)]]) {
        return blurAlong(source, in.position.xy, float2(0.0, 1.0), \(WashBlurSigmaDown));
    }

    struct Final {
        float2 size;
        float turn;
        float magnify;
        float gain;
        float seed;
        float pad0;
        float pad1;
    };

    float grain(float2 p) {
        return fract(sin(dot(p, float2(12.9898, 78.233))) * 43758.5453);
    }

    fragment float4 finalPass(Out in [[stage_in]], texture2d<float> wash [[texture(0)]], constant Final& u [[buffer(0)]]) {
        constexpr sampler s(address::clamp_to_edge, filter::linear);
        float2 c = in.position.xy;
        float2 p = c - u.size * 0.5;
        p = float2(p.x / (u.magnify * u.size.x / \(Float(WashSize))), p.y / (u.magnify * u.size.y / \(Float(WashSize))));
        float cs = cos(u.turn);
        float sn = sin(u.turn);
        float2 q = float2(cs * p.x + sn * p.y, -sn * p.x + cs * p.y) + \(Float(WashSize) / 2);
        float3 col = wash.sample(s, q / \(Float(WashSize))).rgb * u.gain;
        float n = grain(c + u.seed) + grain(c.yx + u.seed * 1.61803 + 17.0) - 1.0;
        col += n / 255.0;
        return float4(clamp(col, float3(0.0), float3(1.0)), 1.0);
    }

    struct Mesh {
        float2 size;
        float time;
        float pad;
        float4 c0;
        float4 c1;
        float4 c2;
        float4 c3;
    };

    float weight(float2 uv, float2 p, float aspect) {
        float2 d = (uv - p) * float2(aspect, 1.0);
        return 1.0 / (dot(d, d) + 0.02);
    }

    fragment float4 mesh(Out in [[stage_in]], constant Mesh& u [[buffer(0)]]) {
        float2 coord = in.position.xy;
        float2 uv = coord / u.size;
        float aspect = u.size.x / u.size.y;
        float t = u.time;
        uv += 0.05 * sin(uv.yx * 3.0 + t * 0.3);
        float2 p0 = float2(0.20 + 0.18 * sin(t * 0.20), 0.18 + 0.14 * cos(t * 0.31));
        float2 p1 = float2(0.82 + 0.16 * cos(t * 0.43), 0.26 + 0.16 * sin(t * 0.37));
        float2 p2 = float2(0.24 + 0.16 * cos(t * 0.53), 0.78 + 0.14 * sin(t * 0.61));
        float2 p3 = float2(0.80 + 0.14 * sin(t * 0.70), 0.84 + 0.12 * cos(t * 0.47));
        float w0 = weight(uv, p0, aspect);
        float w1 = weight(uv, p1, aspect);
        float w2 = weight(uv, p2, aspect);
        float w3 = weight(uv, p3, aspect);
        float3 color = (u.c0.rgb * w0 + u.c1.rgb * w1 + u.c2.rgb * w2 + u.c3.rgb * w3) / (w0 + w1 + w2 + w3);
        float g = fract(sin(dot(coord, float2(12.9898, 78.233))) * 43758.5453);
        color += (g - 0.5) * 0.008;
        return float4(color, 1.0);
    }
    """
}

/// A view whose layer the GPU draws into.
final class MetalCanvas: UIView {
    override class var layerClass: AnyClass { CAMetalLayer.self }
    var metal: CAMetalLayer { layer as! CAMetalLayer }

    override func layoutSubviews() {
        super.layoutSubviews()
        let scale = window?.screen.scale ?? traitCollection.displayScale
        metal.contentsScale = scale
        metal.drawableSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)
    }
}

// MARK: The immersive wash

/// What the wash is asked to show this moment.
struct WashInputs: Equatable {
    var cover: WashCover?
    var bpm: Float
    var fpsLimit: Int
    var speed: Float
    var moving: Bool
    var focused: Bool
    var closing: Bool
    /// How much brighter than usual the wash is drawn.
    var gain: Float = 1

    static func == (a: WashInputs, b: WashInputs) -> Bool {
        a.cover === b.cover && a.bpm == b.bpm && a.fpsLimit == b.fpsLimit && a.speed == b.speed && a.moving == b.moving
            && a.focused == b.focused && a.closing == b.closing && a.gain == b.gain
    }
}

/// The moving wash. One clock drives the motion and the cover fade; it runs while the app is in
/// view and while there is something to move: the motion, or a cover still fading in. It starts
/// transparent and fades in once its first frame is drawn, or after 1.5 s.
struct ImmersiveWash: UIViewRepresentable {
    let inputs: WashInputs

    func makeUIView(context: Context) -> WashView { WashView() }

    func updateUIView(_ view: WashView, context: Context) { view.update(inputs) }

    static func dismantleUIView(_ view: WashView, coordinator: ()) { view.stop() }
}

final class WashView: UIView {
    private let canvas = MetalCanvas()
    private let gpu = WashGPU.shared
    private var clock: WashClock?
    private let swap = CoverSwap<WashCover>()
    private var oldTexture: MTLTexture?
    private var newTexture: MTLTexture?
    private var square: MTLTexture?
    private var blurred: MTLTexture?
    private var link: CADisplayLink?
    private var inputs: WashInputs?
    private var shownCover: WashCover?
    private var drawnFirst = false
    private var openedAt = CACurrentMediaTime()
    private var closingAt: CFTimeInterval?
    private var fadeInFrom: CFTimeInterval?
    private var foreground = true
    private var watches: [NSObjectProtocol] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        canvas.metal.isOpaque = false
        canvas.metal.pixelFormat = .bgra8Unorm
        canvas.metal.framebufferOnly = true
        canvas.alpha = 0
        if let gpu { canvas.metal.device = gpu.device }
        addSubview(canvas)
        let center = NotificationCenter.default
        watches.append(center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.foreground = false
                self?.pause()
            }
        })
        watches.append(center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.foreground = true
                self?.wake()
            }
        })
        watches.append(center.addObserver(forName: Notification.Name.NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.wake() }
        })
    }

    required init?(coder: NSCoder) { nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        canvas.frame = bounds
    }

    func update(_ next: WashInputs) {
        let before = inputs
        inputs = next
        if clock == nil { clock = WashClock(targetFps(next.focused ? .focused : .unfocused, next.fpsLimit, powerSave: lowPower)) }
        if next.closing, closingAt == nil { closingAt = CACurrentMediaTime() }
        // A new brightness is drawn at once, even with the wash at rest.
        if next.gain != before?.gain { wake() }
        if let cover = next.cover, cover !== shownCover, let clock, let gpu {
            shownCover = cover
            let nowMs = Int(CACurrentMediaTime() * 1000)
            let (from, to) = swap.arrive(cover, clock.fade, nowMs) { old, new, mix in WashCover.mixed(old, new, mix) }
            oldTexture = gpu.texture(from)
            newTexture = from === to ? oldTexture : gpu.texture(to)
        }
        if before != next { wake() }
    }

    private var lowPower: Bool { ProcessInfo.processInfo.isLowPowerModeEnabled }

    private func wake() {
        guard foreground, link == nil, inputs != nil else { return }
        let link = CADisplayLink(target: WashTarget(self), selector: #selector(WashTarget.tick(_:)))
        // The clock paces the wash itself; the range never caps the screen below what the rest
        // of the app asks for (the system picks one rate that suits every link).
        let limit = Float(inputs?.fpsLimit ?? 60)
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 10, maximum: 120, preferred: limit)
        link.add(to: .main, forMode: .common)
        self.link = link
        clock?.start(Int(link.timestamp * 1e9))
    }

    private func pause() {
        link?.invalidate()
        link = nil
    }

    func stop() {
        pause()
        for watch in watches { NotificationCenter.default.removeObserver(watch) }
        watches = []
    }

    fileprivate func tick(_ link: CADisplayLink) {
        guard let inputs, let clock else { return }
        let now = link.timestamp
        let target = targetFps(inputs.focused ? .focused : .unfocused, inputs.fpsLimit, powerSave: lowPower)
        let nanos = Int(now * 1e9)
        let due = clock.tick(nanos, target: target, bpm: inputs.bpm, speed: inputs.speed, moving: inputs.moving)
        let dollyMoving = closingAt != nil || now - openedAt < 0.85
        if due || dollyMoving { draw(now) }
        if !drawnFirst && now - openedAt > 1.5 { fadeIn(now) }
        updateFade(now)
        if !clock.busy(inputs.moving) && !dollyMoving && fadeInFrom.map({ now - $0 > 0.5 }) != false { pause() }
    }

    /// The way in and out: in over 0.8 s after 0.02 s, quick then settling; out over 0.5 s, slow
    /// then quick.
    private func dolly(_ now: CFTimeInterval) -> Float {
        if let closingAt {
            let t = min(max((now - closingAt) / 0.5, 0), 1)
            let opened = min(max((closingAt - openedAt - 0.02) / 0.8, 0), 1)
            let start = Float(Easing.cubicBezier(0.22, 1, 0.36, 1, opened))
            return start * Float(1 - Easing.cubicBezier(0.64, 0, 0.78, 0, t))
        }
        let t = min(max((now - openedAt - 0.02) / 0.8, 0), 1)
        return Float(Easing.cubicBezier(0.22, 1, 0.36, 1, t))
    }

    private func fadeIn(_ now: CFTimeInterval) {
        guard fadeInFrom == nil else { return }
        fadeInFrom = now
    }

    private func updateFade(_ now: CFTimeInterval) {
        guard let from = fadeInFrom else { return }
        canvas.alpha = CGFloat(min(max((now - from) / 0.5, 0), 1))
    }

    private func draw(_ now: CFTimeInterval) {
        guard let gpu, let clock, let oldTexture, let newTexture, bounds.width > 0, bounds.height > 0,
              let drawable = canvas.metal.nextDrawable(), let buffer = gpu.queue.makeCommandBuffer()
        else { return }
        if square == nil { square = gpu.square() }
        if blurred == nil { blurred = gpu.square() }
        guard let square, let blurred else { return }
        let motion = clock.motion
        let b = motion.breathing
        var placement = [Float](repeating: 0, count: 6 * WashCopies.count)
        for (i, copy) in WashCopies.enumerated() { copyPlacement(copy, motion.time, motion.rotation, b, &placement, i * 6) }
        var uniforms = [Float](repeating: 0, count: 8 * 4 + 8 * 4 + 4)
        for i in 0..<WashCopies.count {
            uniforms[i * 4] = placement[i * 6]
            uniforms[i * 4 + 1] = placement[i * 6 + 1]
            uniforms[i * 4 + 2] = placement[i * 6 + 2]
            uniforms[i * 4 + 3] = placement[i * 6 + 3]
            uniforms[32 + i * 4] = placement[i * 6 + 4]
            uniforms[32 + i * 4 + 1] = placement[i * 6 + 5]
        }
        uniforms[64] = motion.rotation
        uniforms[65] = motion.warpPhase
        uniforms[66] = clock.fade.mix
        pass(buffer, gpu.composite, into: square) { encoder in
            encoder.setFragmentTexture(oldTexture, index: 0)
            encoder.setFragmentTexture(newTexture, index: 1)
            encoder.setFragmentBytes(uniforms, length: uniforms.count * 4, index: 0)
        }
        pass(buffer, gpu.blurAcross, into: blurred) { $0.setFragmentTexture(square, index: 0) }
        pass(buffer, gpu.blurDown, into: square) { $0.setFragmentTexture(blurred, index: 0) }
        let size = canvas.metal.drawableSize
        let screen: [Float] = [Float(size.width), Float(size.height), motion.turn, 2 * b * dollyScale(dolly(now)), FinalGain * (inputs?.gain ?? 1),
                               Float.random(in: 0..<64), 0, 0]
        pass(buffer, gpu.finalPass, into: drawable.texture) { encoder in
            encoder.setFragmentTexture(square, index: 0)
            encoder.setFragmentBytes(screen, length: screen.count * 4, index: 0)
        }
        buffer.present(drawable)
        buffer.commit()
        if !drawnFirst {
            drawnFirst = true
            fadeIn(now)
        }
    }

    private func pass(_ buffer: MTLCommandBuffer, _ pipeline: MTLRenderPipelineState, into target: MTLTexture,
                      _ setUp: (MTLRenderCommandEncoder) -> Void) {
        let description = MTLRenderPassDescriptor()
        description.colorAttachments[0].texture = target
        description.colorAttachments[0].loadAction = .dontCare
        description.colorAttachments[0].storeAction = .store
        guard let encoder = buffer.makeRenderCommandEncoder(descriptor: description) else { return }
        encoder.setRenderPipelineState(pipeline)
        setUp(encoder)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }
}

/// Holds the view weakly, so the display link never keeps it alive.
@MainActor
private final class WashTarget: NSObject {
    weak var view: WashView?

    init(_ view: WashView) { self.view = view }

    @objc func tick(_ link: CADisplayLink) {
        guard let view else {
            link.invalidate()
            return
        }
        view.tick(link)
    }
}

// MARK: The classic mesh

/// Four soft pools of the artwork's colors that drift around the corners. Time moves forward at
/// full pace while music plays and at 0.15 while paused, the pace easing over 1.2 s; it stops
/// while the app is out of view. Colors ease to each song's over 0.52 s.
struct ClassicMesh: UIViewRepresentable {
    let colors: [UInt32]
    let playing: Bool
    /// The player is opening, pulled or closing: the mesh draws every frame meanwhile.
    var moving = false

    func makeUIView(context: Context) -> MeshView { MeshView() }

    func updateUIView(_ view: MeshView, context: Context) { view.update(colors: colors, playing: playing, moving: moving) }

    static func dismantleUIView(_ view: MeshView, coordinator: ()) { view.stop() }
}

final class MeshView: UIView {
    private let canvas = MetalCanvas()
    private let gpu = WashGPU.shared
    private var link: CADisplayLink?
    private var time: Float = 0
    private var pace: Float = 1
    private var paceFrom: Float = 1
    private var paceTo: Float = 1
    private var paceAt: CFTimeInterval = 0
    private var colorFrom: [SIMD4<Float>] = []
    private var colorTo: [SIMD4<Float>] = []
    private var colorAt: CFTimeInterval = 0
    private var last: CFTimeInterval?
    private var drawnAt: CFTimeInterval?
    private var moving = false
    private var watches: [NSObjectProtocol] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        canvas.metal.pixelFormat = .bgra8Unorm
        canvas.metal.framebufferOnly = true
        if let gpu { canvas.metal.device = gpu.device }
        addSubview(canvas)
        let center = NotificationCenter.default
        watches.append(center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.pause() }
        })
        watches.append(center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.start() }
        })
        start()
    }

    required init?(coder: NSCoder) { nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        canvas.frame = bounds
    }

    func update(colors: [UInt32], playing: Bool, moving: Bool) {
        if moving != self.moving {
            self.moving = moving
            link?.preferredFrameRateRange = frameRange
        }
        let now = CACurrentMediaTime()
        let next = colors.map { c in SIMD4<Float>(Float((c >> 16) & 0xFF) / 255, Float((c >> 8) & 0xFF) / 255, Float(c & 0xFF) / 255, 1) }
        if colorTo.isEmpty {
            colorFrom = next
            colorTo = next
        } else if next != colorTo {
            colorFrom = shownColors(now)
            colorTo = next
            colorAt = now
        }
        let target: Float = playing ? 1 : 0.15
        if target != paceTo {
            paceFrom = pace
            paceTo = target
            paceAt = now
        }
    }

    private func shownColors(_ now: CFTimeInterval) -> [SIMD4<Float>] {
        let t = Float(min(max((now - colorAt) / 0.52, 0), 1))
        let eased = Float(Easing.fastOutSlowIn(Double(t)))
        return zip(colorFrom, colorTo).map { $0 + ($1 - $0) * eased }
    }

    private func start() {
        guard link == nil else { return }
        last = nil
        drawnAt = nil
        let link = CADisplayLink(target: MeshTarget(self), selector: #selector(MeshTarget.tick(_:)))
        link.preferredFrameRateRange = frameRange
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    /// At rest the mesh paces itself; while the player moves it asks for the screen's full rate.
    private var frameRange: CAFrameRateRange {
        moving
            ? CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
            : CAFrameRateRange(minimum: 10, maximum: 120, preferred: Float(meshFullFps))
    }

    private func pause() {
        link?.invalidate()
        link = nil
    }

    func stop() {
        pause()
        for watch in watches { NotificationCenter.default.removeObserver(watch) }
        watches = []
    }

    fileprivate func tick(_ link: CADisplayLink) {
        let now = link.timestamp
        let t = Float(min(max((now - paceAt) / 1.2, 0), 1))
        pace = paceFrom + (paceTo - paceFrom) * Float(Easing.fastOutSlowIn(Double(t)))
        if let last { time += Float(now - last) * pace }
        last = now
        // A slow flow needs few frames: 30 a second at full speed, down to 10 paused, and every
        // frame while the player moves. A twentieth short, so a frame landing a hair early still
        // counts.
        let step = meshFrameStep(pace, moving: moving)
        if let drawnAt, step > 0, now - drawnAt < step - step / 20 { return }
        drawnAt = now
        draw(now)
    }

    private func draw(_ now: CFTimeInterval) {
        guard let gpu, bounds.width > 0, colorTo.count == 4, let drawable = canvas.metal.nextDrawable(),
              let buffer = gpu.queue.makeCommandBuffer()
        else { return }
        let colors = shownColors(now)
        let size = canvas.metal.drawableSize
        var uniforms: [Float] = [Float(size.width), Float(size.height), time, 0]
        for color in colors { uniforms += [color.x, color.y, color.z, 1] }
        let description = MTLRenderPassDescriptor()
        description.colorAttachments[0].texture = drawable.texture
        description.colorAttachments[0].loadAction = .dontCare
        description.colorAttachments[0].storeAction = .store
        guard let encoder = buffer.makeRenderCommandEncoder(descriptor: description) else { return }
        encoder.setRenderPipelineState(gpu.mesh)
        encoder.setFragmentBytes(uniforms, length: uniforms.count * 4, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        buffer.present(drawable)
        buffer.commit()
    }
}

@MainActor
private final class MeshTarget: NSObject {
    weak var view: MeshView?

    init(_ view: MeshView) { self.view = view }

    @objc func tick(_ link: CADisplayLink) {
        guard let view else {
            link.invalidate()
            return
        }
        view.tick(link)
    }
}
