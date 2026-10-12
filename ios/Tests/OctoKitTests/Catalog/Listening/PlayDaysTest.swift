import Foundation
import Testing
@testable import OctoKit

@Suite struct PlayDaysTest {
    let zone = TimeZone(identifier: "America/Chicago")!
    let us = Locale(identifier: "en_US")

    func at(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Int64 {
        listeningTime(zone, year, month, day, hour, minute)
    }

    @Test func playsFallUnderTodayYesterdayTheWeekdayAndTheDate() {
        let now = at(2026, 9, 28, 20)
        let plays: [(String, Int64)] = [
            ("a", at(2026, 9, 28, 19)),
            ("b", at(2026, 9, 28, 0, 5)),
            ("c", at(2026, 9, 27, 23, 59)),
            ("d", at(2026, 9, 24)),
            ("e", at(2026, 9, 2)),
            ("f", at(2025, 12, 31)),
        ]
        let days = byPlayDay(plays, at: { $0.1 }, now: now, zone: zone, locale: us)
        #expect(days.map(\.heading) == ["Today", "Yesterday", "Thursday", "September 2", "December 31, 2025"])
        #expect(days[0].items.map(\.0) == ["a", "b"])
    }

    @Test func aWeekAgoIsADateNotAWeekday() {
        let today = listeningDay(2026, 9, 28)
        #expect(playDayHeading(listeningDay(2026, 9, 22), today: today, zone: zone, locale: us) == "Tuesday")
        #expect(playDayHeading(listeningDay(2026, 9, 21), today: today, zone: zone, locale: us) == "September 21")
    }

    @Test func midnightIsTheListenersOwn() {
        let now = at(2026, 9, 28, 23, 45)
        let days = byPlayDay([at(2026, 9, 28, 23, 30)], at: { $0 }, now: now, zone: zone, locale: us)
        #expect(days.map(\.heading) == ["Today"])
    }
}
