import Foundation
import Testing
@testable import OctoKit

@Suite struct HomeGateTests {
    @Test func serverOnlyListenerWithAccessDeniedGetsShelvesAndTheQuietCard() {
        #expect(homeLayout(.denied, accessDismissed: false, librarySongs: 5_000) == HomeLayout(askAccess: true, shelves: true, empty: false))
    }

    @Test func notNowPutsTheCardAwayButKeepsTheShelves() {
        #expect(homeLayout(.deniedForever, accessDismissed: true, librarySongs: 5_000) == HomeLayout(askAccess: false, shelves: true, empty: false))
    }

    @Test func accessAllowedNeverShowsTheCard() {
        #expect(homeLayout(.granted, accessDismissed: false, librarySongs: 12) == HomeLayout(askAccess: false, shelves: true, empty: false))
        #expect(homeLayout(.granted, accessDismissed: false, librarySongs: 0) == HomeLayout(askAccess: false, shelves: false, empty: true))
    }

    @Test func anEmptyLibraryShowsTheNoteAndTheCardWhileAccessIsMissing() {
        #expect(homeLayout(.notAsked, accessDismissed: false, librarySongs: 0) == HomeLayout(askAccess: true, shelves: false, empty: true))
        #expect(homeLayout(.notAsked, accessDismissed: true, librarySongs: 0) == HomeLayout(askAccess: false, shelves: false, empty: true))
    }

    @Test func nothingShowsForValuesNotReadYet() {
        #expect(homeLayout(.notAsked, accessDismissed: nil, librarySongs: nil) == HomeLayout(askAccess: false, shelves: false, empty: false))
        // The count known but not the choice: shelves, no card until it is read.
        #expect(homeLayout(.denied, accessDismissed: nil, librarySongs: 3) == HomeLayout(askAccess: false, shelves: true, empty: false))
    }

    @Test func theAccessButtonSaysWhereItGoes() {
        #expect(accessButtonLabel(.deniedForever) == "Open settings")
        #expect(accessButtonLabel(.denied) == "Allow access")
    }
}

@Suite struct StationsTests {
    private let now: Int64 = 1_000_000_000

    @Test func loadsWhenNeverLoaded() {
        #expect(stationsDue(now: now, loadedAt: nil, failed: false, loading: false))
    }

    @Test func neverLoadsTwiceAtOnce() {
        #expect(!stationsDue(now: now, loadedAt: nil, failed: true, loading: true))
        #expect(!stationsDue(now: now, loadedAt: now - stationsStaleMs * 2, failed: false, loading: true))
    }

    @Test func loadsAgainAfterAFailure() {
        #expect(stationsDue(now: now, loadedAt: now - 1_000, failed: true, loading: false))
    }

    @Test func keepsAFreshList() {
        #expect(!stationsDue(now: now, loadedAt: now - 1_000, failed: false, loading: false))
        #expect(!stationsDue(now: now, loadedAt: now - stationsStaleMs + 1, failed: false, loading: false))
    }

    @Test func loadsAgainOnceStale() {
        #expect(stationsDue(now: now, loadedAt: now - stationsStaleMs, failed: false, loading: false))
    }

    @Test func aMadeForYouListSaysHowManySongs() {
        #expect(songCountLine(1) == "1 song")
        #expect(songCountLine(24) == "24 songs")
    }

    @Test func aStationTheServerNoLongerHasSaysSo() {
        #expect(stationGoneLine("Chill mix") == "Chill mix isn't on the server any more")
    }

    @Test func madeForYouListsComeInTheirKindsOrder() throws {
        let lists = try JSONDecoder().decode([Playlist].self, from: Data("""
        [{"id":"1","name":"Mine"},{"id":"2","name":"Deep","octoList":"deepCuts"},{"id":"3","name":"Odd","octoList":"weekly"},
         {"id":"4","name":"New","octoList":"newReleases"},{"id":"5","name":"Liked","octoList":"liked"},
         {"id":"6","name":"Other","octoList":"monthly"}]
        """.utf8))
        #expect(madeForYouLists(lists).map(\.id) == ["5", "4", "2", "3", "6"])
    }
}

@Suite struct WhatsNewTests {
    @Test func aFreshInstallHasNoNews() {
        #expect(!whatsNewDue(lastSeen: nil, current: 3, freshInstall: true))
    }

    @Test func theFirstUpdateSinceTheCardExistedShowsIt() {
        #expect(whatsNewDue(lastSeen: nil, current: 3, freshInstall: false))
    }

    @Test func itShowsOncePerVersion() {
        #expect(whatsNewDue(lastSeen: 2, current: 3, freshInstall: false))
        #expect(!whatsNewDue(lastSeen: 3, current: 3, freshInstall: false))
    }

    @Test func theHomeCardLineIsShortAndPlain() {
        #expect(whatsNewSummary.count <= 70)
        #expect(!whatsNewSummary.unicodeScalars.contains { $0.value == 0x2014 || $0.value == 0x2013 })
    }
}
