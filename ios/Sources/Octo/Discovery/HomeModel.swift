import Foundation
import MediaPlayer
import Observation
import OctoKit
import UIKit

/// Albums worth going back to: not played in six months, never finished, never played.
struct RevisitShelves: Sendable {
    var notPlayedLately: [LibraryAlbum] = []
    var neverFinished: [LibraryAlbum] = []
    var neverPlayed: [LibraryAlbum] = []
}

/// Something pinned to the front of Home.
enum HomePin: Identifiable {
    case album(LibraryAlbum)
    case artist(LibraryArtist)
    case playlist(PlaylistSummary)

    var id: String {
        switch self {
        case .album(let album): "album:\(album.id)"
        case .artist(let artist): "artist:\(artist.id)"
        case .playlist(let playlist): "playlist:\(playlist.id)"
        }
    }
}

/// What Home reads from the library: phone and server together.
@MainActor
protocol HomeLibrary: AnyObject {
    /// Every song in the library; nil until read.
    func homeSongCount() async -> Int
    func homeRecentlyPlayed() async -> [LibraryAlbum]
    func homeMostPlayed() async -> [LibraryTrack]
    func homeRecentlyAdded() async -> [LibraryAlbum]
    func homeFavoriteAlbums() async -> [LibraryAlbum]
    func homeRandomAlbums(_ count: Int) async -> [LibraryAlbum]
    func homeRandomArtists(_ count: Int) async -> [LibraryArtist]
    func homeRevisit() async -> RevisitShelves
    func homePins() async -> [HomePin]
}

/// How many albums or songs each shelf holds.
private let shelfSize = 20

extension Library: HomeLibrary {
    func homeSongCount() async -> Int { await trackCount() }
    func homeRecentlyPlayed() async -> [LibraryAlbum] { await recentlyPlayedAlbums(limit: shelfSize) }
    func homeMostPlayed() async -> [LibraryTrack] { await mostPlayedTracks(limit: shelfSize) }
    func homeRecentlyAdded() async -> [LibraryAlbum] { await recentAlbums(limit: shelfSize) }

    func homeFavoriteAlbums() async -> [LibraryAlbum] {
        Array(await likedAlbums().sorted { $0.likedAt > $1.likedAt }.prefix(shelfSize).map(\.album))
    }

    func homeRandomAlbums(_ count: Int) async -> [LibraryAlbum] { Array(await albums().shuffled().prefix(count)) }
    func homeRandomArtists(_ count: Int) async -> [LibraryArtist] { Array(await artists().shuffled().prefix(count)) }

    func homeRevisit() async -> RevisitShelves {
        revisitShelves(await albums(), await playedTracks(), nowMs: msSince1970())
    }

    func homePins() async -> [HomePin] {
        let shown = await shownPins()
        if shown.isEmpty { return [] }
        let lists = await playlists()
        var pins: [HomePin] = []
        for pin in shown {
            switch pin.kind {
            case "album": if let album = await album(pin.itemId) { pins.append(.album(album)) }
            case "artist": if let artist = await artist(pin.itemId) { pins.append(.artist(artist)) }
            case "playlist": if let list = lists.first(where: { $0.id == pin.itemId }) { pins.append(.playlist(list)) }
            default: break
            }
        }
        return pins
    }
}

/// The shelves from the library's own plays. An album shows on one shelf only: not played lately
/// first, then never finished; never played is apart.
func revisitShelves(_ albums: [LibraryAlbum], _ played: [PlayedTrack], nowMs: Int64) -> RevisitShelves {
    struct Listening {
        var songs: Int
        var playedSongs: Int
        var plays: Int64
        var lastPlayed: Int64?
        var added: Int64?
        var played: Bool { playedSongs > 0 || plays > 0 || lastPlayed != nil }
    }
    var byAlbum: [String: [PlayedTrack]] = [:]
    for play in played { byAlbum[play.track.albumId, default: []].append(play) }
    var listening: [String: Listening] = [:]
    for album in albums {
        var seen = Set<String>()
        let songs = (byAlbum[album.id] ?? []).filter { seen.insert($0.track.id).inserted }
        let last = songs.map(\.lastPlayedAt).max()
        listening[album.id] = Listening(songs: album.songCount, playedSongs: songs.filter { $0.plays > 0 }.count,
                                        plays: songs.reduce(0) { $0 + Int64($1.plays) }, lastPlayed: last.flatMap { $0 > 0 ? $0 : nil },
                                        added: album.addedAt > 0 ? album.addedAt : nil)
    }
    let before = nowMs - 180 * 24 * 60 * 60 * 1_000
    func of(_ album: LibraryAlbum) -> Listening { listening[album.id] ?? Listening(songs: 0, playedSongs: 0, plays: 0) }
    let quiet = albums.filter { of($0).lastPlayed.map { $0 < before } ?? false }.sorted { a, b in
        let la = of(a), lb = of(b)
        if la.plays != lb.plays { return la.plays > lb.plays }
        if la.lastPlayed != lb.lastPlayed { return (la.lastPlayed ?? 0) < (lb.lastPlayed ?? 0) }
        return a.id < b.id
    }.prefix(shelfSize)
    let shown = Set(quiet.map(\.id))
    let unfinished = albums.filter { !shown.contains($0.id) && of($0).playedSongs > 0 && of($0).playedSongs < of($0).songs }.sorted { a, b in
        let la = of(a).lastPlayed ?? .min, lb = of(b).lastPlayed ?? .min
        return la != lb ? la > lb : a.id < b.id
    }.prefix(shelfSize)
    let unplayed = albums.filter { !of($0).played }.sorted { a, b in
        let la = of(a).added ?? .min, lb = of(b).added ?? .min
        return la != lb ? la > lb : a.id < b.id
    }.prefix(shelfSize)
    return RevisitShelves(notPlayedLately: Array(quiet), neverFinished: Array(unfinished), neverPlayed: Array(unplayed))
}

