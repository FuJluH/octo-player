import Foundation
import Testing
@testable import OctoKit

private let now = queryTestNow
private let utc = TimeZone(identifier: "UTC") ?? TimeZone(secondsFromGMT: 0) ?? .current

private let songs = [
    QueryTestSong("1", "Karma Police", album: "OK Computer", albumId: "a1", artist: "Radiohead", year: 1997, duration: 264,
                  suffix: "flac", bitRate: 900, genre: "Alternative", created: queryTestDaysAgo(3), played: queryTestDaysAgo(1),
                  playCount: 12, userRating: 5, starred: queryTestDaysAgo(2), bpm: 75, track: 6),
    QueryTestSong("2", "Beyoncé Interlude", album: "Lemonade", albumId: "a2", artist: "Beyoncé", year: 2016, duration: 95,
                  suffix: "mp3", bitRate: 320, genres: ["R&B", "Pop"], created: queryTestDaysAgo(20), playCount: 0),
    QueryTestSong("3", "Windowlicker", album: "Windowlicker", albumId: "a3", artist: "Aphex Twin", year: 1999, duration: 367,
                  suffix: "m4a", bitDepth: 16, genre: "Electronic", created: queryTestDaysAgo(400), played: queryTestDaysAgo(300),
                  playCount: 2, userRating: 3, displayComposer: "Richard D. James", albumArtists: ["Aphex Twin"]),
    QueryTestSong("4", "Teardrop", album: "Mezzanine", albumId: "a4", artist: "Massive Attack", duration: 330, suffix: "m4a",
                  genre: "electronic", created: queryTestDaysAgo(100), played: queryTestDaysAgo(10), playCount: 7, userRating: 4),
]

private func ids(_ query: LibraryQuery) -> [String] { query.select(songs, now: now, fields: QueryTestFields()).map(\.id) }

private func rule(_ rule: QueryRule) -> [String] { ids(LibraryQuery([rule])) }

private func label(_ rule: QueryRule) -> String { rule.label(zone: utc) }

@Suite struct LibraryQueryTests {
    @Test func anEmptyQueryKeepsEverySongInItsOrder() {
        #expect(ids(LibraryQuery()) == ["1", "2", "3", "4"])
        #expect(!LibraryQuery().filters)
    }

    @Test func typedWordsIgnoreCaseAndAccentsAndMustAllAppear() {
        #expect(ids(LibraryQuery(text: "beyonce")) == ["2"])
        #expect(ids(LibraryQuery(text: "BEYONCÉ lemon")) == ["2"])
        // Genre and album artist count too.
        #expect(ids(LibraryQuery(text: "electronic")) == ["3", "4"])
        #expect(ids(LibraryQuery(text: "pop")) == ["2"])
        #expect(ids(LibraryQuery(text: "  radiohead   karma ")) == ["1"])
        #expect(ids(LibraryQuery(text: "radiohead windowlicker")) == [])
        #expect(LibraryQuery(text: "x").filters)
        #expect(!LibraryQuery(text: "   ").filters)
    }

    @Test func wordsAreNotLookedForInTheComposer() {
        #expect(ids(LibraryQuery(text: "richard")) == [])
    }

    @Test func textRules() {
        #expect(rule(QueryRule(.title, .contains, text: "POLICE")) == ["1"])
        #expect(rule(QueryRule(.title, .is, text: "windowlicker")) == ["3"])
        #expect(rule(QueryRule(.title, .isNot, text: "Windowlicker")) == ["1", "2", "4"])
        #expect(rule(QueryRule(.artist, .startsWith, text: "mass")) == ["4"])
        #expect(rule(QueryRule(.artist, .doesNotContain, text: "radio")) == ["2", "3", "4"])
        #expect(rule(QueryRule(.composer, .contains, text: "james")) == ["3"])
        #expect(rule(QueryRule(.albumArtist, .is, text: "aphex twin")) == ["3"])
        #expect(rule(QueryRule(.format, .is, text: "FLAC")) == ["1"])
    }

