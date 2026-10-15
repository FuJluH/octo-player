import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: What the update page answers

/// One Octo release on GitHub, as the server read it.
public struct ServerRelease: Sendable, Equatable {
    public var tag: String
    public var name: String?
    /// The release notes, in Markdown.
    public var notes: String?
    public var url: String?
    public var publishedUtc: String?

    public init(tag: String, name: String? = nil, notes: String? = nil, url: String? = nil, publishedUtc: String? = nil) {
        self.tag = tag
        self.name = name
        self.notes = notes
        self.url = url
        self.publishedUtc = publishedUtc
    }

    init?(_ json: Any?) {
        guard let object = json as? [String: Any], let tag = AdminJSON.string(object["tag"]),
              !tag.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        self.init(tag: tag, name: AdminJSON.string(object["name"]), notes: AdminJSON.string(object["notes"]),
                  url: AdminJSON.string(object["url"]), publishedUtc: AdminJSON.string(object["publishedUtc"]))
    }
}

/// The small program on the server's machine that fetches a release and restarts Octo.
public struct ServerUpdateHelper: Sendable, Equatable {
    public var installed = false
    public var version: String?
    /// How it brings a release in: "image" pulls the published images, "git" checks the release
    /// out first, "build" builds it.
    public var mode: String?
    public var dir: String?
    public var installedUtc: String?
    /// Older than this Octo needs; it has to be installed again before it can update.
    public var outdated = false

    public init(installed: Bool = false, version: String? = nil, mode: String? = nil, dir: String? = nil,
                installedUtc: String? = nil, outdated: Bool = false) {
        self.installed = installed
        self.version = version
        self.mode = mode
        self.dir = dir
        self.installedUtc = installedUtc
        self.outdated = outdated
    }

    init(_ json: Any?) {
        let object = json as? [String: Any] ?? [:]
        self.init(installed: AdminJSON.bool(object["installed"]) ?? false, version: AdminJSON.string(object["version"]),
                  mode: AdminJSON.string(object["mode"]), dir: AdminJSON.string(object["dir"]),
                  installedUtc: AdminJSON.string(object["installedUtc"]), outdated: AdminJSON.bool(object["outdated"]) ?? false)
    }
}

/// The states a run of the helper moves through.
public enum ServerRunState {
    public static let accepted = "accepted"
    public static let fetching = "fetching"
    public static let building = "building"
    public static let restarting = "restarting"
    public static let done = "done"
    public static let failed = "failed"

    /// The states of a run that has not ended yet.
    public static let active: Set<String> = [accepted, fetching, building, restarting]
}

/// An update the helper is carrying out, or the last one it finished.
public struct ServerUpdateRun: Sendable, Equatable {
    public var id: String?
    /// The release being put in.
    public var tag: String?
    /// The release it replaces.
    public var from: String?
    /// One of `ServerRunState`.
    public var state: String
    public var step: String?
    public var error: String?
    public var startedUtc: String?
    public var finishedUtc: String?
    public var log: [String]

    public init(id: String? = nil, tag: String? = nil, from: String? = nil, state: String, step: String? = nil, error: String? = nil,
                startedUtc: String? = nil, finishedUtc: String? = nil, log: [String] = []) {
        self.id = id
        self.tag = tag
        self.from = from
        self.state = state
        self.step = step
        self.error = error
        self.startedUtc = startedUtc
        self.finishedUtc = finishedUtc
        self.log = log
    }

    init?(_ json: Any?) {
        guard let object = json as? [String: Any], let state = AdminJSON.string(object["state"]) else { return nil }
        self.init(id: AdminJSON.string(object["id"]), tag: AdminJSON.string(object["tag"]), from: AdminJSON.string(object["from"]),
                  state: state, step: AdminJSON.string(object["step"]), error: AdminJSON.string(object["error"]),
                  startedUtc: AdminJSON.string(object["startedUtc"]), finishedUtc: AdminJSON.string(object["finishedUtc"]),
                  log: (object["log"] as? [Any])?.compactMap { AdminJSON.string($0) } ?? [])
    }

