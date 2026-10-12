import AVFoundation
import MediaPlayer
import Observation
import OctoKit
import SwiftUI
import UIKit

/// The queue and the audio. AVQueuePlayer holds the song playing and the one after it, so the
/// next song is already loading when this one ends and albums play without a gap. The lock
/// screen, Control Center, AirPlay and headphone buttons all drive this one player.
@MainActor
@Observable
final class Player {
    private(set) var queue: [Song] = []
    private(set) var index = 0
    private(set) var isPlaying = false
    private(set) var isWaiting = false
    private(set) var elapsed: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    /// The song radio was started from, while the queue is a radio.
    private(set) var radioSeed: Song?
    private(set) var repeatMode: RepeatMode = .off
    private(set) var shuffled = false
    /// Playback speed, 0.5 to 2.
    private(set) var speed: Float = 1
    /// Whether voices keep their pitch at other speeds.
    private(set) var keepsPitch = true
    private(set) var sleep: SleepTimer?

    enum RepeatMode { case off, all, one }

    /// When the music stops on its own.
    enum SleepTimer: Equatable {
        case at(Date)
        /// After this many more songs end, counting the one playing.
        case afterSongs(Int)
    }

    var current: Song? { queue.indices.contains(index) ? queue[index] : nil }
    /// How far through the song, from 0 to 1.
    var progress: Double { duration > 0 ? min(elapsed / duration, 1) : 0 }
    var upNext: ArraySlice<Song> { queue.indices.contains(index + 1) ? queue[(index + 1)...] : [] }

    @ObservationIgnored private let engine = AVQueuePlayer()
    @ObservationIgnored private var itemIndex: [ObjectIdentifier: Int] = [:]
    /// The loaders behind trusted-stream assets, kept as long as their asset is queued.
    @ObservationIgnored private var streams: [ObjectIdentifier: TrustedStream] = [:]
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var listen = Listen()
    @ObservationIgnored private var refilling = false
    @ObservationIgnored private let session: Session
    @ObservationIgnored private let sound: SoundProcessor
    /// The queue as it was before shuffling, to go back to.
    @ObservationIgnored private var unshuffled: [Song]?
    @ObservationIgnored private weak var lastItem: AVPlayerItem?
    /// When `elapsed` was last read from the engine, so the position can be told between reads.
    @ObservationIgnored private var tickedAt = Date()

