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
    /// "git" or "image".
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

/// An update the helper is carrying out, or the last one it finished.
public struct ServerUpdateRun: Sendable, Equatable {
    public var id: String?
    /// The release being put in.
    public var tag: String?
    /// The release it replaces.
    public var from: String?
    /// "accepted", "fetching", "building", "restarting", "done" or "failed".
    public var state: String
    public var step: String?
    public var error: String?
    public var startedUtc: String?
    public var finishedUtc: String?
    public var log: [String]

    /// The states of a run that has not ended yet.
    public static let activeStates: Set<String> = ["accepted", "fetching", "building", "restarting"]

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

    public var active: Bool { Self.activeStates.contains(state) }
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
    /// An update was handed to the helper and it has not picked it up yet.
    public var pending = false
    public var pendingId: String?
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

    /// An update is under way: handed over and waiting, or being carried out.
    public var runActive: Bool { pending || run?.active == true }

    /// Whether the app may start the update itself: a newer release, a helper that is installed
    /// and current, and no update under way.
    public var canUpdateNow: Bool {
        updateAvailable && latest != nil && helper.installed && !helper.outdated && !runActive
    }
}

// MARK: Comparing releases

/// Orders two release tags by their numbers ("2026.10.03.1" after "2026.10.03"), a leading "v"
/// ignored. Nil when either is not made of numbers only.
public func compareServerTags(_ a: String, _ b: String) -> Int? {
    guard let left = tagNumbers(a), let right = tagNumbers(b) else { return nil }
    for index in 0..<max(left.count, right.count) {
        let x = index < left.count ? left[index] : 0
        let y = index < right.count ? right[index] : 0
        if x != y { return x < y ? -1 : 1 }
    }
    return 0
}

private func tagNumbers(_ tag: String) -> [Int]? {
    var text = tag.trimmingCharacters(in: .whitespaces)
    if text.first == "v" || text.first == "V" { text.removeFirst() }
    let parts = text.split(separator: ".", omittingEmptySubsequences: false)
    guard !parts.isEmpty else { return nil }
    var numbers: [Int] = []
    for part in parts {
        guard !part.isEmpty, part.allSatisfy(\.isASCII), let number = Int(part) else { return nil }
        numbers.append(number)
    }
    return numbers
}

/// Whether "Later" on `dismissed` still hides `latest`: until a newer release than the one put
/// off comes out. Tags that are not numbers count as the same only when written the same.
public func laterHides(latest: String, dismissed: String?) -> Bool {
    guard let dismissed, !dismissed.isEmpty else { return false }
    if let order = compareServerTags(latest, dismissed) { return order <= 0 }
    return latest == dismissed
}

// MARK: Following an update

/// The steps an update goes through, as the panel lists them.
public enum ServerUpdateStep: Int, Sendable, Equatable, CaseIterable, Comparable {
    case handed, fetching, pulling, restarting

    public static func < (a: ServerUpdateStep, b: ServerUpdateStep) -> Bool { a.rawValue < b.rawValue }

    public var words: String {
        switch self {
        case .handed: "Handed to the update helper"
        case .fetching: "Fetching the release"
        case .pulling: "Pulling the new Octo"
        case .restarting: "Restarting Octo"
        }
    }

    /// The step a run's state stands for; nil for a state that is not a step.
    public init?(runState: String) {
        switch runState {
        case "accepted": self = .handed
        case "fetching": self = .fetching
        case "building": self = .pulling
        case "restarting": self = .restarting
        default: return nil
        }
    }
}

/// How often and how long the update page is asked.
public enum ServerUpdateTiming {
    /// While an update runs.
    public static let runPollMs: Int64 = 2_000
    /// Each call while an update runs gives up after this, so a connection left pointing at the
    /// old Octo is dropped instead of waiting.
    public static let runCallSeconds: TimeInterval = 5
    /// Calls at other times.
    public static let callSeconds: TimeInterval = 15
    /// Between looks when nothing runs.
    public static let idlePollMs: Int64 = 3 * 60 * 60 * 1_000
    /// Unanswered calls during an update read as a restart this long, then as a server that has
    /// not come back.
    public static let notBackAfterMs: Int64 = 15 * 60 * 1_000
    /// Between looks once the server has not come back.
    public static let notBackPollMs: Int64 = 15_000
    /// A run that leaves no trace this soon after it was handed over may simply not be listed yet.
    public static let settleMs: Int64 = 10_000
}

/// One update the app follows to its end, from the moment it was handed over or first seen.
public struct ServerUpdateWatch: Sendable, Equatable {
    public enum Outcome: Sendable, Equatable {
        case done
        case failed(String)
    }

    /// The release being put in.
    public var tag: String
    public var id: String?
    public var startedMs: Int64
    public var step: ServerUpdateStep = .handed
    /// The first of the calls that have gone unanswered since the last answer.
    public var failingSinceMs: Int64?
    /// The run was seen under way at least once.
    public var seenActive = false
    public var outcome: Outcome?

    public init(tag: String, id: String?, startedMs: Int64) {
        self.tag = tag
        self.id = id
        self.startedMs = startedMs
    }