    @Test func onlyALibraryFileThatLosesDetailCanBeUpgraded() {
        let flac = Song(id: "1", title: "Karma Police", suffix: "flac")
        let mp3 = Song(id: "2", title: "Beyoncé Interlude", suffix: "mp3")
        var alac = Song(id: "3", title: "Windowlicker", suffix: "m4a")
        alac.bitDepth = 16
        let aac = Song(id: "4", title: "Teardrop", suffix: "m4a")
        #expect(!isUpgradable(flac))
        #expect(isUpgradable(mp3))
        // An m4a with a bit depth is Apple Lossless; without one it is AAC.
        #expect(!isUpgradable(alac))
        #expect(isUpgradable(aac))
        // A song the server only found online is not a library file.
        var external = mp3
        external.isExternal = true
        #expect(!isUpgradable(external))
        // Nor is one whose kind is unknown: it may be lossless already.
        var unknown = mp3
        unknown.suffix = nil
        #expect(!isUpgradable(unknown))
    }

    @Test func theServersSongsFilterByWhatTheyCarry() {
        var liked = Song(id: "1", title: "Karma Police", artist: "Radiohead", suffix: "flac")
        liked.starred = "2026-01-01T00:00:00Z"
        liked.genre = "Alternative"
        let plain = Song(id: "2", title: "Teardrop", artist: "Massive Attack", suffix: "mp3")
        let list = [liked, plain]
        #expect(LibraryQuery([FilterPresets.favorites]).apply(list, now: now).map(\.id) == ["1"])
        #expect(LibraryQuery([FilterPresets.lossless]).apply(list, now: now).map(\.id) == ["1"])
        #expect(LibraryQuery(text: "massive").apply(list, now: now).map(\.id) == ["2"])
        #expect(LibraryQuery([FilterPresets.genre("alternative")]).apply(list, now: now).map(\.id) == ["1"])
        // No dates come with them: nothing was added lately, and nothing was ever played.
        #expect(LibraryQuery([FilterPresets.addedThisYear]).apply(list, now: now).isEmpty)
        #expect(LibraryQuery([FilterPresets.neverPlayed]).apply(list, now: now).map(\.id) == ["1", "2"])
    }

    @Test func aGenreRuleLooksAtEveryGenreOfASong() {
        #expect(rule(FilterPresets.genre("Electronic")) == ["3", "4"])
        #expect(rule(FilterPresets.genre("pop")) == ["2"])
        #expect(rule(FilterPresets.genre("R&B")) == ["2"])
        // "Is not" holds only when no genre is it.
        #expect(rule(QueryRule(.genre, .isNot, text: "Pop")) == ["1", "3", "4"])
    }

    @Test func numberRules() {
        #expect(rule(QueryRule(.year, .is, number: 1997)) == ["1"])
        // No year: only "is not" holds.
        #expect(rule(QueryRule(.year, .isNot, number: 1997)) == ["2", "3", "4"])
        #expect(rule(QueryRule(.year, .atLeast, number: 1998)) == ["2", "3"])
        #expect(rule(QueryRule(.year, .atMost, number: 1998)) == ["1"])
        #expect(rule(FilterPresets.decade(1990)) == ["1", "3"])
        // A range written the wrong way round still means the same years.
        #expect(rule(QueryRule(.year, .between, number: 1999, to: 1990)) == ["1", "3"])
        #expect(rule(FilterPresets.ratingAtLeast(4)) == ["1", "4"])
        #expect(rule(QueryRule(.plays, .is, number: 0)) == ["2"])
        #expect(rule(QueryRule(.plays, .atLeast, number: 5)) == ["1", "4"])
        #expect(rule(QueryRule(.duration, .atLeast, number: 300)) == ["3", "4"])
        #expect(rule(QueryRule(.bitRate, .atMost, number: 320)) == ["2"])
        #expect(rule(QueryRule(.bpm, .between, number: 70, to: 80)) == ["1"])
    }

