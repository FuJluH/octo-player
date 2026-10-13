import Foundation
import Observation
import OctoKit

/// Whether the Octo server in use has a newer release, read from its own update page (never
/// from GitHub): when Settings starts, when the server page opens, and every few hours. An
/// update started here, or seen under way, is asked about every two seconds until it ends.
/// Only a Navidrome admin account gets an answer; anyone else, and a server without the page,
/// sees nothing.
@MainActor
@Observable
final class ServerUpdates {
    static let shared = ServerUpdates()

    private(set) var tracker = ServerUpdateTracker()
    /// The kept server the tracker's answers belong to.
    private(set) var serverId: String?
    /// The update is being handed to the server.
    private(set) var handing = false
    /// Why the server did not take the update, in words to show.
    private(set) var problem: String?
    /// The release "Later" was chosen on, for the server in use.
    private(set) var dismissed: String?
    /// When the page was last asked, answered or not. The panel reads it, so it is drawn again
    /// after each look, which is what moves an update that does not answer on to "has not come back".
    private(set) var lastReadMs: Int64 = 0

    @ObservationIgnored private weak var session: Session?
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var serverWatch: Watch<String>?
    @ObservationIgnored private let prefs = Prefs("server_update")

    private init() {}

    /// What the panel shows for the server in use now.
    var panel: ServerUpdatePanel {
        guard let session, session.client != nil, session.runsOcto, serverId == session.activeId else { return .hidden }
        return tracker.panel(dismissed: dismissed, nowMs: max(epochNowMs(), lastReadMs))
    }

    /// Starts looking. The first look waits for nothing, but a look in the last few hours counts.
    func start(_ session: Session) {
        guard self.session == nil else { return }
        self.session = session
        serverWatch = Watch({ "\(session.activeId ?? "")|\(session.client != nil)|\(session.runsOcto)" }) { [weak self] _ in
            self?.serverChanged()
        }
        serverChanged()
    }

    /// The server page opened: it is asked at once.
    func pageOpened(_ session: Session) {
        start(session)
        restart(readFirst: true)
    }

    /// Hands the newest release to the server's update helper.
    func updateNow() {
        guard let session, let client = session.client, let id = session.activeId, !handing,
              let state = tracker.state, state.canUpdateNow, let latest = state.latest else { return }
        handing = true
        problem = nil
        Task {
            let request = ServerUpdateCalls.startRequest(client, tag: latest.tag)
            let (status, data) = await Self.send(request, through: client.session)
            handing = false
            guard serverId == id, session.activeId == id else { return }
            switch ServerUpdateCalls.startAnswer(status: status, data: data, tag: latest.tag) {
            case .started(let runId, let tag):
                tracker.started(tag: tag, id: runId, nowMs: epochNowMs())
                restart(readFirst: true)
            case .refused(let words):
                problem = words
                restart(readFirst: true)
            case .failed:
                problem = "Couldn't reach your server to start the update. Try again in a moment."
            }
        }
    }

    /// Hides the offer until a newer release than this one comes out, for the server in use.
    func later() {
        guard let id = serverId, case .offer(let offer) = panel else { return }
        prefs.set(offer.latest.tag, "later", id)
        dismissed = offer.latest.tag
        problem = nil
    }

    /// Puts away a finished update's result.
    func closeResult() {
        tracker.closeResult(nowMs: epochNowMs())
        problem = nil
        restart(readFirst: true)
    }

    // MARK: Looking

    private func serverChanged() {
        guard let session else { return }
        let id = session.client != nil && session.runsOcto ? session.activeId : nil
        if id != serverId {
            serverId = id
            tracker = ServerUpdateTracker()
            problem = nil
            lastReadMs = 0
            dismissed = id.flatMap { prefs.string("later", $0) }
        }
        restart(readFirst: Self.due(lastReadMs: lastReadMs, nowMs: epochNowMs()))
    }

    private static func due(lastReadMs: Int64, nowMs: Int64) -> Bool {
        nowMs - lastReadMs >= ServerUpdateTiming.idlePollMs
    }

    /// One loop asks the page: now when `readFirst`, then as often as the tracker says.
    private func restart(readFirst: Bool) {
        loop?.cancel()
        guard serverId != nil else {
            loop = nil
            return
        }
        loop = Task { [weak self] in
            var read = readFirst
            while !Task.isCancelled {
                guard let self else { return }
                if read { await self.readOnce() }
                read = true
                let wait = self.tracker.following
                    ? self.tracker.nextPollMs(nowMs: epochNowMs())
                    : max(0, ServerUpdateTiming.idlePollMs - (epochNowMs() - self.lastReadMs))
                try? await Task.sleep(for: .milliseconds(wait))
            }
        }
    }

    private func readOnce() async {
        guard let session, let client = session.client, let id = serverId, session.activeId == id else { return }
        let following = tracker.following
        // While an update runs, each look goes through a session of its own with a short limit,
        // so a connection to the Octo that was replaced is never waited on.
        let fresh = following ? session.freshSession(seconds: ServerUpdateTiming.runCallSeconds) : nil
        let seconds = following ? ServerUpdateTiming.runCallSeconds : ServerUpdateTiming.callSeconds
        let request = ServerUpdateCalls.stateRequest(client, seconds: seconds)
        let (status, data) = await Self.send(request, through: fresh ?? client.session)
        fresh?.finishTasksAndInvalidate()
        guard !Task.isCancelled, serverId == id, session.activeId == id else { return }
        let now = epochNowMs()
        lastReadMs = now
        switch ServerUpdateCalls.readAnswer(status: status, data: data) {
        case .state(let state):
            if tracker.read(state, nowMs: now) {
                Task { await session.readServerAgain() }
            }
        case .refused:
            tracker.missed(refused: true, nowMs: now)
        case .missed:
            tracker.missed(refused: false, nowMs: now)
        }
    }

    /// Sends a call and answers its status, nil when nothing came back.
    private static func send(_ request: URLRequest, through session: URLSession) async -> (Int?, Data) {
        guard let (data, response) = try? await session.data(for: request) else { return (nil, Data()) }
        return ((response as? HTTPURLResponse)?.statusCode, data)
    }
}
