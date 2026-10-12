import Foundation

// The server downloads sheet: one row for each download the server is doing for this person, or
// did lately, and the words for its log and for Find songs. The app runs the calls and draws; what
// each answer means is worked out here, once.

/// The phone's own downloads (songs kept on it); the server's are named for where they happen.
public let downloadsTitle = "Downloads"
public let serverDownloadsTitle = "Server downloads"

/// The power user's way back into a search: the button and its page title.
public let findSongsTitle = "Find songs"

/// A finished upgrade the server keeps for a week shows this long, as a finished download does.
public let finishedShownMs: Int64 = 3 * 60 * 60_000

/// What a row is for.
public enum RowKind: Sendable, Equatable { case download, upgrade, pick }

/// Where a row has got to, in the order a download walks.
public enum RowPhase: Int, Sendable, Equatable, Comparable {
    case waiting, searching, downloading, checking, adding, done, failed

    public var finished: Bool { self == .done || self == .failed }

    public static func < (a: RowPhase, b: RowPhase) -> Bool { a.rawValue < b.rawValue }
}

/// One row of the sheet.
public struct DownloadRow: Sendable, Equatable, Identifiable {
    /// The row's own key: a download's, or "upgrade:<id>" for a higher quality copy that has not
    /// started downloading.
    public var key: String
    public var title: String
    public var artist: String
    public var album: String?
    /// The picture to draw, by its id on the server.
    public var coverArt: String?
    public var kind: RowKind
    public var phase: RowPhase
    /// How far, from 0 to 1, while it downloads and the server knows.
    public var fraction: Double?
    /// The one line under the title: "Downloading from Soulseek, 42%".
    public var status: String
    /// The copy being fetched, once chosen: "FLAC 16-bit 44.1 kHz".
    public var quality: String?
    public var source: String?
    public var startedAt: String?
    public var updatedAt: String?
    /// The download whose log opens from this row, when there is one.
    public var logKey: String?
    /// What Find songs looks for from this row: the library song once it is there, otherwise the
    /// found song.
    public var findId: String?
    /// The id the download was asked for with, when it is one.
    public var askedId: String?

    public var id: String { key }
    public var finished: Bool { phase.finished }
}

/// The rows to show, running ones first and newest first within each: every download the server
/// lists, and every higher quality copy asked for, joined to its download once it has one.
/// Finished upgrades leave after `finishedShownMs`, and rows in `hidden` (cleared here) not at all.
public func drawerRows(_ acquisitions: [Acquisition], _ upgrades: [Upgrade], now: Int64 = msSince1970(),
                       hidden: Set<String> = []) -> [DownloadRow] {
    var byKey: [String: Upgrade] = [:]
    for upgrade in upgrades { if let key = upgrade.acquisition, byKey[key] == nil { byKey[key] = upgrade } }
    let fromDownloads = acquisitions.map { rowOf($0, upgrade: $0.key.flatMap { byKey[$0] }) }
    let joined = Set(fromDownloads.map(\.key))
    var order: [String] = []
    var groups: [String: [Upgrade]] = [:]
    for upgrade in upgrades {
        if groups[upgrade.id] == nil { order.append(upgrade.id) }
        groups[upgrade.id, default: []].append(upgrade)
    }
    let fromUpgrades = order.compactMap { id -> Upgrade? in
        let entries = groups[id] ?? []
        return entries.first { $0.stage.pending } ?? firstMax(entries) { $0.updatedAt ?? "" }
    }
    .filter { $0.acquisition == nil || !joined.contains($0.acquisition!) }
    .map(rowOf)
    .filter { !$0.finished || (serverAgeMs($0.updatedAt, now: now).map { $0 < finishedShownMs } ?? false) }
    let rows = (fromDownloads + fromUpgrades).filter { !hidden.contains($0.key) }
    return stableSorted(rows) { a, b in
        if a.finished != b.finished { return !a.finished }
        let ka = a.finished ? (a.updatedAt ?? "") : (a.startedAt ?? "")
        let kb = b.finished ? (b.updatedAt ?? "") : (b.startedAt ?? "")
        return ka > kb
    }
}

