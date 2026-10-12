import AVFoundation
import Foundation
import Network
import Observation
import OctoKit

/// Finds a song's lyrics and follows the song playing while lyrics show. Lyrics come from the
/// listener's pick, if any, or else from the server, then the song file, then an .lrc file
/// beside it, then (when allowed) the online library. Answers are kept per song, in memory and
/// in the cache folder. A server that keeps lyrics choices for every app (octoLyrics) has the
/// last word on its songs.
@MainActor
@Observable
final class LyricsStore {
    /// What the lyrics view shows.
    private(set) var state = LyricsState.hidden
    /// Whether the lyrics show in place of the artwork. Kept for as long as the app runs, so the
    /// player opens on lyrics again after it was closed on them.
    private(set) var open = false
    /// Bumped whenever a song's choice changes, so the menu reads it again.
    private(set) var choicesVersion = 0

    @ObservationIgnored private let session: Session
    @ObservationIgnored private let library: Library?
    @ObservationIgnored private weak var player: Player?
    @ObservationIgnored let choices = LyricsChoices(DefaultsValues(suite: "lyrics_choices"))
    @ObservationIgnored private let answers: LyricsAnswers
    @ObservationIgnored private var serverPicks: [String: String] = [:]
    @ObservationIgnored private var keepsChoices: [String: (yes: Bool, at: Date)] = [:]
    @ObservationIgnored private var revisions: [String: Int] = [:]
    @ObservationIgnored private let network = NetworkWatch()
    @ObservationIgnored private var feed: LyricsFeed?
    @ObservationIgnored private var songId: String?
    @ObservationIgnored private var watchers = 0
    /// Something has shown the lyrics within the last few seconds.
    @ObservationIgnored private var watched = false
    @ObservationIgnored private var leaving: Task<Void, Never>?
    @ObservationIgnored private var neighbors: Task<Void, Never>?
    /// The song whose neighbors are being looked up, while lyrics are open and watched.
    @ObservationIgnored private var neighborsOf: String?

    /// How long the lyrics view may be gone before it counts as off screen, so turning the
    /// phone does not count as leaving.
    static let leaveAfter: Duration = .seconds(5)
    /// How long a song must stay on before its neighbors' lyrics are looked up.
    static let prefetchSettle: Duration = .milliseconds(1200)
    /// How long what the server said about keeping lyrics choices is believed.
    static let recheckChoices: TimeInterval = 30 * 60
    /// How long to wait for the saved sign-in to come back as the app starts.
    static let sessionWait: Duration = .seconds(3)

    init(session: Session, library: Library? = nil, player: Player? = nil) {
        self.session = session
        self.library = library
        let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("lyrics")
        answers = LyricsAnswers(LyricsCache(folder))
        if let player {
            attach(player)
            followSong()
        }
    }

