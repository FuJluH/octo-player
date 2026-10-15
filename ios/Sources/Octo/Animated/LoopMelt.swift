import AVFoundation
import CoreImage
import UIKit

/// The Full screen look, baked into every frame of the tall loop. The loop sits at the top at the
/// screen's width and its own shape, opaque to its own bottom edge F, and goes out of focus down
/// the screen (a blur that grows, never a fade over sharp art). Below F a mirror image of its own
/// bottom edge carries on, blurred further, and gives way over a short band to a copy of the loop
/// covering the whole screen, blurred deep; both a little more saturated. Black shading deepens
/// gently from just above the title to the bottom. Every position is tied to the screen's width
/// and to F, so the melt lands on the same part of the picture on any phone.
final class LoopMelt: @unchecked Sendable {
    /// The frame drawn, in pixels: the screen's shape at `scale` pixels per point.
    let renderSize: CGSize
    private let scale: CGFloat
    private let width: CGFloat
    private let height: CGFloat
    /// F, the loop's own bottom edge, in points from the top.
    private let frameBottom: CGFloat
    private let blurMask: CIImage
    private let blendMask: CIImage
    private let saturateMask: CIImage
    private let lock = NSLock()
    private var darkMask: CIImage
    private var capped = false
    /// The deepest blur, in points: the cover copy's, and the extension's from F + 0.14 W down.
    private let deepest: CGFloat

    /// For a screen `screen` points big, a loop `shape` tall for each point of width (4:3 is
    /// 1.333), drawn at `scale` pixels per point.
    init(screen: CGSize, shape: CGFloat, scale: CGFloat) {
        width = screen.width
        height = screen.height
        self.scale = scale
        renderSize = CGSize(width: (screen.width * scale).rounded(), height: (screen.height * scale).rounded())
        let w = screen.width
        let f = (w * shape).rounded()
        frameBottom = f
        // Blur values were measured on a 430 pt wide screen; they grow with the width.
        let k = w / 430
        deepest = 40 * k
        // 2a: the blur down the loop, as sigma in points, by place from the top.
        let sigma: [(CGFloat, CGFloat)] = [
            (0, 0), (0.80 * f, 0), (0.83 * f, 1), (0.845 * f, 1.5), (0.86 * f, 3), (0.88 * f, 5), (0.90 * f, 8),
            (0.97 * f, 8), (f, 14), (f + 0.07 * w, 24), (f + 0.14 * w, 40),
        ].map { ($0.0, $0.1 * k) }
        // 2b: how much of the loop (and below F its mirrored extension) shows over the cover copy.
        let blend: [(CGFloat, CGFloat)] = [
            (0, 1), (f, 1), (f + 0.019 * w, 0.90), (f + 0.037 * w, 0.74), (f + 0.056 * w, 0.55), (f + 0.074 * w, 0.38),
            (f + 0.098 * w, 0.20), (f + 0.130 * w, 0),
        ]
        // Saturation x1.10 on the loop below u 0.90.
        let saturate: [(CGFloat, CGFloat)] = [(0, 0), (0.89 * f, 0), (0.90 * f, 1)]
        let size = renderSize
        let px = scale
        blurMask = Self.column(sigma.map { ($0.0, $0.1 / (40 * k)) }, size: size, scale: px)
        blendMask = Self.column(blend, size: size, scale: px)
        saturateMask = Self.column(saturate, size: size, scale: px)
        darkMask = Self.column(Self.darkStops(width: w, height: screen.height, frameBottom: f, lift: nil), size: size, scale: px)
    }

    /// 4: the black over everything. Clean to the top edge (no dim there), nothing until u 0.78,
    /// then easing in and deepening to the bottom. `lift` raises the stops from u 0.90 to
    /// F + 0.14 W for a light album, so the words keep their contrast.
    static func darkStops(width w: CGFloat, height h: CGFloat, frameBottom f: CGFloat, lift: CGFloat?) -> [(CGFloat, CGFloat)] {
        func at(_ alpha: CGFloat) -> CGFloat { max(alpha, lift ?? 0) }
        return [
            (0, 0), (0.78 * f, 0), (0.84 * f, 0.08), (0.90 * f, at(0.18)), (f, at(0.26)), (f + 0.14 * w, at(0.32)),
            (0.75 * h, max(0.35, lift ?? 0)), (0.87 * h, max(0.40, lift ?? 0)), (h, max(0.46, lift ?? 0)),
        ].sorted { $0.0 < $1.0 }
    }

