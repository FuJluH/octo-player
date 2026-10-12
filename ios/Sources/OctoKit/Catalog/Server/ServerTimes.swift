import Foundation

private let dateTime = try! NSRegularExpression(
    pattern: #"^([0-9]{4,})-([0-9]{2})-([0-9]{2})T([0-9]{2}):([0-9]{2})(?::([0-9]{2})(?:[.,]([0-9]{1,9}))?)?(Z|z|[+-][0-9]{2}:[0-9]{2}(?::[0-9]{2})?)?$"#)

/// A server's date and time ("2026-09-19T01:44:59.636933547Z", "2026-09-23T10:00:00+02:00"), as
/// milliseconds since 1970. One with no zone is taken as UTC. Nil for anything else.
public func epochMs(_ text: String?) -> Int64? {
    guard let text else { return nil }
    guard let match = dateTime.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
    func group(_ index: Int) -> String? {
        let range = match.range(at: index)
        guard range.location != NSNotFound, let swiftRange = Range(range, in: text) else { return nil }
        return String(text[swiftRange])
    }
    guard let year = group(1).flatMap({ Int64($0) }), let month = group(2).flatMap({ Int64($0) }),
          let day = group(3).flatMap({ Int64($0) }), let hour = group(4).flatMap({ Int64($0) }),
          let minute = group(5).flatMap({ Int64($0) })
    else { return nil }
    let second = group(6).flatMap { Int64($0) } ?? 0
    guard (1...12).contains(month), (1...daysIn(month, year)).contains(day), hour < 24, minute < 60, second < 60 else { return nil }
    var millis: Int64 = 0
    if let fraction = group(7) {
        let three = (fraction + "00").prefix(3)
        millis = Int64(three) ?? 0
    }
    var offset: Int64 = 0
    if let zone = group(8), zone != "Z", zone != "z" {
        let sign: Int64 = zone.hasPrefix("-") ? -1 : 1
        let parts = zone.dropFirst().split(separator: ":").compactMap { Int64($0) }
        guard parts.count >= 2, parts[0] <= 18, parts[1] < 60 else { return nil }
        offset = sign * (parts[0] * 3600 + parts[1] * 60 + (parts.count > 2 ? parts[2] : 0))
    }
    let days = daysFromCivil(year, month, day)
    let seconds = days * 86_400 + hour * 3600 + minute * 60 + second - offset
    return seconds * 1000 + millis
}

/// Seconds since 1970 from a server time.
func epochSeconds(_ text: String?) -> Int64? { epochMs(text).map { floorDiv($0, 1000) } }

func floorDiv(_ a: Int64, _ b: Int64) -> Int64 {
    let (q, r) = a.quotientAndRemainder(dividingBy: b)
    return r != 0 && (r < 0) != (b < 0) ? q - 1 : q
}

private func isLeap(_ year: Int64) -> Bool { (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 }

private func daysIn(_ month: Int64, _ year: Int64) -> Int64 {
    switch month {
    case 2: isLeap(year) ? 29 : 28
    case 4, 6, 9, 11: 30
    default: 31
    }
}

/// Days since 1970-01-01 for a date in the proleptic Gregorian calendar.
func daysFromCivil(_ year: Int64, _ month: Int64, _ day: Int64) -> Int64 {
    let y = month <= 2 ? year - 1 : year
    let era = (y >= 0 ? y : y - 399) / 400
    let yoe = y - era * 400
    let mp = (month + 9) % 12
    let doy = (153 * mp + 2) / 5 + day - 1
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
    return era * 146_097 + doe - 719_468
}
