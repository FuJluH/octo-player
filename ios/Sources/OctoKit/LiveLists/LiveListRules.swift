import Foundation

extension QueryField {
    /// Fields a live list can hold several rules on at once, as in "Genre is Rock or Genre is
    /// Metal", or two decades.
    public var takesMany: Bool { self == .genre || self == .artist || self == .albumArtist || self == .composer || self == .year }
}

extension LibraryQuery {
    /// A rule picked in the live list editor: one already on comes off; one on a field that takes
    /// many joins the others; any other takes the place of the rule on its field, as "In the last
    /// month" replaces "In the last week".
    public func toggling(_ rule: QueryRule) -> LibraryQuery {
        if rules.contains(rule) { return without(rule) }
        if rule.field.takesMany {
            var next = self
            next.rules.append(rule)
            return next
        }
        return setting(rule)
    }

    /// Whether the editor should offer "all of these" or "any of these": only once there are two
    /// rules to join.
    public func asksMatch() -> Bool { rules.count >= 2 }
}

/// One choice in the editor's Add a rule menu: the words the menu shows and the rule it adds. The
/// rule's own label is what the list then shows.
public struct LiveListRuleChoice: Sendable, Hashable {
    public var words: String
    public var rule: QueryRule

    public init(_ words: String, _ rule: QueryRule) {
        self.words = words
        self.rule = rule
    }
}

/// A heading in the Add a rule menu and its choices.
public struct LiveListRuleGroup: Sendable, Hashable {
    public var title: String
    public var choices: [LiveListRuleChoice]

    public init(_ title: String, _ choices: [LiveListRuleChoice]) {
        self.title = title
        self.choices = choices
    }
}

/// The rules a live list offers without asking which, grouped as the menus show them. Genre,
/// artist, year and rating ask which from the library, as the filter bar does.
public let liveListRuleGroups: [LiveListRuleGroup] = [
    LiveListRuleGroup("Added", [
        LiveListRuleChoice("In the last week", FilterPresets.addedThisWeek),
        LiveListRuleChoice("In the last month", FilterPresets.addedThisMonth),
        LiveListRuleChoice("In the last year", FilterPresets.addedThisYear),
    ]),
    LiveListRuleGroup("Played", [
        LiveListRuleChoice("In the last week", FilterPresets.playedInTheLast(7)),
        LiveListRuleChoice("In the last month", FilterPresets.playedInTheLast(30)),
        LiveListRuleChoice("Never", FilterPresets.neverPlayed),
        LiveListRuleChoice("Not in the last 6 months", FilterPresets.notPlayedLately),
        LiveListRuleChoice("Not in the last year", FilterPresets.notPlayedInTheLast(365)),
    ]),
    LiveListRuleGroup("Times played", [
        LiveListRuleChoice("At least once", FilterPresets.playedAtLeast(1)),
        LiveListRuleChoice("5 times or more", FilterPresets.playedAtLeast(5)),
        LiveListRuleChoice("10 times or more", FilterPresets.playedAtLeast(10)),
        LiveListRuleChoice("25 times or more", FilterPresets.playedAtLeast(25)),
    ]),
    LiveListRuleGroup("Length", [
        LiveListRuleChoice("3 minutes or shorter", FilterPresets.shorterThan(180)),
        LiveListRuleChoice("6 minutes or longer", FilterPresets.longerThan(360)),
        LiveListRuleChoice("10 minutes or longer", FilterPresets.longerThan(600)),
    ]),
    LiveListRuleGroup("Other", [
        LiveListRuleChoice("Favorites", FilterPresets.favorites),
        LiveListRuleChoice("Lossless", FilterPresets.lossless),
    ]),
]

/// How many songs a live list can be kept to: all, or the first of these.
public let liveListLimits: [Int?] = [nil, 25, 50, 100, 250, 500]

public func limitWords(_ limit: Int?) -> String { limit.map { "The first \($0)" } ?? "All songs" }

/// The orders a live list can run in, as the song lists offer them.
public let liveListSorts: [QuerySort.By] = [
    .recentlyAdded, .mostPlayed, .recentlyPlayed, .rating, .title, .artist, .album, .year, .length,
]

/// A new live list's order until the listener picks one: newest first.
public let defaultLiveListSort = QuerySort(.recentlyAdded, descending: true)

/// A live list made from a page's filters: the page's own rule when it is a genre or Favorites
/// (the whole library is where a live list looks), then the filters, in the page's order (newest
/// first when the page gives none).
public func liveListQueryFrom(_ page: [QueryRule], filters: LibraryQuery, order: QuerySort?) -> LibraryQuery {
    var rules: [QueryRule] = []
    for rule in page + filters.rules where !rules.contains(rule) { rules.append(rule) }
    return LibraryQuery(rules, match: page.isEmpty ? filters.match : .all,
                        text: filters.text.trimmingCharacters(in: .whitespacesAndNewlines),
                        sort: order ?? defaultLiveListSort, limit: filters.limit)
}

/// A live list the apps suggest while the listener has none. Made only when picked.
public struct LiveListStarter: Sendable, Hashable {
    public var name: String
    public var detail: String
    public var query: LibraryQuery

    public init(name: String, detail: String, query: LibraryQuery) {
        self.name = name
        self.detail = detail
        self.query = query
    }
}

public let liveListStarters: [LiveListStarter] = [
    LiveListStarter(name: "Recently added", detail: "Songs added in the last month, newest first",
                    query: LibraryQuery([FilterPresets.addedThisMonth], sort: defaultLiveListSort)),
    LiveListStarter(name: "Not played in a year", detail: "Songs you played before, not heard in a year",
                    query: LibraryQuery([FilterPresets.playedAtLeast(1), FilterPresets.notPlayedInTheLast(365)],
                                        sort: QuerySort(.mostPlayed, descending: true))),
    LiveListStarter(name: "Most played this month", detail: "Songs played this month, most played first",
                    query: LibraryQuery([FilterPresets.playedInTheLast(30)], sort: QuerySort(.mostPlayed, descending: true),
                                        limit: 50)),
    LiveListStarter(name: "Lossless favorites", detail: "Favorite songs in lossless files",
                    query: LibraryQuery([FilterPresets.favorites, FilterPresets.lossless], sort: QuerySort(.artist, descending: false))),
]
