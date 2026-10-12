import AVFoundation
import Observation
import OctoKit
import Synchronization
import SwiftUI
import UIKit

/// The queue and the audio. Two decks play the songs, through Octo's sound processor, with
/// gapless changes, crossfades and Automix blends between them. The lock screen, Control Center,
/// CarPlay, AirPlay and headphone buttons all drive this one player. Around it: the play count,
/// the sleep timer, Autoplay, the queue kept on the phone and on the server, and headphones that
/// bring the music back.
@MainActor
@Observable
final class Player {
    /// The queue's songs in queue order, as the screens show them.
    private(set) var queue: [Song] = []
    /// The queue as the player holds it: every song with its entry, source and address.
    private(set) var items: [QueueItem] = []
    private(set) var index = 0
    private(set) var isPlaying = false
    /// Waiting for sound while it should play.
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
    /// The pitch moved, in semitones.
    private(set) var semitones = 0
    /// Where the sleep timer stands.
    private(set) var sleepState: SleepState = .off
    /// What the playing song is, for the quality badge.
    private(set) var quality: AudioQuality?
    /// The songs to come, current first, and the songs played, oldest first, each by its key.
    private(set) var upNextSlots: [QueueSlot] = []
    private(set) var playedSlots: [QueueSlot] = []
    /// True until the queue kept from last time is back.
    private(set) var restoring = true

    typealias RepeatMode = OctoKit.RepeatMode

    /// When the music stops on its own.
    enum SleepTimer: Equatable {
        case at(Date)
        /// After this many more songs end, counting the one playing.
        case afterSongs(Int)
    }

    var current: Song? { queue.indices.contains(index) ? queue[index] : nil }
    var currentItem: QueueItem? { items.indices.contains(index) ? items[index] : nil }
    /// How far through the song, from 0 to 1.
    var progress: Double { duration > 0 ? min(elapsed / duration, 1) : 0 }
    /// The songs after the one playing, in the order they will play.
    var upNext: [Song] { upNextSlots.dropFirst().compactMap { queue.indices.contains($0.index) ? queue[$0.index] : nil } }
    var hasNext: Bool { engine.hasNext }
    /// An offer to carry on from another device's queue.
    var resumeOffer: ResumeOffer? { serverQueue.offer }

    /// The sleep timer as a time or a count of songs.
    var sleep: SleepTimer? {
        switch sleepState {
        case .off: nil
        case .counting(let remainingMs): .at(Date().addingTimeInterval(Double(remainingMs) / 1000))
        case .endOfSong: .afterSongs(1)
        case .songs(let left): .afterSongs(left)
        case .afterSong: .afterSongs(1)
        }
    }

    @ObservationIgnored let session: Session
    @ObservationIgnored let data: DataServices?
    @ObservationIgnored let engine: PlaybackEngine
    @ObservationIgnored let lengths = RealLengths()
    @ObservationIgnored let serverQueue: ServerQueueSync
    @ObservationIgnored var playable: PlayableItems { PlayableItems(session: session, data: data) }
    /// Shows a line at the bottom of the screen.
    @ObservationIgnored var announce: (String) -> Void = { _ in }
    /// The car's browse tree, told when the library changes.
    @ObservationIgnored var onLibraryChanged: (() -> Void)?

    @ObservationIgnored private let sound: SoundProcessor
    @ObservationIgnored private let clock = MainClock()
    @ObservationIgnored private var tracker: PlayTracker!
    @ObservationIgnored private var sleepTimer: OctoKit.SleepTimer!
    @ObservationIgnored private var autoplay: Autoplay?
    @ObservationIgnored private var nowPlaying: NowPlayingCenter!
    @ObservationIgnored private var headset: HeadsetWatch!
    @ObservationIgnored private let queueStore = QueueStore(rows: QueueFile.standard, parked: ParkedQueues(PlayerTexts()))
    @ObservationIgnored private let shared: PlayerShared
    @ObservationIgnored private var failuresInARow = 0
    @ObservationIgnored private var saveSoon: Task<Void, Never>?
    @ObservationIgnored private var ticker: Timer?
    @ObservationIgnored private var ticks = 0
    /// When `elapsed` was last read, so the position can be told between reads.
    @ObservationIgnored private var tickedAt = Date()
    /// The queue as it was left for a server switch, until it is handed over.
    @ObservationIgnored private var leftQueue: OctoKit.QueueSnapshot?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var lastPace: Pace?
    @ObservationIgnored private var lastSkipSilence: Bool?