    /// Follows the song playing all the time, the player open or not.
    private func followSong() {
        withObservationTracking {
            _ = player?.current?.id
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.songChanged(self.player?.current?.id)
                self.followSong()
            }
        }
    }

    /// Whether the online library may be asked, as the app's settings say.
    var online: Bool {
        get { AppSettings.shared.player.lyricsOnline }
        set { if newValue != online { AppSettings.shared.setLyricsOnline(newValue) } }
    }

    /// How synced lyrics are drawn.
    enum Look { case flowing, classic }

    /// The lyrics style, as the app's settings say.
    var look: Look {
        get { AppSettings.shared.lyricsLook.style == .classic ? .classic : .flowing }
        set {
            let style: LyricsStyle = newValue == .classic ? .classic : .flowing
            if AppSettings.shared.lyricsLook.style != style { AppSettings.shared.setLyricsStyle(style) }
        }
    }

    // MARK: Following the song

    /// The player whose songs the lyrics follow.
    func attach(_ player: Player) {
        guard self.player !== player else { return }
        self.player = player
        if feed == nil {
            let feed = LyricsFeed(
                lookUp: { [weak self] id, resumed in
                    guard let self else { return .failed }
                    return try await self.lookUp(id, resumed: resumed)
                },
                networkBack: { [network] in try await network.awaitChange() },
                onState: { [weak self] state in self?.state = state }
            )
            self.feed = feed
            feed.start(wanted: wanted(), watched: watchers > 0)
        }
        songChanged(player.current?.id)
    }

    /// The song playing changed.
    func songChanged(_ id: String?) {
        guard id != songId else { return }
        songId = id
        refollow()
    }

    func toggle() {
        open.toggle()
        refollow()
    }

    func setOpen(_ on: Bool) {
        guard on != open else { return }
        open = on
        refollow()
    }

    /// Something shows the lyrics now (the lyrics view or the lyrics bar).
    func watch() {
        watchers += 1
        leaving?.cancel()
        leaving = nil
        watched = true
        feed?.setWatched(true)
        followNeighbors()
    }

    /// It stopped showing them. A short gap does not count as leaving.
    func unwatch() {
        watchers = max(0, watchers - 1)
        guard watchers == 0 else { return }
        leaving?.cancel()
        leaving = Task { [weak self] in
            try? await Task.sleep(for: Self.leaveAfter)
            guard !Task.isCancelled, let self, self.watchers == 0 else { return }
            self.watched = false
            self.feed?.setWatched(false)
            self.followNeighbors()
        }
    }

    /// Whether nothing shows the lyrics right now, for what a lookup saves.
    private var away: Bool { watchers == 0 }

    private func wanted() -> LyricsWanted? {
        guard open, let id = songId else { return nil }
        let choice = choices.current(id)
        return LyricsWanted(id, hidden: choice.hidden, version: "\(choice.pick?.encoded ?? "")#\(revisions[id] ?? 0)")
    }

    private func refollow() {
        feed?.setWanted(wanted())
        followNeighbors()
    }

    /// Asks for the song's lyrics again, for the lyrics view's "tap to retry".
    func retry(_ songId: String) { refresh(songId) }

    private func refresh(_ songId: String) {
        revisions[songId, default: 0] += 1
        choicesVersion += 1
        refollow()
    }

    /// While lyrics show on screen, the songs either side of this one in play order (the next to
    /// play and the last played) have theirs looked up once the song has settled, so skipping
    /// shows them at once. A skip before then starts the wait again; radio stations are left
    /// out, and a neighbor's failed lookup saves nothing.
    private func followNeighbors() {
        let key = open && watched ? songId : nil
        guard key != neighborsOf else { return }
        neighborsOf = key
        neighbors?.cancel()
        guard let id = key, let player else { return }
        neighbors = Task { [weak self] in
            try? await Task.sleep(for: Self.prefetchSettle)
            guard !Task.isCancelled, let self else { return }
            let slots = [player.upNextSlots.dropFirst().first, player.playedSlots.last].compactMap { $0 }
            let around = slots.compactMap { player.items.indices.contains($0.index) ? player.items[$0.index] : nil }
            for item in around where !isRadio(item.trackId) && item.trackId != id {
                guard !Task.isCancelled else { return }
                let facts = LyricsSong(item.trackId, item.title, item.artist, "", item.durationMs)
                _ = try? await self.answerFor(facts, resumed: false)
            }
        }
    }

    private func lookUp(_ id: String, resumed: Bool) async throws -> LyricsAnswer {
        let current = player?.current.flatMap { $0.id == id ? $0 : nil }
        let song = LyricsSong(id, current?.title ?? "", current?.byline ?? "", current?.album ?? "", (current?.duration ?? 0) * 1000)
        return try await answerFor(song, resumed: resumed)
    }

    // MARK: Looking lyrics up

    /// The song's lyrics, None when every source answered without any (or the listener hid
    /// them), or Failed when the lookup could not finish. Lyrics the listener picked come first,
    /// while their source still has them; when it does not, the usual order stands in and the
    /// pick is tried again next time.
    func answerFor(_ song: LyricsSong, resumed: Bool) async throws -> LyricsAnswer {
        let choice = choices.current(song.id)
        let onlineAllowed = online
        if choice.hidden { return .none }
        let picked = choice.pick?.encoded
        return try await answers.answer(song.id, picked: picked, onlineAllowed: onlineAllowed, resumed: resumed, away: { [weak self] in
            self?.away ?? true
        }) {
            try await self.search(song, pick: choice.pick, picked: picked, onlineAllowed: onlineAllowed)
        }
    }

    private func search(_ song: LyricsSong, pick: LyricsPick?, picked: String?, onlineAllowed: Bool) async throws -> LyricsSearch {
        let facts = await described(song)
        let phone = await phoneFile(song.id)
        if let pick {
            if let found = try? await fetchPick(pick, facts, phone, onlineAllowed: onlineAllowed), !found.isEmpty {
                return LyricsSearch(found, complete: true, askedOnline: true, pick: picked)
            }
            try Task.checkCancellation()
        }
        let serverDecides = await serverKeepsChoices(for: song.id)
        let online = OnlineLyrics(userAgent: session.client?.userAgent)
        let server: @Sendable () async throws -> Lyrics? = { [weak self] in try await self?.fromServer(facts, forLookup: true) }
        var songFile: (@Sendable () async throws -> Lyrics?)?
        var lyricsFile: (@Sendable () async throws -> Lyrics?)?
        if let phone {
            songFile = { try await Self.fromSongFile(phone) }
            lyricsFile = { Self.fromLyricsFile(phone) }
        }
        var fromOnline: (@Sendable () async throws -> Lyrics?)?
        if onlineAllowed && !facts.title.isBlank && !facts.artist.isBlank {
            // The length is read when the online library is asked, after the server, by when the
            // song playing has usually opened.
            fromOnline = { [weak self] in
                let length = await self?.lengthOf(facts) ?? facts.durationMs
                return try await online.find(facts.title, artist: facts.artist, album: facts.album, durationMs: length)
            }
        }
        let steps = lyricsSteps(server: server, serverDecides: serverDecides, songFile: songFile, lyricsFile: lyricsFile,
                                online: fromOnline)
        return try await searchInOrder(steps)
    }

    /// The lyrics a pick names, fetched from its source again.
    private func fetchPick(_ pick: LyricsPick, _ facts: LyricsSong, _ phone: URL?, onlineAllowed: Bool) async throws -> Lyrics? {
        switch pick {
        case .online(let id):
            return onlineAllowed ? try await OnlineLyrics(userAgent: session.client?.userAgent).byId(id) : nil
        case .onServer:
            return try await fromServer(facts)
        case .own(let source):
            switch source {
            case .server: return try await fromServer(facts)
            case .songFile: return try await phone.asyncMap(Self.fromSongFile)
            case .lyricsFile: return phone.flatMap(Self.fromLyricsFile)
            case .online: return nil
            }
        }
    }

    /// Uses these lyrics for the song from now on, on this phone. They are kept as the song's
    /// answer before the pick is saved, so the lyrics view, which follows the pick, finds them at
    /// once. A copy the server holds is chosen with chooseOnServer instead.
    func choose(_ songId: String, _ candidate: LyricsCandidate) {
        guard let lyrics = candidate.lyrics else { return }
        let entry = CachedLyrics(savedAt: Self.nowMs, lyrics: lyrics, askedOnline: true, lookupVersion: ONLINE_LOOKUP_VERSION,
                                 pick: candidate.pick.encoded)
        answers.keep(songId, entry)
        choices.pick(songId, candidate.pick)
        choicesVersion += 1
        refollow()
    }

    /// Sets the song's lyrics on the server, for every app: one of its copies by id, "auto" or
    /// "none". This phone then follows the server and the song's lyrics are fetched again at
    /// once. Throws when the server cannot take it.
    func chooseOnServer(_ songId: String, _ choice: String, showAgain: Bool = false) async throws {
        guard let client = session.client, let server = await serverSong(songId) else { throw LyricsStoreError.notOnServer }
        try await sendServerChoice(songId, choice, choices, send: { [weak self] wanted in
            let now = try await client.setLyricsChoice(server.id, candidate: wanted)
            self?.notePin(songId, now)
        }, forget: { [answers] in answers.forget(songId) }, showAgain: showAgain)
        refresh(songId)
    }

    /// Hides the song's lyrics: on the server too, for every app, when it keeps lyrics choices,
    /// or else only on this phone.
    func hide(_ songId: String) async {
        if await !onServerIfKept(songId, LYRICS_NONE) { choices.hide(songId) }
        choicesVersion += 1
        refollow()
    }

    /// Shows the song's lyrics again, on the server too when it keeps lyrics choices.
    func show(_ songId: String) async {
        if await !onServerIfKept(songId, LYRICS_AUTO, showAgain: true) { choices.show(songId) }
        choicesVersion += 1
        refollow()
    }

    private func onServerIfKept(_ songId: String, _ choice: String, showAgain: Bool = false) async -> Bool {
        guard await serverKeepsChoices(for: songId) else { return false }
        do {
            try await chooseOnServer(songId, choice, showAgain: showAgain)
            return true
        } catch {
            return false
        }
    }

    // MARK: Choosing

    /// Every set of lyrics that can be found for the song, for the listener to choose from. With
    /// a server that keeps lyrics choices for every app: its automatic answer, the copies its
    /// sources hold, and the song file's and .lrc file's. Otherwise: the server's, the song
    /// file's, the .lrc file's, and (when allowed) the online library's match and the copies its
    /// search holds with the same title and artist. A source that cannot be reached is named in
    /// the answer and left out.
    func candidatesFor(_ song: LyricsSong) async -> CandidateSearch {
        let onlineAllowed = online
        let facts = await described(song)
        let phone = await phoneFile(song.id)
        if let server = await serverSong(song.id), await keepsChoicesNow(),
           let found = await serverCandidatesFor(song.id, server.id, facts, phone, onlineAllowed: onlineAllowed) {
            return found
        }
        return await localCandidatesFor(facts, phone, onlineAllowed: onlineAllowed)
    }

    private func serverCandidatesFor(_ songId: String, _ serverId: String, _ facts: LyricsSong, _ phone: URL?,
                                     onlineAllowed: Bool) async -> CandidateSearch? {
        guard let client = session.client else { return nil }
        var missed = Set<LyricsSource>()
        var listed: LyricsCandidates?
        do {
            listed = try await client.lyricsCandidates(serverId)
        } catch is URLError {
            missed.insert(.server)
        } catch OctoError.server {
            noteKeepsChoices(false)
            return nil
        } catch {
            return nil
        }
        let choice = listed?.choice ?? LYRICS_AUTO
        if listed != nil {
            notePin(songId, choice)
            // Changed from another app or device since this phone saved it.
            if servedStale(answers.saved(songId), choice) {
                answers.forget(songId)
                refresh(songId)
            }
        }
        let askServer = listed != nil && choice == LYRICS_AUTO
        async let answer: (Lyrics?, Bool) = askServer ? attempt { try await self.fromServer(facts) } : (nil, false)
        async let songFile: (Lyrics?, Bool) = attempt(phone) { try await Self.fromSongFile($0) }
        async let lyricsFile: (Lyrics?, Bool) = attempt(phone) { Self.fromLyricsFile($0) }
        let (served, serverFailed) = await answer
        let (tagged, tagFailed) = await songFile
        let (beside, fileFailed) = await lyricsFile
        if serverFailed { missed.insert(.server) }
        if tagFailed { missed.insert(.songFile) }
        if fileFailed { missed.insert(.lyricsFile) }
        var local: [LyricsCandidate] = []
        if let tagged { local.append(LyricsCandidate(.own(.songFile), .songFile, tagged)) }
        if let beside { local.append(LyricsCandidate(.own(.lyricsFile), .lyricsFile, beside)) }
        return CandidateSearch(serverCandidates(listed, served, local), missed: missed, onlineAllowed: onlineAllowed, serverChoice: choice)
    }

    private func localCandidatesFor(_ facts: LyricsSong, _ phone: URL?, onlineAllowed: Bool) async -> CandidateSearch {
        let askOnline = onlineAllowed && !facts.title.isBlank && !facts.artist.isBlank
        let online = OnlineLyrics(userAgent: session.client?.userAgent)
        let length = lengthOf(facts)
        async let server: (Lyrics?, Bool) = attempt { try await self.fromServer(facts) }
        async let songFile: (Lyrics?, Bool) = attempt(phone) { try await Self.fromSongFile($0) }
        async let lyricsFile: (Lyrics?, Bool) = attempt(phone) { Self.fromLyricsFile($0) }
        async let match: (OnlineCopy?, Bool) = askOnline
            ? attempt { try await online.exact(facts.title, artist: facts.artist, album: facts.album, durationMs: length) } : (nil, false)
        async let search: ([OnlineCopy]?, Bool) = askOnline
            ? attempt { try await online.copiesOf(facts.title, artist: facts.artist, album: facts.album, durationMs: length) } : (nil, false)
        var missed = Set<LyricsSource>()
        var found: [LyricsCandidate] = []
        let (fromServer, serverFailed) = await server
        if let fromServer { found.append(LyricsCandidate(.own(.server), .server, fromServer)) }
        if serverFailed { missed.insert(.server) }
        let (tagged, tagFailed) = await songFile
        if let tagged { found.append(LyricsCandidate(.own(.songFile), .songFile, tagged)) }
        if tagFailed { missed.insert(.songFile) }
        let (beside, fileFailed) = await lyricsFile
        if let beside { found.append(LyricsCandidate(.own(.lyricsFile), .lyricsFile, beside)) }
        if fileFailed { missed.insert(.lyricsFile) }
        let (exact, exactFailed) = await match
        if let exact { found.append(exact.asCandidate(.onlineMatch)) }
        let (copies, copiesFailed) = await search
        for copy in copies ?? [] { found.append(copy.asCandidate(.onlineSearch)) }
        if exactFailed || copiesFailed { missed.insert(.online) }
        return CandidateSearch(found, missed: missed, onlineAllowed: onlineAllowed)
    }

    /// Runs one source for the chooser: what it found, and whether it could not be reached.
    private nonisolated func attempt<T: Sendable>(_ fetch: @Sendable () async throws -> T?) async -> (T?, Bool) {
        do {
            return (try await fetch(), false)
        } catch {
            return (nil, !Task.isCancelled)
        }
    }

    /// Runs a source that reads the song's file, when it has one.
    private nonisolated func attempt<T: Sendable>(_ file: URL?, _ fetch: @Sendable (URL) async throws -> T?) async -> (T?, Bool) {
        guard let file else { return (nil, false) }
        return await attempt { try await fetch(file) }
    }

    /// What the online library finds for words the listener typed.
    func searchOnline(_ query: String) async throws -> [LyricsCandidate] {
        try await OnlineLyrics(userAgent: session.client?.userAgent).search(query).map { $0.asCandidate(.onlineSearch) }
    }

    /// What the server's sources find for words the listener typed, for a song whose tags are
    /// wrong: "artist - title", or a title.
    func searchOnServer(_ songId: String, _ query: String) async throws -> [LyricsCandidate] {
        guard let client = session.client, let server = await serverSong(songId) else { throw LyricsStoreError.notOnServer }
        let (title, artist) = splitLyricsSearch(query)
        let found = try await client.lyricsCandidates(server.id, title: title, artist: artist)
        return found.candidate.filter { !$0.id.isBlank }.map { $0.asCandidate() }
    }

    // MARK: Sources

    /// The server's lyrics for the song. A server with the songLyrics extension is asked by song
    /// id (version 2 adds word timings); an older one by artist and title. Lyrics from a copy the
    /// server has pinned say which.
    private func fromServer(_ song: LyricsSong, forLookup: Bool = false) async throws -> Lyrics? {
        guard let client = try await signedIn(forLookup: forLookup), let server = await serverSong(song.id) else { return nil }
        var found: Lyrics?
        do {
            switch serverLyricsCall(session.extensions) {
            case .byName:
                found = try await client.lyrics(artist: server.copy?.artist ?? song.artist, title: server.copy?.title ?? song.title)
                    .flatMap { parseLyricsText($0, source: .server) }
            case let call:
                let all = try await client.lyricsBySongId(server.id, enhanced: call == .withWords)
                found = serverLyrics(all, language: Self.phoneLanguage)
            }
        } catch OctoError.notFound {
            found = nil
        }
        if let pinned = serverPicks[song.id] { found?.serverPick = pinned }
        return found
    }

    /// The phone's own language, whatever languages the app itself is written in.
    private static var phoneLanguage: String? {
        Locale.preferredLanguages.first.flatMap { Locale.Language(identifier: $0).languageCode?.identifier }
    }

    /// The server in use once the saved sign-in is back, waiting a moment for it as the app
    /// starts. For a lookup, a sign-in still not back is an error, not "not on the server".
    private func signedIn(forLookup: Bool) async throws -> SubsonicClient? {
        if let client = session.client { return client }
        guard session.activeId != nil else { return nil }
        let deadline = ContinuousClock.now + Self.sessionWait
        while session.client == nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(100))
        }
        if let client = session.client { return client }
        if forLookup { throw URLError(.notConnectedToInternet) }
        return nil
    }

    /// The song on the server in use: its id there, and the library's copy of it when there is
    /// one. A song found online is the server's own find; a library song is on the server when
    /// the library holds a copy from it; a server song the library does not hold streams by its
    /// own id. Nil when the song is not on the server.
    private func serverSong(_ songId: String) async -> (id: String, copy: SourceTrack?)? {
        guard session.client != nil else { return nil }
        if isFind(songId) { return (String(songId.dropFirst(findPrefix.count)), nil) }
        let inUse = library?.serverInUse ?? session.inUse?.sourceId
        if let library, let inUse, let copy = await library.copies(songId).first(where: { $0.sourceId == inUse }) {
            return (copy.nativeId, copy)
        }
        if let item = player?.items.first(where: { $0.trackId == songId }), let ref = parseStreamUri(item.uri),
           ref.sourceId == nil || ref.sourceId == inUse {
            return (ref.serverId, nil)
        }
        // Server ids never hold a ":"; library ids always do.
        if !songId.contains(":") { return (songId, nil) }
        return nil
    }

    /// Whether the song is on a server that keeps lyrics choices for every app.
    private func serverKeepsChoices(for songId: String) async -> Bool {
        guard await serverSong(songId) != nil else { return false }
        return await keepsChoicesNow()
    }

    /// Whether the server keeps lyrics choices for every app: from what it listed at sign-in, or
    /// by asking, since it may have been updated since. A "no" learned from the server itself
    /// stands over what it listed, for a while; no answer at all is taken as no and not kept.
    private func keepsChoicesNow() async -> Bool {
        guard let client = session.client, let server = session.activeId else { return false }
        if let known = keepsChoices[server], Date().timeIntervalSince(known.at) < Self.recheckChoices { return known.yes }
        if offersLyricsChoices(session.extensions) { return true }
        guard let yes = await client.supportsIfKnown(OCTO_LYRICS, version: 1) else { return false }
        noteKeepsChoices(yes)
        return yes
    }

    private func noteKeepsChoices(_ yes: Bool) {
        guard let server = session.activeId else { return }
        keepsChoices[server] = (yes, Date())
    }

    /// Remembers what the server has the song set to, for where its lyrics are from.
    private func notePin(_ songId: String, _ choice: String) {
        if choice == LYRICS_AUTO || choice == LYRICS_NONE { serverPicks[songId] = nil } else { serverPicks[songId] = choice }
    }

    /// The song's file on this phone, when it has one: its first copy on the phone with an
    /// address (a Music app song, or a file brought in from Files). A song found online has none.
    private func phoneFile(_ songId: String) async -> URL? {
        guard !isFind(songId), let library else { return nil }
        let copy = await library.copies(songId).first { $0.sourceId == deviceSource && !($0.uri ?? "").isEmpty }
        return copy?.uri.flatMap(URL.init(string:))
    }

    /// Lyrics in the song file's own tags.
    private nonisolated static func fromSongFile(_ file: URL) async throws -> Lyrics? {
        let asset = AVURLAsset(url: file)
        var tags: [(key: String, value: [String])] = []
        for format in try await asset.load(.availableMetadataFormats) {
            for item in try await asset.loadMetadata(for: format) {
                guard let value = try? await item.load(.stringValue), !value.isEmpty else { continue }
                let key: String
                switch item.identifier {
                case .id3MetadataUnsynchronizedLyric, .iTunesMetadataLyrics: key = "LYRICS"
                default:
                    guard let raw = item.key as? String, raw.uppercased().hasPrefix("LYRICS") || raw.uppercased().contains("LYRICS") else { continue }
                    key = raw.uppercased()
                }
                tags.append((key, [value]))
            }
        }
        return songFileLyrics(tags).flatMap { parseLyricsText($0, source: .songFile) }
    }

    /// Lyrics in a .lrc file beside the song. A Music app song has no folder, so only a file has
    /// one beside it.
    private nonisolated static func fromLyricsFile(_ file: URL) -> Lyrics? {
        guard file.isFileURL else { return nil }
        return lyricsFileBeside(file).flatMap { parseLyricsText($0, source: .lyricsFile) }
    }

    /// The library's own facts for the song where it has them, since what the player shows can
    /// be shortened; a blank fact, or no length, is taken from what was given.
    private func described(_ song: LyricsSong) async -> LyricsSong {
        guard let library else { return song }
        var known: LyricsSong?
        if isFind(song.id) {
            if let find = await library.finds([song.id]).first {
                known = LyricsSong(song.id, find.title, find.artist, find.album, Int(find.durationMs))
            }
        } else if let track = await library.track(song.id) {
            known = LyricsSong(song.id, track.title, track.artist, track.album, Int(track.durationMs))
        }
        guard let known else { return song }
        return LyricsSong(
            song.id,
            known.title.isBlank ? song.title : known.title,
            known.artist.isBlank ? song.artist : known.artist,
            known.album.isBlank ? song.album : known.album,
            known.durationMs > 0 ? known.durationMs : song.durationMs
        )
    }

    /// The length the online library matches a song by: its real one once playing it found the
    /// listing wrong.
    private func lengthOf(_ song: LyricsSong) -> Int {
        player?.lengths.lengthMs(song.id, listedMs: song.durationMs) ?? song.durationMs
    }

    private static var nowMs: Int { Int(Date().timeIntervalSince1970 * 1000) }
}

