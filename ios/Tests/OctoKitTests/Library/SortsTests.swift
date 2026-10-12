import Foundation
import Testing
@testable import OctoKit

@Suite struct SortsTests {
    @Test func eachListStartsInItsOwnOrder() {
        #expect(SortList.songs.defaultOrder == ListOrder(.song(.title), descending: false))
        #expect(SortList.liked.defaultOrder == ListOrder(.song(.dateLiked), descending: true))
        #expect(SortList.genreSongs.defaultOrder == ListOrder(.song(.title), descending: false))
        #expect(SortList.folderSongs.defaultOrder == ListOrder(.song(.folderOrder), descending: false))
        #expect(SortList.albums.defaultOrder == ListOrder(.album(.title), descending: false))
        #expect(SortList.artistAlbums.defaultOrder == ListOrder(.album(.year), descending: true))
        #expect(SortList.artists.defaultOrder == ListOrder(.artist(.name), descending: false))
        #expect(SortList.playlists.defaultOrder == ListOrder(.playlist(.recentlyChanged), descending: true))
        #expect(SortList.downloads.defaultOrder == ListOrder(.download(.recentlyDownloaded), descending: true))
    }

    @Test func everyDefaultIsOneOfItsListsOptions() {
        for list in SortList.allCases { #expect(list.options.contains(list.defaultOrder.by), "\(list)") }
    }

    @Test func songsOfferTheWholeSet() {
        #expect(SortList.songs.options.map(\.label) == [
            "Title", "Artist", "Album", "Recently added", "Year", "Length", "Most played", "Recently played", "Rating", "Liked",
        ])
        #expect(SortList.liked.options.map(\.label) == ["Date liked", "Title", "Artist", "Album", "Recently added"])
        #expect(SortList.artistAlbums.options.map(\.label) == ["Year", "Title", "Most played"])
    }

    @Test func everyOrderRoundTripsBothWays() {
        for list in SortList.allCases {
            for option in list.options {
                for descending in [false, true] {
                    let order = ListOrder(option, descending: descending)
                    #expect(list.decode(list.encode(order)) == order, "\(list) \(option.id)")
                }
            }
        }
    }

    @Test func savedTextLooksLikeOptionAndDirection() {
        #expect(SortList.songs.encode(ListOrder(.song(.recentlyAdded), descending: true)) == "RecentlyAdded:desc")
        #expect(SortList.artists.encode(ListOrder(.artist(.name), descending: false)) == "Name:asc")
    }

    @Test func anythingElseSavedFallsBackToTheDefault() {
        let list = SortList.songs
        for saved in [nil, "", "Title", "Title:up", "Title:asc:x", "Nope:asc", "title:asc", "DateLiked:desc", "FolderOrder:asc"] {
            #expect(list.decode(saved) == list.defaultOrder, "'\(saved ?? "nil")'")
        }
    }

    @Test func pickingAnOptionRunsItsUsualWay() {
        let byTitle = ListOrder(.song(.title), descending: true)
        #expect(byTitle.picking(.song(.recentlyAdded)) == ListOrder(.song(.recentlyAdded), descending: true))
        #expect(byTitle.picking(.song(.artist)) == ListOrder(.song(.artist), descending: false))
        #expect(byTitle.picking(.song(.title)) == byTitle)
    }

    @Test func onlyNameOrdersFileUnderLetters() {
        #expect(Set(SongSort.allCases.filter(\.byName)) == [.title, .artist, .album])
        #expect(ArtistSort.name.byName)
        #expect(!AlbumSort.year.byName)
        #expect(AlbumSort.mostPlayed.byListening && ArtistSort.recentlyPlayed.byListening)
    }

    @Test func optionIdsAreUniqueWithinEachList() {
        for list in SortList.allCases { #expect(Set(list.options.map(\.id)).count == list.options.count) }
    }

    @Test func backupsKeepOnlyOrdersThatReadBack() {
        let saved = ["songs": "Year:desc", "albums": "Nope:asc", "liked": "Title:asc", "other": "Title:asc", "artists": "Name:up"]
        let kept = restorableOrders(saved)
        #expect(kept == [.songs: ListOrder(.song(.year), descending: true), .liked: ListOrder(.song(.title), descending: false)])
    }
}

@Suite struct SortDirectionsTests {
    private func labels(_ option: SortOption) -> [String] { directionChoices(option).map(\.label) }

    @Test func namesRunAToZFirst() {
        for option: SortOption in [.song(.title), .album(.artist), .artist(.name), .playlist(.name), .download(.title), .favorite(.name)] {
            #expect(labels(option) == ["A to Z", "Z to A"])
        }
    }

    @Test func datesRunNewestFirst() {
        for option: SortOption in [.song(.recentlyAdded), .song(.year), .song(.dateLiked), .playlist(.recentlyChanged),
                                   .download(.recentlyDownloaded), .favorite(.dateAdded)] {
            #expect(labels(option) == ["Newest", "Oldest"])
        }
    }

    @Test func countsAndPlaysRunMostFirst() {
        for option: SortOption in [.song(.mostPlayed), .album(.songCount), .artist(.albumCount), .playlist(.songCount)] {
            #expect(labels(option) == ["Most", "Least"])
        }
    }

    @Test func theRestSayWhatTheyMean() {
        #expect(labels(.song(.length)) == ["Longest", "Shortest"])
        #expect(labels(.album(.length)) == ["Longest", "Shortest"])
        #expect(labels(.song(.rating)) == ["Highest", "Lowest"])
        #expect(labels(.download(.size)) == ["Largest", "Smallest"])
        #expect(labels(.song(.liked)) == ["Liked first", "Liked last"])
        #expect(labels(.song(.folderOrder)) == ["In order", "Reversed"])
    }