    init(session: Session, sound: SoundProcessor) {
        self.session = session
        self.sound = sound
        engine.actionAtItemEnd = .advance
        observations = Self.watch(engine,
            itemChanged: { [weak self] in Task { @MainActor in self?.currentItemChanged() } },
            statusChanged: { [weak self] in Task { @MainActor in self?.statusChanged() } })
        timeObserver = engine.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 2), queue: .main) { [weak self] time in
            MainActor.assumeIsolated { self?.tick(time.seconds) }
        }
        listenForSystemEvents()
        setUpRemoteCommands()
    }

    /// AVPlayer reports changes on whatever thread it is on, so these handlers are made outside
    /// the main actor and only hop to it.
    nonisolated private static func watch(_ engine: AVQueuePlayer, itemChanged: @escaping @Sendable () -> Void,
                                          statusChanged: @escaping @Sendable () -> Void) -> [NSKeyValueObservation] {
        [
            engine.observe(\.currentItem) { _, _ in itemChanged() },
            engine.observe(\.timeControlStatus) { _, _ in statusChanged() },
        ]
    }

    /// The lock screen asks for the picture from its own thread.
    nonisolated private static func artwork(_ image: UIImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }

    // MARK: Playing

    func play(_ songs: [Song], from start: Int = 0, radio seed: Song? = nil) {
        guard !songs.isEmpty else { return }
        queue = songs
        radioSeed = seed
        load(at: min(max(start, 0), songs.count - 1), playing: true)
    }

    func shuffle(_ songs: [Song]) {
        play(songs.shuffled())
    }

    /// With nothing loaded, the play button shuffles the whole library.
    func shuffleLibrary() async {
        guard let client = session.client, let songs = try? await client.randomSongs(count: 100), !songs.isEmpty else { return }
        play(songs)
    }

    /// Radio from a song: it plays at once and the server's mix follows it.
    func startRadio(from song: Song) async {
        guard let client = session.client else { return }
        play([song], radio: song)
        if let more = try? await client.radio(from: song.id) {
            append(more.filter { $0.id != song.id })
        }
    }

    func toggle() {
        if isPlaying { pause() } else { resume() }
    }

    /// The position that plays after `position`, given repeat.
    private func position(after position: Int) -> Int? {
        if repeatMode == .one { return position }
        if position + 1 < queue.count { return position + 1 }
        return repeatMode == .all && !queue.isEmpty ? 0 : nil
    }

    func cycleRepeat() {
        repeatMode = switch repeatMode {
        case .off: .all
        case .all: .one
        case .one: .off
        }
        reloadUpcoming()
    }

    /// Shuffling keeps the song playing first and mixes the rest; turning it off puts the queue
    /// back the way it was, at the same song.
    func toggleShuffle() {
        guard let song = current else { shuffled.toggle(); return }
        if shuffled, let original = unshuffled {
            queue = original
            index = original.firstIndex(of: song) ?? 0
            unshuffled = nil
            shuffled = false
        } else {
            unshuffled = queue
            var rest = queue
            rest.remove(at: index)
            queue = [song] + rest.shuffled()
            index = 0
            shuffled = true
        }
        reloadUpcoming()
        publishNowPlaying()
    }

    func setSpeed(_ value: Float) {
        speed = min(max(value, 0.5), 2)
        engine.defaultRate = speed
        if engine.timeControlStatus != .paused { engine.rate = speed }
        publishNowPlaying()
    }

    func setKeepsPitch(_ on: Bool) {
        keepsPitch = on
        for item in engine.items() { item.audioTimePitchAlgorithm = on ? .timeDomain : .varispeed }
    }

    func setSleep(_ timer: SleepTimer?) {
        sleep = timer
        engine.volume = 1
    }

    /// Songs not yet played go; the one playing stays.
    func clearUpcoming() {
        guard current != nil else { return }
        queue.removeSubrange((index + 1)...)
        unshuffled = nil
        reloadUpcoming()
    }

    func removePlayed() {
        guard index > 0 else { return }
        queue.removeSubrange(0..<index)
        index = 0
        unshuffled = nil
        publishNowPlaying()
    }

    /// The queue as it is, to put back with Undo.
    var snapshot: QueueSnapshot { QueueSnapshot(songs: queue, index: index) }

    struct QueueSnapshot { let songs: [Song]; let index: Int }

    func restore(_ snapshot: QueueSnapshot) {
        let playingId = current?.id
        queue = snapshot.songs
        index = snapshot.songs.firstIndex { $0.id == playingId } ?? min(snapshot.index, max(snapshot.songs.count - 1, 0))
        reloadUpcoming()
    }

    func resume() {
        guard current != nil else { return }
        if engine.currentItem == nil { load(at: index, playing: true); return }
        activateAudioSession()
        engine.play()
    }

    func pause() {
        engine.pause()
    }

    /// Nothing playing and nothing queued, as after signing out.
    func stop() {
        engine.pause()
        engine.removeAllItems()
        itemIndex.removeAll()
        queue = []
        index = 0
        radioSeed = nil
        elapsed = 0
        duration = 0
        artwork = nil
        publishNowPlaying()
    }

    /// Next always moves on, even when repeating one song.
    func next() {
        guard current != nil else { return }
        let following = index + 1 < queue.count ? index + 1 : (repeatMode == .off ? nil : 0)
        guard let following else { return }
        if engine.items().count > 1, following == position(after: index) {
            engine.advanceToNextItem()
        } else {
            load(at: following, playing: true)
        }
    }

    var hasNext: Bool { current != nil && (index + 1 < queue.count || repeatMode != .off) }

    /// Back to the start of the song, or to the one before when the song has barely begun.
    func previous() {
        if elapsed > 3 || index == 0 {
            seek(to: 0)
        } else {
            load(at: index - 1, playing: true)
        }
    }

    func jump(to position: Int) {
        guard queue.indices.contains(position) else { return }
        load(at: position, playing: true)
    }

    func seek(to seconds: TimeInterval) {
        elapsed = seconds
        engine.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor in self?.publishNowPlaying() }
        }
    }

    func playNext(_ songs: [Song]) {
        guard current != nil else { play(songs); return }
        queue.insert(contentsOf: songs, at: index + 1)
        reloadUpcoming()
    }

    func append(_ songs: [Song]) {
        guard current != nil else { play(songs); return }
        let wasLast = index + 1 >= queue.count
        queue.append(contentsOf: songs)
        if wasLast { reloadUpcoming() }
    }

    func remove(at offsets: IndexSet) {
        let upcoming = offsets.map { $0 + index + 1 }.filter { queue.indices.contains($0) && $0 != index }
        guard !upcoming.isEmpty else { return }
        for position in upcoming.sorted(by: >) { queue.remove(at: position) }
        reloadUpcoming()
    }

    func move(from source: IndexSet, to destination: Int) {
        var rest = Array(upNext)
        rest.move(fromOffsets: source, toOffset: destination)
        queue.replaceSubrange((index + 1)..., with: rest)
        reloadUpcoming()
    }

    // MARK: The engine

    private func load(at position: Int, playing: Bool) {
        engine.removeAllItems()
        itemIndex.removeAll()
        index = position
        elapsed = 0
        duration = TimeInterval(queue[position].duration)
        enqueue(position)
        if let following = self.position(after: position) { enqueue(following) }
        songBegan()
        if playing {
            activateAudioSession()
            engine.play()
        }
    }

    /// Keeps exactly one song loaded after the one playing, matching the queue.
    private func reloadUpcoming() {
        for item in engine.items() where item !== engine.currentItem {
            engine.remove(item)
            itemIndex[ObjectIdentifier(item)] = nil
        }
        if current != nil, let following = position(after: index) { enqueue(following) }
    }

    private func enqueue(_ position: Int) {
        guard let client = session.client else { return }
        let song = queue[position]
        let url = client.streamURL(for: song, quality: session.quality)
        let asset: AVURLAsset
        if ServerTrust.shared.isPinned(url.host) || ServerTrust.shared.hasClientCertificate {
            // Apple's player cannot be told about a pinned certificate or a client certificate,
            // so these servers stream through the app's own session.
            let stream = TrustedStream(headers: client.headers)
            asset = stream.asset(for: url)
            streams[ObjectIdentifier(asset)] = stream
        } else {
            asset = AVURLAsset(url: url, options: [
                "AVURLAssetHTTPHeaderFieldsKey": client.customHeaders.merging(client.device.headers) { $1 },
                AVURLAssetHTTPUserAgentKey: client.userAgent,
            ])
        }
        let item = AVPlayerItem(asset: asset)
        item.audioTimePitchAlgorithm = keepsPitch ? .timeDomain : .varispeed
        attachSound(to: item, asset: asset, song: song)
        itemIndex[ObjectIdentifier(item)] = position
        engine.insert(item, after: engine.items().last)
    }

    /// Every song plays through the sound processor (equalizer, ReplayGain, balance, limiter),
    /// put on its audio track as soon as the track is known. The song's loudness is judged as it
    /// is queued, in play order.
    private func attachSound(to item: AVPlayerItem, asset: AVURLAsset, song: Song) {
        let processor = sound
        let setUp = processor.songSetUp(song)
        Task {
            guard let track = try? await asset.loadTracks(withMediaType: .audio).first,
                  let tap = await processor.makeTap(for: setUp, asset: asset)
            else { return }
            let input = AVMutableAudioMixInputParameters(track: track)
            input.audioTapProcessor = tap
            let mix = AVMutableAudioMix()
            mix.inputParameters = [input]
            item.audioMix = mix
        }
    }

    private func currentItemChanged() {
        guard let item = engine.currentItem else {
            // The queue ran out.
            if !queue.isEmpty, engine.items().isEmpty { isPlaying = false }
            return
        }
        guard let position = itemIndex[ObjectIdentifier(item)] else { return }
        let fresh = item !== lastItem
        lastItem = item
        if fresh, position != index || repeatMode == .one, listen.songId != nil {
            songEnded()
        }
        if position != index || (fresh && repeatMode == .one && listen.played > 0) {
            index = position
            elapsed = 0
            duration = TimeInterval(queue[position].duration)
            songBegan()
        }
        let loaded = Set(engine.items().map(ObjectIdentifier.init))
        itemIndex = itemIndex.filter { loaded.contains($0.key) }
        let assets = Set(engine.items().map { ObjectIdentifier($0.asset) })
        streams = streams.filter { assets.contains($0.key) }
        if engine.items().count < 2, let following = self.position(after: index) { enqueue(following) }
    }

    private func statusChanged() {
        isPlaying = engine.timeControlStatus != .paused
        isWaiting = engine.timeControlStatus == .waitingToPlayAtSpecifiedRate
        publishNowPlaying()
    }

    /// Where the song is at a moment between the engine's half-second reads, for anything that
    /// has to move smoothly (the lyrics).
    func position(at date: Date) -> TimeInterval {
        guard engine.timeControlStatus == .playing else { return elapsed }
        return elapsed + date.timeIntervalSince(tickedAt) * Double(speed)
    }

    private func tick(_ seconds: TimeInterval) {
        guard seconds.isFinite else { return }
        tickedAt = Date()
        if let item = engine.currentItem, item.duration.isNumeric, item.duration.seconds > 0 {
            let measured = item.duration.seconds
            let listed = Double(current?.duration ?? 0)
            // iOS reads some AAC streams (HE-AAC) as twice their length; the server's length
            // wins when the two differ by exactly that.
            duration = listed > 0 && (1.9...2.1).contains(measured / listed) ? listed : measured
        }
        let step = seconds - elapsed
        elapsed = seconds
        if engine.timeControlStatus == .playing, step > 0, step < 2 {
            heard(step)
        }
        refillRadioIfNeeded()
        applySleep()
    }

    /// A timer fades the music out over its last 30 seconds, then pauses.
    private func applySleep() {
        guard case .at(let date) = sleep else { return }
        let left = date.timeIntervalSinceNow
        if left <= 0 {
            pause()
            sleep = nil
            engine.volume = 1
        } else if left < 30 {
            engine.volume = Float(left / 30)
        }
    }

    /// A song ended: counts down a stop-after-songs timer.
    private func songEnded() {
        guard case .afterSongs(let count) = sleep else { return }
        if count <= 1 {
            sleep = nil
            pause()
        } else {
            sleep = .afterSongs(count - 1)
        }
    }

    // MARK: Plays and now playing

    private struct Listen {
        var songId: String?
        var started = Date()
        var played: TimeInterval = 0
        var announced = false
        var counted = false
    }

    private func songBegan() {
        listen = Listen(songId: current?.id)
        if let song = current { sound.songStarted(id: song.id, albumId: song.albumId, replayGain: song.replayGain) }
        publishNowPlaying()
        loadArtwork()
    }

    /// Tells the server what is playing the first time it is really heard, and counts the play
    /// once half of it or four minutes have been heard.
    private func heard(_ step: TimeInterval) {
        guard let song = current, listen.songId == song.id, let client = session.client else { return }
        listen.played += step
        if !listen.announced {
            listen.announced = true
            listen.started = Date().addingTimeInterval(-listen.played)
            let started = listen.started
            Task { try? await client.scrobble(song.id, submission: false, at: started) }
        }
        if !listen.counted, PlayRules.countsAsPlay(played: listen.played, duration: duration) {
            listen.counted = true
            let started = listen.started
            Task { try? await client.scrobble(song.id, submission: true, at: started) }
        }
    }

    /// A radio keeps going: 20 seconds before the last song ends, more songs from its mix.
    private func refillRadioIfNeeded() {
        guard radioSeed != nil, !refilling, index == queue.count - 1, duration > 0, duration - elapsed < 20,
              let song = current, let client = session.client
        else { return }
        refilling = true
        Task {
            defer { refilling = false }
            guard let more = try? await client.radio(from: song.id) else { return }
            let known = Set(queue.map(\.id))
            append(more.filter { !known.contains($0.id) })
        }
    }

    @ObservationIgnored private var artwork: MPMediaItemArtwork?

    private func publishNowPlaying() {
        guard let song = current else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: song.title,
            MPMediaItemPropertyArtist: song.byline,
            MPMediaItemPropertyAlbumTitle: song.album ?? "",
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: engine.timeControlStatus == .playing ? Double(speed) : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: Double(speed),
            MPNowPlayingInfoPropertyPlaybackQueueIndex: index,
            MPNowPlayingInfoPropertyPlaybackQueueCount: queue.count,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]
        if let artwork { info[MPMediaItemPropertyArtwork] = artwork }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused
    }

    private func loadArtwork() {
        artwork = nil
        guard let song = current, let coverId = song.coverArt, let client = session.client else { return }
        Task {
            guard let image = await Covers.shared.image(coverId, size: 600, client: client), current?.id == song.id else { return }
            artwork = Self.artwork(image)
            publishNowPlaying()
        }
    }

    // MARK: The system

    private func activateAudioSession() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, policy: .longFormAudio)
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    private func listenForSystemEvents() {
        let center = NotificationCenter.default
        center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let type = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init)
            let options = (note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt).map(AVAudioSession.InterruptionOptions.init)
            MainActor.assumeIsolated {
                if type == .ended, options?.contains(.shouldResume) == true { self?.resume() }
            }
        }
        center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            let reason = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt).flatMap(AVAudioSession.RouteChangeReason.init)
            // Headphones pulled out: stop rather than play out loud.
            MainActor.assumeIsolated {
                if reason == .oldDeviceUnavailable { self?.pause() }
            }
        }
        center.addObserver(forName: AVPlayerItem.failedToPlayToEndTimeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.next() }
        }
    }

    private func setUpRemoteCommands() {
        let commands = MPRemoteCommandCenter.shared()
        commands.playCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.resume() }
            return .success
        }
        commands.pauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.pause() }
            return .success
        }
        commands.togglePlayPauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.toggle() }
            return .success
        }
        commands.nextTrackCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.next() }
            return .success
        }
        commands.previousTrackCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.previous() }
            return .success
        }
        commands.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let position = event.positionTime
            MainActor.assumeIsolated { self?.seek(to: position) }
            return .success
        }
    }
}
