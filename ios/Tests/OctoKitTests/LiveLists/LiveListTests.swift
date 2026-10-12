import Foundation
import Testing
@testable import OctoKit

private let now = queryTestNow
private let utc = TimeZone(identifier: "UTC") ?? TimeZone(secondsFromGMT: 0) ?? .current

private let library = [
    QueryTestSong("1", "Karma Police", artist: "Radiohead", duration: 264, suffix: "flac", genre: "Alternative",
                  created: queryTestDaysAgo(3), played: queryTestDaysAgo(1), playCount: 12, starred: queryTestDaysAgo(2)),
    QueryTestSong("2", "Interlude", artist: "Beyoncé", duration: 95, suffix: "mp3", genre: "Pop", created: queryTestDaysAgo(20),
                  playCount: 0),
    QueryTestSong("3", "Windowlicker", artist: "Aphex Twin", duration: 367, suffix: "flac", genre: "Electronic",
                  created: queryTestDaysAgo(400), played: queryTestDaysAgo(500), playCount: 2, starred: queryTestDaysAgo(90)),
    QueryTestSong("4", "Teardrop", artist: "Massive Attack", duration: 330, suffix: "m4a", genre: "Electronic",
                  created: queryTestDaysAgo(100), played: queryTestDaysAgo(10), playCount: 7),
]

private func ids(_ list: LiveList) -> [String] { list.songs(of: library, now: now, fields: QueryTestFields()).map(\.id) }

private let lossless = LiveList(
    id: "a", name: "Lossless favorites",
    query: LibraryQuery([FilterPresets.favorites, FilterPresets.lossless], sort: QuerySort(by: "Title"), limit: 10),
    created: 5, changed: 9
)

@Suite struct LiveListTests {
    @Test func listsRoundTripThroughTheirJSON() {
        let lists = [lossless, LiveList(id: "b", name: "Everything", query: LibraryQuery())]
        #expect(decodeLiveLists(encodeLiveLists(lists)) == lists)
        #expect(decodeLiveLists(encodeLiveLists([])) == [])
    }

    @Test func theStoredShapeIsTheSharedOne() {
        let list = LiveList(id: "a", name: "Hearts", query: LibraryQuery([FilterPresets.favorites]), created: 5, changed: 9)
        #expect(encodeLiveLists([list, LiveList(id: "b", name: "All")])
            == #"{"version":1,"lists":[{"id":"a","name":"Hearts","query":{"rules":[{"field":"favourite","op":"is","flag":true}]},"#
            + #""created":5,"changed":9},{"id":"b","name":"All","query":{}}]}"#)
    }

    @Test func aDamagedOrUnknownFileLosesOnlyWhatItCannotRead() {
        #expect(decodeLiveLists(nil) == [])
        #expect(decodeLiveLists("not json") == [])
        #expect(decodeLiveLists("[]") == [])
        #expect(decodeLiveLists("   ") == [])
        let text = """
            {"version":7,"future":true,"lists":[
              {"id":"x","name":"Kept","query":{"rules":[{"field":"mood","op":"is","text":"calm"},{"field":"favourite","op":"is","flag":true}]}},
              {"name":"No id"},
              "a string",
              {"id":"y","name":"No query"},
              {"id":"x","name":"Same id again"}
            ]}
            """
        let read = decodeLiveLists(text)
        #expect(read.map(\.name) == ["Kept", "No query"])
        // The unknown field's rule is dropped, the other kept.
        #expect(read.first?.query.rules == [FilterPresets.favorites])
        #expect(read.last?.query == LibraryQuery())
    }

    @Test func aListPicksFromTheWholeLibraryInItsOrderAtMostItsLimit() {
        #expect(ids(lossless) == ["1", "3"])
        let recent = LiveList(id: "r", name: "Recent", query: LibraryQuery([FilterPresets.addedThisYear], sort: defaultLiveListSort, limit: 2))
        #expect(ids(recent) == ["1", "2"])
        let anyOf = LiveList(id: "g", name: "Pop or Electronic",
                             query: LibraryQuery([FilterPresets.genre("Pop"), FilterPresets.genre("electronic")], match: .any))
        #expect(ids(anyOf) == ["2", "3", "4"])
        // With no order the library's own is kept.
        #expect(ids(LiveList(id: "e", name: "All", query: LibraryQuery())) == ["1", "2", "3", "4"])
    }