/// What the lyrics store says when the song is not on the server in use.
enum LyricsStoreError: LocalizedError {
    case notOnServer

    var errorDescription: String? { "The song is not on the server" }
}

extension String {
    fileprivate var isBlank: Bool { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

extension Optional {
    fileprivate func asyncMap<T>(_ transform: (Wrapped) async throws -> T?) async rethrows -> T? {
        guard let value = self else { return nil }
        return try await transform(value)
    }
}

/// Follows the phone's network, so a lyrics lookup that failed can be tried again once there is
/// a network to try on.
final class NetworkWatch: @unchecked Sendable {
    private let monitor = NWPathMonitor()
    private let lock = NSLock()
    private var network: String?
    private var waiting: [UUID: (String?, CheckedContinuation<Void, Error>)] = [:]

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            // The network in use: the preferred interface, the first of those available.
            let name = path.status == .satisfied ? path.availableInterfaces.first?.name : nil
            self?.changed(name)
        }
        monitor.start(queue: DispatchQueue(label: "app.winters.octo.lyrics.network"))
    }

    private func changed(_ name: String?) {
        lock.lock()
        network = name
        var ready: [CheckedContinuation<Void, Error>] = []
        for (id, entry) in waiting where name != nil && name != entry.0 {
            ready.append(entry.1)
            waiting[id] = nil
        }
        lock.unlock()
        for one in ready { one.resume() }
    }

    /// Returns once the phone has a network other than the one it has now: one back after none,
    /// or a switch to another.
    func awaitChange() async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                lock.lock()
                if Task.isCancelled {
                    lock.unlock()
                    continuation.resume(throwing: CancellationError())
                    return
                }
                waiting[id] = (network, continuation)
                lock.unlock()
            }
        } onCancel: {
            lock.lock()
            let entry = waiting.removeValue(forKey: id)
            lock.unlock()
            entry?.1.resume(throwing: CancellationError())
        }
    }
}