    @Test func eachLabelMatchesItsDirection() {
        #expect(directionChoices(.song(.recentlyAdded)).map(\.descending) == [true, false])
        #expect(directionChoices(.song(.title)).map(\.descending) == [false, true])
        #expect(SortScale.date.label(descending: true) == "Newest")
        #expect(SortScale.name.label(descending: false) == "A to Z")
    }

    @Test func theFallbackIsThePlainWords() {
        #expect(SortScale.plain.label(descending: false) == "Ascending")
        #expect(SortScale.plain.label(descending: true) == "Descending")
    }

    @Test func everyListOffersTwoDifferentDirectionsForEveryOption() {
        for option in SortList.allCases.flatMap(\.options) {
            let choices = directionChoices(option)
            #expect(choices.count == 2)
            #expect(choices[0].descending == option.startsDescending)
            #expect(choices[0].descending != choices[1].descending)
            #expect(choices[0].label != choices[1].label)
        }
    }
}

@Suite struct ListeningTests {
    private let base = ["a", "b", "c", "d", "e"]
    private let heard = [
        "b": Listening(plays: 3, lastPlayedAt: 100),
        "d": Listening(plays: 7, lastPlayedAt: 50),
        "e": Listening(plays: 3, lastPlayedAt: 300),
    ]

    private func order(mostPlayed: Bool, descending: Bool) -> [String] {
        byListening(base, id: { $0 }, listening: heard, mostPlayed: mostPlayed, descending: descending)
    }

    @Test func mostPlayedFirstThenTheRestByName() {
        #expect(order(mostPlayed: true, descending: true) == ["d", "e", "b", "a", "c"])
    }

    @Test func leastPlayedFirstPutsTheUnplayedOnTop() {
        #expect(order(mostPlayed: true, descending: false) == ["a", "c", "b", "e", "d"])
    }

    @Test func recentlyPlayedGoesByTheLastPlay() {
        #expect(order(mostPlayed: false, descending: true) == ["e", "b", "d", "a", "c"])
        #expect(order(mostPlayed: false, descending: false) == ["a", "c", "d", "b", "e"])
    }

    @Test func fullTiesKeepTheBaseOrder() {
        let same = Listening(plays: 2, lastPlayedAt: 10)
        let listening = ["c": same, "a": same, "e": same]
        #expect(byListening(base, id: { $0 }, listening: listening, mostPlayed: true, descending: true) == ["a", "c", "e", "b", "d"])
        #expect(byListening(base, id: { $0 }, listening: listening, mostPlayed: true, descending: false) == ["b", "d", "a", "c", "e"])
    }

    @Test func anAlbumSeenOnlyOnTheServerCountsForRecentButNotForMost() {
        let listening = ["b": Listening(plays: 0, lastPlayedAt: 500)]
        #expect(byListening(base, id: { $0 }, listening: listening, mostPlayed: false, descending: true) == ["b", "a", "c", "d", "e"])
        #expect(byListening(base, id: { $0 }, listening: listening, mostPlayed: true, descending: true) == base)
    }
}

@Suite struct FavoriteSortTests {
    private struct Fav { let id: String; let name: String; let likedAt: Int64 }

    private let favs = [Fav(id: "1", name: "beta", likedAt: 300), Fav(id: "2", name: "alpha", likedAt: 100),
                        Fav(id: "3", name: "gamma", likedAt: 200), Fav(id: "4", name: "alpha", likedAt: 200)]

    private func sorted(_ order: ListOrder) -> [String] {
        sortFavorites(favs, order: order, likedAt: \.likedAt, name: \.name, id: \.id).map(\.id)
    }

    @Test func startsWithTheNewestFavorite() {
        #expect(SortList.favorites.defaultOrder == ListOrder(.favorite(.dateAdded), descending: true))
        #expect(sorted(SortList.favorites.defaultOrder) == ["1", "4", "3", "2"])
        #expect(sorted(ListOrder(.favorite(.dateAdded), descending: false)) == ["2", "4", "3", "1"])
    }

    @Test func byNameRunsAToZThenBack() {
        #expect(sorted(ListOrder(.favorite(.name), descending: false)) == ["2", "4", "1", "3"])
        #expect(sorted(ListOrder(.favorite(.name), descending: true)) == ["3", "1", "2", "4"])
    }

    @Test func theFavoritesPageOffersBoth() {
        #expect(SortList.favorites.options.map(\.label) == ["Date added", "Name"])
        #expect(SortList.favorites.key == "favourites")
    }
}

@Suite struct LettersTests {
    @Test func runsFollowTheListInOrder() {
        #expect(letterRuns(["50 cent", "abba", "adele", "beyonce"]) == [LetterRun("#", 0, 1), LetterRun("A", 1, 2), LetterRun("B", 3, 1)])
    }

    @Test func aLetterThatComesBackGetsAnotherRun() {
        #expect(letterRuns(["1999", "zz top", "ωmega"]) == [LetterRun("#", 0, 1), LetterRun("Z", 1, 1), LetterRun("#", 2, 1)])
    }

    @Test func descendingNamesRunBackwards() {
        #expect(letterRuns(["cat", "bee", "ant", "ape"]).map(\.letter) == ["C", "B", "A"])
    }

    @Test func nothingGivesNoRuns() {
        #expect(letterRuns([]).isEmpty)
    }

    @Test func railStopsCountTheHeadingRows() {
        let runs = letterRuns(["1999", "abba", "adele", "beyonce", "ωmega"])
        #expect(railStops(runs, headed: true) == [RailStop("#", 0), RailStop("A", 2), RailStop("B", 5)])
        #expect(railStops(runs, headed: false, before: 1) == [RailStop("#", 1), RailStop("A", 2), RailStop("B", 4)])
    }
}