    init(session: Session, sound: SoundProcessor, data: DataServices? = nil) {
        self.session = session
        self.sound = sound
        self.data = data
        let shared = PlayerShared()
        self.shared = shared
        let profiles = ServerProfiles(session: { shared.profileSession.withLock { $0 } })
        engine = PlaybackEngine(sound: sound, scout: Scout(), profiles: profiles, lengths: lengths,
                                keepActive: { shared.crossfadeOn.load(ordering: .relaxed) },
                                streamContext: { StreamContext.now(session) })
        serverQueue = ServerQueueSync(session: session, data: data)
        tracker = PlayTracker(
            started: { [weak self] trackId in self?.announceNowPlaying(trackId) },
            record: { [weak self] trackId, startedAt, heardMs, durationMs in
                self?.recordPlay(trackId, startedAt: startedAt, heardMs: heardMs, durationMs: durationMs)
            },
            isPlaying: { [weak self] in self?.engine.isPlaying ?? false },
            clock: clock)
        sleepTimer = OctoKit.SleepTimer(clock: clock)
        sleepTimer.attach(engine)
        sleepTimer.onChange = { [weak self] state in self?.sleepState = state }
        nowPlaying = NowPlayingCenter(player: self)
        CarLink.player = self
        headset = HeadsetWatch(player: self)
        if let data {
            autoplay = Autoplay(data: data, player: self)
            data.serverSwitch.player = self
            data.serverSwitch.onForget("playback") { [weak self] account in
                await self?.queueStore.forget(account)
                self?.serverQueue.forget(account)
            }
            data.plays.realLength = { [weak self] trackId, listedMs in
                Int64(self?.lengths.lengthMs(trackId, listedMs: Int(listedMs)) ?? Int(listedMs))
            }
        }
        engine.songSetUp = { [sound] item in sound.songSetUp(soundSong(item)) }
        wireEngine()
        engine.output.onRouteChange = { [weak self] reason, now, before in self?.headset.routeChanged(reason, now: now, before: before) }
        followSettings()
        listenForApp()
        Task { await restoreSaved() }
    }

    // MARK: Playing

    /// Plays songs from `start`. `source` names the list for the queue's headings; `shuffled`
    /// starts at a random song in a random order.
    func play(_ songs: [Song], from start: Int = 0, radio seed: Song? = nil, source: QueueSource = .played(nil), shuffled: Bool = false) {
        guard !songs.isEmpty else { return }
        radioSeed = seed
        Task {
            let found = await playable.items(songs, source: source)
            let items = found.compactMap { $0 }
            guard !items.isEmpty else { return }
            let startAt = chosenStart(found, min(max(start, 0), songs.count - 1))
            load(items, startIndex: shuffled ? -1 : startAt, shuffled: shuffled)
        }
    }

    /// Plays songs by their library ids, starting at one of them, or shuffled.
    func play(ids: [String], from start: Int = 0, name: String? = nil, shuffled: Bool = false) {
        guard !ids.isEmpty else { return }
        radioSeed = nil
        Task {
            let found = await playable.items(ids: ids, source: .played(name))
            let items = found.compactMap { $0 }
            guard !items.isEmpty else { return }
            load(items, startIndex: shuffled ? -1 : chosenStart(found, min(max(start, 0), ids.count - 1)), shuffled: shuffled)
        }
    }

    private func load(_ items: [QueueItem], startIndex: Int, shuffled: Bool) {
        failuresInARow = 0
        headset.forgetLoss()
        engine.setQueue(items, startIndex: max(startIndex, 0), shuffled: shuffled, play: true)
        if shuffled, let first = engine.queue.firstIndex, first != engine.queue.current {
            engine.seek(to: first)
        }
    }

    func shuffle(_ songs: [Song]) {
        play(songs, shuffled: true)
    }

