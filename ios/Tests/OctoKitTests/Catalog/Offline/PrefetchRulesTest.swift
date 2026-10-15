import Foundation
import Testing
@testable import OctoKit

@Suite struct PrefetchRulesTest {
    let everything: (Int) -> Bool = { _ in true }

    @Test func theNextSongsInPlayOrderAreFetched() {
        #expect(prefetchAhead(playOrder: [0, 1, 2, 3, 4], current: 1, repeatMode: .off, count: 3, fetchable: everything) == [2, 3, 4])
        // Shuffled: the order they play in.
        #expect(prefetchAhead(playOrder: [3, 0, 4, 1, 2], current: 0, repeatMode: .off, count: 2, fetchable: everything) == [4, 1])
    }

    @Test func theEndOfTheQueueStopsItUnlessItRepeats() {
        #expect(prefetchAhead(playOrder: [0, 1, 2], current: 1, repeatMode: .off, count: 3, fetchable: everything) == [2])
        #expect(prefetchAhead(playOrder: [0, 1, 2, 3], current: 2, repeatMode: .all, count: 2, fetchable: everything) == [3, 0])
    }

    @Test func repeatingOneSongCountsAsNoRepeat() {
        #expect(prefetchAhead(playOrder: [0, 1, 2], current: 1, repeatMode: .one, count: 3, fetchable: everything) == [2])
    }

    @Test func comingRoundToTheSongPlayingNowStops() {
        #expect(prefetchAhead(playOrder: [0, 1, 2], current: 1, repeatMode: .all, count: 5, fetchable: everything) == [2, 0])
    }

    @Test func songsFoundOnlineAreSkippedButStillCount() {
        let ids = ["a", "find:b", "c", "d"]
        let fetchable: (Int) -> Bool = { prefetchFetchable(trackId: ids[$0], isServerStream: true) }
        #expect(prefetchAhead(playOrder: [0, 1, 2, 3], current: 0, repeatMode: .off, count: 2, fetchable: fetchable) == [2])
        #expect(!prefetchFetchable(trackId: "phone", isServerStream: false))
    }

    @Test func nothingIsFetchedWhilePausedOrForNoSongs() {
        #expect(prefetchAhead(playOrder: [0, 1], current: 0, repeatMode: .off, playing: false, count: 3, fetchable: everything).isEmpty)
        #expect(prefetchAhead(playOrder: [0, 1], current: 0, repeatMode: .off, count: 0, fetchable: everything).isEmpty)
        #expect(prefetchAhead(playOrder: [], current: 0, repeatMode: .off, count: 3, fetchable: everything).isEmpty)
    }

    @Test func howManyFollowsTheConnection() {
        let prefs = OfflinePrefs()
        #expect(prefetchCount(cacheEnabled: true, onWifi: true, online: true, prefs: prefs) == 3)
        #expect(prefetchCount(cacheEnabled: true, onWifi: false, online: true, prefs: prefs) == 1)
        #expect(prefetchCount(cacheEnabled: true, onWifi: false, online: false, prefs: prefs) == 0)
        #expect(prefetchCount(cacheEnabled: false, onWifi: true, online: true, prefs: prefs) == 0)
    }

    @Test func lowDataModeFetchesAsFewAsMobileData() {
        var prefs = OfflinePrefs()
        prefs.prefetchWifi = 5
        prefs.prefetchMobile = 2
        #expect(prefetchCount(cacheEnabled: true, onWifi: true, online: true, prefs: prefs, lowData: true) == 2)
        #expect(prefetchCount(cacheEnabled: true, onWifi: false, online: true, prefs: prefs, lowData: true) == 2)
        #expect(prefetchCount(cacheEnabled: true, onWifi: true, online: false, prefs: prefs, lowData: true) == 0)
        #expect(prefetchCount(cacheEnabled: true, onWifi: true, online: true, prefs: prefs, lowData: false) == 5)
    }
}