/// A download as a row. `upgrade` is the higher quality copy it fetches, whose verdict comes after
/// the download's own end.
public func rowOf(_ acquisition: Acquisition, upgrade: Upgrade? = nil) -> DownloadRow {
    let kind: RowKind = switch acquisition.kind {
    case AcquisitionKind.upgrade: .upgrade
    case AcquisitionKind.pick: .pick
    default: upgrade != nil ? .upgrade : .download
    }
    var phase = rowPhase(of: acquisition.stage)
    var status = statusOf(acquisition)
    // The upgrade's own answer is the last word: in the library is not yet "upgraded", and a
    // download that failed may still have kept your copy.
    if let upgrade {
        switch upgrade.stage {
        case .upgraded:
            phase = .done
            status = upgrade.detail.flatMap(serverSentence) ?? "Upgraded"
        case .notFound:
            phase = .failed
            status = "No higher quality copy found"
        case .failed, .skipped:
            phase = .failed
            status = upgrade.detail.flatMap(serverSentence) ?? "Your copy is unchanged"
        case .rehearsed:
            phase = .done
            status = "Only rehearsed; nothing changed"
        default:
            // Downloaded, but still being judged before it takes the old one's place.
            if phase.finished {
                phase = .checking
                status = "Checking it before it replaces your copy"
            }
        }
    }
    let title = isBlank(acquisition.title) ? (upgrade?.title ?? "") : acquisition.title
    let updated = max(acquisition.updatedAt ?? "", upgrade?.updatedAt ?? "")
    return DownloadRow(
        key: acquisition.key ?? "\(acquisition.id):\(acquisition.startedAt ?? "")",
        title: isBlank(title) ? "A song" : title,
        artist: isBlank(acquisition.artist) ? (upgrade?.artist ?? "") : acquisition.artist,
        album: acquisition.album ?? upgrade?.album,
        coverArt: acquisition.coverArt ?? acquisition.libraryId ?? (isBlank(acquisition.id) ? nil : acquisition.id),
        kind: kind,
        phase: phase,
        fraction: phase == .downloading ? acquisition.fraction : nil,
        status: status,
        quality: acquisition.quality,
        source: acquisition.source,
        startedAt: acquisition.startedAt,
        updatedAt: updated.isEmpty ? nil : updated,
        logKey: acquisition.key,
        findId: upgrade?.id ?? acquisition.libraryId ?? (isBlank(acquisition.id) ? nil : acquisition.id),
        askedId: isBlank(acquisition.id) ? nil : acquisition.id)
}

/// A higher quality copy that has no download of its own yet, or whose download is gone from the
/// server's list.
public func rowOf(_ upgrade: Upgrade) -> DownloadRow {
    let (phase, status): (RowPhase, String) = switch upgrade.stage {
    case .queued: (.waiting, "Waiting its turn")
    case .waiting: (.waiting, "Waiting for Soulseek")
    case .working: (.searching, "Looking for a higher quality copy")
    case .upgraded: (.done, upgrade.detail.flatMap(serverSentence) ?? "Upgraded")
    case .notFound: (.failed, "No higher quality copy found")
    case .rehearsed: (.done, "Only rehearsed; nothing changed")
    case .skipped, .failed: (.failed, upgrade.detail.flatMap(serverSentence) ?? "Your copy is unchanged")
    case .unknown: (.searching, "Looking for a higher quality copy")
    }
    return DownloadRow(
        key: "upgrade:\(upgrade.id)",
        title: isBlank(upgrade.title) ? "A song" : upgrade.title,
        artist: upgrade.artist,
        album: upgrade.album,
        coverArt: upgrade.id,
        kind: upgrade.picked != nil ? .pick : .upgrade,
        phase: phase,
        fraction: phase == .searching ? upgrade.fraction : nil,
        status: status,
        quality: nil,
        source: nil,
        startedAt: upgrade.updatedAt,
        updatedAt: upgrade.updatedAt,
        logKey: upgrade.acquisition,
        findId: upgrade.id)
}

public func rowPhase(of stage: AcquisitionStage) -> RowPhase {
    switch stage {
    case .queued: .waiting
    case .searching, .unknown: .searching
    case .downloading: .downloading
    case .verifying: .checking
    case .importing: .adding
    case .done: .done
    case .failed: .failed
    }
}

