import Testing
@testable import OctoKit

/// Mirrors SearchMixTest.kt.
struct SearchMixTests {
    @Test func lookingOnlineFollowsWhatIsKnown() {
        #expect(outsideLook(wanted: false, looking: true, failed: false, count: 5) == .off)
        #expect(outsideLook(wanted: true, looking: true, failed: false, count: 0) == .looking)
        #expect(outsideLook(wanted: true, looking: false, failed: true, count: 0) == .failed)
        #expect(outsideLook(wanted: true, looking: false, failed: false, count: 3) == .found)
        #expect(outsideLook(wanted: true, looking: false, failed: false, count: 0) == .noneFound)
    }

    @Test func theLineSaysPlainlyWhatHappened() {
        #expect(outsideLine(.looking, query: "linkin park") == "Searching outside your library…")
        #expect(outsideLine(.noneFound, query: " linkin park ") == "No songs outside your library for \"linkin park\"")
        #expect(outsideLine(.noneFound, query: "x", kind: "albums") == "No albums outside your library for \"x\"")
        #expect(outsideLine(.failed, query: "x") == "Couldn't search outside your library")
        #expect(outsideLine(.found, query: "x") == "Not in your library")
        #expect(outsideLine(.off, query: "x") == nil)
    }

    @Test func allShowsAFewOfEachAndSeeAllForTheRest() {
        #expect(!moreSongsThanShown(library: librarySongsShown, online: onlineSongsShown))
        #expect(moreSongsThanShown(library: librarySongsShown + 1, online: 0))
        #expect(moreSongsThanShown(library: 0, online: onlineSongsShown + 1))
    }

    @Test func songsShowWhileThereIsSomethingToSay() {
        #expect(songsShown(library: 2, look: .off))
        #expect(songsShown(library: 0, look: .looking))
        #expect(songsShown(library: 0, look: .noneFound))
        #expect(!songsShown(library: 0, look: .off))
    }

    @Test func theSameNumbersAsThePhone() {
        #expect(librarySongsShown == 3)
        #expect(onlineSongsShown == 4)
        #expect(waitingRows == 4)
    }

    @Test func aSearchStateSaysWhereLookingStands() {
        #expect(DiscoverState.idle.look(count: 0) == .off)
        #expect(DiscoverState.loading.look(count: 0) == .looking)
        #expect(DiscoverState.failed.look(count: 0) == .failed)
    }
}
