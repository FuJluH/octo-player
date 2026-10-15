import AVFoundation
import OctoKit

/// The one player the rest of the app sees: the lock screen, the car, headphones and the app all
/// talk to this. It holds the queue, forwards to the deck that is playing, and hands over to the
/// other deck for a crossfade without anything outside noticing. It also answers calls and other
/// apps taking the sound.
@MainActor
final class PlaybackEngine: @preconcurrency SleepTarget {
    private(set) var deck: Deck
    private(set) var queue = PlayQueue()
    let output: DeckOutput
    let lengths: RealLengths
    private(set) var crossfader: Crossfader!
    private let decks: [Deck]
    private let streamContextNow: @MainActor () -> StreamContext

    /// What the player wants: playing, or paused.
    private(set) var playWhenReady = false
    /// The song stopped at its end (the sleep timer's end of song); playing again moves on.
    private var stoppedAtEnd = false
    /// The queue played out.
    private(set) var ended = false
    private var resumeWhenFocusReturns = false
    private var lastIsPlaying = false
    private var lastState: DeckState = .idle
    private var lengthTold: String?
    private var ticker: Timer?

    // MARK: What the player hears of

    /// The song on now changed, and why.
    var onSongChange: ((SongChange) -> Void)?
    /// Music started or stopped being heard.
    var onIsPlayingChange: ((Bool) -> Void)?
    /// The wish to play changed; `endOfSong` when it stopped by itself at the end of a song.
    var onPlayWhenReadyChange: ((_ playWhenReady: Bool, _ endOfSong: Bool) -> Void)?
    /// The queue's songs, order or modes changed.
    var onQueueChange: (() -> Void)?
    /// A song could not play.
    var onFailure: ((QueueItem, PlayError) -> Void)?
    /// Loading, ready or ended changed.
    var onStateChange: ((DeckState) -> Void)?
    /// The deck measured the song's length.
    var onLengthFound: ((QueueItem, Int) -> Void)?

    init(sound: SoundProcessor?, scout: Scout?, profiles: ServerProfiles?, lengths: RealLengths,
         keepActive: @escaping @Sendable () -> Bool, streamContext: @escaping @MainActor () -> StreamContext) {
        // Songs streamed last time the app ran are let go.
        try? FileManager.default.removeItem(at: FileManager.default.temporaryDirectory.appendingPathComponent("playing", isDirectory: true))
        let first = Deck(name: "A", sound: sound, keepActive: keepActive)
        let second = Deck(name: "B", sound: sound, keepActive: keepActive)
        second.volume = 0
        decks = [first, second]
        deck = first
        self.lengths = lengths
        streamContextNow = streamContext
        output = DeckOutput(decks: decks)
        crossfader = Crossfader(player: self, spare: second, scout: scout, profiles: profiles, lengths: lengths)
        output.onInterruption = { [weak self] began, shouldResume in self?.interruption(began: began, shouldResume: shouldResume) }
    }

    func streamContext() -> StreamContext { streamContextNow() }

    /// A deck's source for a song, at `startMs`.
    func makeSource(_ item: QueueItem, startMs: Int, setUp: SongSetUp? = nil) -> DeckSource {
        let scheme = URL(string: item.uri)?.scheme
        let local = parseStreamUri(item.uri) == nil && isLocalScheme(scheme)
        // The sound waiting is held long enough for the start-after wait at the fastest speed.
        let holdSeconds = max(15, Double(startAfterMs) / 1_000 * Double(Pace.fastestSpeed) / 0.75)
        return DeckSource(item: item, setUp: setUp ?? songSetUp?(item), startMs: startMs, outputRate: deckRate, isLocal: local,
                          holdSeconds: holdSeconds,
                          skipSilence: skipSilence,
                          open: SongOpener.opener(item, context: streamContext(), outputRate: deckRate))
    }

    /// How a song's loudness is judged, decided as it is set up to play, in play order.
    var songSetUp: ((QueueItem) -> SongSetUp)?

    // MARK: Settings on both decks

    /// Speed and pitch go to both decks, so a blend never jumps in pace.
    var pace = Pace(speed: 1, pitch: 1) {
        didSet {
            guard pace != oldValue else { return }
            crossfader.paceChanged()
            for each in decks { each.setPace(pace) }
            output.updateDelays()
        }
    }

    /// Skips quiet stretches inside songs, on both decks.
    var skipSilence = false {
        didSet { for each in decks { each.skipSilence = skipSilence } }
    }