    @Test func dateRules() {
        #expect(rule(FilterPresets.addedThisWeek) == ["1"])
        #expect(rule(FilterPresets.addedThisMonth) == ["1", "2"])
        #expect(rule(FilterPresets.addedThisYear) == ["1", "2", "4"])
        #expect(rule(QueryRule(.added, .notInTheLast, days: 365)) == ["3"])
        #expect(rule(FilterPresets.neverPlayed) == ["2"])
        // Never played counts as not played lately.
        #expect(rule(FilterPresets.notPlayedLately) == ["2", "3"])
        #expect(rule(QueryRule(.lastPlayed, .inTheLast, days: 30)) == ["1", "4"])
        let cut = now - 50 * 86_400_000
        #expect(rule(QueryRule(.added, .before, at: cut)) == ["3", "4"])
        #expect(rule(QueryRule(.added, .after, at: cut)) == ["1", "2"])
        #expect(rule(QueryRule(.lastPlayed, .before, at: cut)) == ["3"])
    }

    @Test func flagRules() {
        #expect(rule(FilterPresets.favorites) == ["1"])
        #expect(rule(QueryRule(.favorite, .is, flag: false)) == ["2", "3", "4"])
        // An m4a with a bit depth is Apple Lossless; without one, AAC.
        #expect(rule(FilterPresets.lossless) == ["1", "3"])
        #expect(rule(QueryRule(.lossless, .is, flag: false)) == ["2", "4"])
    }

    @Test func allOrAnyAndTheWordsTogether() {
        let rules = [FilterPresets.ratingAtLeast(4), FilterPresets.genre("Electronic")]
        #expect(ids(LibraryQuery(rules)) == ["4"])
        #expect(ids(LibraryQuery(rules, match: .any)) == ["1", "3", "4"])
        #expect(ids(LibraryQuery(rules, match: .any, text: "aphex")) == ["3"])
    }