    /// Still under way: neither done nor failed.
    public var active: Bool { ServerRunState.active.contains(state) }
}

/// Whether the server runs the newest Octo, and what its update helper is doing.
public struct ServerUpdateState: Sendable, Equatable {
    public var enabled = false
    public var repo: String?
    /// The release the server runs.
    public var running = ""
    public var latest: ServerRelease?
    /// Every release newer than the one running, newest first.
    public var newer: [ServerRelease] = []
    public var updateAvailable = false
    /// "behind", "current", "ahead" or "unknown".
    public var standing = "unknown"
    public var checkedUtc: String?
    public var error: String?
    public var helper = ServerUpdateHelper()
    public var reinstallCommand: String?
    /// A request written for the helper that it has not picked up yet.
    public var pending = false
    public var pendingId: String?
    /// The id of a request the helper never picked up.
    public var unanswered: String?
    public var run: ServerUpdateRun?
    public var command: String?
    public var imageCommand: String?

    public init(enabled: Bool = true, repo: String? = nil, running: String = "", latest: ServerRelease? = nil,
                newer: [ServerRelease] = [], updateAvailable: Bool = false, standing: String = "unknown",
                checkedUtc: String? = nil, error: String? = nil, helper: ServerUpdateHelper = ServerUpdateHelper(),
                reinstallCommand: String? = nil, pending: Bool = false, pendingId: String? = nil, unanswered: String? = nil,
                run: ServerUpdateRun? = nil, command: String? = nil, imageCommand: String? = nil) {
        self.enabled = enabled
        self.repo = repo
        self.running = running
        self.latest = latest
        self.newer = newer
        self.updateAvailable = updateAvailable
        self.standing = standing
        self.checkedUtc = checkedUtc
        self.error = error
        self.helper = helper
        self.reinstallCommand = reinstallCommand
        self.pending = pending
        self.pendingId = pendingId
        self.unanswered = unanswered
        self.run = run
        self.command = command
        self.imageCommand = imageCommand
    }

    /// Reads the update page's answer. A missing, null or wrong value is the default.
    public static func read(_ data: Data) throws -> ServerUpdateState {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw AdminJSON.notObject }
        return ServerUpdateState(
            enabled: AdminJSON.bool(object["enabled"]) ?? false,
            repo: AdminJSON.string(object["repo"]),
            running: AdminJSON.string(object["running"]) ?? "",
            latest: ServerRelease(object["latest"]),
            newer: (object["newer"] as? [Any] ?? []).compactMap { ServerRelease($0) },
            updateAvailable: AdminJSON.bool(object["updateAvailable"]) ?? false,
            standing: AdminJSON.string(object["standing"]) ?? "unknown",
            checkedUtc: AdminJSON.string(object["checkedUtc"]),
            error: AdminJSON.string(object["error"]),
            helper: ServerUpdateHelper(object["helper"]),
            reinstallCommand: AdminJSON.string(object["reinstallCommand"]),
            pending: AdminJSON.bool(object["pending"]) ?? false,
            pendingId: AdminJSON.string(object["pendingId"]),
            unanswered: AdminJSON.string(object["unanswered"]),
            run: ServerUpdateRun(object["run"]),
            command: AdminJSON.string(object["command"]),
            imageCommand: AdminJSON.string(object["imageCommand"]))
    }

    /// An update is waiting for the helper or under way.
    public var busy: Bool { pending || run?.active == true }

    /// Whether the app may start the update itself: one is out, the helper is there and current,
    /// and nothing is under way.
    public var canUpdate: Bool {
        updateAvailable && latest != nil && helper.installed && !helper.outdated && !busy
    }
}

// MARK: Comparing releases