    /// A change to start-after reaches every deck at once.
    var startAfterMs = 1_000 {
        didSet { for each in decks { each.startAfterMs = startAfterMs } }
    }

    var automix: AutomixSettings {
        get { crossfader.settings }
        set { crossfader.settings = newValue }
    }

    // MARK: SleepTarget

    var sleepFade: Float = 1 {
        didSet { applyVolume() }
    }

    var pauseAtEndOfSong: Bool {
        get { deck.pauseAtEndOfSong }
        set { deck.pauseAtEndOfSong = newValue }
    }

    var currentKey: String? { queue.currentItem?.entryId }
    var isBlending: Bool { crossfader.isBlending }

    func hasEntry(_ key: String) -> Bool { queue.position(ofEntry: key) != nil }

    // MARK: Where it is

    var currentItem: QueueItem? { queue.currentItem }
    var isPlaying: Bool { deck.isPlaying }
    var state: DeckState { ended ? .ended : deck.state }

    var positionMs: Int {
        guard queue.currentItem != nil else { return 0 }
        return deck.item == nil ? restoredPositionMs : deck.positionMs
    }

    /// Where a queue brought back without loading waits to start.
    private var restoredPositionMs = 0

    /// The deck's own measure of the song's length, when it has one.
    var measuredMs: Int? { deck.item?.entryId == queue.currentItem?.entryId ? deck.durationMs : nil }

    /// The format the deck found the song to be.
    var playingQuality: (codecMime: String?, bitDepth: Int?, sampleRate: Int?, bitrate: Int?)? { deck.current?.quality }

    // MARK: The queue

    /// A new queue, playing from `startIndex` at `startMs`. `shuffled` starts it in a random
    /// play order.
    func setQueue(_ items: [QueueItem], startIndex: Int, startMs: Int = 0, shuffled: Bool? = nil, play: Bool) {
        crossfader.interrupt()
        queue.setItems(items, startIndex: startIndex)
        if let shuffled { queue.shuffle = shuffled }
        if shuffled == true, let first = queue.firstIndex, startIndex < 0 { queue.setCurrent(first) }
        ended = false
        stoppedAtEnd = false
        let wasPlaying = playWhenReady
        // A queue put in place to carry on from elsewhere waits paused; so does one asked to play
        // while the system will not give the sound (a call).
        let playing = play && startOutput()
        playWhenReady = playing
        if playing || queue.currentItem?.isRadioStation != true {
            loadCurrent(atMs: startMs)
        } else {
            // A live station put in place paused is not opened until it plays.
            deck.clear()
        }
        onQueueChange?()
        onSongChange?(.playlistChanged)
        if playing {
            if !wasPlaying { onPlayWhenReadyChange?(true, false) }
        } else if wasPlaying {
            onPlayWhenReadyChange?(false, false)
        }
    }

    /// A queue brought back as it was left, paused, without loading anything until it plays.
    func restoreQueue(_ items: [QueueItem], order: [Int]?, index: Int, positionMs: Int, repeatMode: RepeatMode, shuffle: Bool) {
        crossfader.interrupt()
        deck.clear()
        queue.setItems(items, startIndex: index)
        if let order { queue.setPlayOrder(order) }
        queue.repeatMode = repeatMode
        queue.shuffle = shuffle
        playWhenReady = false
        ended = false
        stoppedAtEnd = false
        restoredPositionMs = max(0, positionMs)
        onQueueChange?()
        onSongChange?(.playlistChanged)
    }

    /// Loads the song on now on the playing deck, from `ms`.
    private func loadCurrent(atMs ms: Int) {
        guard let item = queue.currentItem else {
            deck.clear()
            return
        }
        lengthTold = nil
        restoredPositionMs = 0
        deck.setPace(pace)
        deck.skipSilence = skipSilence
        deck.startAfterMs = startAfterMs
        deck.load(makeSource(item, startMs: ms))
        deck.playWhenReady = playWhenReady
        applyVolume()
        ensureTicking()
    }

