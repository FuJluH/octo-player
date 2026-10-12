import Foundation
import Observation

/// Where the admin pages are: still looking, out of reach, or found.
public enum AdminPlace: Equatable, Sendable {
    case looking
    case away
    case found(URL)
}

/// One section of the admin screen: loading, ready, or failed with the words to show.
public enum AdminLoad<T: Equatable & Sendable>: Equatable, Sendable {
    case loading
    case ready(T)
    case failed(String)

    public var value: T? {
        if case .ready(let value) = self { value } else { nil }
    }
}

/// The Octo admin screen's state: where the pages are, each section on its own, a pull to
/// refresh, and a station refresh asked for here.
@MainActor
@Observable
public final class OctoAdminModel {
    public private(set) var place: AdminPlace = .looking
    public private(set) var status: AdminLoad<AdminStatus> = .loading
    public private(set) var radio: AdminLoad<RadioState> = .loading
    public private(set) var library: AdminLoad<LibraryStatus> = .loading
    public private(set) var downloads: AdminLoad<[DownloadRecord]> = .loading
    /// A pull to refresh in progress.
    public private(set) var refreshing = false
    /// A station refresh asked for here, until the new list is read.
    public private(set) var refreshingStations = false
    public private(set) var stationsProblem: String?

    @ObservationIgnored private let admin: OctoAdmin
    @ObservationIgnored private let signIn: @MainActor () -> AdminSignIn?
    @ObservationIgnored private let refreshWaitMs: Int
    @ObservationIgnored private let refreshChecks: Int
    @ObservationIgnored private var job: Task<Void, Never>?
    @ObservationIgnored private var stationsJob: Task<Void, Never>?
    /// Counts the loads, so one that was replaced leaves the pull indicator alone.
    @ObservationIgnored private var generation = 0

    public init(admin: OctoAdmin, signIn: @escaping @MainActor () -> AdminSignIn?, refreshWaitMs: Int = 4_000, refreshChecks: Int = 5) {
        self.admin = admin
        self.signIn = signIn
        self.refreshWaitMs = refreshWaitMs
        self.refreshChecks = refreshChecks
    }

    /// A fresh look, as the screen opens.
    public func open() { _ = load(fresh: true) }

    public func tryAgain() { _ = load(fresh: true) }

    /// Keeps what is shown until the new answers arrive; ignored while one is running. Returns
    /// when the load ends.
    public func refresh() async {
        guard !refreshing else { return }
        await load(fresh: false).value
    }

    /// Another server in use: its own admin pages are looked for.
    public func serverChanged() {
        stationsJob?.cancel()
        refreshingStations = false
        stationsProblem = nil
        _ = load(fresh: true)
    }

    public func stop() {
        job?.cancel()
        stationsJob?.cancel()
    }

    /// The full admin pages, for everything the app does not show.
    public var pageUrl: URL? {
        if case .found(let base) = place { OctoAdmin.pageUrl(base) } else { nil }
    }

    public func refreshStations() {
        guard case .found(let base) = place, !refreshingStations else { return }
        refreshingStations = true
        stationsProblem = nil
        let admin = admin
        let signIn = signIn()
        let wait = refreshWaitMs
        let checks = refreshChecks
        stationsJob = Task { [weak self] in
            defer { self?.refreshingStations = false }
            do {
                try await admin.refreshStations(base, signIn)
                // Octo rebuilds in the background, so the list is read again once it has had
                // time, and again while it is still busy.
                for _ in 0..<checks {
                    try await Task.sleep(nanoseconds: UInt64(wait) * 1_000_000)
                    let next = await Self.read("the stations") { try await admin.radio(base, signIn) }
                    if case .ready = next { self?.radio = next }
                    guard next.value?.learning?.refreshing == true else { return }
                }
            } catch is CancellationError {
                return
            } catch {
                if !Task.isCancelled { self?.stationsProblem = "Octo could not start a refresh just now." }
            }
        }
    }

    private func load(fresh: Bool) -> Task<Void, Never> {
        job?.cancel()
        generation += 1
        let mine = generation
        if fresh { place = .looking }
        refreshing = !fresh
        let admin = admin
        let signIn = signIn()
        let task = Task { [weak self] in
            defer { if let self, mine == self.generation { self.refreshing = false } }
            let base = await admin.locate(signIn)
            guard let self, !Task.isCancelled else { return }
            guard let base else {
                place = .away
                return
            }
            if fresh || place != .found(base) {
                status = .loading
                radio = .loading
                library = .loading
                downloads = .loading
            }
            place = .found(base)
            // The four sections are read side by side, each shown as soon as it answers.
            async let health: Void = showStatus(base, signIn)
            async let stations: Void = showRadio(base, signIn)
            async let folder: Void = showLibrary(base, signIn)
            async let recent: Void = showDownloads(base, signIn)
            _ = await (health, stations, folder, recent)
        }
        job = task
        return task
    }

    private func showStatus(_ base: URL, _ signIn: AdminSignIn?) async {
        let admin = admin
        let answer = await Self.read("Octo's health") { try await admin.status(base, signIn) }
        if !Task.isCancelled { status = answer }
    }

    private func showRadio(_ base: URL, _ signIn: AdminSignIn?) async {
        let admin = admin
        let answer = await Self.read("the stations") { try await admin.radio(base, signIn) }
        if !Task.isCancelled { radio = answer }
    }

    private func showLibrary(_ base: URL, _ signIn: AdminSignIn?) async {
        let admin = admin
        let answer = await Self.read("the library folder") { try await admin.library(base, signIn) }
        if !Task.isCancelled { library = answer }
    }

    private func showDownloads(_ base: URL, _ signIn: AdminSignIn?) async {
        let admin = admin
        let answer = await Self.read("recent downloads") { try await admin.downloads(base, signIn) }
        if !Task.isCancelled { downloads = answer }
    }

    private nonisolated static func read<T: Equatable & Sendable>(_ what: String, _ call: @Sendable () async throws -> T) async -> AdminLoad<T> {
        do {
            return .ready(try await call())
        } catch {
            return .failed(adminLoadFailed(what))
        }
    }
}
