import AVFoundation
import OctoKit

/// Brings the music back when headphones connect, as the listener asked: wired and Bluetooth
/// each on their own switch, and either only after the music stopped because the output went
/// away, or always. It waits a moment for the sound to move to the new output, and checks the
/// output is still there.
@MainActor
final class HeadsetWatch {
    private unowned let player: Player
    /// Outputs seen before, so only a new one counts.
    private var known: Set<String>
    /// When the music stopped because the output went away, in ms since 1970.
    private(set) var lostOutputAt: Int?
    private var waiting: Task<Void, Never>?

    init(player: Player) {
        self.player = player
        known = Set(AVAudioSession.sharedInstance().currentRoute.outputs.map(\.uid))
    }

    /// Whether any resume switch is on, so the music waits longer after a pause.
    var anyOn: Bool {
        let prefs = AppSettings.shared.player
        return prefs.resumeWired || prefs.resumeBluetooth
    }

    func routeChanged(_ reason: AVAudioSession.RouteChangeReason, now: [AVAudioSessionPortDescription],
                      before: [AVAudioSessionPortDescription]) {
        defer { known = Set(now.map(\.uid)) }
        switch reason {
        case .oldDeviceUnavailable:
            // Headphones pulled out: stop rather than play out loud.
            let wasPlaying = player.engine.playWhenReady
            player.pause()
            if wasPlaying { lostOutputAt = epochMs() }
        case .newDeviceAvailable:
            for output in now where !known.contains(output.uid) {
                guard let kind = headsetKind(portType: output.portType.rawValue) else { continue }
                connected(kind, uid: output.uid)
            }
        default:
            break
        }
    }

    /// Any other pause, or playing again, forgets when the output went away.
    func forgetLoss() {
        lostOutputAt = nil
    }

    private func connected(_ kind: HeadsetKind, uid: String) {
        waiting?.cancel()
        let settle = kind == .bluetooth ? bluetoothSettleMs : wiredSettleMs
        waiting = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(settle))
            guard !Task.isCancelled, let self else { return }
            // The output must still be there once the sound has moved.
            guard AVAudioSession.sharedInstance().currentRoute.outputs.contains(where: { $0.uid == uid }) else { return }
            let prefs = AppSettings.shared.player
            let resume = ResumePrefs(resumeWired: prefs.resumeWired, resumeBluetooth: prefs.resumeBluetooth, resumeAlways: prefs.resumeAlways)
            let engine = self.player.engine
            if shouldResumeOnConnect(kind, prefs: resume, playing: engine.playWhenReady, hasQueue: !engine.queue.isEmpty,
                                     lostOutputAt: self.lostOutputAt, now: self.epochMs()) {
                self.player.resume()
            }
        }
    }

    private func epochMs() -> Int { Int(Date().timeIntervalSince1970 * 1000) }
}
