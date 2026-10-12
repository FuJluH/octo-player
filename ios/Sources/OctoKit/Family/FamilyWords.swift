import Foundation

// The family's words, the same on the phone and the desktop.
public enum FamilyText {
    public static let family = "Family"
    public static let myPlan = "My plan"
    public static let yourLogin = "Your login"
    public static let useInAnyApp = "Use this in any app"
    public static let changePassword = "Change password"
    public static let signOutEverywhere = "Sign out everywhere"
    public static let signOutEverywhereLine = "Changing your password signs out every app and device. Each one then needs the new password."
    public static let removeFromList = "Remove from list"
    public static let resetPassword = "Reset password"
    public static let passwordLine = "The one you chose"
    public static let openInOcto = "Open in Octo"
    public static let homeOnlyLogin = "You can listen only on your home network, so only the home address works."
    public static let saved = "Saved"
    public static let requests = "Requests"
    public static let devices = "Devices"
    public static let members = "Members"
    public static let requestsWaiting = "Requests waiting"
    public static let requestACopy = "Request a copy"
    public static let save = "Save"
    public static let removeFromMyLibrary = "Remove from my library"
    public static let offlineCopiesOff = "Offline copies are off for this account"
}

public func roleLabel(_ role: FamilyRole) -> String {
    switch role {
    case .owner: "Owner"
    case .coAdmin: "Co-admin"
    case .member: "Member"
    case .listener: "Listener"
    case .kid: "Kid"
    case .unmanaged: "Not in the family"
    }
}

/// A role by the server's name for it: this app's words for the roles it knows, and the
/// server's own name, spaced out, for one it does not ("FamilyGuest" reads "Family Guest").
public func roleLabel(name: String) -> String {
    if let role = familyRole(name) { return roleLabel(role) }
    var out = ""
    var previous: Character?
    for character in name {
        if let previous, previous.isASCII, previous.isLowercase, character.isASCII, character.isUppercase { out.append(" ") }
        out.append(character)
        previous = character
    }
    let trimmed = out.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? "Member" : trimmed
}

public func qualityLabel(_ quality: RequestQuality) -> String {
    switch quality {
    case .best: "Best"
    case .flac: "FLAC"
    case .mp3: "MP3"
    }
}

/// What each quality means, under its name in the request sheet.
public func qualityDetail(_ quality: RequestQuality) -> String {
    switch quality {
    case .best: "The best copy Octo can find"
    case .flac: "Lossless FLAC only"
    case .mp3: "A smaller MP3"
    }
}

/// One thing an account can or cannot do, in plain words. `on` is false for what is held back.
public struct AbilityLine: Sendable, Equatable, Hashable {
    public var text: String
    public var on: Bool

    public init(_ text: String, on: Bool = true) {
        self.text = text
        self.on = on
    }
}

/// Everything this account may do, in the order a person cares about: adding music, listening,
/// devices, then the rest.
public func abilityLines(_ can: FamilyAbilities) -> [AbilityLine] {
    var lines: [AbilityLine] = []
    switch can.addToLibrary {
    case .direct: lines.append(AbilityLine("Songs you add go straight into your library"))
    case .request: lines.append(AbilityLine("Songs you add are saved. Request a copy to keep one in your library"))
    case .saveOnly: lines.append(AbilityLine("Songs you add are saved and play from the internet"))
    }
    if can.addToLibrary == .request {
        switch can.requestQuality {
        case .best: lines.append(AbilityLine("Copies in any quality, up to the best"))
        case .flac: lines.append(AbilityLine("Copies in FLAC or MP3"))
        case .mp3: lines.append(AbilityLine("Copies in MP3"))
        }
        lines.append(AbilityLine(can.autoApprove ? "Your requests are approved right away" : "Your requests wait for approval"))
        lines.append(AbilityLine(can.weeklyRequestLimit > 0 ? "\(plural(can.weeklyRequestLimit, "request")) a week" : "No limit on requests"))
    }
    if can.instantFromFamily { lines.append(AbilityLine("Songs the family already has are added right away")) }
    lines.append(AbilityLine(can.storageLimitGb > 0 ? "Room for \(can.storageLimitGb) GB in your library" : "No limit on your library's size"))
    if can.streamCap > 0 { lines.append(AbilityLine("Your family plan limits listening to \(can.streamCap) kbps", on: false)) }
    let awayLower = can.awayCap > 0 && (can.streamCap == 0 || can.awayCap < can.streamCap)
    if !can.away {
        lines.append(AbilityLine("Listening away from home is off", on: false))
    } else if awayLower {
        lines.append(AbilityLine("Your family plan limits away listening to \(can.awayCap) kbps", on: false))
    } else {
        lines.append(AbilityLine("Listens away from home too"))
    }
    lines.append(AbilityLine(can.devicesAtOnce > 0 ? "Plays on \(plural(can.devicesAtOnce, "device")) at once" : "Plays on any number of devices at once"))
    lines.append(AbilityLine(can.offlineCopies ? "Can keep songs on a device to play offline" : "Offline copies are off", on: can.offlineCopies))
    lines.append(AbilityLine(can.downloadFiles ? "Can download song files" : "Cannot download song files", on: can.downloadFiles))
    lines.append(AbilityLine(can.share ? "Can share links to songs" : "Cannot share links to songs", on: can.share))
    lines.append(AbilityLine(can.importPlaylists ? "Can import playlists" : "Cannot import playlists", on: can.importPlaylists))
    lines.append(AbilityLine(can.familyPlaylistsEdit ? "Can add to family playlists" : "Can listen to family playlists", on: can.familyPlaylistsEdit))
    if can.cleanOnly { lines.append(AbilityLine("Clean songs only")) }
    if can.approveRequests { lines.append(AbilityLine("Approves the family's requests")) }
    if can.manageFamily { lines.append(AbilityLine("Manages the family")) }
    return lines
}