    /// With nothing loaded, the play button shuffles the whole library.
    func shuffleLibrary() async {
        if let data {
            let ids = await data.library.tracks().map(\.id)
            if !ids.isEmpty {
                play(ids: ids, shuffled: true)
                return
            }
        }
        guard let client = session.client, let songs = try? await client.randomSongs(count: 100), !songs.isEmpty else { return }
        play(songs)
    }

    /// Radio from a song: it plays at once and Octo's mix of songs like it follows.
    func startRadio(from song: Song) async {
        radioSeed = song
        guard let data else {
            guard let client = session.client else { return }
            play([song], radio: song)
            if let more = try? await client.radio(from: song.id, count: radioLength) {
                append(more.filter { $0.id != song.id })
            }
            return
        }
        var seed = await data.library.songs(ids: [song.id]).first
        if seed == nil { seed = await data.discovery.resolveFromServer([song]).first }
        guard let seed else {
            play([song], radio: song)
            return
        }
        let ids = await LibraryRadio(data: data).songsLike([seed], count: radioLength, exclude: [seed.id])
        let found = await playable.items(ids: [seed.id] + ids, source: .played(nil))
        let items = found.compactMap { $0 }
        guard !items.isEmpty else { return }
        radioSeed = song
        load(items, startIndex: 0, shuffled: false)
    }

    func toggle() {
        if engine.queue.isEmpty {
            Task { await shuffleLibrary() }
        } else if engine.playWhenReady && engine.state != .ended {
            pause()
        } else {
            resume()
        }
    }

    func resume() {
        guard !engine.queue.isEmpty else { return }
        headset.forgetLoss()
        failuresInARow = 0
        engine.play()
    }

    func pause() {
        headset.forgetLoss()
        engine.pause()
    }

    /// Nothing playing and nothing queued, as after signing out.
    func stop() {
        tracker.flush()
        sleepTimer.cancel()
        engine.clear()
        radioSeed = nil
        publishQueue()
        publishPosition()
        nowPlaying.publish()
    }

    /// Close, from the lock screen: the queue is kept, the timer goes, the music stops and the
    /// lock screen lets go of it.
    func close() {
        saveQueue()
        sleepTimer.cancel()
        engine.pause()
        engine.output.stopNow()
        nowPlaying.clear()
    }

    /// Next always moves on, even when repeating one song.
    func next() {
        failuresInARow = 0
        engine.next()
    }

    /// Back to the start of the song, or to the one before when the song has barely begun.
    func previous() {
        failuresInARow = 0
        engine.previous()
    }

    /// Plays the song at a queue position.
    func jump(to position: Int) {
        guard engine.queue.items.indices.contains(position) else { return }
        failuresInARow = 0
        engine.seek(to: position)
        if !engine.playWhenReady { engine.play() }
    }

    /// Plays the queue entry with this key.
    func jump(toKey key: String) {
        guard let slot = (upNextSlots + playedSlots).first(where: { $0.key == key }) else { return }
        jump(to: slot.index)
    }

    func seek(to seconds: TimeInterval) {
        elapsed = max(0, seconds)
        tickedAt = Date()
        engine.seek(toMs: Int(max(0, seconds) * 1000))
        nowPlaying.publish()
    }

    func cycleRepeat() {
        setRepeat(repeatMode.cycled)
    }

    func setRepeat(_ mode: RepeatMode) {
        engine.repeatMode = mode
        repeatMode = mode
        autoplay?.check()
    }

    /// Shuffle changes the play order only; the queue keeps its order.
    func toggleShuffle() {
        engine.shuffle = !engine.shuffle
        shuffled = engine.shuffle
        autoplay?.check()
    }

    func setSpeed(_ value: Float) {
        AppSettings.shared.setSpeed(value)
    }

    func setKeepsPitch(_ on: Bool) {
        AppSettings.shared.setKeepPitch(on)
    }

    func setPitchSemitones(_ value: Int) {
        AppSettings.shared.setPitchSemitones(value)
    }

    // MARK: The sleep timer

    func setSleep(_ timer: SleepTimer?) {
        switch timer {
        case nil: sleepTimer.cancel()
        case .at(let date): sleepTimer.start(minutes: max(1, Int((date.timeIntervalSinceNow / 60).rounded(.up))))
        case .afterSongs(let count): sleepTimer.startAfterSongs(count)
        }
    }

