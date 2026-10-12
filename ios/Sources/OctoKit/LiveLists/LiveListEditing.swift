import Foundation

// The live list editor's plain logic, apart from the screen so it can be tested.

/// What the editor starts from: the saved list, a page's filters, or nothing picked yet, newest
/// first.
public func editorStart(_ existing: LiveList?, start: LibraryQuery?) -> LiveListDraft {
    if let existing { return LiveListDraft(of: existing) }
    if let start { return LiveListDraft(name: "", query: start) }
    return LiveListDraft(name: "", query: LibraryQuery(sort: defaultLiveListSort))
}

/// The starters show on a new, empty editor while the listener has no live lists at all.
public func offersStarters(_ lists: [LiveList], id: String?, start: LibraryQuery?) -> Bool {
    lists.isEmpty && id == nil && !(start?.filters ?? false)
}

/// Where a pick on the first page of Add a rule leads: a group of choices, a page that asks which
/// from the library, or a rule straight away.
public enum RulePick: Sendable, Hashable {
    case group(LiveListRuleGroup)
    case rating
    case genre
    case artist
    case year
    case rule(QueryRule)
}

/// The first page of Add a rule, as words and where each leads: the groups, then the pages that
/// ask from the library, then the rules that need nothing chosen.
public func liveListRuleMenu() -> [(String, RulePick)] {
    let other = liveListRuleGroups.first { $0.title == "Other" }?.choices ?? []
    return liveListRuleGroups.filter { $0.title != "Other" }.map { ($0.title, RulePick.group($0)) }
        + [("Rating", .rating), ("Genre", .genre), ("Artist", .artist), ("Year", .year)]
        + other.map { ($0.words, RulePick.rule($0.rule)) }
}

/// The ratings on offer, highest first.
public let ratingRules: [(String, QueryRule)] = (1...5).reversed().map { (FilterPresets.ratingWords($0), FilterPresets.ratingAtLeast($0)) }

/// Which of `rules` is on, for a choice list's tick, or -1.
public func pickedIn(_ rules: [QueryRule], query: LibraryQuery) -> Int {
    rules.firstIndex { query.rules.contains($0) } ?? -1
}

/// Said once a copy of a live list is made as a playlist.
public func liveCopyMessage(_ name: String, count: Int) -> String {
    "Saved a copy of \(name) as a playlist, \(count == 1 ? "1 song" : "\(LiveListDraft.grouped(count)) songs")"
}

public func nothingToCopy(_ name: String) -> String { "\"\(name)\" has no songs right now, so there is nothing to copy." }
