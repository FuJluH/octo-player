import Foundation

// The words and rules of the family sheets (an invite, a sign-in handed to another device, and
// the Your login card), the same on the phone and the desktop.

/// A new member's invite sheet, or the new sign-in link after a manager resets a member's
/// password: who it is for, their link once made, and how asking for a new one goes.
public struct InviteSheet: Sendable, Equatable, CustomStringConvertible {
    public var name: String
    public var username: String
    public var url: String?
    public var loading = false
    public var error: String?
    /// The invite's two links, when the server gives them.
    public var links: FamilyLinkChoices?
    public var anywhereAvailable = true
    /// The server has no public address: the link works only at home.
    public var homeOnly = false
    /// Whether they may listen away from home.
    public var awayAllowed = true
    /// A reset: the member had a password, which no longer works.
    public var reset = false

    public init(name: String, username: String, url: String?, loading: Bool = false, error: String? = nil, links: FamilyLinkChoices? = nil,
                anywhereAvailable: Bool = true, homeOnly: Bool = false, awayAllowed: Bool = true, reset: Bool = false) {
        self.name = name
        self.username = username
        self.url = url
        self.loading = loading
        self.error = error
        self.links = links
        self.anywhereAvailable = anywhereAvailable
        self.homeOnly = homeOnly
        self.awayAllowed = awayAllowed
        self.reset = reset
    }

    public var title: String { reset ? "New sign-in link for \(name)" : "Invite \(name)" }

    public var options: LinkOptions {
        inviteLinkOptions(url: url, choices: links, anywhereAvailable: anywhereAvailable, homeOnly: homeOnly, awayAllowed: awayAllowed)
    }

    public var description: String { "InviteSheet(name=\(name), loading=\(loading), reset=\(reset))" }
}

/// When `expires` (an ISO time) falls, in milliseconds, or nil without one.
public func expiresAtMs(_ expires: String?) -> Int64? { epochMs(expires) }

/// Seconds left until `expires`, or nil when the server set no expiry.
public func secondsLeft(_ expires: String?, nowMs: Int64) -> Int64? {
    guard let at = epochMs(expires) else { return nil }
    return max(0, at / 1_000 - nowMs / 1_000)
}

/// "9:42": minutes and seconds.
public func minutesSeconds(_ seconds: Int64) -> String {
    let rest = seconds % 60
    return "\(seconds / 60):\(rest < 10 ? "0" : "")\(rest)"
}

/// The header's line under the title: "Works once · expires in 1:42", or without an expiry
/// "Works once". At the end a new code is on its way.
public func countdownLine(_ seconds: Int64?) -> String {
    guard let seconds else { return "Works once" }
    if seconds <= 0 { return "Works once · getting a new code" }
    return "Works once · expires in \(minutesSeconds(seconds))"
}

/// Under 30 seconds the countdown shows in the warning color.
public func countdownWarns(_ seconds: Int64?) -> Bool { seconds.map { $0 < 30 } ?? false }

/// What a screen reader is told about the countdown: only near the end.
public func countdownAnnouncement(_ seconds: Int64?) -> String? {
    guard let seconds else { return nil }
    if seconds <= 0 { return "This code expired. Getting a new one." }
    if seconds <= 30 { return "Thirty seconds left" }
    return nil
}

/// A long text with its middle left out, so its start and its end show.
public func middleEllipsized(_ text: String, max: Int = 48) -> String {
    let characters = Array(text)
    if characters.count <= max { return text }
    let keep = max - 1
    let head = (keep + 1) / 2
    let tail = keep - head
    return String(characters.prefix(head)) + "…" + String(characters.suffix(tail))
}

/// A link as a sheet shows it: where it goes, without the scheme, then its middle left out and
/// its telling end kept, the first part after #.
public func shownLink(_ url: String, max: Int = 52) -> String {
    let bare = url.range(of: "://").map { String(url[$0.upperBound...]) } ?? url
    var base = bare.range(of: "#").map { String(bare[..<$0.lowerBound]) } ?? bare
    if base.hasSuffix("/") { base.removeLast() }
    let afterHash = bare.range(of: "#").map { String(bare[$0.upperBound...]) } ?? ""
    let first = String((afterHash.range(of: "&").map { String(afterHash[..<$0.lowerBound]) } ?? afterHash).prefix(20))
    if first.isEmpty { return middleEllipsized(base, max: max) }
    let tail = "…#" + first
    let room = Swift.max(max - tail.count, 10)
    if base.count <= room { return base + tail }
    let cut = String(base.prefix(room))
    if let slash = cut.lastIndex(of: "/"), slash != cut.startIndex { return String(cut[..<slash]) + tail }
    return cut + tail
}

/// A server address as people read it: no scheme, no slash at the end.
public func shownServer(_ server: String) -> String {
    var text = server.range(of: "://").map { String(server[$0.upperBound...]) } ?? server
    if text.hasSuffix("/") { text.removeLast() }
    return text
}

