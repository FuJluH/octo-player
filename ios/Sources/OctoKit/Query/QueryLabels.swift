import Foundation

extension QueryField {
    /// What a field is called in a rule's words.
    public var label: String {
        switch self {
        case .title: "Title"
        case .artist: "Artist"
        case .album: "Album"
        case .albumArtist: "Album artist"
        case .genre: "Genre"
        case .composer: "Composer"
        case .format: "Format"
        case .year: "Year"
        case .plays: "Plays"
        case .rating: "Rating"
        case .duration: "Length"
        case .bitRate: "Bit rate"
        case .bpm: "BPM"
        case .added: "Added"
        case .lastPlayed: "Played"
        case .favorite: "Favorite"
        case .lossless: "Lossless"
        }
    }
}

extension QueryRule {
    /// A rule in plain words, for a pill or a live list's summary: "Added in the last month",
    /// "Genre is Electronic", "Never played", "Rating at least 4", "Favorites". Dates are told in
    /// `zone`.
    public func label(zone: TimeZone = .current) -> String {
        let name = field.label
        guard complete else { return name }
        switch field.kind {
        case .text:
            let value = field == .format ? (text ?? "").uppercased() : (text ?? "")
            return "\(name) \(textWords(op)) \(value)"
        case .number:
            return numberLabel(name)
        case .date:
            return dateLabel(zone)
        case .flag:
            if field == .lossless { return flag == true ? "Lossless" : "Lossy" }
            return flag == true ? "Favorites" : "Not favorites"
        }
    }

    /// "week", "month", "6 months", "2 years", "10 days": a span in the words a person would use,
    /// for the spans the filters offer.
    public static func spanWords(_ days: Int) -> String {
        if days == 1 { return "day" }
        if days == 7 { return "week" }
        if days == 30 { return "month" }
        if days == 365 { return "year" }
        if days > 0, days % 365 == 0 { return "\(days / 365) years" }
        if days > 0, days % 30 == 0 { return "\(days / 30) months" }
        if days > 0, days % 7 == 0 { return "\(days / 7) weeks" }
        return "\(days) days"
    }

    private func textWords(_ op: QueryOp) -> String {
        switch op {
        case .contains: "contains"
        case .doesNotContain: "does not contain"
        case .startsWith: "starts with"
        case .isNot: "is not"
        default: "is"
        }
    }

    private func numberLabel(_ name: String) -> String {
        let low = number ?? 0
        let high = to ?? low
        // A year range of one whole decade reads as the decade.
        if field == .year, op == .between, low % 10 == 0, high == low + 9 { return "From the \(low)s" }
        let show: (Int64) -> String
        switch field {
        case .duration: show = lengthWords
        case .bitRate: show = { "\($0) kbps" }
        default: show = { String($0) }
        }
        // Plays and lengths read as a person says them: "Played 10 times or more", "3:00 or
        // shorter".
        if field == .plays {
            func times(_ n: Int64) -> String { n == 1 ? "once" : "\(n) times" }
            switch op {
            case .is: return low == 0 ? "Never played" : "Played \(times(low))"
            case .atLeast: return low <= 1 ? "Played at least once" : "Played \(times(low)) or more"
            case .atMost: return "Played \(times(low)) or fewer"
            default: break
            }
        }
        if field == .duration {
            switch op {
            case .atLeast: return "\(show(low)) or longer"
            case .atMost: return "\(show(low)) or shorter"
            default: break
            }
        }
        switch op {
        case .is: return "\(name) is \(show(low))"
        case .isNot: return "\(name) is not \(show(low))"
        case .atLeast: return "\(name) at least \(show(low))"
        case .atMost: return "\(name) at most \(show(low))"
        default: return "\(name) between \(show(min(low, high))) and \(show(max(low, high)))"
        }
    }

    private func dateLabel(_ zone: TimeZone) -> String {
        let added = field == .added
        let span = Self.spanWords(days ?? 0)
        let day = at.map { dayWords($0, zone: zone) } ?? ""
        switch op {
        case .inTheLast: return added ? "Added in the last \(span)" : "Played in the last \(span)"
        case .notInTheLast: return added ? "Not added in the last \(span)" : "Not played in the last \(span)"
        case .before: return added ? "Added before \(day)" : "Last played before \(day)"
        case .after: return added ? "Added since \(day)" : "Last played since \(day)"
        default: return added ? "No date added" : "Never played"
        }
    }
}

private let monthWords = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

/// A moment's day in `zone`, as "5 Jan 2024".
private func dayWords(_ ms: Int64, zone: TimeZone) -> String {
    let seconds = floorDiv(ms, 1_000)
    let offset = Int64(zone.secondsFromGMT(for: Date(timeIntervalSince1970: TimeInterval(seconds))))
    let days = floorDiv(seconds + offset, 86_400)
    // Days since 1970 to a proleptic Gregorian date.
    let z = days + 719_468
    let era = (z >= 0 ? z : z - 146_096) / 146_097
    let doe = z - era * 146_097
    let yoe = (doe - doe / 1_460 + doe / 36_524 - doe / 146_096) / 365
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
    let mp = (5 * doy + 2) / 153
    let day = doy - (153 * mp + 2) / 5 + 1
    let month = mp < 10 ? mp + 3 : mp - 9
    let year = yoe + era * 400 + (month <= 2 ? 1 : 0)
    let yearText = year >= 0 && year < 1_000 ? String(repeating: "0", count: 4 - String(year).count) + String(year) : String(year)
    return "\(day) \(monthWords[Int(month) - 1]) \(yearText)"
}

/// "3:07", or "1:02:03" for an hour or more.
private func lengthWords(_ seconds: Int64) -> String {
    let h = seconds / 3_600
    let m = (seconds % 3_600) / 60
    let s = seconds % 60
    return h > 0 ? "\(h):\(twoDigits(m)):\(twoDigits(s))" : "\(m):\(twoDigits(s))"
}

private func twoDigits(_ n: Int64) -> String { n >= 0 && n < 10 ? "0\(n)" : "\(n)" }
