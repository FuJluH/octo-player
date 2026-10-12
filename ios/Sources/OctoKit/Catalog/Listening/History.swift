import Foundation

/// One play in the history: the song, and when it started.
public struct HistoryPlay: Sendable, Hashable {
    public var track: LibraryTrack
    public var at: Int64

    public init(track: LibraryTrack, at: Int64) {
        self.track = track
        self.at = at
    }
}

/// A day's plays under its heading, newest first.
public struct HistoryDay: Sendable, Hashable {
    public var label: String
    public var plays: [HistoryPlay]
}

/// Octo sends its own plays to the server with their start time, which the server may keep to the
/// second only.
private let samePlaySlackMs: Int64 = 1_000

/// The latest plays, newest first. The phone knows every play it made; the server adds only the
/// last time each song was played anywhere, which joins the list unless it is one of the phone's
/// own plays sent there. Past the oldest phone play loaded, that cannot be told, so older server
/// plays are left out.
public func recentHistory(_ local: [PlayedAt], _ server: [ServerPlayedTrack], limit: Int) -> [HistoryPlay] {
    var mine: [String: [Int64]] = [:]
    for play in local { mine[play.track.id, default: []].append(play.startedAt) }
    let horizon = local.count >= limit ? (local.map(\.startedAt).min() ?? Int64.min) : Int64.min
    let elsewhere: [HistoryPlay] = server.compactMap { copy in
        guard let at = copy.serverLastPlayedAt else { return nil }
        let window = max(copy.track.durationMs, 0) + samePlaySlackMs
        let ours = (mine[copy.track.id] ?? []).contains { abs($0 - at) <= window }
        return ours || at < horizon ? nil : HistoryPlay(track: copy.track, at: at)
    }
    var seen = Set<String>()
    let all = (local.map { HistoryPlay(track: $0.track, at: $0.startedAt) } + elsewhere)
        .filter { seen.insert("\($0.track.id)\u{0}\($0.at)").inserted }
    return Array(all.enumerated().sorted { a, b in
        if a.element.at != b.element.at { return a.element.at > b.element.at }
        if a.element.track.id != b.element.track.id { return a.element.track.id < b.element.track.id }
        return a.offset < b.offset
    }.map(\.element).prefix(limit))
}

/// Plays under a heading per day: Today, Yesterday, the weekday for the rest of the week, then
/// the date, with the year once it is not this one.
public func historyDays(_ plays: [HistoryPlay], now: Int64, zone: TimeZone, locale: Locale = .current) -> [HistoryDay] {
    byPlayDay(plays, at: \.at, now: now, zone: zone, locale: locale).map { HistoryDay(label: $0.heading, plays: $0.items) }
}

/// The heading for one day of the history.
public func dayLabel(_ day: DateComponents, today: DateComponents, zone: TimeZone = .current, locale: Locale = .current) -> String {
    playDayHeading(day, today: today, zone: zone, locale: locale)
}

/// How far back "most played" looks.
public enum HistoryRange: String, Sendable, CaseIterable {
    case fourWeeks, sixMonths, allTime

    public var label: String {
        switch self {
        case .fourWeeks: "Last 4 weeks"
        case .sixMonths: "Last 6 months"
        case .allTime: "All time"
        }
    }
}

/// When a range starts, or nil for all time. Six months is by the calendar.
public func rangeStart(_ range: HistoryRange, now: Int64, zone: TimeZone) -> Int64? {
    switch range {
    case .fourWeeks:
        return now - 28 * 24 * 60 * 60 * 1000
    case .sixMonths:
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let date = Date(timeIntervalSince1970: Double(now) / 1000)
        guard let back = calendar.date(byAdding: .month, value: -6, to: date) else { return nil }
        return Int64((back.timeIntervalSince1970 * 1000).rounded())
    case .allTime:
        return nil
    }
}