private func usFormat(_ format: String, _ value: Double) -> String {
    String(format: format, locale: Locale(identifier: "en_US"), value)
}

/// "5.4 GB": a size in decimal gigabytes, one place after the point below 100.
public func gigabytes(_ bytes: Int64) -> String {
    let gb = Double(bytes) / 1_000_000_000
    if bytes <= 0 { return "0 GB" }
    if gb < 0.1 { return "\(usFormat("%.0f", Double(bytes) / 1_000_000)) MB" }
    if gb < 100 {
        var text = usFormat("%.1f", gb)
        if text.hasSuffix(".0") { text.removeLast(2) }
        return "\(text) GB"
    }
    return "\(usFormat("%.0f", gb)) GB"
}

/// "5.4 of 10 GB used", or with no limit "5.4 GB used".
public func storageLine(usedBytes: Int64, limitGb: Int) -> String {
    limitGb > 0 ? "\(usedOf(usedBytes: usedBytes, limitGb: limitGb)) used" : "\(gigabytes(usedBytes)) used"
}

/// "5.4 of 10 GB": the part before "used", also for the full library line.
public func usedOf(usedBytes: Int64, limitGb: Int) -> String {
    let used = gigabytes(usedBytes)
    return used.hasSuffix(" GB") ? "\(used.dropLast(3)) of \(limitGb) GB" : "\(used) of \(limitGb) GB"
}

/// What the request sheet says when the library is full.
public func storageFullLine(usedBytes: Int64, limitGb: Int) -> String {
    "Your library is full (\(usedOf(usedBytes: usedBytes, limitGb: limitGb)))"
}

/// How full the library is, 0 to 1, or nil with no limit.
public func storageShare(usedBytes: Int64, limitGb: Int) -> Double? {
    guard limitGb > 0 else { return nil }
    return min(1, max(0, Double(usedBytes) / (Double(limitGb) * 1_000_000_000)))
}

public func storageFull(usedBytes: Int64, limitGb: Int) -> Bool {
    limitGb > 0 && usedBytes >= Int64(limitGb) * 1_000_000_000
}

/// "3 of 10 requests used this week", or with no limit "3 requests this week".
public func weeklyLine(used: Int, limit: Int) -> String {
    limit > 0 ? "\(used) of \(plural(limit, "request")) used this week" : "\(plural(used, "request")) this week"
}

/// What became of a request, in a few words.
public func requestStateLine(_ request: FamilyRequest) -> String {
    switch request.state {
    case .pending: "Waiting for approval"
    case .approved: "Approved, getting it now"
    case .declined: "Declined"
    case .cancelled: "Cancelled"
    case .failed:
        if let failure = request.failure, !failure.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { "Failed: \(failure)" } else { "Failed" }
    case .done: outcomeLine(request.outcome)
    }
}

public func outcomeLine(_ outcome: FamilyRequestOutcome?) -> String {
    switch outcome {
    case .alreadyShared: "Already in the family library"
    case .addedFromFamily: "Added from the family library"
    case .downloaded: "Downloaded"
    case nil: "In your library"
    }
}

/// What a request asks for: "Song", "Album" and so on, with its quality.
public func requestKindLine(_ request: FamilyRequest) -> String {
    let kind = switch request.kind {
    case .song: "Song"
    case .album: "Album"
    case .upgrade: "Better copy"
    case .importList: "Imported list"
    case .playlistAdd: "Family playlist"
    }
    return "\(kind) · \(qualityLabel(request.quality))"
}

private func blank(_ text: String) -> Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

/// The request's title and artist as one line.
public func requestTitle(_ request: FamilyRequest) -> String {
    let line = [request.title, request.artist].filter { !blank($0) }.joined(separator: " · ")
    return line.isEmpty ? request.target : line
}

/// A device's second line: the app, home or away, and what it plays.
public func deviceLine(_ device: FamilyDevice) -> String {
    var parts = [blank(device.app) ? "A music app" : device.app, device.place == .away ? "Away" : "Home"]
    if let playing = device.playing {
        parts.append("Playing \([playing.title, playing.artist].filter { !blank($0) }.joined(separator: " by "))")
    }
    return parts.joined(separator: " · ")
}