    @Test func aRuleThatCannotBeTestedIsLeftOut() {
        let broken = [
            QueryRule(.title, .contains),
            QueryRule(.year, .inTheLast, days: 3),
            QueryRule(.added, .is, number: 3),
            QueryRule(.year, .between, number: 1990),
        ]
        for rule in broken { #expect(!rule.complete, "\(rule)") }
        #expect(ids(LibraryQuery(broken)) == ["1", "2", "3", "4"])
        #expect(ids(LibraryQuery(broken, match: .any)) == ["1", "2", "3", "4"])
        #expect(ids(LibraryQuery(broken + [FilterPresets.favorites], match: .any)) == ["1"])
    }

    @Test func anOrderAndALimit() {
        let longest = LibraryQuery(sort: QuerySort(.length, descending: true), limit: 2)
        #expect(ids(longest) == ["3", "4"])
        let mostPlayed = LibraryQuery([FilterPresets.addedThisYear], sort: QuerySort(.mostPlayed, descending: true))
        #expect(ids(mostPlayed) == ["1", "4", "2"])
        #expect(ids(LibraryQuery(sort: QuerySort(by: "NoSuchOrder"))) == ["1", "2", "3", "4"])
        #expect(ids(LibraryQuery(limit: 0)) == [])
    }

    @Test func aQueryCanPickPlacesInAList() {
        // A playlist with a song twice: both places pass or fail together.
        let playlist = [songs[3], songs[0], songs[2], songs[0]]
        let fields = QueryTestFields()
        #expect(LibraryQuery([FilterPresets.favorites]).places(playlist, now: now, fields: fields) == [1, 3])
        #expect(LibraryQuery(text: "electronic").places(playlist, now: now, fields: fields) == [0, 2])
        let byTitle = LibraryQuery(sort: QuerySort(.title, descending: false))
        #expect(byTitle.places(playlist, now: now, fields: fields) == [1, 3, 0, 2])
    }

    @Test func aFilterBarKeepsOneRuleAField() {
        let query = LibraryQuery()
            .setting(FilterPresets.addedThisWeek)
            .setting(FilterPresets.favorites)
            .setting(FilterPresets.addedThisYear)
        #expect(query.rules == [FilterPresets.favorites, FilterPresets.addedThisYear])
        #expect(query.without(FilterPresets.favorites).rules == [FilterPresets.addedThisYear])
        let cleared = query.withText("x").limited(to: 5).cleared()
        #expect(!cleared.filters)
        #expect(cleared.limit == 5)
    }

    @Test func theSavedShapeIsStableAndCompact() {
        let query = LibraryQuery(
            [FilterPresets.addedThisMonth, FilterPresets.genre("Electronic"), FilterPresets.favorites, FilterPresets.decade(1990)],
            match: .any,
            text: "night",
            sort: QuerySort(.recentlyAdded, descending: true),
            limit: 50
        )
        let json = query.toJSON()
        #expect(json == #"{"rules":[{"field":"added","op":"inTheLast","days":30},{"field":"genre","op":"is","text":"Electronic"},"#
            + #"{"field":"favourite","op":"is","flag":true},{"field":"year","op":"between","number":1990,"to":1999}],"#
            + #""match":"any","text":"night","sort":{"by":"RecentlyAdded","descending":true},"limit":50}"#)
        #expect(LibraryQuery.fromJSON(json) == query)
        #expect(LibraryQuery().toJSON() == "{}")
        #expect(LibraryQuery.fromJSON("{}") == LibraryQuery())
    }

    @Test func savedWordsKeepTheirQuotesAndLineBreaks() {
        let query = LibraryQuery([QueryRule(.title, .contains, text: "say \"hi\"\\\n")], text: "tab\there")
        #expect(query.toJSON() == #"{"rules":[{"field":"title","op":"contains","text":"say \"hi\"\\\n"}],"text":"tab\there"}"#)
        #expect(LibraryQuery.fromJSON(query.toJSON()) == query)
    }

    @Test func aSavedQueryFromALaterVersionStillReads() {
        let later = #"{"v":3,"rules":[{"field":"mood","op":"is","text":"calm"},{"field":"added","op":"inTheLast","days":7,"unit":"d"},"#
            + #"{"field":"title","op":"soundsLike","text":"x"}],"match":"most","text":"a","extra":{"x":1}}"#
        #expect(LibraryQuery.fromJSON(later) == LibraryQuery([FilterPresets.addedThisWeek], match: .all, text: "a"))
        #expect(LibraryQuery.fromJSON("not json") == nil)
        #expect(LibraryQuery.fromJSON("[1,2]") == nil)
    }

    @Test func rulesInPlainWords() {
        #expect(label(FilterPresets.addedThisWeek) == "Added in the last week")
        #expect(label(FilterPresets.addedThisMonth) == "Added in the last month")
        #expect(label(FilterPresets.addedThisYear) == "Added in the last year")
        #expect(label(QueryRule(.added, .inTheLast, days: 45)) == "Added in the last 45 days")
        #expect(label(FilterPresets.notPlayedLately) == "Not played in the last 6 months")
        #expect(label(FilterPresets.neverPlayed) == "Never played")
        #expect(label(FilterPresets.favorites) == "Favorites")
        #expect(label(QueryRule(.favorite, .is, flag: false)) == "Not favorites")
        #expect(label(FilterPresets.lossless) == "Lossless")
        #expect(label(QueryRule(.lossless, .is, flag: false)) == "Lossy")
        #expect(label(FilterPresets.ratingAtLeast(4)) == "Rating at least 4")
        #expect(label(FilterPresets.genre("Electronic")) == "Genre is Electronic")
        #expect(label(FilterPresets.decade(1990)) == "From the 1990s")
        #expect(label(QueryRule(.year, .between, number: 2003, to: 1995)) == "Year between 1995 and 2003")
        #expect(label(QueryRule(.title, .doesNotContain, text: "live")) == "Title does not contain live")
        #expect(label(QueryRule(.format, .is, text: "flac")) == "Format is FLAC")
        #expect(label(QueryRule(.duration, .atLeast, number: 300)) == "5:00 or longer")
        #expect(label(FilterPresets.shorterThan(180)) == "3:00 or shorter")
        #expect(label(FilterPresets.playedAtLeast(10)) == "Played 10 times or more")
        #expect(label(FilterPresets.playedAtLeast(1)) == "Played at least once")
        #expect(label(FilterPresets.playedInTheLast(30)) == "Played in the last month")
        #expect(label(FilterPresets.artist("Radiohead")) == "Artist is Radiohead")
        #expect(label(QueryRule(.bitRate, .atMost, number: 320)) == "Bit rate at most 320 kbps")
        #expect(label(QueryRule(.plays, .isNot, number: 0)) == "Plays is not 0")
        let day = epochMs("2024-01-05T00:00:00Z") ?? 0
        #expect(label(QueryRule(.added, .before, at: day)) == "Added before 5 Jan 2024")
        #expect(label(QueryRule(.lastPlayed, .after, at: day)) == "Last played since 5 Jan 2024")
        // One that cannot be tested just names its field.
        #expect(label(QueryRule(.title, .contains)) == "Title")
    }

    @Test func aDayIsToldInTheZoneGiven() {
        let lateEvening = epochMs("2024-01-05T23:30:00Z") ?? 0
        let tokyo = TimeZone(identifier: "Asia/Tokyo") ?? utc
        #expect(QueryRule(.added, .before, at: lateEvening).label(zone: tokyo) == "Added before 6 Jan 2024")
        #expect(label(QueryRule(.duration, .atMost, number: 3_723)) == "1:02:03 or shorter")
    }

    @Test func ratingChoicesInWords() {
        #expect((1...5).reversed().map(FilterPresets.ratingWords)
            == ["5 stars", "4 stars or more", "3 stars or more", "2 stars or more", "1 star or more"])
    }

