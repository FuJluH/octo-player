import Foundation
import Observation
import OctoKit

/// Search's state: what is typed, which kind is shown, the library's answers, what the server
/// found beyond them, the top songs of an artist the search names, the chart before anything is
/// typed, and the recent searches.
@MainActor
@Observable
final class SearchModel {
    var text = "" {
        didSet { if text != oldValue { textChanged() } }
    }

    var filter: SearchFilter = .all {
        didSet { if filter != oldValue { searchLibrary(wait: false); askTopSongs() } }
    }

    /// Whether the artist's top songs, and the chart, show every song or only the first few.
    var topOpen = false
    var chartOpen = false

    /// Nil until at least two characters are typed.
    private(set) var results: LibraryResults?
    private(set) var discover: DiscoverState = .idle
    private(set) var topSongs: RankedSongs<Song>?
    private(set) var chart: RankedSongs<Song>?
    private(set) var recent: [String] = []
    private(set) var hint = AddHintState()

    @ObservationIgnored private var discovery: Discovery?
    @ObservationIgnored private var player: Player?
    @ObservationIgnored private var downloads: Downloads?
    @ObservationIgnored private var libraryTask: Task<Void, Never>?
    @ObservationIgnored private var discoverTask: Task<Void, Never>?
    @ObservationIgnored private var topTask: Task<Void, Never>?
    @ObservationIgnored private var chartTask: Task<Void, Never>?
    @ObservationIgnored private var askedServer: String??
    @ObservationIgnored private var askedText: String?
    @ObservationIgnored private var namedFor: (NamedArtist, String)?
    @ObservationIgnored private var libraryKey: String?
    /// What is typed, trimmed, as it stood when typing last paused.
    @ObservationIgnored private var settledText = ""
    /// Whether this visit has counted the line saying what the plus does.
    @ObservationIgnored private(set) var hintCounted = false

    #if DEBUG
    /// How the server's answer is bent for a drive step: "hold", "fail" or "empty"; nil as usual.
    static var driveOnline: String?
    #endif

    private static let recentKey = "search.recent"
    static let hintShownKey = "add_hint.shown"
    static let hintAddedKey = "add_hint.added"

    init() {
        recent = decodeRecent(UserDefaults.standard.string(forKey: Self.recentKey))
        hint = Self.storedHint()
    }

    func attach(discovery: Discovery, player: Player, downloads: Downloads) {
        let first = self.discovery == nil
        self.discovery = discovery
        self.player = player
        self.downloads = downloads
        hint = Self.storedHint()
        if first { serverChanged() }
    }

    var signedIn: Bool { discovery?.available ?? false }

    // MARK: Changes

    private func textChanged() {
        searchLibrary(wait: true)
        askServer()
    }

    /// The playlists changed: the library is searched again.
    func playlistsChanged() { if results != nil { searchLibrary(wait: false) } }

    /// Another server in use, or signed in or out: the server is asked anew, and its chart.
    func serverChanged() {
        askServer()
        askTopSongs()
        chartTask?.cancel()
        chartTask = nil
        chart = nil
        askChart()
    }

    /// Search is on screen again: the chart is asked for again, which is the one kept within the
    /// hour, a fresh one after it, and another try when the last ask came back with nothing.
    func shownAgain() {
        guard chartTask == nil else { return }
        askChart()
    }

    private func askChart() {
        guard let discovery, discovery.server != nil else { return }
        chartTask = Task { [weak self] in
            let list = await discovery.popularChart()
            guard !Task.isCancelled, let self else { return }
            self.chart = list
            self.chartTask = nil
        }
    }

    /// The library is searched once typing pauses, on the folded text, and again when the kind
    /// changes or the server is asked anew.
    private func searchLibrary(wait: Bool) {
        let folded = searchKey(text)
        let typed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let filter = self.filter
        libraryTask?.cancel()
        libraryTask = Task { [weak self] in
            if wait { try? await Task.sleep(for: .milliseconds(librarySearchAfterMs)) }
            guard !Task.isCancelled, let self else { return }
            self.settledText = typed
            guard folded.count >= 2, let discovery = self.discovery else {
                self.setResults(nil)
                return
            }
            var found = await discovery.searchLibrary(folded, caps: searchCaps(filter))
            guard !Task.isCancelled else { return }
            found.listedFinds = listedFinds(self.downloads?.adoptions ?? [:], songIds: found.songs.map(\.id))
            self.setResults(found)
        }
    }

    private func setResults(_ found: LibraryResults?) {
        results = found
        askTopSongs()
    }