    func startSleep(minutes: Int) { sleepTimer.start(minutes: minutes) }
    func sleepAtEndOfSong() { sleepTimer.startEndOfSong() }
    func extendSleep(minutes: Int) { sleepTimer.extend(minutes: minutes) }
    func sleepAfterSongs(_ count: Int) { sleepTimer.startAfterSongs(count) }
    func sleepAfter(key: String, title: String) { sleepTimer.startAfter(key: key, title: title) }
    func cancelSleep() { sleepTimer.cancel() }

    // MARK: The queue

    /// "Play next": right after the song on now, in the queue and in the play order.
    func playNext(_ songs: [Song]) {
        guard !engine.queue.isEmpty else { play(songs, source: .you); return }
        Task {
            let items = await playable.items(songs, source: .you).compactMap { $0 }
            engine.addNext(items)
        }
    }

    /// "Add to queue": at the end, before any Autoplay songs still to come.
    func append(_ songs: [Song]) {
        guard !engine.queue.isEmpty else { play(songs, source: .you); return }
        Task {
            let items = await playable.items(songs, source: .you).compactMap { $0 }
            engine.add(items)
        }
    }

    /// Play next with an undo: undo finds the run of those songs nearest where they went in and
    /// takes it out.
    func playNextUndoable(_ songs: [Song], inserted: @escaping (@escaping () -> Void) -> Void) {
        Task { [weak self] in
            guard let self else { return }
            let items = await self.playable.items(songs, source: .you).compactMap { $0 }
            guard !items.isEmpty else { return }
            if self.engine.queue.isEmpty {
                self.engine.setQueue(items, startIndex: 0, play: true)
            } else {
                self.engine.addNext(items)
            }
            let ids = items.map(\.trackId)
            let near = self.engine.queue.current + 1
            inserted { [weak self] in
                guard let self else { return }
                if let first = findInserted(self.engine.queue.trackIds, ids, insertedAt: near) {
                    self.engine.remove(from: first, to: first + ids.count)
                }
            }
        }
    }

    func addAutoplay(_ items: [QueueItem]) {
        engine.add(items, at: engine.queue.count)
    }

    /// Takes out songs of the up-next list, by their place in it (after the song on now).
    func remove(at offsets: IndexSet) {
        let slots = Array(upNextSlots.dropFirst())
        let positions = offsets.compactMap { slots.indices.contains($0) ? slots[$0].index : nil }
            .filter { $0 != engine.queue.current }.sorted(by: >)
        guard !positions.isEmpty else { return }
        engine.removeRuns(positions.map { $0...$0 })
    }

    /// Moves songs of the up-next list, by their place in it.
    func move(from source: IndexSet, to destination: Int) {
        let slots = Array(upNextSlots.dropFirst())
        guard let from = source.first, slots.indices.contains(from) else { return }
        let fromIndex = slots[from].index
        let target = destination > from ? destination - 1 : destination
        guard slots.indices.contains(target) else { return }
        engine.move(from: fromIndex, to: fromIndex + 1, newIndex: slots[target].index)
    }

    /// Moves a song from one queue position to another.
    func moveInQueue(from: Int, to: Int) {
        engine.move(from: from, to: from + 1, newIndex: to)
    }

    /// Takes one song out by its key; the answer puts it back.
    @discardableResult
    func removeEntry(_ key: String) -> QueueUndo? {
        var undo: QueueUndo?
        engine.edit { undo = $0.removeEntry(key) }
        return undo
    }

    /// Songs not yet played go; the one playing stays.
    @discardableResult
    func clearUpcoming() -> QueueUndo? {
        var undo: QueueUndo?
        engine.edit { undo = $0.clearAllButCurrent() }
        return undo
    }

    @discardableResult
    func removePlayed() -> QueueUndo? {
        var undo: QueueUndo?
        engine.edit { undo = $0.removePlayed() }
        return undo
    }

    /// Takes these songs out wherever they are, as when their files are about to go.
    @discardableResult
    func removeSongs(_ trackIds: Set<String>) -> QueueUndo? {
        var undo: QueueUndo?
        engine.edit { undo = $0.removeSongs(trackIds) }
        return undo
    }

    /// Moves a song already queued to play next.
    func playEntryNext(_ key: String) {
        engine.edit { _ = $0.playEntryNext(key) }
    }