/// The line under a download's title.
public func statusOf(_ acquisition: Acquisition) -> String {
    switch acquisition.stage {
    case .queued:
        if let ahead = acquisition.ahead, ahead > 0 { return "Waiting, \(ahead) ahead" }
        return "Waiting its turn"
    case .searching, .unknown:
        if let note = acquisition.note.flatMap(serverSentence) { return note }
        if let source = acquisition.source { return "Looking on \(source)" }
        return "Looking for a copy"
    case .downloading:
        var words = "Downloading"
        if let source = acquisition.source, !isBlank(source) { words += " from \(source)" }
        if let fraction = acquisition.fraction { words += ", \(percent(fraction))%" }
        return words
    case .verifying: return "Checking the file"
    case .importing: return "Adding to your library"
    case .done: return "In your library"
    case .failed: return acquisition.error.flatMap(serverSentence) ?? "Could not get it"
    }
}

/// What a row is for, as a small word beside the title, or nil for a plain download.
public func kindLabel(_ kind: RowKind) -> String? {
    switch kind {
    case .download: nil
    case .upgrade: "Higher quality"
    case .pick: "Picked"
    }
}

/// The line over the list: "2 on the way, 5 finished".
public func drawerSummary(_ rows: [DownloadRow]) -> String {
    let running = runningCount(rows)
    let finished = rows.count - running
    return [running > 0 ? "\(running) on the way" : nil, finished > 0 ? "\(finished) finished" : nil]
        .compactMap { $0 }.joined(separator: ", ")
}

/// What the sheet says with nothing in it.
public let downloadsEmpty = "Nothing downloading. Songs you add show here, with every step on the way."

/// What Find songs says about picking, for a song in the library and one that is not.
public let findReplacesText = "Only a better copy can take your copy's place, and yours stays until the new one passes every check."
public let findReplacesAsksText = "Picking a copy asks you before it replaces yours. Yours stays until the new one passes every check."
public func findReplaces(asksFirst: Bool) -> String { asksFirst ? findReplacesAsksText : findReplacesText }
public let findDownloadsText = "Pick a copy to download that one. It goes through the same checks as any download."

/// Why no copy can be picked yet: the list still grows while sources answer.
public let findPickWait = "You can pick a copy once the search is done."

/// A pick from a list that a new search has since replaced.
public let findListChanged = "The list changed. Pick a copy from it again."

/// Whether a copy on the list can be picked: once the search is done, and only a copy the server
/// named.
public func canPick(_ found: FoundSongs?, _ copy: FoundCandidate) -> Bool {
    guard let found else { return false }
    return !found.searching && (copy.id != nil || copy.index != nil)
}

/// A copy's key on the list: its id, or its place on a server older than ids.
public func copyKey(_ copy: FoundCandidate) -> String {
    if let id = copy.id { return "id:\(id)" }
    if let index = copy.index { return "at:\(index)" }
    return "copy:\(copy.hashValue)"
}

/// The library's copy of a song, in words: "Your copy: MP3 220 kbps, 7.0 MB".
public func ownedCopyText(quality: String?, size: Int64?, locale: Locale = .current) -> String? {
    let what = [quality.flatMap { isBlank($0) ? nil : $0 }, size.flatMap { $0 > 0 ? downloadBytesText($0, locale: locale) : nil }]
        .compactMap { $0 }
    return what.isEmpty ? nil : "Your copy: \(what.joined(separator: ", "))"
}

/// How many rows are still running.
public func runningCount(_ rows: [DownloadRow]) -> Int { rows.filter { !$0.finished }.count }

/// The mean progress of the rows downloading, or nil when none says how far it is.
public func overallFraction(_ rows: [DownloadRow]) -> Double? {
    let known = rows.compactMap { $0.finished ? nil : $0.fraction }
    return known.isEmpty ? nil : known.reduce(0, +) / Double(known.count)
}

// MARK: The pill

/// The running row the pill speaks for: the one furthest along, and of those the one that started
/// first, so the pill does not hop between two songs at the same step.
public func pillLead(_ rows: [DownloadRow]) -> DownloadRow? {
    stableSorted(rows.filter { !$0.finished }) { a, b in
        if a.phase != b.phase { return a.phase > b.phase }
        return (a.startedAt ?? "") < (b.startedAt ?? "")
    }.first
}