/// The server a family link goes to, path and all: everything before /family/. A bare address
/// is its own server.
public func linkServer(_ url: String) -> String? {
    var text = url.range(of: "#").map { String(url[..<$0.lowerBound]) } ?? url
    if let family = text.range(of: "/family/") { text = String(text[..<family.lowerBound]) }
    if text.hasSuffix("/") { text.removeLast() }
    return text.contains("://") ? text : nil
}

public enum FamilySheetText {
    public static let inviteSubtitle = "The link works once and expires in 7 days"
    public static let sendNewLink = "Send a new link"
    public static let copied = "Copied"
    public static let linkFailed = "Couldn't make a new link. Try again."
    public static let tryAgain = "Try again"
    public static let moreBelow = "More below"
    public static let makeNewCode = "Make a new code"
    public static let stillThere = "Still there?"
    public static let newCode = "New code"
    public static let renewFailed = "Couldn't get a new code. Trying again."
    public static let setOutsideFirst = "Set your outside address first"
    public static let askOwnerOutside = "Ask your family owner to set an outside address"
    public static let openStatus = "Open the Status page"
    public static let allowAway = "Allow listening away from home"
    public static let allowAwayLine = "Off keeps them to your home network; their links work only there."
    /// How long "Copied" shows after a copy, and "New code" after a renewal.
    public static let copiedMs = 2_000
    public static let newCodeMs = 3_000
}

public func inviteCaption(_ name: String) -> String { "\(name) scans this with their phone" }

public func inviteNext(_ name: String) -> String { "\(name) picks a password, then signs in on any app." }

/// Which of a link's two forms shows: through the outside address, or through the home one.
public enum LinkReach: String, CaseIterable, Sendable {
    case anywhere = "Anywhere", home = "Home"

    public var label: String { self == .anywhere ? "Anywhere" : "At home" }
}

/// The question over the two choices: the new device is one's own, or someone else's.
public func reachQuestion(own: Bool) -> String { own ? "Where will you use it?" : "Where will they use it?" }

/// The line under the choices: which address the link goes through.
public func reachLine(_ reach: LinkReach, _ options: LinkOptions) -> String? {
    guard let link = options.linkFor(reach), let server = linkServer(link) else { return nil }
    if reach == .home && options.home != nil { return "Uses your home network (\(shownServer(server)))" }
    return "Uses \(originOf(server))"
}

private func originOf(_ server: String) -> String {
    let scheme = server.range(of: "://").map { String(server[..<$0.lowerBound]) } ?? "https"
    let rest = server.range(of: "://").map { String(server[$0.upperBound...]) } ?? server
    return "\(scheme)://" + (rest.range(of: "/").map { String(rest[..<$0.lowerBound]) } ?? rest)
}

/// A link's two forms, as the server answered them, and whether the person it is for may
/// listen away from home at all.
public struct LinkOptions: Sendable, Equatable, CustomStringConvertible {
    public var anywhere: String?
    public var home: String?
    public var anywhereAvailable: Bool
    public var awayAllowed: Bool

    public init(anywhere: String?, home: String?, anywhereAvailable: Bool = true, awayAllowed: Bool = true) {
        self.anywhere = anywhere
        self.home = home
        self.anywhereAvailable = anywhereAvailable
        self.awayAllowed = awayAllowed
    }

    /// The choice shows when there are two ways to choose between.
    public var choosable: Bool { awayAllowed && home != nil }

    /// Anywhere when it can be had, else home.
    public var defaultReach: LinkReach {
        home == nil || (awayAllowed && anywhereAvailable && anywhere != nil) ? .anywhere : .home
    }

    /// The link for a choice; nil for Anywhere before the server has an outside address.
    public func linkFor(_ reach: LinkReach) -> String? {
        if home == nil { return anywhere }
        if reach == .home || !awayAllowed { return home }
        return anywhereAvailable ? anywhere : nil
    }

    public var description: String { "LinkOptions(anywhereAvailable=\(anywhereAvailable), awayAllowed=\(awayAllowed))" }
}

/// An invite's links: the server's two when it gives them, else the one link, which is home
/// only when the server says so.
public func inviteLinkOptions(url: String?, choices: FamilyLinkChoices?, anywhereAvailable: Bool, homeOnly: Bool, awayAllowed: Bool = true) -> LinkOptions {
    if let choices {
        return LinkOptions(anywhere: choices.anywhere, home: choices.home,
                           anywhereAvailable: anywhereAvailable && choices.anywhere != nil && !homeOnly, awayAllowed: awayAllowed)
    }
    if homeOnly || !anywhereAvailable { return LinkOptions(anywhere: nil, home: url, anywhereAvailable: false, awayAllowed: awayAllowed) }
    return LinkOptions(anywhere: url, home: nil, anywhereAvailable: true, awayAllowed: awayAllowed)
}

/// The dashboard's Status page, where the owner sets the outside address.
public func dashboardStatusPage(_ server: String) -> String {
    ServerAddress.trimmedSlash(server.trimmingCharacters(in: .whitespacesAndNewlines)) + "/admin/#status"
}