    /// Puts an edit back; false when the queue changed some other way since.
    @discardableResult
    func undo(_ undo: QueueUndo) -> Bool {
        var done = false
        engine.edit { done = $0.undo(undo) }
        return done
    }

    /// The queue as it is, to put back with Undo.
    var snapshot: QueueSnapshot { QueueSnapshot(songs: queue, index: index, items: engine.queue.items, order: engine.queue.order) }

    struct QueueSnapshot {
        let songs: [Song]
        let index: Int
        var items: [QueueItem] = []
        var order: [Int] = []
    }

    func restore(_ snapshot: QueueSnapshot) {
        let playing = engine.queue.currentItem?.entryId
        engine.edit { queue in
            let items = snapshot.items
            guard !items.isEmpty else { return }
            let current = items.firstIndex { $0.entryId == playing } ?? min(snapshot.index, items.count - 1)
            let wasShuffled = queue.shuffle, mode = queue.repeatMode
            var rebuilt = PlayQueue()
            rebuilt.setItems(items, startIndex: current)
            rebuilt.setPlayOrder(snapshot.order)
            rebuilt.shuffle = wasShuffled
            rebuilt.repeatMode = mode
            queue = rebuilt
        }
    }

    /// Where the song is at a moment between reads, for anything that moves smoothly (lyrics).
    func position(at date: Date) -> TimeInterval {
        guard isPlaying else { return elapsed }
        return elapsed + date.timeIntervalSince(tickedAt) * Double(engine.pace.speed)
    }

    // MARK: The lock screen's heart and download

    func likeFromOutside() {
        guard let item = engine.currentItem, !item.isFind, let data else { return }
        data.likes.toggle(item.trackId)
        nowPlaying.updateHeart(item)
    }

    func downloadFromOutside() {
        guard let item = engine.currentItem, item.isFind, let data else { return }
        let song = songOf(item)
        Task {
            _ = await data.downloads.request(serverSong(song, item))
            nowPlaying.updateHeart(item)
        }
    }

    private func serverSong(_ song: Song, _ item: QueueItem) -> Song {
        var server = song
        server.id = isFind(item.trackId) ? String(item.trackId.dropFirst(findPrefix.count)) : (parseStreamUri(item.uri)?.serverId ?? song.id)
        server.isExternal = true
        return server
    }

    // MARK: The Resume offer

    func takeResumeOffer(_ offer: ResumeOffer) async {
        guard let taken = await serverQueue.take(offer) else { return }
        let found = await playable.items(ids: taken.trackIds, source: .played(nil))
        let items = found.compactMap { $0 }
        guard !items.isEmpty else { return }
        let index = chosenStart(found, min(max(taken.index, 0), taken.trackIds.count - 1))
        engine.setQueue(items, startIndex: index, startMs: taken.positionMs, shuffled: false, play: false)
    }

    func dismissResumeOffer(_ offer: ResumeOffer) {
        serverQueue.dismiss(offer)
    }

    func setQueueSync(_ on: Bool) {
        serverQueue.setEnabled(on)
    }

    // MARK: What the engine says

    private func wireEngine() {
        engine.onSongChange = { [weak self] reason in self?.songChanged(reason) }
        engine.onIsPlayingChange = { [weak self] playing in self?.isPlayingChanged(playing) }
        engine.onPlayWhenReadyChange = { [weak self] playWhenReady, endOfSong in
            guard let self else { return }
            self.sleepTimer.playWhenReadyChanged(playWhenReady, endOfSong: endOfSong)
            if !playWhenReady {
                self.saveQueue()
                self.serverQueue.paused(self.queueSnapshot(), items: self.engine.queue.items)
                self.engine.silentWaitSeconds = self.headset.anyOn ? 1_800 : 600
            }
            self.publishState()
            self.autoplay?.check()
        }
        engine.onQueueChange = { [weak self] in self?.queueChanged() }
        engine.onFailure = { [weak self] item, error in self?.failed(item, error) }
        engine.onStateChange = { [weak self] state in
            guard let self else { return }
            if state == .ready { self.failuresInARow = 0 }
            self.publishState()
            self.autoplay?.check()
        }
        engine.onLengthFound = { [weak self] item, measured in
            guard let self else { return }
            _ = self.lengths.learn(item.trackId, listedMs: item.durationMs, playerMs: measured)
            self.tracker.lengthFound(item.trackId, length: playingLengthMs(listedMs: item.durationMs, playerMs: measured))
            self.publishPosition()
            self.publishQuality()
        }
    }