/// The step a row is on, in a word or two: "Downloading 42%", "Checking".
public func stepWords(_ row: DownloadRow) -> String {
    switch row.phase {
    case .waiting: "Waiting"
    case .searching: "Searching"
    case .downloading: row.fraction.map { "Downloading \(percent(min(1, max(0, $0))))%" } ?? "Downloading"
    case .checking: "Checking"
    case .adding: "Adding"
    case .done: "Done"
    case .failed: "Failed"
    }
}

/// How many songs the pill counts: the sheet's running rows, and songs asked for here that no list
/// shows but that are still taken as on their way.
public func pillCount(_ rows: [DownloadRow], _ asked: [AskedSong], listedSince: Int64?, now: Int64) -> Int {
    runningCount(rows) + unlisted(rows, asked, listedSince: listedSince, now: now).count
}

/// How long until `pillCount` may change with no new list or ask: when the first ask it counts runs
/// out, or nil when it counts none.
public func pillRecheckMs(_ rows: [DownloadRow], _ asked: [AskedSong], listedSince: Int64?, now: Int64) -> Int64? {
    unlisted(rows, asked, listedSince: listedSince, now: now).compactMap { stillAskedForMs($0, listedSince: listedSince, now: now) }.min()
}

private func unlisted(_ rows: [DownloadRow], _ asked: [AskedSong], listedSince: Int64?, now: Int64) -> [AskedSong] {
    var running = Set<String>()
    for row in rows where !row.finished {
        if let id = row.askedId { running.insert(id) }
        if let id = row.findId { running.insert(id) }
    }
    return asked.filter { !running.contains($0.serverId) && stillAsked($0, listedSince: listedSince, now: now) }
}

/// What the pill says aloud: "Downloading 42%, Da Funk. 2 more on the way".
public func pillSpoken(_ rows: [DownloadRow]) -> String {
    guard let lead = pillLead(rows) else { return "" }
    let more = runningCount(rows) - 1
    return "\(stepWords(lead)), \(lead.title)" + (more > 0 ? ". \(more) more on the way" : "")
}

/// The pill's words while the server's list has not said which step a song is on.
public func comingText(_ count: Int) -> String { count == 1 ? "1 downloading" : "\(count) downloading" }

/// The ring for the server's step: turning while it looks, filling as it downloads, full while it
/// is checked and added.
public func ringPhase(_ row: DownloadRow) -> DownloadPhase {
    switch row.phase {
    case .downloading: .downloading(row.fraction)
    case .checking, .adding: .adding
    case .done: .done
    default: .queued
    }
}

// MARK: The steps

/// The steps every download walks, as the log's head draws them.
public enum DownloadStep: Int, CaseIterable, Sendable {
    case find, download, check, add

    public var label: String {
        switch self {
        case .find: "Find"
        case .download: "Download"
        case .check: "Check"
        case .add: "Add"
        }
    }
}

/// Where a row is on those steps: the step it is on, or the number of steps once it is in. A
/// failed row stops on the step its log last reached.
public func stepOf(_ row: DownloadRow, events: [AcquisitionEvent] = []) -> Int {
    switch row.phase {
    case .waiting, .searching: return DownloadStep.find.rawValue
    case .downloading: return DownloadStep.download.rawValue
    case .checking: return DownloadStep.check.rawValue
    case .adding: return DownloadStep.add.rawValue
    case .done: return DownloadStep.allCases.count
    case .failed:
        if let last = events.last(where: { !afterwords.contains(markOf($0.logKind)) }) { return stepOfMark(markOf(last.logKind)) }
        return DownloadStep.find.rawValue
    }
}

/// The step a log line belongs to.
public func stepOfMark(_ mark: LogMark) -> Int {
    switch mark {
    case .queued, .search, .found, .note: DownloadStep.find.rawValue
    case .try, .transfer: DownloadStep.download.rawValue
    case .check: DownloadStep.check.rawValue
    case .tags, .cover, .lyrics, .library: DownloadStep.add.rawValue
    case .done: DownloadStep.allCases.count
    case .failed: DownloadStep.find.rawValue
    }
}

