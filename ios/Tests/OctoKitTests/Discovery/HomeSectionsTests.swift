import Foundation
import Testing
@testable import OctoKit

@Suite struct HomeSectionsTests {
    private let defaultIds = "pinned,recentlyPlayed,madeForYou,stations,internetRadio,yearMixes,genreMixes,artistMixes,countryMixes,"
        + "recentlyAdded,mostPlayed,favoriteAlbums,charts,artists,somethingDifferent,notPlayedLately,neverFinished,neverPlayed"
    private let mixIds = ["yearMixes", "genreMixes", "artistMixes", "countryMixes"]

    private func ids(_ entries: [HomeSectionEntry]) -> [String] { entries.map { ($0.shown ? "" : "-") + $0.section.rawValue } }

    @Test func theDefaultOrder() {
        #expect(encodeHomeSections(defaultHomeSections) == defaultIds)
        #expect(!defaultHomeSections.contains { !$0.shown })
        #expect(homeSectionsKey == "home_sections")
    }

    @Test func nothingStoredIsTheDefault() {
        #expect(homeSectionOrder(stored: nil) == defaultHomeSections)
        #expect(homeSectionOrder(stored: "") == defaultHomeSections)
        #expect(homeSectionOrder(stored: " , ,") == defaultHomeSections)
    }

    @Test func aStoredOrderReadsBackTheSame() {
        let stored = "charts,-pinned,neverPlayed,recentlyPlayed,madeForYou,stations,-internetRadio,countryMixes,-yearMixes,genreMixes,"
            + "artistMixes,recentlyAdded,mostPlayed,favoriteAlbums,artists,-somethingDifferent,notPlayedLately,neverFinished"
        let entries = homeSectionOrder(stored: stored)
        #expect(encodeHomeSections(entries) == stored)
        #expect(entries.first == HomeSectionEntry(.charts))
        #expect(entries[1] == HomeSectionEntry(.pinned, shown: false))
    }

    @Test func unknownIdsAreLeftOutAndRepeatsCountOnce() {
        let entries = homeSectionOrder(stored: "radio,-charts,pinned,charts, -nope ,recentlyPlayed")
        let stored: Set<HomeSection> = [.charts, .pinned, .recentlyPlayed]
        #expect(ids(entries.filter { stored.contains($0.section) }) == ["-charts", "pinned", "recentlyPlayed"])
        #expect(entries.count == HomeSection.allCases.count)
    }

    @Test func spacesAroundIdsDoNotMatter() {
        let entries = homeSectionOrder(stored: " charts , - pinned ")
        #expect(ids(entries.filter { $0.section == .charts || $0.section == .pinned }) == ["charts", "-pinned"])
    }

    @Test func aMissingSectionGoesInAfterTheOneBeforeItByDefault() {
        // "stations" and "internetRadio" are missing; "madeForYou" comes before them by default.
        let entries = homeSectionOrder(stored: "madeForYou,pinned,recentlyPlayed,recentlyAdded,mostPlayed,favoriteAlbums,charts,artists,"
            + "somethingDifferent,notPlayedLately,neverFinished,neverPlayed")
        #expect(Array(ids(entries).prefix(9)) == ["madeForYou", "stations", "internetRadio"] + mixIds + ["pinned", "recentlyPlayed"])
        #expect(entries.first { $0.section == .stations }?.shown == true)
    }

    @Test func anOrderSavedBeforeLiveRadioGetsItRightAfterRadio() {
        let entries = homeSectionOrder(stored: "-stations,charts,pinned,recentlyPlayed,madeForYou,recentlyAdded,mostPlayed,favoriteAlbums,"
            + "artists,somethingDifferent,notPlayedLately,neverFinished,neverPlayed")
        #expect(Array(ids(entries).prefix(7)) == ["-stations", "internetRadio"] + mixIds + ["charts"])
        #expect(entries.count == HomeSection.allCases.count)
    }

    @Test func anOrderSavedBeforeTheMixesGetsThemRightAfterLiveRadio() {
        let entries = homeSectionOrder(stored: "charts,internetRadio,-stations,pinned,recentlyPlayed,madeForYou,recentlyAdded,mostPlayed,"
            + "favoriteAlbums,artists,somethingDifferent,notPlayedLately,neverFinished,neverPlayed")
        #expect(Array(ids(entries).prefix(7)) == ["charts", "internetRadio"] + mixIds + ["-stations"])
        let mixesShown = entries.filter { mixIds.contains($0.section.rawValue) }.allSatisfy { $0.shown }
        #expect(mixesShown)
    }