    @Test func spansInWords() {
        #expect([1, 7, 14, 30, 180, 365, 730, 10].map(QueryRule.spanWords)
            == ["day", "week", "2 weeks", "month", "6 months", "year", "2 years", "10 days"])
    }

    @Test func theGenresAndDecadesAListOffers() {
        #expect(genresIn(songs, fields: QueryTestFields()) == ["Alternative", "Electronic", "Pop", "R&B"])
        #expect(decadesIn(songs, fields: QueryTestFields()) == [1990, 2010])
        #expect(artistsIn(songs, fields: QueryTestFields()) == ["Aphex Twin", "Beyoncé", "Massive Attack", "Radiohead"])
    }

    @Test func foldingMatchesTheSearchKey() {
        let names = ["Beyoncé", "  Sigur Rós ", "Mötley Crüe", "ÆSIR", "Ångström", "坂本龍一", "Straße", "Ǆ", "Plain Words", "Zoë́", "ﬁre",
                     "𝄞 clef", "\tTabbed\n"]
        for name in names { #expect(foldText(name) == searchKey(name), "\(name)") }
    }

    @Test func theQuickTimeReadsWhatServerTimeReads() {
        let times: [String?] = [
            "2026-09-28T10:00:00Z", "2026-09-28T10:00:00.5Z", "2026-09-28T10:00:00.123Z", "2026-09-28T10:00:00.123456789Z",
            "1999-12-31T23:59:59Z", "2024-02-29T00:00:00Z", "2026-09-28T10:00:00+02:00", "2026-09-28T10:00:00.250-05:30",
            "2026-02-30T10:00:00Z", "2026-13-01T10:00:00Z", "not a time at all ok", "2026-09-28", "", nil,
        ]
        for time in times { #expect(quickTime(time) == epochMs(time), "\(time ?? "nil")") }
        #expect(quickTime("2026-09-28T10:00:00Z") == epochMs("2026-09-28T10:00:00Z"))
        #expect(quickTime("2026-09-28T10:00:00Z") != nil)
    }

    @Test func everyOpIsOfferedForTheKindsItSuits() {
        for field in QueryField.allCases {
            for op in QueryOp.forKind(field.kind) { #expect(QueryOp.allCases.contains(op), "\(field) \(op)") }
        }
        #expect(QueryOp.forKind(.flag) == [.is])
    }

    @Test func theOrdersSayHowTheyRunAndWhatTheyAreCalled() {
        #expect(QuerySort.By.allCases.map(\.rawValue) == ["Title", "Artist", "Album", "RecentlyAdded", "Year", "Length", "MostPlayed",
                                                          "RecentlyPlayed", "Rating", "Liked", "DateLiked", "FolderOrder"])
        #expect(LibraryQuery().sorted(by: .mostPlayed).sort == QuerySort(.mostPlayed, descending: true))
        #expect(LibraryQuery().sorted(by: .title).sort == QuerySort(.title, descending: false))
        #expect(QuerySort.By.recentlyAdded.label == "Recently added")
    }
}