    @Test func theStartersPickWhatTheySay() {
        let byName = Dictionary(uniqueKeysWithValues: liveListStarters.map {
            ($0.name, LiveList.new(name: $0.name, query: $0.query, now: now, id: $0.name))
        })
        #expect(byName["Recently added"].map(ids) == ["1", "2"])
        // Played before but not in a year: never played is left out.
        #expect(byName["Not played in a year"].map(ids) == ["3"])
        #expect(byName["Most played this month"].map(ids) == ["1", "4"])
        #expect(byName["Lossless favorites"].map(ids) == ["3", "1"])
        #expect(Set(liveListStarters.map(\.name)).count == 4)
    }

    @Test func savingRemovingAndDuplicating() {
        let b = LiveList(id: "b", name: "B")
        let c = LiveList(id: "c", name: "C")
        let lists = [lossless, b].saving(c)
        #expect(lists.map(\.id) == ["a", "b", "c"])
        var renamed = b
        renamed.name = "Bee"
        #expect(lists.saving(renamed).map(\.name) == ["Lossless favorites", "Bee", "C"])
        #expect(lists.removing("b").map(\.id) == ["a", "c"])
        let (copied, copy) = lists.duplicating(lossless, now: now, id: "d")
        #expect(copied.map(\.id) == ["a", "d", "b", "c"])
        #expect(copy.name == "Lossless favorites (copy)")
        #expect(copy.query == lossless.query)
        #expect(copy.created == now)
    }

    @Test func aNewListGetsAnIdAndATrimmedName() {
        let made = LiveList.new(name: "  Hearts ", query: LibraryQuery(), now: 7)
        #expect(made.name == "Hearts")
        #expect(made.created == 7 && made.changed == 7)
        #expect(!made.id.isEmpty)
        #expect(made.id != LiveList.new(name: "Hearts", query: LibraryQuery(), now: 7).id)
    }

