import Foundation

/// The OpenSubsonic extension an Octo server lists when it can rank the songs people play most: an
/// artist's (getArtistTopSongs) and the chart of the moment (getTopChart).
public let octoTopSongs = "octoTopSongs"

/// The octoTopSongs version whose getTopChart takes a chart and that answers getCharts.
public let octoTopSongsCharts = 2

/// Where a ranked list's order came from, as the server names it.
public let topSongsLastFm = "lastfm"
public let topSongsDeezer = "deezer"
public let topSongsApple = "apple"

/// How many of an artist's top songs a search asks the server for, and how many it shows before
/// "Show all".
public let searchTopSongs = 20
public let searchTopShown = 5

/// How many of the chart's songs an empty search asks for, and shows before "Show all".
public let topChartSongs = 50
public let topChartShown = 10

/// How many of the overall chart's songs Home's Charts row shows.
public let chartsRow = 10

/// Which of a search's artists the search was for: the first whose name is what was typed, case,
/// accents and a leading "The" aside. None when no name is, so "daft" or a song's title shows no
/// top songs.
public func searchedArtist<T>(_ query: String, _ artists: [T], name: (T) -> String) -> T? {
    if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return nil }
    let typed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    return artists.first { SongIdentity.sameArtistName(name($0), typed) }
}

/// Last.fm's play count, short: "940 plays", "12K plays", "2.5M plays".
public func playsText(_ plays: Int64) -> String {
    if plays == 1 { return "1 play" }
    if plays < 1_000 { return "\(plays) plays" }
    let units: [(Int64, String)] = [(1_000, "K"), (1_000_000, "M"), (1_000_000_000, "B")]
    var at = units.lastIndex { plays >= $0.0 } ?? 0
    var tenths = Int64((Double(plays) * 10.0 / Double(units[at].0)).rounded())
    // 999,960 rounds to 1000K, which is 1M.
    if tenths >= 10_000 && at < units.count - 1 {
        at += 1
        tenths = Int64((Double(plays) * 10.0 / Double(units[at].0)).rounded())
    }
    let number: String
    if tenths >= 100 {
        number = "\((tenths + 5) / 10)"
    } else if tenths % 10 == 0 {
        number = "\(tenths / 10)"
    } else {
        number = "\(tenths / 10).\(tenths % 10)"
    }
    return "\(number)\(units[at].1) plays"
}

/// What a ranked list is ranked by, in a person's words, or nil when the server did not say.
/// `chart` is the chart's id, which tells Apple Music's picks of the week and its trending songs
/// from its most played.
public func rankedBy(_ source: String, chart: String? = nil) -> String? {
    switch source {
    case topSongsLastFm: return "Most played on Last.fm"
    case topSongsDeezer: return "Most popular on Deezer"
    case topSongsApple:
        switch chart {
        case Charts.newSongs: return "Picked by Apple Music"
        case Charts.trending: return "Trending on Apple Music"
        default: return "Most played on Apple Music"
        }
    default: return nil
    }
}

/// How many songs a chart holds at most: Best New Songs and Trending Songs up to 100, every other
/// chart 50.
public func chartSongs(_ chart: String) -> Int { chart == Charts.newSongs || chart == Charts.trending ? 100 : 50 }

/// Whether a server's extensions offer the Charts page: octoTopSongs at the version whose
/// getTopChart takes a chart.
public func chartsOffered(_ extensions: [String]) -> Bool { extensions.contains("\(octoTopSongs):\(octoTopSongsCharts)") }

/// One ranked song as the app shows it. Plays are Last.fm's, when the list was ranked by them.
public struct RankedSong<Track>: Sendable where Track: Sendable {
    public var rank: Int
    public var track: Track
    public var plays: Int64?

    public init(rank: Int, track: Track, plays: Int64?) {
        self.rank = rank
        self.track = track
        self.plays = plays
    }
}