    func play() {
        guard !queue.isEmpty else { return }
        // Playing asks for the sound first: refused (a call is on), the player stays paused.
        guard startOutput() else { return }
        resumeWhenFocusReturns = false
        if ended {
            // The queue played out: it starts again from its first song.
            ended = false
            if let first = queue.firstIndex { queue.setCurrent(first) }
            playWhenReady = true
            loadCurrent(atMs: 0)
            onSongChange?(.seek)
        } else if stoppedAtEnd {
            stoppedAtEnd = false
            playWhenReady = true
            if let next = queue.nextOnEnd {
                queue.setCurrent(next)
                loadCurrent(atMs: 0)
                onSongChange?(.auto)
            } else {
                loadCurrent(atMs: 0)
            }
        } else {
            playWhenReady = true
            if deck.item == nil || deck.item?.entryId != queue.currentItem?.entryId {
                loadCurrent(atMs: restoredPositionMs)
            } else if deck.current?.failure != nil {
                // The song failed to load before: it is tried again from where it was.
                loadCurrent(atMs: deck.positionMs)
            } else {
                deck.playWhenReady = true
            }
        }
        onPlayWhenReadyChange?(true, false)
        ensureTicking()
    }

    func pause() {
        resumeWhenFocusReturns = false
        guard playWhenReady else { return }
        playWhenReady = false
        crossfader.interrupt()
        deck.playWhenReady = false
        dropLiveStream()
        onPlayWhenReadyChange?(false, false)
        stopOutputLater()
    }

    /// A live station stopped lets go of its stream, so playing again rejoins what is on air
    /// then instead of what was buffered when it stopped.
    private func dropLiveStream() {
        guard deck.item?.isRadioStation == true else { return }
        deck.clear()
    }

    /// Stops and empties the player.
    func stop() {
        crossfader.interrupt()
        playWhenReady = false
        deck.clear()
        onPlayWhenReadyChange?(false, false)
        output.stopNow()
    }

    func seek(toMs ms: Int) {
        guard queue.currentItem != nil else { return }
        crossfader.interrupt()
        ended = false
        stoppedAtEnd = false
        if deck.item == nil || deck.item?.entryId != queue.currentItem?.entryId {
            loadCurrent(atMs: ms)
        } else {
            deck.seek(toMs: ms)
            if playWhenReady { deck.playWhenReady = true }
        }
        crossfader.songChanged()
    }

    /// Plays the song at queue position `index` from `ms`.
    func seek(to index: Int, ms: Int = 0) {
        guard queue.items.indices.contains(index) else { return }
        crossfader.interrupt()
        ended = false
        stoppedAtEnd = false
        queue.setCurrent(index)
        loadCurrent(atMs: ms)
        crossfader.songChanged()
        onSongChange?(.seek)
    }

    /// Skips on, even when repeating one song.
    func next() {
        guard let next = queue.nextForSkip else { return }
        seek(to: next)
    }

    var hasNext: Bool { queue.nextForSkip != nil }

    /// Back to the start of the song, or to the one before when the song has barely begun.
    func previous() {
        if positionMs > 3_000 {
            seek(toMs: 0)
        } else if let before = queue.previousForSkip {
            seek(to: before)
        } else {
            seek(toMs: 0)
        }
    }

    var repeatMode: RepeatMode {
        get { queue.repeatMode }
        set {
            crossfader.interrupt()
            queue.repeatMode = newValue
            refreshFollowing()
            onQueueChange?()
        }
    }

    var shuffle: Bool {
        get { queue.shuffle }
        set {
            crossfader.interrupt()
            queue.shuffle = newValue
            refreshFollowing()
            onQueueChange?()
        }
    }

    /// Adds songs at `index` (at the end when nil), by the queue's rules for added songs.
    func add(_ items: [QueueItem], at index: Int? = nil) {
        guard !items.isEmpty else { return }
        if queue.isEmpty {
            setQueue(items, startIndex: 0, play: false)
            return
        }
        crossfader.interrupt()
        queue.add(items, at: index ?? queue.count)
        changedUnder()
    }

    /// "Play next": right after the song on now, in the queue and in the play order.
    func addNext(_ items: [QueueItem]) {
        guard !items.isEmpty else { return }
        if queue.isEmpty {
            setQueue(items, startIndex: 0, play: false)
            return
        }
        crossfader.interrupt()
        queue.addNext(items)
        changedUnder()
    }

    /// Takes out queue positions `from` until `to`.
    func remove(from: Int, to: Int) {
        crossfader.interrupt()
        let wasCurrent = queue.currentItem?.entryId
        let result = queue.remove(from: from, to: to)
        afterRemoval(result, wasCurrent)
    }