/// Orders two of Octo's dated release tags, like 2026.10.03 and 2026.10.03.1: number by number,
/// a longer tag after the shorter one it starts with, a leading "v" ignored. Parts that are not
/// numbers compare as words.
public func compareReleaseTags(_ a: String, _ b: String) -> Int {
    let left = tagParts(a)
    let right = tagParts(b)
    for index in 0..<max(left.count, right.count) {
        guard index < left.count else { return -1 }
        guard index < right.count else { return 1 }
        let x = left[index]
        let y = right[index]
        if let nx = Int64(x), let ny = Int64(y) {
            if nx != ny { return nx < ny ? -1 : 1 }
        } else if x != y {
            return x < y ? -1 : 1
        }
    }
    return 0
}

private func tagParts(_ tag: String) -> [String] {
    var text = tag.trimmingCharacters(in: .whitespaces)
    if text.hasPrefix("v") { text.removeFirst() }
    return text.split(omittingEmptySubsequences: false) { $0 == "." || $0 == "-" }.map(String.init)
}

// MARK: Following an update

/// What asking the server gave.
public enum ServerUpdateAnswer: Sendable, Equatable {
    case state(ServerUpdateState)
    /// The server does not offer this to this account: a listener's account, or a server too old
    /// for it. The app then shows nothing.
    case refused
    /// No answer: away, restarting, or a connection that went nowhere.
    case missed
}

/// What asking the server to update gave.
public enum ServerUpdateStart: Sendable, Equatable {
    case started(id: String?, tag: String)
    /// Why it would not, in the server's own words where it gave them.
    case refused(String)
}

/// The steps a run goes through, as the panel lists them.
public enum ServerUpdateStep: Int, Sendable, Equatable, CaseIterable, Comparable {
    case handed, fetching, bringing, restarting

    public static func < (a: ServerUpdateStep, b: ServerUpdateStep) -> Bool { a.rawValue < b.rawValue }

    /// The step's words; a helper that builds says so.
    public func words(mode: String? = nil) -> String {
        switch self {
        case .handed: "Handed to the update helper"
        case .fetching: "Fetching the release"
        case .bringing: mode == "build" ? "Building the new Octo" : "Pulling the new Octo"
        case .restarting: "Restarting Octo"
        }
    }

    /// The step a run is on.
    init(run: ServerUpdateRun) {
        switch run.state {
        case ServerRunState.fetching: self = .fetching
        case ServerRunState.building: self = .bringing
        case ServerRunState.restarting: self = .restarting
        default: self = .handed
        }
    }
}

/// An update being followed until it ends: the release, the request this app made for it (if it
/// made one), and the step it was last seen on. `quietSinceMs` is when the server stopped
/// answering, during a restart.
public struct ServerUpdateWatch: Sendable, Equatable {
    public var tag: String
    public var requestId: String?
    public var byThisApp = false
    public var step: ServerUpdateStep = .handed
    public var mode: String?
    public var quietSinceMs: Int64?

    public init(tag: String, requestId: String? = nil, byThisApp: Bool = false, step: ServerUpdateStep = .handed,
                mode: String? = nil, quietSinceMs: Int64? = nil) {
        self.tag = tag
        self.requestId = requestId
        self.byThisApp = byThisApp
        self.step = step
        self.mode = mode
        self.quietSinceMs = quietSinceMs
    }
}

/// How an update followed here ended.
public enum ServerUpdateOutcome: Sendable, Equatable {
    case done(tag: String)
    case failed(tag: String, words: String)
    /// The server stopped answering during the restart and has not come back.
    case notBack(tag: String)

    public var tag: String {
        switch self {
        case .done(let tag), .failed(let tag, _), .notBack(let tag): tag
        }
    }
}

/// How often and how long the update page is asked.
public enum ServerUpdateTiming {
    /// While an update is under way.
    public static let activeReadMs: Int64 = 2_000
    /// Otherwise. The server itself looks for releases every six hours, so asking more often
    /// learns nothing.
    public static let idleReadMs: Int64 = 3 * 60 * 60 * 1_000
    /// How long one question may take. A connection kept open to a server that has since
    /// restarted can hang with no answer; this drops it.
    public static let callSeconds: TimeInterval = 5
    /// How long a server may stay quiet during a restart before the app says it has not come back.
    public static let restartGraceMs: Int64 = 15 * 60 * 1_000
}