/// Lines that say how it ended, not which step it reached.
private let afterwords: Set<LogMark> = [.failed, .note, .done]

// MARK: The log

/// What a line of the log is drawn with.
public enum LogMark: Sendable, Equatable, Hashable { case queued, search, found, `try`, transfer, check, tags, cover, lyrics, library, done, failed, note }

public func markOf(_ kind: LogKind) -> LogMark {
    switch kind {
    case .queued: .queued
    case .search: .search
    case .found: .found
    case .try: .try
    case .transfer: .transfer
    case .check: .check
    case .tags: .tags
    case .cover: .cover
    case .lyrics: .lyrics
    case .library: .library
    case .done: .done
    case .failed: .failed
    case .note, .unknown: .note
    }
}

/// The clock time of a line, "18:04:31", in this phone's time zone.
public func logTime(_ at: String?, zone: TimeZone = .current) -> String {
    guard let date = at.flatMap(parseServerInstant) else { return "" }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = zone
    formatter.dateFormat = "HH:mm:ss"
    return formatter.string(from: date)
}

/// The facts of a copy, in the order a person weighs them: its quality, its size and length, then
/// where it comes from and how soon.
public func candidateFacts(_ copy: FoundCandidate, locale: Locale = .current) -> [String] {
    var facts: [String] = []
    if let quality = copy.quality ?? copy.format?.uppercased(), !isBlank(quality) { facts.append(quality) }
    if let size = copy.size, size > 0 { facts.append(downloadBytesText(size, locale: locale)) }
    if let length = copy.length, length > 0 { facts.append(downloadClockText(length)) }
    if !isBlank(copy.source) { facts.append(copy.source) }
    if let peer = copy.peer, !isBlank(peer) { facts.append(peer) }
    if copy.freeSlot == true {
        facts.append("Free to send now")
    } else if let queue = copy.queueLength, queue > 0 {
        facts.append("\(queue) in queue")
    }
    if let speed = copy.speed, speed > 0 { facts.append(downloadSpeedText(speed, locale: locale)) }
    return facts
}

/// A copy's kind in one short word for its badge: "FLAC", "MP3", or nil.
public func copyBadge(_ copy: FoundCandidate) -> String? {
    let kind: String?
    if let format = copy.format {
        kind = String(format.trimmingCharacters(in: .whitespacesAndNewlines).drop { $0 == "." })
    } else {
        kind = copy.quality.map { String($0.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false).first ?? "") }
    }
    guard let kind, !isBlank(kind) else { return nil }
    return kind.uppercased()
}

/// A copy's facts beside its badge: the quality's remainder ("16-bit 44.1 kHz") in place of the
/// whole quality, then the rest as `candidateFacts`.
public func badgeFacts(_ copy: FoundCandidate, locale: Locale = .current) -> [String] {
    let facts = candidateFacts(copy, locale: locale)
    guard let badge = copyBadge(copy), let first = facts.first, first.uppercased().hasPrefix(badge) else { return facts }
    let rest = String(first.dropFirst(badge.count)).trimmingCharacters(in: .whitespacesAndNewlines)
    return (rest.isEmpty ? [] : [rest]) + facts.dropFirst()
}

/// "1st choice" beside the copy Octo would try first, "2nd choice" and on.
public func rankWords(_ rank: Int) -> String {
    let suffix: String
    if (11...13).contains(rank % 100) {
        suffix = "th"
    } else {
        switch rank % 10 {
        case 1: suffix = "st"
        case 2: suffix = "nd"
        case 3: suffix = "rd"
        default: suffix = "th"
        }
    }
    return "\(rank)\(suffix) choice"
}

/// How many copies a log line shows before "Show all".
public let logCopiesShown = 3

/// The line a copy is known by: its title, or its file's name.
public func candidateTitle(_ copy: FoundCandidate) -> String {
    if let title = copy.title, !isBlank(title) { return title }
    if let file = copy.file, !isBlank(file) { return file }
    return copy.source
}

/// "Octo's first choice", or the server's reason for passing it over.
public func candidateVerdict(_ copy: FoundCandidate) -> String? {
    if copy.rank == 1 { return "Octo's first choice" }
    if let rank = copy.rank { return "Octo's choice \(rank)" }
    return copy.note.flatMap(serverSentence)
}