    /// Takes in an answer from the server.
    public mutating func saw(_ state: ServerUpdateState, nowMs: Int64) {
        failingSinceMs = nil
        guard outcome == nil else { return }
        let run = state.run.flatMap { belongs($0) ? $0 : nil }
        if run?.state == "done" || (!state.running.isEmpty && state.running == tag) {
            outcome = .done
            return
        }
        if id == nil, let run, run.active { id = run.id }
        // Handed over and not picked up yet: a run listed now is an earlier one.
        if state.pending, run?.active != true {
            seenActive = true
            return
        }
        if let run, run.state == "failed" {
            outcome = .failed(Self.failureWords(run.error))
            return
        }
        if let run, let step = ServerUpdateStep(runState: run.state) {
            seenActive = true
            self.step = max(self.step, step)
            return
        }
        // Nothing under way any more, and the server still runs the old release.
        if seenActive || nowMs - startedMs >= ServerUpdateTiming.settleMs {
            outcome = .failed(Self.failureWords(state.unanswered ?? state.run?.error))
        }
    }

    /// A call went unanswered, as it does while Octo restarts.
    public mutating func missed(nowMs: Int64) {
        guard outcome == nil, failingSinceMs == nil else { return }
        failingSinceMs = nowMs
    }

    /// The server has not answered for too long.
    public func notBack(nowMs: Int64) -> Bool {
        guard outcome == nil, let since = failingSinceMs else { return false }
        return nowMs - since >= ServerUpdateTiming.notBackAfterMs
    }

    /// The step shown now: a server that does not answer is restarting.
    public var shownStep: ServerUpdateStep { failingSinceMs == nil ? step : .restarting }

    /// Whether a run the server lists is this one.
    func belongs(_ run: ServerUpdateRun) -> Bool {
        if let id, let runId = run.id { return id == runId }
        return run.tag == nil || run.tag == tag
    }

    static func failureWords(_ error: String?) -> String {
        let text = (error ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "The update did not finish." : text
    }
}

// MARK: The panel

/// What the server update panel offers to do.
public enum ServerUpdateAction: Sendable, Equatable {
    case updateNow
    /// No helper on the server; the dashboard says how to update.
    case noHelper
    /// The helper is too old; the command reinstalls it.
    case outdatedHelper(String?)
}

/// A newer release, in the panel's words.
public struct ServerUpdateOffer: Sendable, Equatable {
    public var latest: ServerRelease
    public var running: String
    /// Every release newer than the one running, newest first.
    public var newer: [ServerRelease]
    public var action: ServerUpdateAction

    /// "Octo 2026.10.13 is out. Your server runs 2026.10.11.", and how many releases that is when
    /// more than one.
    public var words: String {
        var text = "Octo \(latest.tag) is out."
        if !running.isEmpty { text += " Your server runs \(running)." }
        if newer.count > 1 { text += " That is \(newer.count) releases ahead." }
        return text
    }

    /// What the question before updating says.
    public var confirmWords: String {
        "Octo fetches \(latest.tag) and restarts. Music from your server stops for a minute or two."
    }

    /// The releases "What's new" shows: the newer ones, or the latest alone when none are listed.
    public var notes: [ServerRelease] { newer.isEmpty ? [latest] : newer }
}

/// What the server update panel shows.
public enum ServerUpdatePanel: Sendable, Equatable {
    case hidden
    case offer(ServerUpdateOffer)
    case running(tag: String, step: ServerUpdateStep)
    case notBack(tag: String)
    case done(tag: String)
    case failed(tag: String, words: String)

    /// Whether the row leading to the panel carries a badge.
    public var badged: Bool {
        switch self {
        case .hidden, .done: false
        default: true
        }
    }
}

/// The update page's answers over time, and the update being followed, if any.
public struct ServerUpdateTracker: Sendable, Equatable {
    public private(set) var state: ServerUpdateState?
    public private(set) var watch: ServerUpdateWatch?

    public init(state: ServerUpdateState? = nil, watch: ServerUpdateWatch? = nil) {
        self.state = state
        self.watch = watch
    }

    /// An update is being followed and has not ended: the page is asked often.
    public var following: Bool { watch != nil && watch?.outcome == nil }

    /// Takes in an answer. An update under way that is not followed yet starts being followed.
    /// True when this answer showed the followed update done.
    @discardableResult
    public mutating func read(_ answer: ServerUpdateState, nowMs: Int64) -> Bool {
        state = answer
        if watch == nil || watch?.outcome != nil, answer.runActive {
            let tag = answer.run?.tag ?? answer.latest?.tag ?? ""
            watch = ServerUpdateWatch(tag: tag, id: answer.run?.id ?? answer.pendingId, startedMs: nowMs)
        }
        guard var followed = watch, followed.outcome == nil else { return false }
        followed.saw(answer, nowMs: nowMs)
        watch = followed
        return followed.outcome == .done
    }

    /// A call that got no answer. `refused` is a server that does not offer the page to this
    /// account (or at all): the panel hides, unless an update is being followed, when it counts
    /// like any other missed call.
    public mutating func missed(refused: Bool, nowMs: Int64) {
        if following {
            watch?.missed(nowMs: nowMs)
        } else if refused {
            state = nil
        }
    }