/// What the app knows about updating the server, and what the panel shows from it. Every change
/// comes through `read`, `started` or the listener's own choices, so the rules can be checked
/// without a server.
public struct ServerUpdateTrack: Sendable, Equatable {
    /// The server's last answer, or nil when it gave none or does not offer this.
    public var status: ServerUpdateState?
    /// The newest release the listener chose Later for, on this server.
    public var dismissed: String?
    public var watch: ServerUpdateWatch?
    public var outcome: ServerUpdateOutcome?
    /// The request to update is on its way.
    public var starting = false
    /// Why the server would not start the update, until the next try.
    public var startProblem: String?

    public init(status: ServerUpdateState? = nil, dismissed: String? = nil, watch: ServerUpdateWatch? = nil,
                outcome: ServerUpdateOutcome? = nil, starting: Bool = false, startProblem: String? = nil) {
        self.status = status
        self.dismissed = dismissed
        self.watch = watch
        self.outcome = outcome
        self.starting = starting
        self.startProblem = startProblem
    }

    /// Takes the server's answer, or its silence, at `nowMs`.
    public func read(_ answer: ServerUpdateAnswer, nowMs: Int64) -> ServerUpdateTrack {
        switch answer {
        case .state(let state):
            return answered(state)
        case .refused:
            if watch != nil { return quiet(nowMs) }
            var next = self
            next.status = nil
            return next
        case .missed:
            return watch != nil ? quiet(nowMs) : self
        }
    }

    /// The request to update is on its way.
    public func beganStart() -> ServerUpdateTrack {
        var next = self
        next.starting = true
        next.startProblem = nil
        next.outcome = nil
        return next
    }

    /// What the server said to the request to update.
    public func started(_ result: ServerUpdateStart) -> ServerUpdateTrack {
        var next = self
        next.starting = false
        switch result {
        case .started(let id, let tag):
            next.startProblem = nil
            next.outcome = nil
            next.watch = ServerUpdateWatch(tag: tag, requestId: id, byThisApp: true, mode: status?.helper.mode)
        case .refused(let words):
            next.startProblem = words
        }
        return next
    }

    /// The listener put the news away until a newer release.
    public func later() -> ServerUpdateTrack {
        var next = self
        next.dismissed = status?.latest?.tag ?? dismissed
        return next
    }

    /// The listener read how it ended.
    public func closeOutcome() -> ServerUpdateTrack {
        var next = self
        next.outcome = nil
        return next
    }

    /// How long until asking again.
    public var nextReadMs: Int64 { watch != nil || starting ? ServerUpdateTiming.activeReadMs : ServerUpdateTiming.idleReadMs }

    private func answered(_ s: ServerUpdateState) -> ServerUpdateTrack {
        var next = self
        next.status = s
        guard let w = watch else { return next.followIfBusy(s) }
        // The run for this release, by its request or its tag.
        let run = s.run.flatMap { run in (w.requestId != nil && run.id == w.requestId) || run.tag == w.tag ? run : nil }
        if s.running == w.tag || run?.state == ServerRunState.done {
            next.watch = nil
            next.outcome = w.byThisApp ? .done(tag: w.tag) : nil
        } else if let run, run.state == ServerRunState.failed {
            next.watch = nil
            next.outcome = .failed(tag: w.tag, words: nonBlank(run.error) ?? ServerUpdateWords.stopped)
        } else if let id = w.requestId, s.unanswered == id {
            next.watch = nil
            next.outcome = .failed(tag: w.tag, words: ServerUpdateWords.helperSilent)
        } else if s.busy {
            let active = s.run.flatMap { $0.active ? $0 : nil }
            if let active, let tag = active.tag, tag != w.tag {
                // Another release's run under way is the one to follow.
                next.watch = ServerUpdateWatch(tag: tag, requestId: active.id, step: ServerUpdateStep(run: active), mode: s.helper.mode)
            } else {
                var kept = w
                kept.step = active.map(ServerUpdateStep.init(run:)) ?? .handed
                kept.quietSinceMs = nil
                kept.mode = s.helper.mode ?? w.mode
                next.watch = kept
            }
        } else {
            next.watch = nil
            next.outcome = .failed(tag: w.tag, words: ServerUpdateWords.stoppedEarly(running: s.running))
        }
        return next
    }