/// Home's state: what the library holds, the server's stations, Made for you lists and charts, and
/// the cards at the top.
@MainActor
@Observable
final class HomeModel {
    private(set) var songCount: Int?
    private(set) var recentlyPlayed: [LibraryAlbum] = []
    private(set) var mostPlayed: [LibraryTrack] = []
    private(set) var recentlyAdded: [LibraryAlbum] = []
    private(set) var favoriteAlbums: [LibraryAlbum] = []
    private(set) var revisit = RevisitShelves()
    private(set) var pins: [HomePin] = []
    /// Picked once, then again on a pull, when the library changes size, or after a server copy.
    private(set) var surprise: [LibraryAlbum] = []
    private(set) var artists: [LibraryArtist] = []
    /// The signed-in server's stations, kept through a failed load.
    private(set) var stations: [RadioStation] = []
    /// The lists Octo made for the listener, kept through a failed load.
    private(set) var madeForYou: [Playlist] = []
    /// The first songs of the server's chart of the moment; empty on a server without charts.
    private(set) var charts: [Song] = []
    /// The station, or Made for you list, whose songs are on the way.
    private(set) var startingStation: String?
    private(set) var access: PhoneAccess = HomeModel.phoneAccess()
    /// Whether "Not now" put the access card away; nil until read.
    private(set) var accessDismissed: Bool?
    private(set) var whatsNewDue = false

    @ObservationIgnored private var library: HomeLibrary?
    @ObservationIgnored private var discovery: Discovery?
    @ObservationIgnored private var player: Player?
    @ObservationIgnored private var router: Router?
    @ObservationIgnored private var stationsTask: Task<Void, Never>?
    @ObservationIgnored private var chartsTask: Task<Void, Never>?
    @ObservationIgnored private var stationsLoadedAt: Int64?
    @ObservationIgnored private var stationsFailed = false
    @ObservationIgnored private var stationsFrom: String??
    @ObservationIgnored private var rolledFor: String?

    private static let accessDismissedKey = "home.phone_access_dismissed"
    private static let whatsNewKey = "whats_new.last_seen_version"

    func attach(library: HomeLibrary, discovery: Discovery, player: Player, router: Router) {
        self.library = library
        self.discovery = discovery
        self.player = player
        self.router = router
        accessDismissed = UserDefaults.standard.bool(forKey: Self.accessDismissedKey)
        settleWhatsNew()
    }

    var layout: HomeLayout { homeLayout(access, accessDismissed: accessDismissed, librarySongs: songCount) }

    // MARK: The library's shelves

    /// Reads every library shelf again, as the library, plays, likes or pins change.
    func readLibrary() async {
        guard let library else { return }
        songCount = await library.homeSongCount()
        recentlyPlayed = await library.homeRecentlyPlayed()
        mostPlayed = await library.homeMostPlayed()
        recentlyAdded = await library.homeRecentlyAdded()
        favoriteAlbums = await library.homeFavoriteAlbums()
        pins = await library.homePins()
        revisit = await library.homeRevisit()
    }

    /// Picks the random albums and artists again, when the library's size or its last server copy
    /// changed since the last pick.
    func reroll(for key: String) async {
        guard key != rolledFor else { return }
        rolledFor = key
        await reroll()
    }

    private func reroll() async {
        guard let library else { return }
        surprise = await library.homeRandomAlbums(20)
        artists = await library.homeRandomArtists(16)
    }