    /// The video composition that draws the look into each frame of `asset`.
    func composition(for asset: AVAsset) async -> AVVideoComposition? {
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let duration = try? await asset.load(.duration)
        else { return nil }
        let rate = (try? await track.load(.nominalFrameRate)) ?? 24
        let instruction = MeltInstruction(timeRange: CMTimeRange(start: .zero, duration: duration), trackID: track.trackID, melt: self)
        let configuration = AVVideoComposition.Configuration(
            customVideoCompositorClass: MeltCompositor.self,
            frameDuration: CMTime(value: 1, timescale: CMTimeScale(rate > 0 ? rate.rounded() : 24)),
            instructions: [instruction], renderSize: renderSize)
        return AVVideoComposition(configuration: configuration)
    }

    /// The look drawn into one frame of the loop (or its still).
    func render(_ frame: CIImage) -> CIImage {
        let bounds = CGRect(origin: .zero, size: renderSize)
        let src = frame.transformed(by: CGAffineTransform(translationX: -frame.extent.minX, y: -frame.extent.minY))
        let size = src.extent.size
        guard size.width > 0, size.height > 0 else { return CIImage(color: .black).cropped(to: bounds) }
        let fit = renderSize.width / size.width
        let fPixels = frameBottom * scale
        // The loop at the top, at the screen's width, and below F its mirror image.
        let loop = src.transformed(by: CGAffineTransform(scaleX: fit, y: fit))
            .transformed(by: CGAffineTransform(translationX: 0, y: renderSize.height - fPixels))
        let mirror = src.transformed(by: CGAffineTransform(scaleX: fit, y: -fit))
            .transformed(by: CGAffineTransform(translationX: 0, y: renderSize.height - fPixels))
        let extended = loop.composited(over: mirror).cropped(to: bounds)
        // The blur that grows down the screen, drawn only where it is more than nothing.
        let sharpUntil = renderSize.height - 0.80 * fPixels + 2
        let band = CGRect(x: 0, y: 0, width: renderSize.width, height: sharpUntil)
        let blurred = extended.clampedToExtent()
            .applyingFilter("CIMaskedVariableBlur", parameters: ["inputMask": blurMask, "inputRadius": deepest * scale])
            .cropped(to: band)
        let livelier = blurred.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.10])
        let bandDrawn = livelier.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: blurred, kCIInputMaskImageKey: saturateMask])
        let melted = bandDrawn.composited(over: extended).cropped(to: bounds)
        // The cover copy: the loop covering the whole screen, blurred deep from an eighth-size
        // copy, a little more saturated.
        let cover = max(renderSize.width / size.width, renderSize.height / size.height)
        let eighth = cover / 8
        let small = src.transformed(by: CGAffineTransform(scaleX: eighth, y: eighth))
        let smallBlur = small.clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: deepest * scale / 8])
            .cropped(to: small.extent)
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.10])
        let coverCopy = smallBlur.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        let centered = coverCopy.transformed(by: CGAffineTransform(
            translationX: (renderSize.width - coverCopy.extent.width) / 2 - coverCopy.extent.minX,
            y: (renderSize.height - coverCopy.extent.height) / 2 - coverCopy.extent.minY))
            .clampedToExtent().cropped(to: bounds)
        let joined = melted.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: centered, kCIInputMaskImageKey: blendMask])
        let dark = lock.withLock { darkMask }
        let black = CIImage(color: .black).cropped(to: bounds)
        // The shading was measured on screen values, so it is laid on in sRGB, not in light.
        let screenValues = joined.applyingFilter("CILinearToSRGBToneCurve")
        let shaded = black.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: screenValues, kCIInputMaskImageKey: dark])
            .applyingFilter("CISRGBToneCurveToLinear")
        capIfLight(screenValues)
        return shaded.cropped(to: bounds)
    }

    /// For a light album, once: when the band under the words (u 0.90 down to the times, about
    /// F + 0.25 W) reads brighter than 80 of 255 after the shading, the shading there is raised so
    /// it reads at 80.
    private func capIfLight(_ undimmed: CIImage) {
        let first = lock.withLock { () -> Bool in
            if capped { return false }
            capped = true
            return true
        }
        guard first else { return }
        let top = 0.90 * frameBottom
        let bottom = frameBottom + 0.25 * width
        let rect = CGRect(x: 0, y: renderSize.height - bottom * scale, width: renderSize.width, height: (bottom - top) * scale)
        guard let luma = Self.averageLuma(undimmed, in: rect) else { return }
        let dimmed = luma * (1 - 0.26)
        guard dimmed > 80 else { return }
        let lift = 1 - 80 / luma
        let mask = Self.column(Self.darkStops(width: width, height: height, frameBottom: frameBottom, lift: lift), size: renderSize, scale: scale)
        lock.withLock { darkMask = mask }
    }

    private static let measuring = CIContext(options: [.workingColorSpace: NSNull()])

    /// The Rec. 709 luma (0 to 255) of a part of a picture, averaged.
    private static func averageLuma(_ image: CIImage, in rect: CGRect) -> CGFloat? {
        let average = image.applyingFilter("CIAreaAverage", parameters: [kCIInputExtentKey: CIVector(cgRect: rect)])
        var pixel = [UInt8](repeating: 0, count: 4)
        measuring.render(average, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                         format: .RGBA8, colorSpace: nil)
        return 0.2126 * CGFloat(pixel[0]) + 0.7152 * CGFloat(pixel[1]) + 0.0722 * CGFloat(pixel[2])
    }

    /// A gray picture the size of the frame, its value at each height following `stops` (points
    /// from the top), straight between them.
    private static func column(_ stops: [(CGFloat, CGFloat)], size: CGSize, scale: CGFloat) -> CIImage {
        let rows = max(Int(size.height), 1)
        var bytes = [UInt8](repeating: 0, count: rows)
        for row in 0..<rows {
            let y = (CGFloat(row) + 0.5) / scale
            var value = stops.last?.1 ?? 0
            for (a, b) in zip(stops, stops.dropFirst()) where y >= a.0 && y <= b.0 {
                let t = b.0 > a.0 ? (y - a.0) / (b.0 - a.0) : 1
                value = a.1 + (b.1 - a.1) * t
                break
            }
            if let first = stops.first, y < first.0 { value = first.1 }
            bytes[row] = UInt8((min(max(value, 0), 1) * 255).rounded())
        }
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        let picture = CGImage(width: 1, height: rows, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: 1,
                              space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                              provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        return CIImage(cgImage: picture, options: [.colorSpace: NSNull()])
            .samplingNearest()
            .transformed(by: CGAffineTransform(scaleX: size.width, y: 1))
            .cropped(to: CGRect(origin: .zero, size: size))
    }

    /// The look drawn into a still, for showing before the loop's first frame.
    func still(_ picture: UIImage) -> UIImage? {
        guard let source = picture.cgImage else { return nil }
        let drawn = render(CIImage(cgImage: source))
        guard let made = Self.drawing.createCGImage(drawn, from: CGRect(origin: .zero, size: renderSize)) else { return nil }
        return UIImage(cgImage: made)
    }

    private static let drawing = CIContext()
}