    /// Says it is looking as soon as the text changes, then asks once typing pauses; new text
    /// cancels the question before it. Another server in use asks it anew.
    private func askServer() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let server = discovery?.server
        let query: String? = server != nil && searchKey(trimmed).count >= 2 ? trimmed : nil
        if askedText == query, askedServer == .some(server) { return }
        askedText = query
        askedServer = .some(server)
        discoverTask?.cancel()
        guard let query, let discovery else {
            discover = .idle
            return
        }
        discover = .loading
        discoverTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(discoverAfterMs))
            guard !Task.isCancelled, let self else { return }
            // The library is searched again each time the server is asked anew.
            self.searchLibrary(wait: false)
            #if DEBUG
            if Self.driveOnline == "hold" { return }
            if Self.driveOnline == "fail" {
                self.discover = .failed
                return
            }
            #endif
            do {
                var found = try await discovery.search(query)
                guard !Task.isCancelled else { return }
                #if DEBUG
                if Self.driveOnline == "empty" { found = found.map { _ in Discovered(songs: [], albums: [], artists: []) } }
                #endif
                self.discover = found.map { .done($0) } ?? .idle
            } catch {
                guard !Task.isCancelled else { return }
                self.discover = .failed
            }
            self.askTopSongs()
        }
    }

    /// The top songs of the artist the search names, from the library's artists or those found
    /// online, only for everything at once, worked out from the text once typing pauses. Each
    /// change of artist closes "Show all" first.
    private func askTopSongs() {
        var named: (NamedArtist, String)?
        if filter == .all, let results, let server = discovery?.server {
            let online: [OnlineArtist] = if case .done(let found) = discover { found.artists } else { [] }
            named = namedArtist(settledText, library: results.artists, online: online).map { ($0, server) }
        }
        if named?.0 == namedFor?.0 && named?.1 == namedFor?.1 { return }
        namedFor = named
        topTask?.cancel()
        topOpen = false
        topSongs = nil
        guard let (artist, _) = named, let discovery else { return }
        topTask = Task { [weak self] in
            let list = await discovery.artistTopSongs(name: artist.name, libraryId: artist.libraryId, serverId: artist.serverId)
            guard !Task.isCancelled else { return }
            self?.topSongs = list
        }
    }

    /// Asks the server again after it could not be reached.
    func retryOnline() {
        askedText = nil
        askServer()
    }

    // MARK: Recent searches

    /// Keeps what was typed among the recent searches, once it led to a result being opened or
    /// played.
    func keepSearch() { saveRecent(withRecent(recent, text)) }

    func searchAgain(_ query: String) { text = query }

    func forget(_ query: String) { saveRecent(withoutRecent(recent, query)) }

    func forgetAll() { saveRecent([]) }

    private func saveRecent(_ list: [String]) {
        recent = list
        UserDefaults.standard.set(encodeRecent(list), forKey: Self.recentKey)
    }

    // MARK: Playing

    /// Plays the library songs found from the one tapped.
    func playSong(_ track: LibraryTrack) {
        guard let tracks = results?.songs, let player else { return }
        keepSearch()
        player.play(tracks.map(\.asSong), from: max(0, tracks.firstIndex { $0.id == track.id } ?? 0))
    }

    /// Plays a ranked list from the song tapped. The chart names no artist, so it is not kept.
    func playRanked(_ list: RankedSongs<Song>, _ index: Int) {
        if list.artist != nil { keepSearch() }
        player?.play(list.songs.map(\.track), from: max(0, index))
    }

    /// Plays the songs found online from the one tapped.
    func playFound(_ song: Song) {
        guard case .done(let found) = discover, let player else { return }
        keepSearch()
        let songs = found.songs.map(\.asSong)
        player.play(songs, from: max(0, songs.firstIndex(where: { $0.id == song.id }) ?? 0))
    }

    // MARK: The add hint

    var showsHint: Bool { showsAddHint(hint, countedThisVisit: hintCounted) }

    /// The line came on screen: one showing, however many searches follow.
    func hintSeen() {
        if hintCounted { return }
        hintCounted = true
        let shown = UserDefaults.standard.integer(forKey: Self.hintShownKey) + 1
        UserDefaults.standard.set(shown, forKey: Self.hintShownKey)
        hint = Self.storedHint()
    }

    /// A song or album was added: the line stops for good.
    static func hintAdded() { UserDefaults.standard.set(true, forKey: hintAddedKey) }

    private static func storedHint() -> AddHintState {
        AddHintState(shown: UserDefaults.standard.integer(forKey: hintShownKey), added: UserDefaults.standard.bool(forKey: hintAddedKey))
    }
}