/// A ranked list: an artist's top songs, or a chart, which names no artist.
public struct RankedSongs<Track>: Sendable where Track: Sendable {
    public var artist: String?
    public var source: String
    public var songs: [RankedSong<Track>]

    public init(artist: String?, source: String, songs: [RankedSong<Track>]) {
        self.artist = artist
        self.source = source
        self.songs = songs
    }

    /// The list as "Library songs only" shows it: its library songs, each at its own rank; nil
    /// when none is in the library.
    public func inLibraryOnly(outside: (Track) -> Bool) -> RankedSongs? {
        var copy = self
        copy.songs = librarySongsOnly(songs, hide: true) { outside($0.track) }
        return copy.songs.isEmpty ? nil : copy
    }
}

/// Each entry with the song the app shows for it (`tracks`, in the same places), so a rank stays
/// with its song. A song gone from the library is left out, and a song listed twice (two copies
/// of it, or a find that became the library song above it) stands once, at its better place. An
/// entry the server sent without a rank takes its place in the list.
public func rankTracks<Track>(_ entries: [TopSong], _ tracks: [Track?], id: (Track) -> String) -> [RankedSong<Track>] {
    var seen = Set<String>()
    var ranked: [RankedSong<Track>] = []
    for (index, (entry, track)) in zip(entries, tracks).enumerated() {
        guard let track, seen.insert(id(track)).inserted else { continue }
        ranked.append(RankedSong(rank: entry.rank > 0 ? entry.rank : index + 1, track: track, plays: entry.plays.map(Int64.init)))
    }
    return ranked
}

/// A chart as the app shows it: which chart, its name, who ranked it, the country it is for, and
/// its songs.
public struct ChartList<Track>: Sendable where Track: Sendable {
    public var chart: String
    public var name: String?
    public var source: String
    public var country: String?
    public var songs: [RankedSong<Track>]

    public init(chart: String, name: String?, source: String, country: String?, songs: [RankedSong<Track>]) {
        self.chart = chart
        self.name = name
        self.source = source
        self.country = country
        self.songs = songs
    }
}

/// Who ranked a chart and for which country: "Most played on Apple Music in United States". Only
/// who ranked it when the country is not a two-letter code; nothing when nobody ranked it.
public func chartCaption(source: String, chart: String, country: String?, locale: Locale = .current) -> String? {
    guard let by = rankedBy(source, chart: chart) else { return nil }
    guard let code = country, code.count == 2,
          let name = locale.localizedString(forRegionCode: code.uppercased()), !name.trimmingCharacters(in: .whitespaces).isEmpty
    else { return by }
    return "\(by) in \(name)"
}

/// How many of an artist's top songs are looked through for an album's main song.
public let albumHighlightRanked = 30

/// A song as a ranking knows it: its id on the server, title and artist.
public struct TopSongRef: Sendable, Equatable {
    public var id: String
    public var title: String
    public var artist: String

    public init(id: String, title: String, artist: String) {
        self.id = id
        self.title = title
        self.artist = artist
    }
}

/// The album's main song, as Apple Music marks it with a star: of the album's songs, the one that
/// comes first in the artist's top songs. Matched by id, or for a song the ranking knows by another
/// id (one found online, say) by its title, features left out, and its artist. None when no album
/// song is among the top songs.
public func albumHighlight(_ tracks: [(id: String, title: String, artist: String)], _ ranked: [TopSongRef]) -> String? {
    func titleKey(_ title: String) -> String { SongIdentity.key(SongIdentity.stripFeatures(title)) }
    for top in ranked {
        if let hit = tracks.first(where: { $0.id == top.id }) { return hit.id }
        let title = titleKey(top.title)
        if title.isEmpty { continue }
        if let hit = tracks.first(where: { titleKey($0.title) == title && SongIdentity.sameArtistName($0.artist, top.artist) }) {
            return hit.id
        }
    }
    return nil
}
