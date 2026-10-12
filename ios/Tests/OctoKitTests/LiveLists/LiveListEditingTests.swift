import Foundation
import Testing
@testable import OctoKit

private let favorites = LibraryQuery([FilterPresets.favorites])
private let saved = LiveList.new(name: "Hearts", query: favorites, now: 0, id: "h")

/// The editor's plain logic: where it starts, when it offers starters, its Add a rule menu, and
/// what it says.
@Suite struct LiveListEditingTests {
    @Test func theEditorStartsFromTheListThePagesFiltersOrNothing() {
        #expect(editorStart(saved, start: nil).name == "Hearts")
        #expect(editorStart(saved, start: nil).query == favorites)
        #expect(editorStart(nil, start: favorites).query == favorites)
        #expect(editorStart(nil, start: favorites).name == "")
        #expect(editorStart(nil, start: nil).query == LibraryQuery(sort: defaultLiveListSort))
        // The name it would get is the rules', until one is typed.
        #expect(editorStart(nil, start: favorites).savedName == "Favorites")
    }

    @Test func startersShowOnlyOnANewEmptyEditorWhileThereAreNone() {
        #expect(offersStarters([], id: nil, start: nil))
        #expect(!offersStarters([saved], id: nil, start: nil))
        #expect(!offersStarters([], id: "h", start: nil))
        #expect(!offersStarters([], id: nil, start: favorites))
        #expect(offersStarters([], id: nil, start: LibraryQuery(sort: defaultLiveListSort)))
    }

    @Test func addARuleListsTheGroupsThenTheAsksThenTheRules() {
        let menu = liveListRuleMenu()
        let words = menu.map(\.0)
        #expect(words == ["Added", "Played", "Times played", "Length", "Rating", "Genre", "Artist", "Year", "Favorites", "Lossless"])
        #expect(menu.last?.1 == .rule(FilterPresets.lossless))
        #expect(menu.first?.1 == .group(liveListRuleGroups[0]))
        #expect(words.count == liveListRuleGroups.count - 1 + 4 + 2)
        #expect(ratingRules.map(\.0) == ["5 stars", "4 stars or more", "3 stars or more", "2 stars or more", "1 star or more"])
        #expect(ratingRules.map(\.1) == [5, 4, 3, 2, 1].map(FilterPresets.ratingAtLeast))
    }

    @Test func theTickSitsOnTheRuleThatIsOn() {
        let added = liveListRuleGroups.first { $0.title == "Added" }?.choices.map(\.rule) ?? []
        #expect(pickedIn(added, query: LibraryQuery([FilterPresets.addedThisMonth])) == 1)
        #expect(pickedIn(added, query: favorites) == -1)
    }

    @Test func whatItSaysReadsPlainly() {
        #expect(liveCopyMessage("Hearts", count: 42) == "Saved a copy of Hearts as a playlist, 42 songs")
        #expect(liveCopyMessage("Hearts", count: 1) == "Saved a copy of Hearts as a playlist, 1 song")
        #expect(liveCopyMessage("Hearts", count: 1_500) == "Saved a copy of Hearts as a playlist, 1,500 songs")
        #expect(nothingToCopy("Hearts") == "\"Hearts\" has no songs right now, so there is nothing to copy.")
        let shown = [liveCopyMessage("Hearts", count: 2), nothingToCopy("Hearts"), limitWords(nil), limitWords(50), matchWords(3)]
            + liveListStarters.flatMap { [$0.name, $0.detail] }
            + liveListRuleGroups.flatMap { [$0.title] + $0.choices.map(\.words) }
        for words in shown { #expect(!words.contains("\u{2014}") && !words.contains("\u{2013}"), "\(words)") }
    }
}