    private func songChanged(_ reason: SongChange) {
        publishQueue()
        publishPosition()
        publishQuality()
        sleepTimer.songChanged(reason)
        let item = engine.currentItem
        tracker.moved(item?.trackId, length: item.map { lengths.lengthMs($0.trackId, listedMs: $0.durationMs) } ?? 0)
        saveQueue()
        serverQueue.changed(queueSnapshot(), items: engine.queue.items)
        autoplay?.check()
        nowPlaying.publish()
        ensureTicking()
    }

    private func isPlayingChanged(_ playing: Bool) {
        isPlaying = playing
        tracker.playingChanged(playing)
        publishState()
        publishPosition()
        nowPlaying.publish()
        autoplay?.check()
        ensureTicking()
    }

    private func queueChanged() {
        publishQueue()
        sleepTimer.queueChanged()
        saveSoon?.cancel()
        saveSoon = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.saveQueue()
        }
        serverQueue.changed(queueSnapshot(), items: engine.queue.items)
        autoplay?.check()
        nowPlaying.publish()
    }

    /// A song that fails while music should play is skipped with one line; once as many songs
    /// have failed in a row as the queue holds, or nothing is next, it stops.
    private func failed(_ item: QueueItem, _ error: PlayError) {
        guard engine.playWhenReady else { return }
        let why = playFailureOf(error, outside: item.isFind).words
        let title = item.title.trimmingCharacters(in: .whitespaces).isEmpty ? "a song" : item.title
        failuresInARow += 1
        playbackLog.info("playback failed: \(error.detail, privacy: .public)")
        if failuresInARow >= engine.queue.count || engine.queue.nextForSkip == nil {
            announce(stoppedLine(title, why))
            engine.pause()
            failuresInARow = 0
        } else {
            announce(skippedLine(title, why))
            engine.next()
        }
    }

    // MARK: Plays

    /// A song is heard for the first time: now playing, on the server and ListenBrainz.
    private func announceNowPlaying(_ trackId: String) {
        guard let item = engine.queue.items.first(where: { $0.trackId == trackId }) else { return }
        if isRadio(trackId) { return }
        if isOpenedFile(trackId) {
            ListenBrainzSync.shared.nowPlaying(playedSong(item, reachesServer: false))
            return
        }
        Task {
            if let data, await inCatalog(trackId) {
                data.plays.started(trackId)
            } else if let serverId = parseStreamUri(item.uri)?.serverId, let client = session.client {
                try? await client.scrobble(serverId, submission: false, at: Date())
                ListenBrainzSync.shared.nowPlaying(playedSong(item, reachesServer: true))
            }
        }
    }

    /// A song was heard enough to count: kept on the phone, sent to the server and ListenBrainz.
    private func recordPlay(_ trackId: String, startedAt: Int, heardMs: Int, durationMs: Int) {
        guard countsAsPlay(playedMs: heardMs, durationMs: durationMs), !isRadio(trackId) else { return }
        let item = engine.queue.items.first { $0.trackId == trackId }
        if isOpenedFile(trackId) {
            if let item {
                ListenBrainzSync.shared.played(playedSong(item, reachesServer: false),
                                               startedAt: Date(timeIntervalSince1970: Double(startedAt) / 1000))
            }
            return
        }
        let server = session.inUse
        Task {
            if let data, await inCatalog(trackId) {
                data.plays.record(trackId, startedAt: Int64(startedAt), playedMs: Int64(heardMs), durationMs: Int64(durationMs))
            } else if let item, let serverId = parseStreamUri(item.uri)?.serverId, let server {
                let started = Date(timeIntervalSince1970: Double(startedAt) / 1000)
                try? await server.client.scrobble(serverId, submission: true, at: started)
                ListenBrainzSync.shared.played(playedSong(item, reachesServer: true), startedAt: started)
            }
        }
    }

    private func inCatalog(_ trackId: String) async -> Bool {
        guard let data else { return false }
        return !(await data.library.songs(ids: [trackId]).isEmpty)
    }

    private func playedSong(_ item: QueueItem, reachesServer: Bool) -> PlayedSong {
        PlayedSong(item.title, item.artist, item.album, durationMs: Int64(lengths.lengthMs(item.trackId, listedMs: item.durationMs)),
                   trackNumber: item.trackNo, reachesServer: reachesServer)
    }

    // MARK: What the screens show

    private func publishQueue() {
        let queueState = engine.queue
        items = queueState.items
        queue = queueState.items.map(songOf)
        index = queueState.current
        repeatMode = queueState.repeatMode
        shuffled = queueState.shuffle
        upNextSlots = queueState.upNext()
        playedSlots = queueState.played()
    }

    private func publishState() {
        isPlaying = engine.isPlaying
        isWaiting = engine.playWhenReady && engine.state == .buffering
    }

    private func publishPosition() {
        guard let item = engine.currentItem else {
            elapsed = 0
            duration = 0
            return
        }
        let position = engine.positionMs
        let listed = lengths.lengthMs(item.trackId, listedMs: item.durationMs)
        elapsed = Double(position) / 1000
        duration = Double(playingLengthMs(listedMs: listed, playerMs: engine.measuredMs, positionMs: position)) / 1000
        tickedAt = Date()
    }

    private func publishQuality() {
        guard let item = engine.currentItem else {
            quality = nil
            return
        }
        let found = engine.playingQuality
        quality = audioQuality(codecMime: found?.codecMime, fileMime: item.mimeType ?? item.fileMime, bitDepth: found?.bitDepth,
                               sampleRate: found?.sampleRate, bitrate: found?.bitrate)
    }

    /// Reads the position four times a second while there is a song, and saves the queue every
    /// 15 seconds while it plays.
    private func ensureTicking() {
        guard ticker == nil else { return }
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func tick() {
        publishPosition()
        publishState()
        ticks += 1
        if isPlaying && ticks % 60 == 0 { saveQueue() }
        if ticks % 4 == 0 { nowPlaying.publish() }
        if !isPlaying && !engine.playWhenReady {
            ticker?.invalidate()
            ticker = nil
        }
    }

    // MARK: Settings

    /// Acts on the settings and keeps acting on them as they change.
    private func followSettings() {
        applySettings()
        withObservationTracking {
            _ = AppSettings.shared.player
            _ = AppSettings.shared.stream
            _ = session.inUse?.account
            _ = session.profile
        } onChange: { [weak self] in
            Task { @MainActor in self?.followSettings() }
        }
    }

    private func applySettings() {
        let prefs = AppSettings.shared.player
        let pace = prefs.pace
        // Speed, pitch and skip silence reach the player only when they change, so a blend is
        // not cut short.
        if pace != lastPace {
            lastPace = pace
            engine.pace = pace
        }
        if prefs.skipSilence != lastSkipSilence {
            lastSkipSilence = prefs.skipSilence
            engine.skipSilence = prefs.skipSilence
        }
        speed = prefs.speed
        keepsPitch = prefs.keepPitch
        semitones = prefs.pitchSemitones
        engine.startAfterMs = AppSettings.shared.stream.startAfter.ms
        engine.automix = AutomixSettings(maxOverlapMs: prefs.crossfadeMs, smart: prefs.smartTransitions,
                                         filterSweeps: prefs.filterSweeps, beatMatch: prefs.matchTempo)
        shared.crossfadeOn.store(prefs.crossfadeMs > 0, ordering: .relaxed)
        let inUse = session.inUse
        shared.profileSession.withLock {
            $0 = inUse.map { ProfileSession(sourceId: $0.sourceId, isOcto: $0.isOcto, extensions: $0.extensions, client: $0.client) }
        }
        autoplay?.check()
    }

    // MARK: The queue kept on the phone

    private func queueSnapshot() -> OctoKit.QueueSnapshot {
        let state = engine.queue
        return OctoKit.QueueSnapshot(trackIds: state.trackIds, shuffleOrder: state.order, index: state.current,
                                     positionMs: max(0, engine.positionMs), repeatMode: state.repeatMode.rawValue,
                                     shuffle: state.shuffle, items: state.items)
    }

    /// Saves the queue in use now.
    func saveQueue() {
        guard !restoring else { return }
        queueStore.save(queueSnapshot())
    }

    /// Brings back the queue in use, paused at its song and place, once the library is there.
    private func restoreSaved() async {
        restoring = true
        defer { restoring = false }
        if let data {
            let deadline = Date().addingTimeInterval(5)
            while data.library.ready == nil && Date() < deadline { try? await Task.sleep(for: .milliseconds(100)) }
        }
        guard let saved = await queueStore.load(), !saved.trackIds.isEmpty else {
            engine.clear()
            publishQueue()
            return
        }
        let resolved = await playable.items(ids: saved.trackIds, source: .none)
        let savedItems = saved.items ?? []
        let sourceInUse = session.inUse?.sourceId
        var items: [QueueItem?] = []
        for (position, id) in saved.trackIds.enumerated() {
            let old = savedItems.indices.contains(position) && savedItems[position].trackId == id ? savedItems[position] : nil
            if var fresh = resolved[position] {
                if let old {
                    fresh.entryId = old.entryId
                    fresh.source = old.source
                }
                items.append(fresh)
            } else if let old, let ref = parseStreamUri(old.uri), ref.sourceId == nil || ref.sourceId == sourceInUse {
                // A server song the library does not hold still streams from its server.
                items.append(old)
            } else {
                items.append(nil)
            }
        }
        let found = items.map { $0 != nil }
        let point = restorePoint(found, savedIndex: saved.index, positionMs: saved.positionMs)
        let order = restoredShuffle(saved.shuffleOrder, found)
        let kept = items.compactMap { $0 }
        guard !kept.isEmpty else {
            engine.clear()
            publishQueue()
            return
        }
        engine.restoreQueue(kept, order: order, index: point.index, positionMs: point.positionMs,
                            repeatMode: RepeatMode(rawValue: saved.repeatMode) ?? .off, shuffle: saved.shuffle)
        serverQueue.restored(queueSnapshot())
        publishQueue()
        publishPosition()
        nowPlaying.publish()
    }

    // MARK: The app

    private func listenForApp() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.saveQueue() }
        })
        observers.append(center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.serverQueue.check() }
        })
        observers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.serverQueue.check() }
        })
        observers.append(center.addObserver(forName: UIApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.saveQueue()
                self.tracker.flush()
                self.sleepTimer.cancel()
            }
        })
    }
}