/// The most played songs, most first, then the one played last, from the phone's plays counted
/// since `since` (all of them when nil). For all time, the server's counts join; within a range a
/// song played elsewhere counts one more play when the server's last play falls in the range and
/// was not the phone's own.
public func mostPlayed(_ local: [PlayedTrack], _ server: [ServerPlayedTrack], _ sent: [String: SentPlays], since: Int64?,
                       limit: Int) -> [PlayedTrack] {
    let merged = since.map { withServerPlaysSince(local, server, sent, $0) } ?? withServerPlays(local, server, sent)
    return Array(merged.enumerated().sorted { a, b in
        if a.element.plays != b.element.plays { return a.element.plays > b.element.plays }
        if a.element.lastPlayedAt != b.element.lastPlayedAt { return a.element.lastPlayedAt > b.element.lastPlayedAt }
        if a.element.track.id != b.element.track.id { return a.element.track.id < b.element.track.id }
        return a.offset < b.offset
    }.map(\.element).prefix(limit))
}

private func withServerPlaysSince(_ local: [PlayedTrack], _ server: [ServerPlayedTrack], _ sent: [String: SentPlays],
                                  _ since: Int64) -> [PlayedTrack] {
    var order: [String] = []
    var byId: [String: PlayedTrack] = [:]
    for row in local {
        if byId[row.track.id] == nil { order.append(row.track.id) }
        byId[row.track.id] = row
    }
    for copy in server {
        guard let last = copy.serverLastPlayedAt, last >= since else { continue }
        // Plays the server holds that are not the phone's own.
        let others = copy.serverPlays - sent[copy.serverId].heldBy(last)
        if others <= 0 { continue }
        if var mine = byId[copy.track.id] {
            // The phone's latest play in the range is the server's last: its own.
            if abs(mine.lastPlayedAt - last) <= samePlaySlackMs { continue }
            mine.plays += 1
            mine.lastPlayedAt = max(mine.lastPlayedAt, last)
            byId[copy.track.id] = mine
        } else {
            order.append(copy.track.id)
            byId[copy.track.id] = PlayedTrack(track: copy.track, plays: 1, lastPlayedAt: last)
        }
    }
    return order.compactMap { byId[$0] }
}

/// One day's plays under its heading, in the order they came.
public struct PlayDay<T> {
    public var heading: String
    public var items: [T]
}

extension PlayDay: Sendable where T: Sendable {}

/// Groups plays that come newest first by the day they began: Today, Yesterday, the weekday for
/// the rest of the week, then the date, with the year once it is not this one. The plays keep
/// their order.
public func byPlayDay<T>(_ items: [T], at: (T) -> Int64, now: Int64, zone: TimeZone, locale: Locale = .current) -> [PlayDay<T>] {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    func day(_ ms: Int64) -> DateComponents {
        calendar.dateComponents([.year, .month, .day], from: Date(timeIntervalSince1970: Double(ms) / 1000))
    }
    let today = day(now)
    var days: [PlayDay<T>] = []
    var current: DateComponents?
    var bunch: [T] = []
    for item in items {
        let date = day(at(item))
        if date != current {
            if let current { days.append(PlayDay(heading: playDayHeading(current, today: today, zone: zone, locale: locale), items: bunch)) }
            current = date
            bunch = []
        }
        bunch.append(item)
    }
    if let current { days.append(PlayDay(heading: playDayHeading(current, today: today, zone: zone, locale: locale), items: bunch)) }
    return days
}

/// The heading for one day's plays.
public func playDayHeading(_ day: DateComponents, today: DateComponents, zone: TimeZone, locale: Locale = .current) -> String {
    let dayNumber = civilDay(day)
    let todayNumber = civilDay(today)
    if dayNumber == todayNumber { return "Today" }
    if dayNumber == todayNumber - 1 { return "Yesterday" }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    let formatter = DateFormatter()
    formatter.locale = locale
    formatter.timeZone = zone
    formatter.calendar = calendar
    var noon = day
    noon.hour = 12
    let date = calendar.date(from: noon) ?? Date()
    if dayNumber > todayNumber - 7 && dayNumber <= todayNumber {
        formatter.dateFormat = "EEEE"
    } else if day.year == today.year {
        formatter.dateFormat = "MMMM d"
    } else {
        formatter.dateFormat = "MMMM d, yyyy"
    }
    return formatter.string(from: date)
}

private func civilDay(_ day: DateComponents) -> Int64 {
    daysFromCivil(Int64(day.year ?? 1970), Int64(day.month ?? 1), Int64(day.day ?? 1))
}