    /// Starts following a run the server says is under way, from any app or the dashboard.
    private func followIfBusy(_ s: ServerUpdateState) -> ServerUpdateTrack {
        guard s.busy else { return self }
        let active = s.run.flatMap { $0.active ? $0 : nil }
        guard let tag = active?.tag ?? s.latest?.tag else { return self }
        var next = self
        next.watch = ServerUpdateWatch(tag: tag, requestId: active?.id ?? s.pendingId,
                                       step: active.map(ServerUpdateStep.init(run:)) ?? .handed, mode: s.helper.mode)
        return next
    }

    /// No answer while an update is under way: the server is restarting, until it has been quiet
    /// too long.
    private func quiet(_ nowMs: Int64) -> ServerUpdateTrack {
        guard var w = watch else { return self }
        var next = self
        let since = w.quietSinceMs ?? nowMs
        if nowMs - since >= ServerUpdateTiming.restartGraceMs {
            next.watch = nil
            next.outcome = .notBack(tag: w.tag)
        } else {
            w.quietSinceMs = since
            w.step = .restarting
            next.watch = w
        }
        return next
    }
}

private func nonBlank(_ text: String?) -> String? {
    guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
    return text
}

// MARK: The panel

/// How the server can be updated from here.
public enum ServerUpdateWay: Sendable, Equatable {
    /// Update now, through the helper.
    case now
    /// No helper on the host: from the dashboard instead.
    case noHelper
    /// The helper is too old and needs reinstalling first.
    case helperOutdated
}

/// A newer release, as the panel offers it.
public struct ServerUpdateOffer: Sendable, Equatable {
    public var latest: ServerRelease
    public var running: String
    /// Every release newer than the one running, newest first; the latest alone when none are listed.
    public var newer: [ServerRelease]
    public var way: ServerUpdateWay
    public var reinstallCommand: String
    /// Why the last try at this release stopped, when it did.
    public var lastFailure: String?
    public var starting: Bool
    public var problem: String?
}

public enum ServerUpdateStepState: Sendable, Equatable {
    case done, now, waiting
}

public struct ServerUpdateStepLine: Sendable, Equatable {
    public var words: String
    public var state: ServerUpdateStepState
}

/// What the server update panel shows.
public enum ServerUpdatePanel: Sendable, Equatable {
    case hidden
    /// A newer release is out.
    case available(ServerUpdateOffer)
    case updating(tag: String, steps: [ServerUpdateStepLine])
    case finished(ServerUpdateOutcome)
}

extension ServerUpdateTrack {
    /// What the panel shows now.
    public var panel: ServerUpdatePanel {
        if let outcome { return .finished(outcome) }
        if let watch { return .updating(tag: watch.tag, steps: Self.stepLines(watch.step, mode: watch.mode)) }
        guard let s = status, let latest = s.latest, s.updateAvailable else { return .hidden }
        if let dismissed, compareReleaseTags(latest.tag, dismissed) <= 0 { return .hidden }
        let way: ServerUpdateWay = !s.helper.installed ? .noHelper : s.helper.outdated ? .helperOutdated : .now
        let failed = s.run.flatMap { $0.state == ServerRunState.failed && $0.tag == latest.tag ? $0 : nil }
        return .available(ServerUpdateOffer(
            latest: latest,
            running: s.running,
            newer: s.newer.isEmpty ? [latest] : s.newer,
            way: way,
            reinstallCommand: s.reinstallCommand ?? "",
            lastFailure: failed.map { nonBlank($0.error) ?? ServerUpdateWords.stopped },
            starting: starting,
            problem: startProblem))
    }