/// How to sign in from an app, by app: a few numbered steps each.
public struct AppSteps: Sendable, Equatable {
    public var app: String
    public var steps: [String]
}

public func loginSteps(server: String, username: String) -> [AppSteps] {
    [
        AppSteps(app: "Octo", steps: [
            "Open Octo and choose Sign in.",
            "Type \(server) as the server and \(username) as the username.",
            "Type your password and sign in.",
        ]),
        AppSteps(app: "Symfonium", steps: [
            "Open Settings, then Media providers, then Add media provider, and pick Subsonic.",
            "Type \(server) as the server address and \(username) as the username.",
            "Type your password, then tap Test and Save.",
        ]),
        AppSteps(app: "Feishin", steps: [
            "Choose Add server and pick Subsonic (or Navidrome).",
            "Type \(server) as the URL and \(username) as the username.",
            "Type your password and save.",
        ]),
        AppSteps(app: "Amperfy", steps: [
            "On the login screen, type \(server) as the server URL.",
            "Type \(username) as the username and your password, then log in.",
        ]),
        AppSteps(app: "Substreamer", steps: [
            "Choose Add server, then Subsonic.",
            "Type \(server), \(username) and your password, then connect.",
        ]),
        AppSteps(app: "Tempo", steps: [
            "On the login screen, type \(server) as the server and \(username) as the username.",
            "Type your password and log in.",
        ]),
    ]
}

// MARK: Notices

/// One notice to show: a request of mine was decided or arrived, or (for a manager) requests
/// are waiting. `key` stays the same for the same news, so showing it twice replaces it.
public struct FamilyNotice: Sendable, Equatable {
    public var key: String
    public var title: String
    public var text: String
}

/// What has been told already: each request's state when it was last told, and how many
/// waiting requests a manager was last told about.
public struct NoticeMemory: Codable, Sendable, Equatable {
    public var told: [String: String]
    public var waitingTold: Int
    /// False until the first check: what is already decided then is old news.
    public var started: Bool

    public init(told: [String: String] = [:], waitingTold: Int = 0, started: Bool = false) {
        self.told = told
        self.waitingTold = waitingTold
        self.started = started
    }

    enum CodingKeys: String, CodingKey { case told, waitingTold, started }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        told = (try? c.decodeIfPresent([String: String].self, forKey: .told)) ?? [:]
        waitingTold = c.int(.waitingTold) ?? 0
        started = c.bool(.started) ?? false
    }

    /// A request answered while the app watched, so the next check does not tell it again.
    public func alreadyTold(_ request: FamilyRequest) -> NoticeMemory {
        var copy = self
        copy.told[request.id] = request.state.rawValue
        return copy
    }
}

public let waitingNoticeKey = "family-waiting"

/// The notices for a check, and what to remember after it. The first check tells nothing about
/// requests, only a manager's waiting count.
public func familyNotices(_ memory: NoticeMemory, mine: [FamilyRequest], waiting: Int?) -> ([FamilyNotice], NoticeMemory) {
    let toldStates: Set<FamilyRequestState> = [.approved, .declined, .done, .failed]
    var notices: [FamilyNotice] = []
    if memory.started {
        for request in mine where toldStates.contains(request.state) && memory.told[request.id] != request.state.rawValue {
            notices.append(requestNotice(request))
        }
    }
    let count = waiting ?? 0
    if count > 0 && count > memory.waitingTold {
        notices.append(FamilyNotice(key: waitingNoticeKey, title: "\(plural(count, "request")) waiting", text: "Open Family to approve or decline."))
    }
    var told: [String: String] = [:]
    for request in mine { told[request.id] = request.state.rawValue }
    return (notices, NoticeMemory(told: told, waitingTold: count, started: true))
}

public func requestNotice(_ request: FamilyRequest) -> FamilyNotice {
    let what = requestTitle(request)
    switch request.state {
    case .approved: return FamilyNotice(key: request.id, title: "Approved", text: "\(what) is on its way to your library.")
    case .declined:
        let note = request.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? what : "\(what). \"\(request.note)\""
        return FamilyNotice(key: request.id, title: "Declined", text: note)
    case .done: return FamilyNotice(key: request.id, title: "Added", text: "\(what). \(outcomeLine(request.outcome)).")
    case .failed:
        let failure = request.failure.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 } ?? "Ask for it again later."
        return FamilyNotice(key: request.id, title: "Could not get it", text: "\(what). \(failure)")
    default: return FamilyNotice(key: request.id, title: "Request", text: what)
    }
}

/// One look at the server: what to tell this account and what it has been told from then on.
public func checkFamilyNotices(_ client: SubsonicClient, memory: NoticeMemory) async throws -> ([FamilyNotice], NoticeMemory) {
    let me = try await client.family().me
    let mine = try await client.familyRequests()
    let waiting = me.abilities.approveRequests ? try await client.familyRequests(all: true, state: .pending).count : nil
    return familyNotices(memory, mine: mine, waiting: waiting)
}

/// How often requests are checked in the background.
public let familyCheckMs = 30 * 60 * 1_000