    func removeRuns(_ runs: [ClosedRange<Int>]) {
        crossfader.interrupt()
        let wasCurrent = queue.currentItem?.entryId
        let result = queue.removeRuns(runs)
        afterRemoval(result, wasCurrent)
    }

    private func afterRemoval(_ result: (currentRemoved: Bool, ended: Bool), _ wasCurrent: String?) {
        if queue.isEmpty {
            stop()
            onQueueChange?()
            onSongChange?(.playlistChanged)
            return
        }
        if result.currentRemoved {
            if result.ended {
                ended = true
                playWhenReady = false
                deck.clear()
                onPlayWhenReadyChange?(false, false)
            } else {
                loadCurrent(atMs: 0)
            }
            onQueueChange?()
            onSongChange?(.playlistChanged)
            return
        }
        changedUnder()
    }

    func move(from: Int, to: Int, newIndex: Int) {
        crossfader.interrupt()
        queue.move(from: from, to: to, newIndex: newIndex)
        changedUnder()
    }

    /// Puts songs back exactly where they were, for an undo.
    func putBack(_ runs: [(at: Int, items: [QueueItem])], order: [Int]) {
        crossfader.interrupt()
        queue.putBack(runs, order: order)
        changedUnder()
    }

    func setPlayOrder(_ order: [Int]) {
        queue.setPlayOrder(order)
        changedUnder()
    }

    /// Runs an edit of the queue. `change` answers whether it took out the song on now with
    /// nothing left to play after it: then the queue has played out.
    func edit(_ change: (inout PlayQueue) -> Bool) {
        crossfader.interrupt()
        let before = queue.currentItem?.entryId
        let playedOut = change(&queue)
        if queue.isEmpty {
            stop()
        } else if queue.currentItem?.entryId != before {
            if playedOut {
                ended = true
                playWhenReady = false
                deck.clear()
                onPlayWhenReadyChange?(false, false)
            } else {
                loadCurrent(atMs: 0)
            }
            onSongChange?(.playlistChanged)
        }
        changedUnder()
    }

    /// Changes one song in place.
    func update(at index: Int, _ change: (inout QueueItem) -> Void) {
        queue.update(at: index, change)
        onQueueChange?()
    }

    func clear() {
        crossfader.interrupt()
        queue.clear()
        stop()
        onQueueChange?()
        onSongChange?(.playlistChanged)
    }

    /// The queue changed but the song on now did not.
    private func changedUnder() {
        refreshFollowing()
        onQueueChange?()
    }

    // MARK: Hand-over between decks

    /// The blend begins: the incoming deck (already playing, its processor holding it silent
    /// until its entry) becomes the one everything talks to, while the outgoing one keeps
    /// sounding. Their processors run the volumes from here; the decks' own volume only carries
    /// the sleep timer's fade.
    func handOver(into: Deck, from: Deck) {
        deck = into
        if let next = queue.nextOnEnd, queue.items[next].entryId == into.item?.entryId {
            queue.setCurrent(next)
        } else if let entry = into.item?.entryId, let at = queue.position(ofEntry: entry) {
            queue.setCurrent(at)
        }
        lengthTold = nil
        applyVolume()
        if !into.playWhenReady { into.playWhenReady = true }
        refreshFollowing()
        onSongChange?(.playlistChanged)
    }

    func endFade() {
        applyVolume()
    }

    private func applyVolume() {
        deck.volume = sleepFade
        crossfader.outgoing?.volume = sleepFade
    }

    // MARK: Calls and other apps

    private func interruption(began: Bool, shouldResume: Bool) {
        if began {
            // A call or a short interruption: pause, and come back after if it was playing.
            resumeWhenFocusReturns = isPlaying || resumeWhenFocusReturns
            guard playWhenReady else { return }
            playWhenReady = false
            crossfader.interrupt()
            deck.playWhenReady = false
            dropLiveStream()
            onPlayWhenReadyChange?(false, false)
        } else {
            let resume = resumeWhenFocusReturns && shouldResume
            resumeWhenFocusReturns = false
            if resume { play() }
        }
    }

    // MARK: The ticker

    /// Starts the sound for playing. False when the system refused it (a call is on). A sound
    /// device that will not start fails the song on now, as a song that could not play.
    private func startOutput() -> Bool {
        switch output.start() {
        case .started:
            output.updateDelays()
            return true
        case .refused:
            return false
        case .failed:
            if let item = queue.currentItem {
                // Told once this request is done, so the failure is handled with the player wanting to play.
                DispatchQueue.main.async { [weak self] in
                    self?.onFailure?(item, PlayError(.audioTrackInitFailed, detail: "the sound device did not start"))
                }
            }
            return true
        }
    }