    /// Whether the rows leading to the panel carry their small dot.
    public var showsDot: Bool {
        switch panel {
        case .hidden, .finished(.done): false
        case .available, .updating, .finished: true
        }
    }

    /// "Octo 2026.10.13, up to date" for the server facts, when the server knows it runs the
    /// newest release.
    public var upToDateLine: String? {
        guard let s = status, s.standing == "current", !s.updateAvailable,
              !s.running.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return "Octo \(s.running), up to date"
    }

    static func stepLines(_ now: ServerUpdateStep, mode: String?) -> [ServerUpdateStepLine] {
        ServerUpdateStep.allCases.map { step in
            ServerUpdateStepLine(words: step.words(mode: mode), state: step < now ? .done : step == now ? .now : .waiting)
        }
    }
}

// MARK: Words

/// The words the server update panel shows.
public enum ServerUpdateWords {
    public static func headline(_ offer: ServerUpdateOffer) -> String { "Octo \(offer.latest.tag) is out." }

    /// "Your server runs 2026.10.11.", and how far behind when more than one release came out since.
    public static func detail(_ offer: ServerUpdateOffer) -> String {
        let ahead = offer.newer.count
        return "Your server runs \(offer.running)." + (ahead > 1 ? " That is \(ahead) releases ahead." : "")
    }

    /// How to update when the app cannot do it itself, or nil when it can.
    public static func way(_ way: ServerUpdateWay) -> String? {
        switch way {
        case .now: nil
        case .noHelper: "You can update it from Octo's dashboard."
        case .helperOutdated:
            "The update helper on your server needs reinstalling before Octo can update from here. Run this on the server, or update from the dashboard:"
        }
    }

    public static func lastFailure(_ words: String) -> String { "The last try stopped: \(words)" }

    public static let confirmTitle = "Update your server?"

    public static func confirmDetail(_ tag: String) -> String {
        "Octo fetches \(tag) and restarts. Music from your server stops for a minute or two."
    }

    public static func updatingTitle(_ tag: String) -> String { "Updating your server to \(tag)" }

    public static let musicStops = "Music from your server stops for a minute or two."

    public static func outcomeTitle(_ outcome: ServerUpdateOutcome) -> String {
        switch outcome {
        case .done(let tag): "Your server now runs \(tag)."
        case .failed(let tag, _): "The update to \(tag) did not finish."
        case .notBack: "Your server has not come back."
        }
    }

    public static func outcomeDetail(_ outcome: ServerUpdateOutcome) -> String? {
        switch outcome {
        case .done: nil
        case .failed(_, let words): words
        case .notBack:
            "Octo has not answered for \(ServerUpdateTiming.restartGraceMs / 60_000) minutes since it began restarting. Check the server, or open the dashboard once it answers."
        }
    }

    /// A release's title for the notes: its name when it has one beyond the tag.
    public static func releaseTitle(_ release: ServerRelease) -> String {
        if let name = release.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty, name != release.tag { return name }
        return "Octo \(release.tag)"
    }

    /// What a screen reader hears for the small dot.
    public static let mark = "Server update available"

    static let stopped = "The update stopped before it finished."

    static let helperSilent =
        "The update helper on your server did not pick up the request. It may have stopped. Update from Octo's dashboard instead."

    static func stoppedEarly(running: String) -> String { "The update stopped before it finished. Your server still runs \(running)." }

    static let noAnswer = "Octo did not answer. Try again in a moment."
    static let wouldNotStart = "Octo would not start the update just now."
    static let adminOnly = "Only a Navidrome admin can update the server."
}

// MARK: Calls