/// Whether a copy is lossless, by its kind.
public func isLosslessCopy(_ copy: FoundCandidate) -> Bool {
    guard let format = copy.format else { return false }
    let kind = String(format.trimmingCharacters(in: .whitespacesAndNewlines).drop { $0 == "." }).lowercased()
    let word = String(kind.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false).first ?? "")
    let head = String(word.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false).first ?? "")
    return losslessKinds.contains(head)
}

private let losslessKinds: Set<String> = ["flac", "wav", "alac", "ape", "aiff", "aif", "wv"]

/// Kilobytes under a megabyte, megabytes above.
public func downloadBytesText(_ bytes: Int64, locale: Locale = .current) -> String {
    if bytes < 1_048_576 { return String(format: "%.0f KB", locale: locale, Double(bytes) / 1024) }
    if bytes < 1_073_741_824 { return String(format: "%.1f MB", locale: locale, Double(bytes) / 1_048_576) }
    return String(format: "%.2f GB", locale: locale, Double(bytes) / 1_073_741_824)
}

/// "3:07".
public func downloadClockText(_ seconds: Int) -> String { String(format: "%d:%02d", seconds / 60, seconds % 60) }

/// Bytes a second as "1.4 MB/s" or "340 KB/s".
public func downloadSpeedText(_ bytesPerSecond: Int, locale: Locale = .current) -> String {
    if bytesPerSecond >= 1_048_576 { return String(format: "%.1f MB/s", locale: locale, Double(bytesPerSecond) / 1_048_576) }
    return "\(max(1, bytesPerSecond / 1024)) KB/s"
}

/// How long ago an ISO time was, or nil when it cannot be read.
public func serverAgeMs(_ at: String?, now: Int64) -> Int64? {
    guard let date = at.flatMap(parseServerInstant) else { return nil }
    return now - Int64((date.timeIntervalSince1970 * 1_000).rounded(.down))
}

/// The server's words as one line: trimmed, without a closing full stop.
public func serverSentence(_ text: String) -> String? {
    var words = text.trimmingCharacters(in: .whitespacesAndNewlines)
    while words.hasSuffix(".") { words.removeLast() }
    words = words.trimmingCharacters(in: .whitespacesAndNewlines)
    return words.isEmpty ? nil : words
}

/// An ISO 8601 instant, with any number of fraction digits and a Z or an offset.
public func parseServerInstant(_ text: String) -> Date? {
    let plain = ISO8601DateFormatter()
    plain.formatOptions = [.withInternetDateTime]
    if let date = plain.date(from: text) { return date }
    // The fraction kept to milliseconds, which every formatter reads.
    guard let dot = text.firstIndex(of: "."), text[..<dot].contains("T") else { return nil }
    let afterDot = text[text.index(after: dot)...]
    let digits = afterDot.prefix { $0.isASCII && $0.isNumber }
    guard !digits.isEmpty else { return nil }
    let zone = afterDot.dropFirst(digits.count)
    let milli = String(digits.prefix(3)).padding(toLength: 3, withPad: "0", startingAt: 0)
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return fractional.date(from: String(text[..<dot]) + "." + milli + zone)
}

/// Now, in milliseconds since 1970.
public func msSince1970() -> Int64 { Int64((Date().timeIntervalSince1970 * 1_000).rounded(.down)) }

/// A fraction as a whole percent, cut rather than rounded.
fileprivate func percent(_ fraction: Double) -> Int { Int(Float(fraction) * 100) }

fileprivate func isBlank(_ text: String) -> Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

/// The first element with the largest key.
fileprivate func firstMax<T>(_ items: [T], key: (T) -> String) -> T? {
    var best: T?
    var bestKey = ""
    for item in items {
        let k = key(item)
        if best == nil || k > bestKey {
            best = item
            bestKey = k
        }
    }
    return best
}

/// Sorted, keeping the order of equal elements.
fileprivate func stableSorted<T>(_ items: [T], by before: (T, T) -> Bool) -> [T] {
    items.enumerated().sorted { a, b in
        if before(a.element, b.element) { return true }
        if before(b.element, a.element) { return false }
        return a.offset < b.offset
    }.map(\.element)
}
