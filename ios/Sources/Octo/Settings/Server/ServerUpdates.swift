import Foundation
import Observation
import OctoKit

/// Whether the Octo server in use has a newer release, read from its own update page (never
/// from GitHub), and updating it from the app. It asks once when the server is taken up, then
/// every few hours, every two seconds while an update is under way, and at once when the server
/// page opens. Only a Navidrome admin account gets an answer; anyone else, and any other server,
/// sees nothing.
@MainActor
@Observable
final class ServerUpdates {
    static let shared = ServerUpdates()

    private(set) var track = ServerUpdateTrack()
    /// The kept server the track belongs to.
    private(set) var serverId: String?

    @ObservationIgnored private weak var session: Session?
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var serverWatch: Watch<String>?
    @ObservationIgnored private let prefs = Prefs("server_update")

    private init() {}

    /// What the panel shows for the server in use now.
    var panel: ServerUpdatePanel { current ? track.panel : .hidden }

    /// Whether the rows and the tab leading to the panel carry their small dot.
    var showsDot: Bool { current && track.showsDot }

    /// "Octo 2026.10.13, up to date" for the server facts, when the server says so.
    var upToDateLine: String? { current ? track.upToDateLine : nil }

    private var current: Bool {
        guard let session, session.client != nil, session.runsOcto, let serverId else { return false }
        return serverId == session.activeId
    }

    /// Follows whichever Octo server is in use, from now on.
    func start(_ session: Session) {
        guard self.session == nil else { return }
        self.session = session
        serverWatch = Watch({ "\(session.activeId ?? "")|\(session.client != nil)|\(session.runsOcto)" }) { [weak self] _ in
            self?.serverChanged()
        }
        serverChanged()
    }

    /// Asks the server now, as the server page opens.
    func refresh() {
        guard serverId != nil else { return }
        restart()
    }

    /// Asks the server to bring in the newest release.
    func updateNow() {
        guard let session, let client = session.client, let id = serverId, current,
              let status = track.status, status.canUpdate, let tag = status.latest?.tag,
              !track.starting, track.watch == nil else { return }
        track = track.beganStart()
        Task {
            let (code, data) = await Self.send(ServerUpdateCalls.startRequest(client, tag: tag), through: client.session)
            guard serverId == id, session.activeId == id else { return }
            track = track.started(ServerUpdateCalls.startAnswer(status: code, data: data, tag: tag))
            restart()
        }
    }

    /// Puts the news away until a release newer than this one, for the server in use.
    func later() {
        guard let id = serverId else { return }
        track = track.later()
        if let tag = track.dismissed { prefs.set(tag, "later", id) }
    }

    /// The listener has read how the update ended.
    func closeOutcome() {
        track = track.closeOutcome()
    }

    /// Octo's dashboard, for updating there.
    func dashboard() -> URL? {
        session?.client.map(ServerUpdateCalls.dashboard)
    }

    // MARK: Asking

    /// The server in use changed: the one followed already changes nothing; another starts afresh.
    private func serverChanged() {
        guard let session else { return }
        let id = session.client != nil && session.runsOcto ? session.activeId : nil
        guard id != serverId else { return }
        loop?.cancel()
        loop = nil
        serverId = id
        track = ServerUpdateTrack(dismissed: id.flatMap { prefs.string("later", $0) })
        if id != nil { restart() }
    }

    /// One loop asks the page now, then as often as the track says.
    private func restart() {
        loop?.cancel()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.readOnce()
                guard !Task.isCancelled else { return }
                try? await Task.sleep(for: .milliseconds(self.track.nextReadMs))
            }
        }
    }

    private func readOnce() async {
        guard let session, let client = session.client, let id = serverId, session.activeId == id else { return }
        // While an update is under way each question goes through a session of its own, so a
        // connection kept open to the Octo that was replaced is never waited on.
        let fresh = track.watch != nil ? session.freshSession(seconds: ServerUpdateTiming.callSeconds) : nil
        let (code, data) = await Self.send(ServerUpdateCalls.stateRequest(client), through: fresh ?? client.session)
        fresh?.finishTasksAndInvalidate()
        guard !Task.isCancelled, serverId == id, session.activeId == id else { return }
        let before = track
        track = track.read(ServerUpdateCalls.readAnswer(status: code, data: data), nowMs: epochNowMs())
        if case .done = track.outcome, before.outcome != track.outcome {
            Task { await session.readServerAgain() }
        }
    }

    /// Sends a call and answers its status, nil when nothing came back.
    private static func send(_ request: URLRequest, through session: URLSession) async -> (Int?, Data) {
        guard let (data, response) = try? await session.data(for: request) else { return (nil, Data()) }
        return ((response as? HTTPURLResponse)?.statusCode, data)
    }
}
