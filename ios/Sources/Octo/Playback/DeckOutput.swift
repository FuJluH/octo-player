import AVFoundation
import OctoKit

/// The sound going out: one audio engine both decks play into, the phone's audio session, and
/// what the system says about it (a call, another app, headphones coming and going, a new
/// output). Both decks share the one session.
@MainActor
final class DeckOutput {
    let engine = AVAudioEngine()
    private let decks: [Deck]
    /// Whether the engine should be running: music plays, or it waits silent a while after a pause.
    private var wanted = false
    private var stopTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []

    /// A call or another app took the sound (`began`), or gave it back (`shouldResume` when the
    /// system says playing may go on).
    var onInterruption: ((_ began: Bool, _ shouldResume: Bool) -> Void)?
    /// The output changed: why, and the outputs now and before.
    var onRouteChange: ((_ reason: AVAudioSession.RouteChangeReason, _ now: [AVAudioSessionPortDescription],
                         _ before: [AVAudioSessionPortDescription]) -> Void)?

    init(decks: [Deck]) {
        self.decks = decks
        for deck in decks { connect(deck) }
        engine.prepare()
        listen()
    }

    private func connect(_ deck: Deck) {
        let format = AVAudioFormat(standardFormatWithSampleRate: deckRate, channels: 2)
        engine.attach(deck.node)
        engine.attach(deck.timePitch)
        engine.connect(deck.node, to: deck.timePitch, format: format)
        engine.connect(deck.timePitch, to: engine.mainMixerNode, format: format)
    }

    /// How starting the sound went.
    enum Start {
        case started
        /// The system would not give the sound (a call is on).
        case refused
        /// The sound device would not start.
        case failed
    }

    /// Starts the sound: the session for long playback, then the engine.
    @discardableResult
    func start() -> Start {
        stopTask?.cancel()
        stopTask = nil
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, policy: .longFormAudio)
            try session.setActive(true)
        } catch {
            playbackLog.info("audio session refused: \(String(describing: error), privacy: .public)")
            return .refused
        }
        wanted = true
        if !engine.isRunning {
            do {
                try engine.start()
            } catch {
                playbackLog.info("audio engine did not start: \(String(describing: error), privacy: .public)")
                return .failed
            }
        }
        updateDelays()
        return .started
    }

    /// Lets the engine stop once it has stayed silent for `after` seconds; playing again before
    /// then keeps it.
    func stopLater(after seconds: Double) {
        stopTask?.cancel()
        stopTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.stopNow()
        }
    }

    /// Stops the engine and gives the sound back to other apps.
    func stopNow() {
        stopTask?.cancel()
        stopTask = nil
        wanted = false
        engine.pause()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    var isRunning: Bool { engine.isRunning }

    /// The time between a deck handing out sound and it being heard, for each deck's position.
    func updateDelays() {
        let session = AVAudioSession.sharedInstance()
        let device = session.outputLatency + session.ioBufferDuration
        for deck in decks {
            let stage = deck.timePitch.bypass ? 0 : deck.timePitch.latency
            deck.outputDelayMs = (device + stage) * 1000
        }
    }

    private func listen() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let type = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init)
            let options = (note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt).map(AVAudioSession.InterruptionOptions.init)
            MainActor.assumeIsolated {
                guard let self, let type else { return }
                self.onInterruption?(type == .began, options?.contains(.shouldResume) == true)
            }
        })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            let reason = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt).flatMap(AVAudioSession.RouteChangeReason.init)
            let before = (note.userInfo?[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription)?.outputs ?? []
            MainActor.assumeIsolated {
                guard let self, let reason else { return }
                self.updateDelays()
                self.onRouteChange?(reason, AVAudioSession.sharedInstance().currentRoute.outputs, before)
            }
        })
        observers.append(center.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                // The output changed under the engine (a new device, another rate): it stopped, so
                // it starts again when it should be running.
                guard let self, self.wanted, !self.engine.isRunning else { return }
                try? self.engine.start()
                self.updateDelays()
            }
        })
        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.engine.stop()
                if self.wanted { self.start() }
            }
        })
    }
}
