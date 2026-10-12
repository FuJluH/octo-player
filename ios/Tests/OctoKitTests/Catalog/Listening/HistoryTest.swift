import Foundation
import Testing
@testable import OctoKit

@Suite struct HistoryTest {
    let zone = TimeZone(identifier: "America/Chicago")!
    let us = Locale(identifier: "en_US")

    func track(_ id: String, durationMs: Int64 = 200_000) -> LibraryTrack {
        listeningTrack(id, durationMs: durationMs)
    }

    func at(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Int64 {
        listeningTime(zone, year, month, day, hour, minute)
    }

    func play(_ id: String, _ time: Int64) -> HistoryPlay {
        HistoryPlay(track: track(id), at: time)
    }

    // Days

    @Test func playsFallUnderTodayYesterdayAndTheWeekday() {
        let now = at(2026, 9, 26, 20)
        let plays = [
            play("a", at(2026, 9, 26, 19)),
            play("b", at(2026, 9, 26, 0, 5)),
            play("c", at(2026, 9, 25, 23, 59)),
            play("d", at(2026, 9, 22)),
        ]
        let days = historyDays(plays, now: now, zone: zone, locale: us)
        #expect(days.map(\.label) == ["Today", "Yesterday", "Tuesday"])
        #expect(days[0].plays.map(\.track.id) == ["a", "b"])
        #expect(days[1].plays.map(\.track.id) == ["c"])
    }

    @Test func olderDaysShowTheDateAndTheYearOnceItIsNotThisOne() {
        let today = listeningDay(2026, 9, 26)
        #expect(dayLabel(listeningDay(2026, 9, 19), today: today, zone: zone, locale: us) == "September 19")
        #expect(dayLabel(listeningDay(2026, 9, 20), today: today, zone: zone, locale: us) == "Sunday")
        #expect(dayLabel(listeningDay(2025, 12, 31), today: today, zone: zone, locale: us) == "December 31, 2025")
    }

    @Test func midnightIsCountedInTheListenersZone() {
        // 23:30 in Chicago is already the next day in UTC.
        let now = at(2026, 9, 26, 23, 45)
        let days = historyDays([play("a", at(2026, 9, 26, 23, 30))], now: now, zone: zone, locale: us)
        #expect(days.map(\.label) == ["Today"])
    }

    @Test func theSameSongPlayedTwiceShowsTwice() {
        let now = at(2026, 9, 26, 20)
        let days = historyDays([play("a", at(2026, 9, 26, 19)), play("a", at(2026, 9, 26, 18))], now: now, zone: zone, locale: us)
        #expect(days.count == 1)
        #expect(days.first?.plays.count == 2)
    }

    @Test func noPlaysNoDays() {
        #expect(historyDays([], now: at(2026, 9, 26), zone: zone, locale: us) == [])
    }

    // The recent list

    func local(_ id: String, _ time: Int64) -> PlayedAt {
        PlayedAt(track: track(id), startedAt: time)
    }

    func server(_ id: String, _ plays: Int, _ last: Int64?, serverId: String? = nil) -> ServerPlayedTrack {
        ServerPlayedTrack(track: track(id), serverId: serverId ?? "s\(id)", serverPlays: plays, serverLastPlayedAt: last)
    }

    @Test func theServersLastPlayJoinsWhenItIsNotThePhonesOwn() {
        let mine = [local("a", 5_000_000)]
        let elsewhere = [server("b", 3, 9_000_000)]
        let list = recentHistory(mine, elsewhere, limit: 100)
        #expect(list.map(\.track.id) == ["b", "a"])
    }

    @Test func aPlayTheServerHeardFromThePhoneIsNotShownTwice() {
        // Sent with its start time; the server keeps whole seconds.
        let mine = [local("a", 5_000_400)]
        let list = recentHistory(mine, [server("a", 1, 5_000_000)], limit: 100)
        #expect(list.count == 1)
        #expect(list.first?.at == 5_000_400)
    }

    @Test func serverPlaysOlderThanTheLoadedPhonePlaysAreLeftOut() {
        // The list is full, so an old server play might be the phone's own.
        let mine = [local("a", 9_000_000), local("b", 8_000_000)]
        let list = recentHistory(mine, [server("c", 1, 1_000_000)], limit: 2)
        #expect(list.map(\.track.id) == ["a", "b"])
    }

    @Test func aSongNeverPlayedOnTheServerAddsNothing() {
        let list = recentHistory([], [server("a", 0, nil)], limit: 100)
        #expect(list == [])
    }

    // Most played over a range

    @Test func rangesStartFourWeeksOrSixCalendarMonthsBack() {
        let now = at(2026, 9, 26, 12)
        #expect(rangeStart(.fourWeeks, now: now, zone: zone) == now - 28 * 24 * 60 * 60 * 1000)
        #expect(rangeStart(.sixMonths, now: now, zone: zone) == at(2026, 3, 26, 12))
        #expect(rangeStart(.allTime, now: now, zone: zone) == nil)
    }

    func counted(_ id: String, _ plays: Int, _ last: Int64) -> PlayedTrack {
        PlayedTrack(track: track(id), plays: plays, lastPlayedAt: last)
    }

    func idsAndPlays(_ list: [PlayedTrack]) -> [String] {
        list.map { "\($0.track.id)=\($0.plays)" }
    }

    @Test func allTimeAddsTheServersCounts() {
        let top = mostPlayed([counted("a", 2, 100)], [server("a", 5, 50), server("b", 4, 70)], [:], since: nil, limit: 10)
        #expect(idsAndPlays(top) == ["a=7", "b=4"])
    }

    @Test func aRangeCountsOnlyThePhonesPlaysInIt() {
        // The phone's plays arrive already counted from the range's start.
        let since: Int64 = 1_000
        let top = mostPlayed([counted("a", 2, 5_000), counted("b", 3, 4_000)], [], [:], since: since, limit: 10)
        #expect(idsAndPlays(top) == ["b=3", "a=2"])
    }

    @Test func aRangeCountsAServerPlayElsewhereOnceWhenItFallsInside() {
        let since: Int64 = 1_000_000
        let elsewhere = [server("a", 40, 2_000_000), server("b", 9, 500_000)]
        let top = mostPlayed([counted("a", 1, 1_500_000)], elsewhere, [:], since: since, limit: 10)
        // "a": one on the phone plus one elsewhere; "b" was last played before the range.
        #expect(idsAndPlays(top) == ["a=2"])
    }

    @Test func aRangeDoesNotCountThePhonesOwnPlayTwice() {
        let since: Int64 = 1_000
        // The server's last play is the phone's, sent to it.
        let top = mostPlayed([counted("a", 1, 2_000)], [server("a", 1, 2_000)], [:], since: since, limit: 10)
        #expect(idsAndPlays(top) == ["a=1"])
    }

    @Test func aRangeLeavesOutServerPlaysThatAreAllThePhonesOwn() {
        let since: Int64 = 1_000
        let sent = ["sa": SentPlays(folded: 3)]
        let top = mostPlayed([], [server("a", 3, 2_000)], sent, since: since, limit: 10)
        #expect(top == [])
    }

    @Test func theListStopsAtItsLimitMostFirst() {
        let songs = (1...30).map { counted("s\($0)", $0, Int64($0)) }
        let top = mostPlayed(songs, [], [:], since: 0, limit: 10)
        #expect(top.count == 10)
        #expect(top.first?.track.id == "s30")
    }
}