public enum ServerUpdateCalls {
    /// The update page on the server in use, signed with its sign-in.
    public static func stateRequest(_ client: SubsonicClient) -> URLRequest {
        var request = URLRequest(url: client.signed(address(client)), timeoutInterval: ServerUpdateTiming.callSeconds)
        client.headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    /// Asks the server to bring in `tag`.
    public static func startRequest(_ client: SubsonicClient, tag: String) -> URLRequest {
        var request = URLRequest(url: client.signed(address(client)), timeoutInterval: ServerUpdateTiming.callSeconds)
        request.httpMethod = "POST"
        client.headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        request.setValue("1", forHTTPHeaderField: "X-Octo-Admin")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["tag": tag])
        return request
    }

    /// Octo's dashboard, for updating there.
    public static func dashboard(_ client: SubsonicClient) -> URL { rooted(client.baseURL, "/admin/") }

    static func address(_ client: SubsonicClient) -> URL { rooted(client.baseURL, "/api/admin/update") }

    private static func rooted(_ base: URL, _ path: String) -> URL {
        var parts = URLComponents(url: base, resolvingAgainstBaseURL: false) ?? URLComponents()
        parts.percentEncodedPath = path
        parts.query = nil
        parts.fragment = nil
        return parts.url ?? base
    }

    /// Reads the answer to `stateRequest`; nil `status` is no answer at all. 401, 403 and 404 are a
    /// listener's account, or a server that has no such page or does not take the app's sign-in there.
    public static func readAnswer(status: Int?, data: Data) -> ServerUpdateAnswer {
        guard let status else { return .missed }
        if notOffered.contains(status) { return .refused }
        guard (200..<300).contains(status), let state = try? ServerUpdateState.read(data) else { return .missed }
        return .state(state)
    }

    /// Reads the answer to `startRequest`; nil `status` is no answer at all.
    public static func startAnswer(status: Int?, data: Data, tag: String) -> ServerUpdateStart {
        guard let status else { return .refused(ServerUpdateWords.noAnswer) }
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let words = nonBlank(AdminJSON.string(object?["error"]))
        if (200..<300).contains(status) {
            return .started(id: AdminJSON.string(object?["id"]), tag: AdminJSON.string(object?["tag"]) ?? tag)
        }
        if status == 409 { return .refused(words ?? ServerUpdateWords.wouldNotStart) }
        if notOffered.contains(status) { return .refused(ServerUpdateWords.adminOnly) }
        return .refused(words ?? ServerUpdateWords.noAnswer)
    }

    private static let notOffered: Set<Int> = [401, 403, 404]
}

// MARK: Notes

/// A link in release notes stays a link only when it is an https page on github.com itself.
public func isGitHubLink(_ text: String?) -> Bool {
    guard let text, let parts = URLComponents(string: text), parts.scheme == "https", let host = parts.host else { return false }
    return host.lowercased() == "github.com"
}

/// Release notes ready to draw: links that do not lead to GitHub stay as plain words.
public func serverReleaseNotes(_ markdown: String?) -> [Markdown.Block] {
    Markdown.parse(markdown ?? "").map { (block: Markdown.Block) -> Markdown.Block in
        switch block {
        case .heading(let level, let spans): return .heading(level, keepGitHubLinks(spans))
        case .paragraph(let spans): return .paragraph(keepGitHubLinks(spans))
        case .bullets(let items): return .bullets(items.map(keepGitHubLinks(in:)))
        case .rule: return .rule
        }
    }
}

private func keepGitHubLinks(_ spans: [Markdown.Span]) -> [Markdown.Span] {
    spans.map { span in
        var kept = span
        if !isGitHubLink(span.link) { kept.link = nil }
        return kept
    }
}

private func keepGitHubLinks(in bullet: Markdown.Bullet) -> Markdown.Bullet {
    Markdown.Bullet(keepGitHubLinks(bullet.text), children: bullet.children.map(keepGitHubLinks(in:)))
}
