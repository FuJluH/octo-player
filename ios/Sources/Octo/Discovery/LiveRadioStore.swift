import Foundation
import Observation
import OctoKit

/// Live radio near the listener: the place and radius chosen, the stations the Radio Browser
/// catalog lists there, and the stations kept on the phone. The place, radius, order and kept
/// stations stay on the phone (preferences suite "live_radio"); only the place's rounded
/// coordinates, and its state and country, go to the catalog.
@MainActor
@Observable
final class LiveRadioStore {
    static let shared = LiveRadioStore()

    /// What the page shows under its controls.
    enum Found: Equatable {
        /// No place chosen yet.
        case noPlace
        case loading
        case failed(String)
        case ready([LiveStation])
    }

    private(set) var kept: KeptStations
    private(set) var place: LivePlace?
    private(set) var radiusIndex: Int
    private(set) var sort: LiveSort
    private(set) var found: Found = .noPlace
    /// Whether distances are in miles, by the phone's region.
    let miles: Bool

    /// HLS stations play through the app's own HLS reader.
    static let hlsPlays = true

    @ObservationIgnored private let store = UserDefaults(suiteName: "live_radio") ?? .standard
    @ObservationIgnored private let browser = RadioBrowser(userAgent: octoUserAgent(Session.appVersion))
    @ObservationIgnored private var loading: Task<Void, Never>?

    private enum Keys {
        static let kept = "kept"
        static let place = "place"
        static let radius = "radius"
        static let sort = "sort"
    }

    private init() {
        miles = Locale.current.measurementSystem != .metric
        kept = KeptStations.decoded(store.string(forKey: Keys.kept))
        place = store.data(forKey: Keys.place).flatMap { try? JSONDecoder().decode(LivePlace.self, from: $0) }
        radiusIndex = store.object(forKey: Keys.radius) as? Int ?? liveRadiusDefaultIndex
        sort = LiveSort(rawValue: store.string(forKey: Keys.sort) ?? "") ?? .distance
    }

    var radius: LiveRadius { LiveRadius.at(radiusIndex, miles: miles) }
    var radiusChoices: [LiveRadius] { LiveRadius.choices(miles: miles) }

    /// The stations found that this app plays, in the order chosen, and how many were left out.
    var shown: (stations: [LiveStation], hidden: Int) {
        guard case .ready(let all) = found else { return ([], 0) }
        let playable = playableStations(all, hlsPlays: Self.hlsPlays)
        return (sortStations(playable.stations, by: sort), playable.hidden)
    }

    // MARK: Choices

    func choose(_ next: LivePlace) {
        // Only the rounded place is ever kept.
        let rounded = next.rounded
        place = rounded
        if let data = try? JSONEncoder().encode(rounded) { store.set(data, forKey: Keys.place) }
        load(fresh: true)
    }

    func setRadius(_ index: Int) {
        guard index != radiusIndex, radiusChoices.indices.contains(index) else { return }
        radiusIndex = index
        store.set(index, forKey: Keys.radius)
        load(fresh: true)
    }

    func setSort(_ next: LiveSort) {
        guard next != sort else { return }
        sort = next
        store.set(next.rawValue, forKey: Keys.sort)
    }

    // MARK: Finding

    /// Asks the catalog for the stations around the place, kept answers first. Asking again
    /// while one is on the way starts over. `fresh` (a new place or radius) shows the spinner in
    /// place of the stations found for the old one.
    @discardableResult
    func load(fresh: Bool = false) -> Task<Void, Never>? {
        guard let place else {
            found = .noPlace
            return nil
        }
        loading?.cancel()
        if fresh {
            found = .loading
        } else if case .ready = found {
        } else {
            found = .loading
        }
        let radius = radius.meters
        let browser = browser
        loading = Task { [weak self] in
            do {
                let stations = try await browser.near(place, radiusMeters: radius)
                guard !Task.isCancelled else { return }
                self?.found = .ready(stations)
            } catch {
                guard !Task.isCancelled, !(error is CancellationError) else { return }
                self?.found = .failed("Couldn't reach the radio station list. Check the connection and try again.")
            }
        }
        return loading
    }

    /// A pull on the page: asks again and waits for the answer.
    func refresh() async {
        await load()?.value
    }

    /// The page is open again: the stations are asked for again, the kept answer coming at once
    /// while it is under six hours old.
    func shownAgain() {
        if place != nil { load() }
    }

    // MARK: Playing

    /// Plays a station among the stations of the list it was tapped in (`among`, in its order), so
    /// Back and Next step through them, and tells the catalog it was started. An HLS station
    /// whose address does not say so is queued as one, since its id says so.
    func play(_ station: LiveStation, among stations: [LiveStation], on player: Player) {
        play(station, among: stations.map { (stream: $0.streamUrl, id: $0.radioId()) }, on: player)
    }

    /// The same, for a list that also holds stations the catalog does not know, each by its
    /// stream and radio id.
    func play(_ station: LiveStation, among stations: [(stream: String, id: String)], on player: Player) {
        let id = station.radioId()
        let tapped = stations.firstIndex { $0.id == id } ?? stations.firstIndex { liveStreamKey($0.stream) == liveStreamKey(station.streamUrl) }
        if let tapped {
            player.playStations(stations, tapped: tapped)
        } else {
            player.playStations([id], from: 0)
        }
        let browser = browser
        let uuid = station.uuid
        Task.detached { await browser.started(uuid) }
    }

    // MARK: Keeping

    func isKept(_ uuid: String) -> Bool { kept.has(uuid) }

    func keep(_ station: LiveStation) { save(kept.keep(station)) }

    func drop(_ uuid: String) { save(kept.drop(uuid)) }

    /// Adds a backup's kept stations after the ones here.
    func restore(_ stations: [LiveStation]) {
        guard !stations.isEmpty else { return }
        save(kept.adding(stations))
    }

    private func save(_ next: KeptStations) {
        kept = next
        store.set(next.encoded(), forKey: Keys.kept)
    }
}