    @Test func theSummarySaysWhatItMatchesInPlainWords() {
        let month = LibraryQuery([FilterPresets.addedThisMonth, FilterPresets.lossless])
        #expect(liveListSummary(month, count: 42, zone: utc) == "Added in the last month, lossless, 42 songs")
        #expect(liveListSummary(LibraryQuery([FilterPresets.genre("Pop"), FilterPresets.genre("Rock")], match: .any), count: 1, zone: utc)
            == "Genre is Pop or genre is Rock, 1 song")
        #expect(liveListSummary(LibraryQuery(sort: defaultLiveListSort), count: 1_204, zone: utc) == "Every song, newest first, 1,204 songs")
        let top = LibraryQuery([FilterPresets.playedInTheLast(30)], sort: QuerySort(.mostPlayed, descending: true), limit: 50)
        #expect(liveListSummary(top, count: 50, zone: utc) == "Played in the last month, most played first, the top 50 songs")
        #expect(liveListSummary(top, count: 12, zone: utc) == "Played in the last month, most played first, 12 songs")
        // Without a count, as in a list of lists.
        #expect(liveListSummary(top, count: nil, zone: utc) == "Played in the last month, most played first, the top 50")
        #expect(liveListSummary(month, count: nil, zone: utc) == "Added in the last month, lossless")
        #expect(liveListSummary(LibraryQuery(text: " live "), count: 3, zone: utc) == "With \u{201C}live\u{201D}, 3 songs")
        // Capitals inside a word stay.
        let bpm = QueryRule(.bpm, .atLeast, number: 120)
        #expect(liveListSummary(LibraryQuery([FilterPresets.favorites, bpm]), count: 0, zone: utc) == "Favorites, BPM at least 120, 0 songs")
        #expect(matchWords(1) == "1 song matches right now")
        #expect(matchWords(1_204) == "1,204 songs match right now")
        #expect(matchWords(1_234_567) == "1,234,567 songs match right now")
        // No dashes of any kind in what the apps show.
        #expect(!liveListSummary(top, count: 1, zone: utc).contains("\u{2014}"))
    }

    @Test func eachOrderReadsInWords() {
        #expect(sortWords(defaultLiveListSort) == "newest first")
        #expect(sortWords(QuerySort(.title, descending: true)) == "by title, Z to A")
        #expect(sortWords(QuerySort(.recentlyPlayed, descending: false)) == "longest unplayed first")
        #expect(sortWords(QuerySort(by: "NoSuchOrder")) == nil)
        #expect(liveListSorts.allSatisfy { sortWords(QuerySort($0, descending: true)) != nil })
        #expect(limitWords(nil) == "All songs")
        #expect(limitWords(25) == "The first 25")
    }

    @Test func aNameIsSuggestedFromTheRules() {
        #expect(liveListName(LibraryQuery([FilterPresets.addedThisMonth]), zone: utc) == "Added in the last month")
        #expect(liveListName(LibraryQuery([FilterPresets.favorites, FilterPresets.lossless, FilterPresets.neverPlayed]), zone: utc)
            == "Favorites, lossless")
        #expect(liveListName(LibraryQuery(text: "remix"), zone: utc) == "Remix")
        #expect(liveListName(LibraryQuery(), zone: utc) == "New live list")
    }

    @Test func aDraftSavesUnderItsNameOrOneFromItsRules() {
        let list = LiveList(id: "h", name: "Favorites", query: LibraryQuery([FilterPresets.favorites]))
        #expect(!LiveListDraft(of: list).changes(list))
        #expect(LiveListDraft(name: " ", query: list.query).savedName == "Favorites")
        #expect(!LiveListDraft(name: " ", query: list.query).changes(list))
        #expect(LiveListDraft(name: "Hearts", query: list.query).changes(list))
        #expect(LiveListDraft(name: "Favorites", query: LibraryQuery()).changes(list))
    }

    @Test func theEditorTogglesRulesAndLetsSomeFieldsTakeMany() {
        var query = LibraryQuery()
        query = query.toggling(FilterPresets.addedThisWeek)
        query = query.toggling(FilterPresets.addedThisMonth)
        #expect(query.rules == [FilterPresets.addedThisMonth])
        query = query.toggling(FilterPresets.genre("Pop")).toggling(FilterPresets.genre("Rock"))
        #expect(query.rules == [FilterPresets.addedThisMonth, FilterPresets.genre("Pop"), FilterPresets.genre("Rock")])
        query = query.toggling(FilterPresets.genre("Pop"))
        #expect(query.rules == [FilterPresets.addedThisMonth, FilterPresets.genre("Rock")])
        #expect(query.asksMatch())
        #expect(!LibraryQuery([FilterPresets.lossless]).asksMatch())
        // Every choice the menu offers is a rule that can be tested.
        let choices = liveListRuleGroups.flatMap(\.choices)
        #expect(choices.allSatisfy { $0.rule.complete })
    }

    @Test func aPagesFiltersBecomeAListOverTheWholeLibrary() {
        let filters = LibraryQuery([FilterPresets.neverPlayed], text: " remix ")
        let genre = liveListQueryFrom([FilterPresets.genre("Pop")], filters: filters, order: QuerySort(.title, descending: false))
        #expect(genre.rules == [FilterPresets.genre("Pop"), FilterPresets.neverPlayed])
        #expect(genre.text == "remix")
        #expect(genre.sort == QuerySort(by: "Title", descending: false))
        // No order given: newest first.
        #expect(liveListQueryFrom([], filters: filters, order: nil).sort == defaultLiveListSort)
        // The page's own rule is not added twice.
        #expect(liveListQueryFrom([FilterPresets.favorites], filters: LibraryQuery([FilterPresets.favorites]), order: nil).rules
            == [FilterPresets.favorites])
    }

    @Test func theAccountKeyIsStable() {
        #expect(liveListAccountKey(username: "listener", address: "https://music.example")
            == liveListAccountKey(username: "listener", address: "https://music.example"))
        #expect(liveListAccountKey(username: "a", address: "b").count == 16)
        #expect(liveListAccountKey(username: "a", address: "b") != liveListAccountKey(username: "a", address: "c"))
        // The first 8 bytes of SHA-256 of "a@b".
        #expect(liveListAccountKey(username: "a", address: "b") == String(Hashes.sha256Hex(Array("a@b".utf8)).prefix(16)))
    }
}