    /// While paused the sound waits a while silent, so headphones and the lock screen can bring
    /// it back at once; then it is let go.
    var silentWaitSeconds: Double = 600

    private func stopOutputLater() {
        output.stopLater(after: silentWaitSeconds)
    }

    private func ensureTicking() {
        guard ticker == nil else { return }
        let timer = Timer(timeInterval: 0.04, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func tick() {
        for event in deck.poll() { handle(event) }
        if let outgoing = crossfader.outgoing { _ = outgoing.poll() }
        _ = crossfader.spare.poll()
        let playing = deck.isPlaying
        if playing != lastIsPlaying {
            lastIsPlaying = playing
            crossfader.isPlayingChanged(playing)
            onIsPlayingChange?(playing)
        }
        let now = state
        if now != lastState {
            lastState = now
            onStateChange?(now)
        }
        // The length is taught each time the deck has a new measure of the song (a reopened
        // source measures again); a live station's measure is never believed.
        if let item = queue.currentItem, !item.isRadioStation, let measured = measuredMs, measured > 0 {
            let told = "\(item.entryId ?? "")|\(measured)"
            if lengthTold != told {
                lengthTold = told
                onLengthFound?(item, measured)
            }
        }
        loadFollowingWhenNear()
        if (!playWhenReady || ended) && !playing && crossfader.outgoing == nil {
            ticker?.invalidate()
            ticker = nil
        }
    }

    private func handle(_ event: DeckEvent) {
        switch event {
        case .advanced(let from, let to):
            if let at = to.entryId.flatMap(queue.position(ofEntry:)) { queue.setCurrent(at) }
            lengthTold = nil
            crossfader.songChanged()
            refreshFollowing()
            onSongChange?(from.entryId == to.entryId ? .repeated : .auto)
        case .ended(_, let paused):
            if paused || deck.pauseAtEndOfSong {
                // Stopped at the end of the song, as asked: playing again moves on.
                stoppedAtEnd = true
                playWhenReady = false
                deck.pauseAtEndOfSong = false
                onPlayWhenReadyChange?(false, true)
                stopOutputLater()
            } else if let item = queue.currentItem, item.isRadioStation {
                // A live station that ends stops there with its line, as one that fails does:
                // the next station never starts by itself, and playing again rejoins this one.
                if playWhenReady { onFailure?(item, PlayError(.networkConnectionFailed, detail: "the live stream ended")) }
                if playWhenReady || deck.item != nil {
                    playWhenReady = false
                    deck.clear()
                    onPlayWhenReadyChange?(false, false)
                    stopOutputLater()
                }
            } else if queue.nextOnEnd == nil {
                ended = true
                onStateChange?(.ended)
                stopOutputLater()
            } else if let next = queue.nextOnEnd {
                // Nothing was loaded to follow in time: the next song plays now.
                queue.setCurrent(next)
                loadCurrent(atMs: 0)
                onSongChange?(.auto)
            }
        case .failed(let item, let error):
            onFailure?(item, error)
        }
    }

    // MARK: The song to follow without a gap

    /// What should follow the song on now changed: the deck lets go of what it loaded for it.
    private func refreshFollowing() {
        let wanted = queue.nextOnEnd.map { queue.items[$0] }
        if let loaded = deck.followingItem, loaded.entryId != wanted?.entryId || loaded.uri != wanted?.uri {
            deck.setFollowing(nil)
        }
    }

    /// The song to follow is loaded once the one on now is close to its end. A live station has
    /// no end, so nothing is loaded to follow it.
    private func loadFollowingWhenNear() {
        guard deck.followingItem == nil, !deck.pauseAtEndOfSong, let current = deck.current, !current.item.isRadioStation,
              current.item.entryId == queue.currentItem?.entryId, let next = queue.nextOnEnd else { return }
        let length = playingLengthMs(listedMs: lengths.lengthMs(current.item.trackId, listedMs: current.item.durationMs),
                                     playerMs: current.measuredMs, positionMs: deck.positionMs)
        let near = current.decodedToEnd.load(ordering: .relaxed) || (length > 0 && length - deck.positionMs < 30_000)
        guard near else { return }
        deck.setFollowing(makeSource(queue.items[next], startMs: 0))
    }
}