/// A member's line for a manager: role, devices, playing, waiting requests.
public func memberLine(_ member: FamilyMember) -> String {
    var parts = [roleLabel(name: member.roleName)]
    if member.suspended { parts.append("Paused") }
    parts.append(plural(member.devices, "device"))
    if member.playingNow { parts.append("Playing now") }
    if member.pendingRequests > 0 { parts.append("\(plural(member.pendingRequests, "request")) waiting") }
    return parts.joined(separator: " · ")
}

/// "Alex, Listener": who this plan is for.
public func planTitle(_ me: FamilyMe) -> String {
    "\(blank(me.displayName) ? me.username : me.displayName), \(roleLabel(name: me.roleName))"
}

public func plural(_ count: Int, _ word: String) -> String {
    count == 1 ? "1 \(word)" : "\(count) \(word)s"
}

public func presetName(_ preset: FamilyPreset) -> String {
    switch preset {
    case .coAdmin: "Co-admin"
    case .member: "Member"
    case .listener: "Listener"
    case .kid: "Kid"
    }
}

/// What a new member of each kind may do, in a line, before they are added.
public func presetLine(_ preset: FamilyPreset) -> String {
    switch preset {
    case .coAdmin: "Runs the family with you: members, devices and requests."
    case .member: "Adds songs straight into their own library."
    case .listener: "Saves songs and asks for copies, which you approve."
    case .kid: "Clean songs only. Their requests wait for you."
    }
}

// MARK: Rules

/// What an outside song (one found online) offers this account.
public struct OutsideActions: Sendable, Equatable {
    /// The add action's words, or nil to keep the app's usual ones.
    public var addLabel: String?
    /// Whether "Request a copy" is offered.
    public var offersRequest: Bool

    public static let usual = OutsideActions(addLabel: nil, offersRequest: false)
}

public func outsideActions(_ me: FamilyMe?) -> OutsideActions {
    switch me?.abilities.addToLibrary {
    case nil, .direct?: .usual
    case .request?: OutsideActions(addLabel: FamilyText.save, offersRequest: true)
    case .saveOnly?: OutsideActions(addLabel: FamilyText.save, offersRequest: false)
    }
}

/// Whether "Remove from my library" can be offered at all: to a member the family manages.
public func offersRemoveFromMyLibrary(_ me: FamilyMe?) -> Bool {
    guard let me else { return false }
    return me.managed && me.role != .owner && me.role != .unmanaged
}

/// Whether "Remove from my library" goes on one song: the member's own songs when the server
/// marks them; every library song on a server that marks none.
public func offersRemoveOn(personal: Bool, serverMarksPersonal: Bool) -> Bool { personal || !serverMarksPersonal }

/// Whether this account may keep offline copies. Without a family, always.
public func offlineCopiesAllowed(_ me: FamilyMe?) -> Bool { me?.abilities.offlineCopies ?? true }

/// One quality in the request sheet, held back when it is above the account's limit.
public struct QualityChoice: Sendable, Equatable, Hashable {
    public var quality: RequestQuality
    public var enabled: Bool
    public var label: String { qualityLabel(quality) }
    public var detail: String { enabled ? qualityDetail(quality) : "Not on your plan" }
}

/// Everything the request sheet shows, from the account's abilities.
public struct RequestSheet: Sendable, Equatable {
    public var choices: [QualityChoice]
    /// The quality picked when the sheet opens: the best the account may ask for.
    public var initial: RequestQuality
    public var quotaLine: String?
    public var quotaUsed: Bool
    public var storageLine: String?
    public var approvalLine: String
}

public func requestSheet(_ me: FamilyMe) -> RequestSheet {
    let can = me.abilities
    let choices = [RequestQuality.best, .flac, .mp3].map { QualityChoice(quality: $0, enabled: $0.allowedUnder(can.requestQuality)) }
    let limit = can.weeklyRequestLimit
    let left = max(0, limit - me.requestsThisWeek)
    let quota: String? = if limit <= 0 {
        nil
    } else if left == 0 {
        "You have used all \(plural(limit, "request")) this week. Songs the family already has can still be added."
    } else {
        "\(left) of \(plural(limit, "request")) left this week"
    }
    return RequestSheet(
        choices: choices,
        initial: choices.first { $0.enabled }?.quality ?? .mp3,
        quotaLine: quota,
        quotaUsed: limit > 0 && left == 0,
        storageLine: storageFull(usedBytes: me.storageUsedBytes, limitGb: can.storageLimitGb)
            ? storageFullLine(usedBytes: me.storageUsedBytes, limitGb: can.storageLimitGb) : nil,
        approvalLine: can.autoApprove ? "Approved right away" : "Waits for approval")
}

/// What the sheet says once a request is sent.
public func requestAnswerLine(_ request: FamilyRequest) -> String {
    switch request.state {
    case .done: outcomeLine(request.outcome)
    case .approved: "Approved. Getting it now"
    case .pending: "Requested. You'll hear when it's decided"
    default: requestStateLine(request)
    }
}
