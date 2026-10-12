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

    var current: Song? { queue.indices.contains(index) ? queue[index] : nil }
    var upNext: ArraySlice<Song> { queue.indices.contains(index + 1) ? queue[(index + 1)...] : [] }

    @ObservationIgnored private let engine = AVQueuePlayer()
    @ObservationIgnored private var itemIndex: [ObjectIdentifier: Int] = [:]
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var listen = Listen()
    @ObservationIgnored private var refilling = false
    @ObservationIgnored private let session: Session

    init(session: Session) {
        self.session = session
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

    func next() {
        guard index + 1 < queue.count else { return }
        if engine.items().count > 1 {
            engine.advanceToNextItem()
        } else {
            load(at: index + 1, playing: true)
        }
    }

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
        if position + 1 < queue.count { enqueue(position + 1) }
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
        if index + 1 < queue.count { enqueue(index + 1) }
    }

    private func enqueue(_ position: Int) {
        guard let client = session.client else { return }
        let song = queue[position]
        let asset = AVURLAsset(url: client.streamURL(for: song, quality: session.quality), options: [
            "AVURLAssetHTTPHeaderFieldsKey": client.device.headers,
            AVURLAssetHTTPUserAgentKey: client.userAgent,
        ])
        let item = AVPlayerItem(asset: asset)
        itemIndex[ObjectIdentifier(item)] = position
        engine.insert(item, after: engine.items().last)
    }

    private func currentItemChanged() {
        guard let item = engine.currentItem else {
            // The queue ran out.
            if !queue.isEmpty, engine.items().isEmpty { isPlaying = false }
            return
        }
        guard let position = itemIndex[ObjectIdentifier(item)] else { return }
        if position != index {
            index = position
            elapsed = 0
            duration = TimeInterval(queue[position].duration)
            songBegan()
        }
        let loaded = Set(engine.items().map(ObjectIdentifier.init))
        itemIndex = itemIndex.filter { loaded.contains($0.key) }
        if engine.items().count < 2, index + 1 < queue.count { enqueue(index + 1) }
    }

    private func statusChanged() {
        isPlaying = engine.timeControlStatus != .paused
        isWaiting = engine.timeControlStatus == .waitingToPlayAtSpecifiedRate
        publishNowPlaying()
    }

    private func tick(_ seconds: TimeInterval) {
        guard seconds.isFinite else { return }
        if let item = engine.currentItem, item.duration.isNumeric, item.duration.seconds > 0 {
            duration = item.duration.seconds
        }
        let step = seconds - elapsed
        elapsed = seconds
        if engine.timeControlStatus == .playing, step > 0, step < 2 {
            heard(step)
        }
        refillRadioIfNeeded()
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
            MPNowPlayingInfoPropertyPlaybackRate: engine.timeControlStatus == .playing ? 1.0 : 0.0,
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
