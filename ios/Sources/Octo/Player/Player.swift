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
    /// Whether it should play: playing, or on its way to (connecting, buffering).
    private(set) var wantsToPlay = false
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
    /// The real lengths of songs whose listing was wrong, learned by playing them, by song id, so
    /// rows show the length of the sound.
    private(set) var learnedLengths: [String: Int] = [:]
    /// Counts the moments the position jumps or changes pace: a seek, a new song or the same one
    /// again, play or pause, a new speed. Views that run their own clock off the position take a
    /// fresh reading on each.
    private(set) var timeEvents = 0

    typealias RepeatMode = OctoKit.RepeatMode

    /// When the music stops on its own.
    enum SleepTimer: Equatable {
        case at(Date)
        /// After this many more songs end, counting the one playing.
        case afterSongs(Int)
    }

    /// The song on now. A live station shows what it has on air as the song, with "Artist ·
    /// Station" under it; while it names no song, its own name with its tagline or where it is.
    var current: Song? {
        guard queue.indices.contains(index) else { return nil }
        return liveShown(queue[index])
    }

    /// A station's lines as its stream names them now; any other song as it is.
    func liveShown(_ song: Song) -> Song {
        guard isRadio(song.id), let live = LiveTitleBoard.shared.shown(song.id) else { return song }
        var shown = song
        shown.title = live.title
        shown.artist = live.subtitle
        shown.displayArtist = live.subtitle
        return shown
    }

    /// What the live station on now has on air, nil while a song plays.
    var live: LiveShown? {
        guard let item = currentItem, item.isRadioStation else { return nil }
        return LiveTitleBoard.shared.shown(item.trackId)
    }

    /// The stations Back and Next step through while a live station plays, nil while a song
    /// plays.
    var lineup: LiveLineup? { liveLineup(items.map(\.trackId), current: index) }

    /// Whether the live station on now is on: playing or connecting, so its button is Stop.
    var liveOn: Bool { isPlaying || wantsToPlay }

    /// How long the listener has been on the live station, as the live bar shows it.
    var listened: String { listenedFor(Int(elapsed * 1_000)) }
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
    /// Told when Close takes the music off the lock screen, for the home screen widget.
    @ObservationIgnored var onClose: (() -> Void)?
    /// The car's now playing screen, told when the heart beside the song changes.
    @ObservationIgnored var onHeartChange: ((NotificationHeart) -> Void)? {
        get { nowPlaying.onHeartChange }
        set { nowPlaying.onHeartChange = newValue }
    }
    /// The heart or download beside the song on now.
    var heart: NotificationHeart { nowPlaying.heart }

    @ObservationIgnored private let sound: SoundProcessor
    @ObservationIgnored private let clock = MainClock()
    @ObservationIgnored private var tracker: PlayTracker!
    @ObservationIgnored private var sleepTimer: OctoKit.SleepTimer!
    @ObservationIgnored private var autoplay: Autoplay?
    @ObservationIgnored private var stationRefill: StationRefill?
    @ObservationIgnored private var nowPlaying: NowPlayingCenter!
    @ObservationIgnored private var headset: HeadsetWatch!
    @ObservationIgnored private let queueStore = QueueStore(rows: QueueFile.standard, parked: ParkedQueues(PlayerTexts()))
    @ObservationIgnored private let shared: PlayerShared
    @ObservationIgnored private var failuresInARow = 0
    /// The queue entry last opened again because the server began sending another file for it.
    @ObservationIgnored private var reopenedEntry: String?
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
    /// Lengths learned by playing, kept with songs found online too.
    @ObservationIgnored private var findLengths: FindLengths?
    /// Requests made while the saved queue was coming back, run in order once it is.
    @ObservationIgnored private var afterRestore: [@MainActor () -> Void] = []
    /// While the server in use changes, nothing is saved over the queue being handed over.
    @ObservationIgnored private var holding = false

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
        sleepTimer = OctoKit.SleepTimer(clock: SleepClock())
        sleepTimer.attach(engine)
        sleepTimer.onChange = { [weak self] state in self?.sleepState = state }
        nowPlaying = NowPlayingCenter(player: self)
        CarLink.player = self
        headset = HeadsetWatch(player: self)
        if let data {
            autoplay = Autoplay(data: data, player: self)
            let refill = StationRefill(data: data, player: self)
            refill.settled = { [weak self] in self?.autoplay?.check() }
            stationRefill = refill
            data.serverSwitch.player = self
            data.serverSwitch.onForget("playback") { [weak self] account in
                await self?.queueStore.forget(account)
                self?.serverQueue.forget(account)
            }
            data.plays.realLength = { [weak self] trackId, listedMs in
                Int64(self?.lengths.lengthMs(trackId, listedMs: Int(listedMs)) ?? Int(listedMs))
            }
            let store = data.library.store
            let lengths = lengths
            findLengths = FindLengths(
                store: { id, ms in try await store.setFindLength(id, durationMs: ms) },
                correct: { id, listed, measured in lengths.learn(id, listedMs: Int(listed), playerMs: Int(measured)).map(Int64.init) })
        }
        engine.songSetUp = { [sound] item in sound.songSetUp(soundSong(item)) }
        wireEngine()
        // A station's new title shows on the lock screen at once, and its song is looked up in
        // Octo for its cover and the heart; the cover follows when Octo answers.
        LiveTitleBoard.shared.onChange = { [weak self] in
            self?.lookUpLiveSong()
            self?.nowPlaying.publish()
        }
        LiveLookup.shared.onAnswer = { [weak self] in self?.nowPlaying.publish() }
        // A corrected length shows at once in the queue, the time line and the rows.
        lengths.onChange = { [weak self] corrected in
            Task { @MainActor in
                guard let self else { return }
                self.learnedLengths = corrected
                self.publishQueue()
                self.publishPosition()
            }
        }
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
            // The chosen song by its place; the first when it is gone.
            load(items, startIndex: shuffled ? -1 : chosenStart(found, start), shuffled: shuffled)
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
            load(items, startIndex: shuffled ? -1 : chosenStart(found, start), shuffled: shuffled)
        }
    }

    private func load(_ items: [QueueItem], startIndex: Int, shuffled: Bool) {
        headset.forgetLoss()
        // Shuffled, the queue starts at the first song of its random order.
        engine.setQueue(items, startIndex: shuffled ? -1 : startIndex, shuffled: shuffled, play: true)
    }

    /// A spoken request, like "play Nothing Was the Same". An album or artist named exactly (case,
    /// accents and punctuation aside) wins, then songs that match; saying nothing in particular
    /// shuffles everything. Only the library is searched. Nothing matching leaves the queue empty.
    func playFromSearch(_ query: String) async {
        guard let library = data?.library else { return }
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var ids: [String] = []
        var shuffled = false
        if text.isEmpty {
            ids = await library.tracks().sorted { $0.sortKey < $1.sortKey }.map(\.id)
            shuffled = true
        } else {
            let name = matchKey(text)
            let found = await library.search(text, artists: 5, albums: 5, songs: 50)
            if let album = found.albums.prefix(5).first(where: { !name.isEmpty && matchKey($0.title) == name }) {
                ids = await library.albumTracks(album.id).map(\.id)
            } else if let artist = found.artists.prefix(5).first(where: { SongIdentity.sameArtistName($0.name, text) }) {
                for album in await library.artistAlbums(artist.id) { ids += await library.albumTracks(album.id).map(\.id) }
                shuffled = true
            } else {
                ids = found.tracks.prefix(50).map(\.id)
            }
        }
        guard !ids.isEmpty else {
            engine.clear()
            return
        }
        let items = await playable.items(ids: ids, source: .none).compactMap { $0 }
        guard !items.isEmpty else {
            engine.clear()
            return
        }
        load(items, startIndex: 0, shuffled: shuffled)
    }

    func shuffle(_ songs: [Song]) {
        play(songs, shuffled: true)
    }

    /// Plays one of the server's lists from `start`: a station as a station, which adds more of
    /// its songs as it runs low, any other list under its name (`octoGroup` is the kind Octo says
    /// it is). A station shuffled has its songs put in a new order and played in it, so the songs
    /// it adds later come after them.
    func playServerList(_ songs: [Song], from start: Int = 0, id: String, name: String, octoGroup: String? = nil,
                        shuffled: Bool = false) {
        let source = serverListSource(id: id, name: name, octoGroup: octoGroup)
        if shuffled && source.isStation {
            play(songs.shuffled(), from: 0, source: source)
        } else {
            play(songs, from: start, source: source, shuffled: shuffled)
        }
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
            announce("No similar songs found")
            return
        }
        // Spaced on from the seed, which plays first; the queue is named for it.
        let ids = await LibraryRadio(data: data).songsLike([seed], count: radioLength, before: [seed.id])
        guard !ids.isEmpty else {
            announce("No similar songs found")
            return
        }
        let found = await playable.items(ids: [seed.id] + ids, source: .played("\(seed.title) radio"))
        let items = found.compactMap { $0 }
        guard !items.isEmpty else { return }
        radioSeed = song
        load(items, startIndex: 0, shuffled: false)
    }

    /// Plays the live station at `start` among the stations of the list it was tapped in, each
    /// by its radio id: the whole list is queued, in its order and never shuffled, so Back and
    /// Next step through it.
    func playStations(_ ids: [String], from start: Int) {
        let songs = ids.compactMap(radioSong)
        guard !songs.isEmpty else { return }
        radioSeed = nil
        Task {
            let found = await playable.items(songs, source: .played(nil))
            let items = found.compactMap { $0 }
            guard !items.isEmpty else { return }
            load(items, startIndex: chosenStart(found, min(max(start, 0), songs.count - 1)), shuffled: false)
        }
    }

    /// Plays the station tapped (`tapped` is its place in `stations`) among the stations of the
    /// list it was tapped in, each stream once, in the list's order.
    func playStations(_ stations: [(stream: String, id: String)], tapped: Int) {
        let lineup = lineupOf(stations, tapped: tapped, stream: { $0.stream }, id: { $0.id })
        playStations(lineup.ids, from: lineup.index)
    }

    /// Play or pause. With nothing queued, the whole library plays shuffled. Asked while the saved
    /// queue is still coming back, it waits for it.
    func toggle() {
        whenRestored { [weak self] in
            guard let self else { return }
            if self.engine.queue.isEmpty {
                Task { await self.shuffleLibrary() }
            } else if self.engine.playWhenReady && self.engine.state != .ended {
                self.pause()
            } else {
                self.resume()
            }
        }
    }

    /// Plays the queue. Asked while the saved queue is still coming back, it plays once it is.
    func resume() {
        whenRestored { [weak self] in
            guard let self, !self.engine.queue.isEmpty else { return }
            self.headset.forgetLoss()
            self.engine.play()
        }
    }

    /// A queue coming back is paused anyway, so a pause never waits.
    func pause() {
        headset.forgetLoss()
        engine.pause()
    }

    /// Runs a request now, or once the saved queue is back, in the order asked, so nothing
    /// mistakes a queue still coming back for an empty one.
    private func whenRestored(_ request: @escaping @MainActor () -> Void) {
        if restoring {
            afterRestore.append(request)
        } else {
            request()
        }
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
        onClose?()
    }

    /// Next always moves on, even when repeating one song. On a live station it is the next
    /// station of its list, and nothing at the last one.
    func next() {
        whenRestored { [weak self] in
            guard let self else { return }
            if let lineup = self.lineup {
                if let next = lineup.next { self.jump(to: next) }
                return
            }
            self.engine.next()
        }
    }

    /// Back to the start of the song, or to the one before when the song has barely begun. On a
    /// live station it is the station before in its list, and nothing at the first one.
    func previous() {
        whenRestored { [weak self] in
            guard let self else { return }
            if let lineup = self.lineup {
                if let previous = lineup.previous { self.jump(to: previous) }
                return
            }
            self.engine.previous()
        }
    }

    /// Plays the song at a queue position.
    func jump(to position: Int) {
        guard engine.queue.items.indices.contains(position) else { return }
        engine.seek(to: position)
        if !engine.playWhenReady { engine.play() }
    }

    /// Plays the queue entry with this key.
    func jump(toKey key: String) {
        guard let slot = (upNextSlots + playedSlots).first(where: { $0.key == key }) else { return }
        jump(to: slot.index)
    }

    /// Moves to `seconds` into the song. A live station cannot be moved through.
    func seek(to seconds: TimeInterval) {
        guard currentItem?.isRadioStation != true else { return }
        elapsed = max(0, seconds)
        tickedAt = Date()
        engine.seek(toMs: Int(max(0, seconds) * 1000))
        timeEvents += 1
        nowPlaying.publish()
    }

    func cycleRepeat() {
        setRepeat(repeatMode.cycled)
    }

    func setRepeat(_ mode: RepeatMode) {
        whenRestored { [weak self] in
            guard let self else { return }
            self.engine.repeatMode = mode
            self.repeatMode = mode
            self.autoplay?.check()
        }
    }

    /// Shuffle changes the play order only; the queue keeps its order.
    func toggleShuffle() {
        whenRestored { [weak self] in
            guard let self else { return }
            self.engine.shuffle = !self.engine.shuffle
            self.shuffled = self.engine.shuffle
            self.autoplay?.check()
        }
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

    /// "Play next": right after the song on now, in the queue and in the play order. With nothing
    /// queued, the songs wait there, paused.
    func playNext(_ songs: [Song]) {
        Task {
            let items = await playable.items(songs, source: .you).compactMap { $0 }
            whenRestored { self.engine.addNext(items) }
        }
    }

    /// "Add to queue": at the end, before any Autoplay songs still to come. With nothing queued,
    /// the songs wait there, paused.
    func append(_ songs: [Song]) {
        Task {
            let items = await playable.items(songs, source: .you).compactMap { $0 }
            whenRestored { self.engine.add(items) }
        }
    }

    /// Play next with an undo: undo finds the run of those songs nearest where they went in and
    /// takes it out.
    func playNextUndoable(_ songs: [Song], inserted: @escaping (@escaping () -> Void) -> Void) {
        Task { [weak self] in
            guard let self else { return }
            let items = await self.playable.items(songs, source: .you).compactMap { $0 }
            guard !items.isEmpty else { return }
            self.whenRestored { [weak self] in self?.putNextUndoable(items, inserted: inserted) }
        }
    }

    private func putNextUndoable(_ items: [QueueItem], inserted: @escaping (@escaping () -> Void) -> Void) {
        // Where the songs go in the list, which is where undo looks first.
        let near = min(engine.queue.current + 1, engine.queue.count)
        engine.addNext(items)
        let ids = items.map(\.trackId)
        inserted { [weak self] in
            guard let self else { return }
            if let first = findInserted(self.engine.queue.trackIds, ids, insertedAt: near) {
                self.engine.remove(from: first, to: first + ids.count)
            }
        }
    }

    func addAutoplay(_ items: [QueueItem]) {
        engine.add(items, at: engine.queue.count)
    }

    /// More of a station's songs, at the end of the queue.
    func addStationSongs(_ items: [QueueItem]) {
        engine.add(items, at: engine.queue.count)
    }

    /// Whether a station in the queue is being kept going, so Autoplay leaves it alone.
    var stationKeepsGoing: Bool { stationRefill?.keepsGoing ?? false }

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
        engine.edit { undo = $0.removeEntry(key); return undo?.ended ?? false }
        return undo
    }

    /// Songs not yet played go; the one playing stays.
    @discardableResult
    func clearUpcoming() -> QueueUndo? {
        var undo: QueueUndo?
        engine.edit { undo = $0.clearAllButCurrent(); return undo?.ended ?? false }
        return undo
    }

    @discardableResult
    func removePlayed() -> QueueUndo? {
        var undo: QueueUndo?
        engine.edit { undo = $0.removePlayed(); return undo?.ended ?? false }
        return undo
    }

    /// Takes these songs out wherever they are, as when their files are about to go.
    @discardableResult
    func removeSongs(_ trackIds: Set<String>) -> QueueUndo? {
        var undo: QueueUndo?
        engine.edit { undo = $0.removeSongs(trackIds); return undo?.ended ?? false }
        return undo
    }

    /// Moves a song already queued to play next.
    func playEntryNext(_ key: String) {
        engine.edit { _ = $0.playEntryNext(key); return false }
    }

    /// Puts an edit back; false when the queue changed some other way since.
    @discardableResult
    func undo(_ undo: QueueUndo) -> Bool {
        var done = false
        engine.edit { done = $0.undo(undo); return false }
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

    /// Puts back songs taken out since the snapshot, where they were.
    func restore(_ snapshot: QueueSnapshot) {
        guard !snapshot.items.isEmpty else { return }
        undo(QueueUndo(items: snapshot.items, order: snapshot.order, kept: engine.queue.items.map { $0.entryId ?? "" }))
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
            // Any pause or playing again forgets when the output went away; a pause because it
            // went away notes the time again after this.
            self.headset.forgetLoss()
            self.sleepTimer.playWhenReadyChanged(playWhenReady, endOfSong: endOfSong)
            if !playWhenReady {
                self.saveQueue()
                self.serverQueue.paused(self.queueSnapshot(), items: self.engine.queue.items)
                self.engine.silentWaitSeconds = self.headset.anyOn ? 1_800 : 600
            }
            self.publishState()
            // The lock screen's Play or Stop follows at once, a station still connecting too.
            self.nowPlaying.publish()
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
            if let findLengths = self.findLengths {
                let trackId = item.trackId, listed = Int64(item.durationMs)
                Task { try? await findLengths.learn(trackId, listedMs: listed, playerMs: Int64(measured)) }
            } else {
                _ = self.lengths.learn(item.trackId, listedMs: item.durationMs, playerMs: measured)
            }
            self.tracker.lengthFound(item.trackId, length: playingLengthMs(listedMs: self.lengths.lengthMs(item.trackId, listedMs: item.durationMs),
                                                                           playerMs: measured))
            self.publishPosition()
            self.publishQuality()
        }
    }

    private func songChanged(_ reason: SongChange) {
        timeEvents += 1
        publishQueue()
        publishPosition()
        publishQuality()
        sleepTimer.songChanged(reason)
        let item = engine.currentItem
        tracker.moved(item?.trackId, length: item.map { lengths.lengthMs($0.trackId, listedMs: $0.durationMs) } ?? 0)
        saveQueue()
        serverQueue.changed(queueSnapshot(), items: engine.queue.items)
        stationRefill?.check()
        autoplay?.check()
        lookUpLiveSong()
        nowPlaying.publish()
        updatePrefetch()
        ensureTicking()
    }

    /// Asks Octo once for the song the live station on now has on air.
    private func lookUpLiveSong() {
        guard let live, live.onAir.named else { return }
        LiveLookup.shared.start(live.onAir, session: session)
    }

    private func isPlayingChanged(_ playing: Bool) {
        isPlaying = playing
        timeEvents += 1
        tracker.playingChanged(playing)
        // Saved whenever the music stops being heard: a pause, the queue playing out, a stall.
        if !playing { saveQueue() }
        publishState()
        publishPosition()
        nowPlaying.publish()
        autoplay?.check()
        updatePrefetch()
        ensureTicking()
    }

    /// Hands fetching ahead what comes next: the queue in play order, repeat, and whether music plays.
    private func updatePrefetch() {
        guard let prefetcher = data?.prefetcher else { return }
        let state = engine.queue
        let repeatMode: PrefetchRepeat = switch state.repeatMode {
        case .off: .off
        case .one: .one
        case .all: .all
        }
        prefetcher.update(PrefetchQueue(entries: state.items.map { PrefetchEntry(trackId: $0.trackId, uri: $0.uri) },
                                        playOrder: state.playOrder(), current: state.current, repeatMode: repeatMode,
                                        playing: engine.isPlaying))
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
        stationRefill?.check()
        autoplay?.check()
        nowPlaying.publish()
        updatePrefetch()
    }

    /// A song that fails while music should play is skipped with one line; once as many songs
    /// have failed in a row as the queue holds, or nothing is next, it stops. The count starts
    /// over only when a song becomes ready. A live station that fails stops there with its line,
    /// never moving on to the next station by itself.
    private func failed(_ item: QueueItem, _ error: PlayError) {
        // The server began sending another file for the playing song: it opens again from where
        // it is, once for each time it is in the queue.
        if error.code == .sourceChanged, let entry = item.entryId, entry == engine.currentItem?.entryId, reopenedEntry != entry {
            reopenedEntry = entry
            engine.reopenCurrent()
            return
        }
        guard engine.playWhenReady else { return }
        let why = item.isRadioStation ? stationFailureWords(error) : playFailureOf(error, outside: item.isFind).words
        let title = item.title.trimmingCharacters(in: .whitespaces).isEmpty ? "a song" : item.title
        failuresInARow += 1
        playbackLog.info("playback failed: \(error.detail, privacy: .public)")
        if item.isRadioStation || failuresInARow >= engine.queue.count || engine.queue.nextForSkip == nil {
            announce(stoppedLine(title, why))
            engine.pause()
        } else {
            announce(skippedLine(title, why))
            engine.next()
            // A sound device that would not start is asked again for the next song.
            if !engine.output.isRunning { engine.play() }
        }
    }

    // MARK: Plays

    /// A song is heard for the first time: now playing, on the server and ListenBrainz.
    private func announceNowPlaying(_ trackId: String) {
        guard let item = engine.queue.items.first(where: { $0.trackId == trackId }) else { return }
        if isRadio(trackId) { return }
        if let data {
            data.plays.started(trackId)
            // A file opened from another app goes to ListenBrainz by its title and artist alone.
            if isOpenedFile(trackId) { ListenBrainzSync.shared.nowPlaying(openedFileSong(item)) }
            return
        }
        Task {
            if let serverId = parseStreamUri(item.uri)?.serverId, let client = session.client {
                try? await client.scrobble(serverId, submission: false, at: Date())
            }
        }
    }

    /// A song was heard enough to count: kept on the phone at once (an opened file under its own
    /// id, which no library song has), noted for the server in use now and sent there, and sent to
    /// ListenBrainz. Noted at once, so a play counted as a server switch begins still counts for
    /// the server it played from.
    private func recordPlay(_ trackId: String, startedAt: Int, heardMs: Int, durationMs: Int) {
        guard countsAsPlay(playedMs: heardMs, durationMs: durationMs), !isRadio(trackId) else { return }
        let item = engine.queue.items.first { $0.trackId == trackId }
        if let data {
            data.plays.record(trackId, startedAt: Int64(startedAt), playedMs: Int64(heardMs), durationMs: Int64(durationMs))
            if isOpenedFile(trackId), let item {
                ListenBrainzSync.shared.played(openedFileSong(item), startedAt: Date(timeIntervalSince1970: Double(startedAt) / 1000))
            }
            return
        }
        guard let item, let serverId = parseStreamUri(item.uri)?.serverId, let server = session.inUse else { return }
        Task {
            try? await server.client.scrobble(serverId, submission: true, at: Date(timeIntervalSince1970: Double(startedAt) / 1000))
        }
    }

    /// An opened file as ListenBrainz hears of it: its title and artist, and nothing else, never
    /// reaching the server.
    private func openedFileSong(_ item: QueueItem) -> PlayedSong {
        // The file's own title and artist, not the name shown for a file without them, so one
        // without them is not sent.
        let file = openedFileOf(item.trackId)
        return PlayedSong(file?.title ?? "", file?.artist ?? "", "",
                          durationMs: Int64(lengths.lengthMs(item.trackId, listedMs: item.durationMs)), trackNumber: nil, reachesServer: false)
    }

    // MARK: What the screens show

    private func publishQueue() {
        let queueState = engine.queue
        items = queueState.items
        // Each song shows the length of its sound once playing found its listing wrong.
        queue = queueState.items.map { lengths.applyTo(songOf($0)) }
        index = queueState.current
        repeatMode = queueState.repeatMode
        shuffled = queueState.shuffle
        upNextSlots = queueState.upNext()
        playedSlots = queueState.played()
        let soon = ([current].compactMap { $0 } + upNext.prefix(2))
        Covers.shared.coming(soon.compactMap { song in song.coverArt.map { (reference: $0, online: song.isExternal) } },
                             client: session.client)
    }

    private func publishState() {
        isPlaying = engine.isPlaying
        isWaiting = engine.playWhenReady && engine.state == .buffering
        wantsToPlay = engine.playWhenReady && engine.state != .ended
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

    /// The badge: what the deck opened once the song is open, the listed file type before then.
    private func publishQuality() {
        guard let item = engine.currentItem else {
            quality = nil
            return
        }
        let found = engine.playingQuality
        // The phone's output rate, when the song is resampled to play.
        let now = audioQuality(codecMime: found?.codecMime, fileMime: item.mimeType ?? item.fileMime, bitDepth: found?.bitDepth,
                               sampleRate: found?.sampleRate, bitrate: found?.bitrate)
            .map { $0.playingAt(Int(AVAudioSession.sharedInstance().sampleRate)) }
        if now != quality { quality = now }
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
        // The badge follows the deck: what opened once it opens, and the output's rate.
        publishQuality()
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
            timeEvents += 1
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
                                         filterSweeps: prefs.filterSweeps, beatMatch: prefs.matchTempo,
                                         fadeCurve: prefs.crossfadeCurve)
        shared.crossfadeOn.store(prefs.crossfadeMs > 0, ordering: .relaxed)
        let inUse = session.inUse
        let probed = session.active?.isOcto ?? false
        shared.profileSession.withLock {
            // Profiles are asked only of a server whose Octo page answered at sign-in (at home).
            $0 = inUse.map { ProfileSession(sourceId: $0.sourceId, isOcto: probed, extensions: $0.extensions, client: $0.client) }
        }
        stationRefill?.check()
        autoplay?.check()
    }

    // MARK: The queue kept on the phone

    private func queueSnapshot() -> OctoKit.QueueSnapshot {
        let state = engine.queue
        return OctoKit.QueueSnapshot(trackIds: state.trackIds, shuffleOrder: state.order, index: state.current,
                                     positionMs: max(0, engine.positionMs), repeatMode: state.repeatMode.rawValue,
                                     shuffle: state.shuffle, items: state.items)
    }

    /// Saves the queue in use now; never while it is coming back, or while a server switch hands
    /// the queues over.
    func saveQueue() {
        guard !restoring, !holding else { return }
        queueStore.save(queueSnapshot())
    }

    /// Brings back the queue in use, paused at its song and place, once the library is there.
    /// Requests made meanwhile run after, in order.
    private func restoreSaved() async {
        restoring = true
        defer {
            restoring = false
            let waiting = afterRestore
            afterRestore = []
            for request in waiting { request() }
        }
        if let data {
            let deadline = Date().addingTimeInterval(5)
            while data.library.ready == nil && Date() < deadline { try? await Task.sleep(for: .milliseconds(100)) }
        }
        guard let saved = await queueStore.load(), !saved.trackIds.isEmpty else {
            publishQueue()
            return
        }
        let resolved = await playable.items(ids: saved.trackIds, source: .none)
        let savedItems = saved.items ?? []
        var items: [QueueItem?] = []
        // Songs gone from the library are left out.
        for (position, id) in saved.trackIds.enumerated() {
            let old = savedItems.indices.contains(position) && savedItems[position].trackId == id ? savedItems[position] : nil
            if var fresh = resolved[position] {
                // Each song keeps where it came from; entries are given again as they go in.
                if let old { fresh.source = old.source }
                items.append(fresh)
            } else {
                items.append(nil)
            }
        }
        let found = items.map { $0 != nil }
        let point = restorePoint(found, savedIndex: saved.index, positionMs: saved.positionMs)
        let order = restoredShuffle(saved.shuffleOrder, found)
        let kept = items.compactMap { $0 }
        // Something started playing while the saved queue was read: that one stays.
        guard engine.queue.isEmpty else { return }
        guard !kept.isEmpty else {
            publishQueue()
            return
        }
        // Bringing the queue back is not a change for the server's copy of it.
        serverQueue.restored(OctoKit.QueueSnapshot(trackIds: kept.map(\.trackId), shuffleOrder: order ?? [], index: point.index,
                                                   positionMs: point.positionMs, repeatMode: saved.repeatMode, shuffle: saved.shuffle))
        engine.restoreQueue(kept, order: order, index: point.index, positionMs: point.positionMs,
                            repeatMode: RepeatMode(rawValue: saved.repeatMode) ?? .off, shuffle: saved.shuffle)
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
    /// Stops what plays for the server being left: the last song counts, and the player is
    /// emptied; then the queue goes to that server (at most 3 s). Nothing is saved over the queues
    /// until the switch is done.
    func leave() async -> Bool {
        holding = true
        saveSoon?.cancel()
        let wasPlaying = engine.isPlaying
        let left = queueSnapshot()
        let leftItems = engine.queue.items
        leftQueue = left.trackIds.isEmpty ? nil : left
        empty()
        if !left.trackIds.isEmpty { await serverQueue.leaving(left, items: leftItems) }
        return wasPlaying
    }

    /// What plays stops and counts, the timer goes, and the player is empty.
    private func empty() {
        guard !engine.queue.isEmpty else { return }
        tracker.flush()
        sleepTimer.cancel()
        engine.clear()
        radioSeed = nil
        publishQueue()
        publishPosition()
        nowPlaying.publish()
    }

    func handOver(from: String, to: String, keepWhenNone: Bool) async -> Bool {
        let left = leftQueue
        leftQueue = nil
        return await queueStore.handOver(from: from, left: left, to: to, keepWhenNone: keepWhenNone)
    }

    func serverArrived() {
        serverQueue.arrived()
    }

    /// The arriving server's queue comes back in place of whatever is in the player, paused.
    func restore() async {
        empty()
        await restoreSaved()
        holding = false
        saveQueue()
    }

    func keep() async {
        holding = false
    }

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

// MARK: Read by the full player

extension Player {
    /// The position as the playing deck has it at this moment, for views that move with the
    /// song every frame (the lyrics, the progress line).
    var livePosition: TimeInterval { Double(engine.positionMs) / 1_000 }
}