    /// A pull: picks again, and reads the stations and Made for you again when offered.
    func refresh() async {
        await reroll()
        await readLibrary()
        if stationsFrom != nil, stationsFrom! != nil { loadStations() }
    }

    // MARK: Stations, Made for you and charts

    /// A new sign-in, another kept server, or the server turning out to be Octo: starts over
    /// without the last one's lists, then loads this one's when it runs Octo.
    func stationsSourceChanged() {
        guard let discovery else { return }
        let server = discovery.stationsFrom
        if stationsFrom == .some(server) { return }
        stationsFrom = .some(server)
        stationsTask?.cancel()
        chartsTask?.cancel()
        stationsTask = nil
        stationsLoadedAt = nil
        stationsFailed = false
        stations = []
        madeForYou = []
        charts = []
        guard server != nil else { return }
        loadStations()
        chartsTask = Task { [weak self] in
            let list = await discovery.chart(Charts.overall)
            guard !Task.isCancelled else { return }
            self?.charts = Array((list?.songs ?? []).prefix(chartsRow).map(\.track))
        }
    }

    /// Home is on screen again: ask for the stations if the last try failed or the list is old.
    func shown() {
        access = Self.phoneAccess()
        guard let from = stationsFrom, from != nil else { return }
        if stationsDue(now: msSince1970(), loadedAt: stationsLoadedAt, failed: stationsFailed, loading: stationsTask != nil) {
            loadStations()
        }
    }

    /// Runs in the background so no other shelf waits on the server. The stations and Made for you
    /// are read apart, so one failing never hides the other.
    private func loadStations() {
        guard stationsTask == nil, let discovery else { return }
        stationsTask = Task { [weak self] in
            var failed = false
            do {
                let got = try await discovery.stations()
                if Task.isCancelled { return }
                self?.stations = got
            } catch {
                failed = true
            }
            do {
                let got = try await discovery.madeForYou()
                if Task.isCancelled { return }
                self?.madeForYou = got
            } catch {
                failed = true
            }
            guard let self, !Task.isCancelled else { return }
            if !failed { self.stationsLoadedAt = msSince1970() }
            self.stationsFailed = failed
            self.stationsTask = nil
        }
    }

    /// Plays what a station has lined up today. Taps while one is on the way are ignored.
    func playStation(id: String, name: String) {
        guard startingStation == nil, let discovery, let player, let router else { return }
        startingStation = id
        Task {
            defer { startingStation = nil }
            do {
                let songs = try await discovery.stationSongs(id)
                if songs.isEmpty { router.show("Nothing is playing on \(name) right now") }
                player.play(songs, from: 0)
            } catch OctoError.notFound {
                // Made anew on the server since the list was read: off Home, and read again.
                stations.removeAll { $0.id == id }
                madeForYou.removeAll { $0.id == id }
                stationsLoadedAt = nil
                loadStations()
                router.show(stationGoneLine(name))
            } catch {
                router.show("Could not start \(name)")
            }
        }
    }

    // MARK: The cards

    /// Whether the phone's music can be read.
    static func phoneAccess() -> PhoneAccess {
        switch MPMediaLibrary.authorizationStatus() {
        case .authorized: .granted
        case .notDetermined: .notAsked
        case .denied, .restricted: .deniedForever
        @unknown default: .denied
        }
    }

    /// Asks for the music on the phone; once refused, the system no longer asks, so this opens the
    /// app's settings instead.
    func requestAccess() {
        if access == .deniedForever {
            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            return
        }
        MPMediaLibrary.requestAuthorization { _ in
            Task { @MainActor [weak self] in self?.access = Self.phoneAccess() }
        }
    }

    /// "Not now" on the phone access card, kept for next time.
    func dismissAccess() {
        UserDefaults.standard.set(true, forKey: Self.accessDismissedKey)
        accessDismissed = true
    }

    static var versionCode: Int {
        Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") ?? 0
    }

    /// A fresh install starts having seen this version, so later updates know where they stand.
    func settleWhatsNew() {
        let defaults = UserDefaults.standard
        let seen = defaults.object(forKey: Self.whatsNewKey) as? Int
        // Installed and never used before this run: no server was ever kept.
        let fresh = defaults.object(forKey: "servers") == nil
        if seen == nil && fresh { defaults.set(Self.versionCode, forKey: Self.whatsNewKey) }
        whatsNewDue = OctoKit.whatsNewDue(lastSeen: defaults.object(forKey: Self.whatsNewKey) as? Int, current: Self.versionCode,
                                          freshInstall: fresh)
    }

    /// Reading the notes or closing the card puts it away until the next update.
    func dismissWhatsNew() {
        UserDefaults.standard.set(Self.versionCode, forKey: Self.whatsNewKey)
        whatsNewDue = false
    }
}