/// The one instruction of a melted loop: the whole loop, drawn from its video track by its melt.
final class MeltInstruction: NSObject, AVVideoCompositionInstructionProtocol, @unchecked Sendable {
    let timeRange: CMTimeRange
    let enablePostProcessing = false
    let containsTweening = true
    let requiredSourceTrackIDs: [NSValue]?
    let passthroughTrackID = kCMPersistentTrackID_Invalid
    let trackID: CMPersistentTrackID
    let melt: LoopMelt

    init(timeRange: CMTimeRange, trackID: CMPersistentTrackID, melt: LoopMelt) {
        self.timeRange = timeRange
        self.trackID = trackID
        self.melt = melt
        requiredSourceTrackIDs = [NSNumber(value: trackID)]
    }
}

/// Draws each frame of a melted loop with Core Image on the GPU, at the screen's shape.
final class MeltCompositor: NSObject, AVVideoCompositing, @unchecked Sendable {
    private static let pixels: [String: any Sendable] = [
        kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
        kCVPixelBufferIOSurfacePropertiesKey as String: [String: Int](),
    ]
    let sourcePixelBufferAttributes: [String: any Sendable]? = MeltCompositor.pixels
    let requiredPixelBufferAttributesForRenderContext: [String: any Sendable] = MeltCompositor.pixels
    private let context = CIContext()
    private let screen = CGColorSpace(name: CGColorSpace.sRGB)

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {}

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        guard let instruction = request.videoCompositionInstruction as? MeltInstruction,
              let source = request.sourceFrame(byTrackID: instruction.trackID),
              let out = request.renderContext.newPixelBuffer()
        else {
            request.finish(with: NSError(domain: "app.winters.octo.melt", code: 1))
            return
        }
        let drawn = instruction.melt.render(CIImage(cvPixelBuffer: source))
        context.render(drawn, to: out, bounds: CGRect(origin: .zero, size: instruction.melt.renderSize), colorSpace: screen)
        request.finish(withComposedVideoFrame: out)
    }
}