    /// The server took the update.
    public mutating func started(tag: String, id: String?, nowMs: Int64) {
        watch = ServerUpdateWatch(tag: tag, id: id, startedMs: nowMs)
        state?.pending = true
    }

    /// The update's result was read and put away: done, failed, or a server that has not come
    /// back. An update still under way stays.
    public mutating func closeResult(nowMs: Int64) {
        guard let watch, watch.outcome != nil || watch.notBack(nowMs: nowMs) else { return }
        self.watch = nil
    }

    /// How long to wait before asking again.
    public func nextPollMs(nowMs: Int64) -> Int64 {
        guard let watch, watch.outcome == nil else { return ServerUpdateTiming.idlePollMs }
        return watch.notBack(nowMs: nowMs) ? ServerUpdateTiming.notBackPollMs : ServerUpdateTiming.runPollMs
    }

    /// What the panel shows now. `dismissed` is the release "Later" was chosen on, for this server.
    public func panel(dismissed: String?, nowMs: Int64) -> ServerUpdatePanel {
        if let watch {
            switch watch.outcome {
            case .done: return .done(tag: watch.tag)
            case .failed(let words): return .failed(tag: watch.tag, words: words)
            case nil:
                if watch.notBack(nowMs: nowMs) { return .notBack(tag: watch.tag) }
                return .running(tag: watch.tag, step: watch.shownStep)
            }
        }
        guard let state else { return .hidden }
        if state.runActive {
            let step = state.run.flatMap { ServerUpdateStep(runState: $0.state) } ?? .handed
            return .running(tag: state.run?.tag ?? state.latest?.tag ?? "", step: step)
        }
        guard state.updateAvailable, let latest = state.latest else { return .hidden }
        if laterHides(latest: latest.tag, dismissed: dismissed) { return .hidden }
        let action: ServerUpdateAction
        if !state.helper.installed {
            action = .noHelper
        } else if state.helper.outdated {
            action = .outdatedHelper(state.reinstallCommand.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 })
        } else {
            action = .updateNow
        }
        return .offer(ServerUpdateOffer(latest: latest, running: state.running, newer: state.newer, action: action))
    }
}

// MARK: Calls

/// What a read of the update page came to.
public enum ServerUpdateAnswer: Sendable, Equatable {
    case state(ServerUpdateState)
    /// Not offered to this account, or not by this server: nothing is shown.
    case refused
    /// No answer, or one that could not be read.
    case missed
}

/// What asking the server to update came to.
public enum ServerUpdateStart: Sendable, Equatable {
    case started(id: String?, tag: String)
    /// The server said no, in words fit to show.
    case refused(String)
    case failed
}

public enum ServerUpdateCalls {
    /// The update page on the server in use, signed with its sign-in.
    public static func stateRequest(_ client: SubsonicClient, seconds: TimeInterval = ServerUpdateTiming.callSeconds) -> URLRequest {
        var request = URLRequest(url: client.signed(address(client)), timeoutInterval: seconds)
        client.headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    /// Asks the server to put in `tag`.
    public static func startRequest(_ client: SubsonicClient, tag: String) -> URLRequest {
        var request = URLRequest(url: client.signed(address(client)), timeoutInterval: ServerUpdateTiming.callSeconds)
        request.httpMethod = "POST"
        client.headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        request.setValue("1", forHTTPHeaderField: "X-Octo-Admin")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["tag": tag])
        return request
    }

    /// The server's dashboard, for what the app does not do.
    public static func dashboard(_ client: SubsonicClient) -> URL {
        client.baseURL.appendingPathComponent("admin/")
    }

    static func address(_ client: SubsonicClient) -> URL {
        client.baseURL.appendingPathComponent("api/admin/update")
    }

    /// Reads the answer to `stateRequest`. 401, 403 and 404 mean the page is not there for this
    /// account or server.
    public static func readAnswer(status: Int?, data: Data) -> ServerUpdateAnswer {
        guard let status else { return .missed }
        if [401, 403, 404].contains(status) { return .refused }
        guard (200..<300).contains(status), let state = try? ServerUpdateState.read(data) else { return .missed }
        return .state(state)
    }

    /// Reads the answer to `startRequest`.
    public static func startAnswer(status: Int?, data: Data, tag: String) -> ServerUpdateStart {
        guard let status else { return .failed }
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        if (200..<300).contains(status) {
            return .started(id: AdminJSON.string(object?["id"]), tag: AdminJSON.string(object?["tag"]) ?? tag)
        }
        let words = AdminJSON.string(object?["error"])?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if status == 409 { return .refused(words.isEmpty ? "The server can't start an update right now." : words) }
        if status == 403 { return .refused("Only a Navidrome admin account can update the server.") }
        return .failed
    }
}

// MARK: Notes

/// A link in release notes may lead only to GitHub.
public func isGitHubLink(_ text: String?) -> Bool {
    guard let text, let parts = URLComponents(string: text), parts.scheme?.lowercased() == "https",
          let host = parts.host?.lowercased() else { return false }
    return host == "github.com" || host == "www.github.com"
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