    @Test func missingSectionsInARowKeepTheirDefaultOrder() {
        let entries = homeSectionOrder(stored: "-recentlyPlayed,neverPlayed")
        #expect(ids(entries) == ["pinned", "-recentlyPlayed", "madeForYou", "stations", "internetRadio"] + mixIds
            + ["recentlyAdded", "mostPlayed", "favoriteAlbums", "charts", "artists", "somethingDifferent", "notPlayedLately", "neverFinished",
               "neverPlayed"])
    }

    @Test func aMissingFirstSectionGoesFirst() {
        // "pinned" has nothing before it by default; "artists" and the rest follow "charts".
        let entries = homeSectionOrder(stored: "charts,recentlyPlayed")
        #expect(ids(entries) == ["pinned", "charts", "artists", "somethingDifferent", "notPlayedLately", "neverFinished", "neverPlayed",
                                 "recentlyPlayed", "madeForYou", "stations", "internetRadio"] + mixIds + ["recentlyAdded", "mostPlayed", "favoriteAlbums"])
    }

    @Test func aMissingSectionFollowsTheNearestEarlierOneThere() {
        // Neither "favoriteAlbums" nor "mostPlayed" is stored, so "charts" goes after "recentlyAdded".
        let entries = homeSectionOrder(stored: "recentlyAdded,pinned,artists")
        #expect(Array(ids(entries).prefix(6)) == ["recentlyAdded", "mostPlayed", "favoriteAlbums", "charts", "pinned", "recentlyPlayed"])
        #expect(entries.count == HomeSection.allCases.count)
    }

    @Test func hiddenIsWrittenWithALeadingDash() {
        let entries = toggleHomeSection(defaultHomeSections, .charts, shown: false)
        #expect(encodeHomeSections(entries) == defaultIds.replacingOccurrences(of: "charts", with: "-charts"))
        #expect(toggleHomeSection(entries, .charts, shown: true) == defaultHomeSections)
    }

    @Test func movingAsAListDragReportsIt() {
        // Drag "charts" (12) to the top.
        var entries = moveHomeSections(defaultHomeSections, fromOffsets: IndexSet(integer: 12), toOffset: 0)
        #expect(Array(ids(entries).prefix(3)) == ["charts", "pinned", "recentlyPlayed"])
        // Drag "pinned" (now 1) down below "stations" (now 4): it lands before offset 5.
        entries = moveHomeSections(entries, fromOffsets: IndexSet(integer: 1), toOffset: 5)
        #expect(Array(ids(entries).prefix(5)) == ["charts", "recentlyPlayed", "madeForYou", "stations", "pinned"])
        // To the very end.
        entries = moveHomeSections(entries, fromOffsets: IndexSet(integer: 0), toOffset: entries.count)
        #expect(ids(entries).last == "charts")
        #expect(entries.count == HomeSection.allCases.count)
    }

    @Test func movingKeepsWhetherItShows() {
        let hidden = toggleHomeSection(defaultHomeSections, .artists, shown: false)
        let moved = moveHomeSection(hidden, .artists, to: 0)
        #expect(moved.first == HomeSectionEntry(.artists, shown: false))
        #expect(moveHomeSection(moved, .artists, to: 99).last == HomeSectionEntry(.artists, shown: false))
    }

    @Test func movingNothingChangesNothing() {
        #expect(moveHomeSections(defaultHomeSections, fromOffsets: IndexSet(), toOffset: 3) == defaultHomeSections)
        #expect(moveHomeSections(defaultHomeSections, fromOffsets: IndexSet(integer: 40), toOffset: 0) == defaultHomeSections)
        #expect(moveHomeSections(defaultHomeSections, fromOffsets: IndexSet(integer: 2), toOffset: 2) == defaultHomeSections)
        #expect(moveHomeSections(defaultHomeSections, fromOffsets: IndexSet(integer: 2), toOffset: 3) == defaultHomeSections)
    }

    @Test func resetIsTheDefaultOrderAllShown() {
        #expect(resetHomeSections() == defaultHomeSections)
    }

    @Test func eachSectionHasHomesName() {
        #expect(HomeSection.stations.title == "Radio")
        #expect(HomeSection.internetRadio.title == "Live radio")
        #expect(HomeSection.yearMixes.title == "Year mixes")
        #expect(HomeSection.genreMixes.title == "Genre mixes")
        #expect(HomeSection.artistMixes.title == "Artist mixes")
        #expect(HomeSection.countryMixes.title == "Country mixes")
        #expect(HomeSection.notPlayedLately.title == "Not played in 6 months")
        #expect(HomeSection.neverFinished.title == "Albums you never finished")
        #expect(HomeSection.neverPlayed.title == "Unplayed albums")
        #expect(HomeSection.somethingDifferent.title == "Something different")
        #expect(Set(HomeSection.allCases.map(\.title)).count == HomeSection.allCases.count)
    }

    @Test func theSummarySaysWhatChanged() {
        #expect(homeSectionsSummary(defaultHomeSections) == "Every section, in the usual order")
        let hidden = toggleHomeSection(defaultHomeSections, .charts, shown: false)
        #expect(homeSectionsSummary(hidden) == "1 hidden")
        let moved = moveHomeSection(defaultHomeSections, .charts, to: 0)
        #expect(homeSectionsSummary(moved) == "Every section, in your order")
        let both = toggleHomeSection(toggleHomeSection(moved, .pinned, shown: false), .artists, shown: false)
        #expect(homeSectionsSummary(both) == "2 hidden, in your order")
    }
}