// MARK: Changing server

extension Player: SwitchPlayer {
    /// Stops what plays for the server being left: the last song counts, the queue goes to that
    /// server, and the player is emptied.
    func leave() async -> Bool {
        let wasPlaying = engine.playWhenReady
        let left = queueSnapshot()
        leftQueue = left
        tracker.flush()
        sleepTimer.cancel()
        await serverQueue.leaving(left, items: engine.queue.items)
        engine.clear()
        radioSeed = nil
        publishQueue()
        publishPosition()
        nowPlaying.publish()
        return wasPlaying
    }

    func handOver(from: String, to: String, keepWhenNone: Bool) async -> Bool {
        let left = leftQueue ?? (engine.queue.isEmpty ? nil : queueSnapshot())
        leftQueue = nil
        return await queueStore.handOver(from: from, left: left, to: to, keepWhenNone: keepWhenNone)
    }

    func serverArrived() {
        serverQueue.arrived()
    }

    func restore() async {
        await restoreSaved()
    }

    func keep() async {}

    func libraryChanged() {
        onLibraryChanged?()
    }
}

/// The song the sound processor judges a queue item's loudness by.
func soundSong(_ item: QueueItem) -> Song {
    var song = songOf(item)
    if song.replayGain == nil, let stored = item.loudness {
        song.replayGain = ReplayGain(trackGain: stored.trackGain, trackPeak: stored.trackPeak,
                                     albumGain: stored.albumGain, albumPeak: stored.albumPeak)
    }
    return song
}

/// What the player shares with other threads: whether crossfade is on (so each deck keeps its
/// live reading), and the server the transition profiles are asked of.
final class PlayerShared: @unchecked Sendable {
    let crossfadeOn = Atomic<Bool>(false)
    let profileSession = Mutex<ProfileSession?>(nil)
}
