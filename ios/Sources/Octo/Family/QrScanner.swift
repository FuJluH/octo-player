@preconcurrency import AVFoundation
import CoreImage
import OctoKit
import SwiftUI
import Vision

/// The family QR scanner: the back camera full screen behind a square guide, the line saying
/// what to do, and Cancel. The first family link read closes it with that link.
struct QrScanner: View {
    let found: (FamilyLink) -> Void
    let cancel: () -> Void
    @State private var reader = QrReader()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if reader.allowed == true, reader.problem == nil {
                CameraPreview(session: reader.session)
                    .ignoresSafeArea()
                    .accessibilityHidden(true)
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.8), lineWidth: 2)
                    .frame(width: 240, height: 240)
                    .accessibilityHidden(true)
            }
            VStack(spacing: 12) {
                Spacer()
                Text(line)
                    .font(.octoBody)
                    .foregroundStyle(OctoColor.textPrimary)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.updatesFrequently)
                GlazeButton("Cancel", size: .medium) {
                    reader.stop()
                    cancel()
                }
            }
            .padding(24)
        }
        .task {
            reader.found = { link in
                reader.stop()
                found(link)
            }
            await reader.start()
        }
        .onDisappear { reader.stop() }
    }

    /// In priority: the camera not starting, the camera refused, not yet allowed, a code that
    /// is not a family link, then the hold line.
    private var line: String {
        if reader.problem != nil { return "The camera did not start. Type the code instead." }
        if reader.allowed == false { return "Octo can't use the camera. Allow it in the phone's settings, or type the code." }
        if reader.allowed == nil { return "Allow the camera to scan the code." }
        if reader.wrongCode { return "That QR code is not a family link. Show the one from Devices or an invite." }
        return "Hold the family QR code inside the square."
    }
}

/// Runs the back camera and reads QR codes from its frames, the latest one only, as they are
/// and with light and dark swapped.
@MainActor
@Observable
final class QrReader {
    /// Nil until the camera permission is answered.
    private(set) var allowed: Bool?
    private(set) var problem: String?
    /// A code was read that is not a family link; stays until a family link is read.
    private(set) var wrongCode = false
    @ObservationIgnored var found: ((FamilyLink) -> Void)?
    @ObservationIgnored let session = AVCaptureSession()
    @ObservationIgnored private let frames = QrFrames()
    @ObservationIgnored private var done = false

    func start() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: allowed = true
        case .notDetermined: allowed = await AVCaptureDevice.requestAccess(for: .video)
        default: allowed = false
        }
        guard allowed == true else { return }
        frames.read = { [weak self] text in
            Task { @MainActor in self?.take(text) }
        }
        let session = session
        let frames = frames
        let started = await Task.detached { () -> Bool in
            guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let input = try? AVCaptureDeviceInput(device: camera) else { return false }
            session.beginConfiguration()
            session.sessionPreset = .high
            guard session.canAddInput(input) else {
                session.commitConfiguration()
                return false
            }
            session.addInput(input)
            let output = AVCaptureVideoDataOutput()
            output.alwaysDiscardsLateVideoFrames = true
            output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
            output.setSampleBufferDelegate(frames, queue: frames.queue)
            guard session.canAddOutput(output) else {
                session.commitConfiguration()
                return false
            }
            session.addOutput(output)
            session.commitConfiguration()
            session.startRunning()
            return session.isRunning
        }.value
        if !started { problem = "The camera did not start." }
    }

    func stop() {
        frames.stopped = true
        let session = session
        Task.detached { if session.isRunning { session.stopRunning() } }
    }

    private func take(_ text: String) {
        guard !done else { return }
        if let link = parseFamilyLink(text) {
            done = true
            wrongCode = false
            found?(link)
        } else {
            wrongCode = true
        }
    }
}

/// Reads one frame at a time on its own queue; frames that arrive while one is read are dropped.
final class QrFrames: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let queue = DispatchQueue(label: "app.winters.octo.qr")
    var read: (@Sendable (String) -> Void)?
    var stopped = false
    private let context = CIContext()
    private let invert = CIFilter(name: "CIColorInvert")

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard !stopped, let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        if let text = decode(CIImage(cvPixelBuffer: pixels)) {
            read?(text)
        }
    }

    /// The text of the first QR code in a frame, read as it is and then with light and dark
    /// swapped, or nil when there is none.
    private func decode(_ image: CIImage) -> String? {
        if let text = detect(image) { return text }
        guard let invert else { return nil }
        invert.setValue(image, forKey: kCIInputImageKey)
        guard let swapped = invert.outputImage, let drawn = context.createCGImage(swapped, from: image.extent) else { return nil }
        return detect(CIImage(cgImage: drawn))
    }

    private func detect(_ image: CIImage) -> String? {
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]
        let handler = VNImageRequestHandler(ciImage: image, options: [:])
        guard (try? handler.perform([request])) != nil else { return nil }
        return request.results?.lazy.compactMap(\.payloadStringValue).first
    }
}

/// The camera's picture, filling its frame.
private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.preview.session = session
        view.preview.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var preview: AVCaptureVideoPreviewLayer {
            // The layer class above makes this layer a preview layer.
            layer as? AVCaptureVideoPreviewLayer ?? AVCaptureVideoPreviewLayer()
        }
    }
}
