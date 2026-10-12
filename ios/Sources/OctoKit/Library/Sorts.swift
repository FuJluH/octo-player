import Foundation

// The ways each list can be ordered, and which order each list starts in.

/// One way a song list can be ordered. The raw value is what gets saved, so it never changes.
public enum SongSort: String, CaseIterable, Sendable {
    case title = "Title"
    case artist = "Artist"
    case album = "Album"
    case recentlyAdded = "RecentlyAdded"
    case year = "Year"
    case length = "Length"
    case mostPlayed = "MostPlayed"
    case recentlyPlayed = "RecentlyPlayed"
    case rating = "Rating"
    case liked = "Liked"
    case dateLiked = "DateLiked"
    /// As the folder lists them: the server's order, or album by album on the phone.
    case folderOrder = "FolderOrder"

    public var label: String {
        switch self {
        case .title: "Title"
        case .artist: "Artist"
        case .album: "Album"
        case .recentlyAdded: "Recently added"
        case .year: "Year"
        case .length: "Length"
        case .mostPlayed: "Most played"
        case .recentlyPlayed: "Recently played"
        case .rating: "Rating"
        case .liked: "Liked"
        case .dateLiked: "Date liked"
        case .folderOrder: "Folder order"
        }
    }

    public var startsDescending: Bool {
        switch self {
        case .title, .artist, .album, .folderOrder: false
        default: true
        }
    }

    public var byName: Bool { self == .title || self == .artist || self == .album }
    public var byListening: Bool { self == .mostPlayed || self == .recentlyPlayed }
}

public enum AlbumSort: String, CaseIterable, Sendable {
    case title = "Title"
    case artist = "Artist"
    case year = "Year"
    case recentlyAdded = "RecentlyAdded"
    case mostPlayed = "MostPlayed"
    case recentlyPlayed = "RecentlyPlayed"
    case songCount = "SongCount"
    case length = "Length"

    public var label: String {
        switch self {
        case .title: "Title"
        case .artist: "Artist"
        case .year: "Year"
        case .recentlyAdded: "Recently added"
        case .mostPlayed: "Most played"
        case .recentlyPlayed: "Recently played"
        case .songCount: "Song count"
        case .length: "Length"
        }
    }

    public var startsDescending: Bool { !(self == .title || self == .artist) }
    public var byName: Bool { self == .title || self == .artist }
    public var byListening: Bool { self == .mostPlayed || self == .recentlyPlayed }
}

public enum ArtistSort: String, CaseIterable, Sendable {
    case name = "Name"
    case songCount = "SongCount"
    case albumCount = "AlbumCount"
    case mostPlayed = "MostPlayed"
    case recentlyPlayed = "RecentlyPlayed"
    /// By the newest song of theirs in the library.
    case recentlyAdded = "RecentlyAdded"

    public var label: String {
        switch self {
        case .name: "Name"
        case .songCount: "Song count"
        case .albumCount: "Album count"
        case .mostPlayed: "Most played"
        case .recentlyPlayed: "Recently played"
        case .recentlyAdded: "Recently added"
        }
    }

    public var startsDescending: Bool { self != .name }
    public var byName: Bool { self == .name }
    public var byListening: Bool { self == .mostPlayed || self == .recentlyPlayed }
}

public enum PlaylistSort: String, CaseIterable, Sendable {
    case name = "Name"
    case recentlyChanged = "RecentlyChanged"
    case recentlyCreated = "RecentlyCreated"
    case songCount = "SongCount"

    public var label: String {
        switch self {
        case .name: "Name"
        case .recentlyChanged: "Recently changed"
        case .recentlyCreated: "Recently created"
        case .songCount: "Song count"
        }
    }

    public var startsDescending: Bool { self != .name }
    public var byName: Bool { self == .name }
}

public enum DownloadSort: String, CaseIterable, Sendable {
    case recentlyDownloaded = "RecentlyDownloaded"
    case title = "Title"
    case size = "Size"

    public var label: String {
        switch self {
        case .recentlyDownloaded: "Recently downloaded"
        case .title: "Title"
        case .size: "Size"
        }
    }

    public var startsDescending: Bool { self != .title }
    public var byName: Bool { self == .title }
}

/// The Favorites page, for its albums and its artists alike.
public enum FavoriteSort: String, CaseIterable, Sendable {
    case dateAdded = "DateAdded"
    case name = "Name"

    public var label: String {
        switch self {
        case .dateAdded: "Date added"
        case .name: "Name"
        }
    }

    public var startsDescending: Bool { self == .dateAdded }
    public var byName: Bool { self == .name }
}

/// One way a list can be ordered, of any kind of list.
public enum SortOption: Hashable, Sendable {
    case song(SongSort)
    case album(AlbumSort)
    case artist(ArtistSort)
    case playlist(PlaylistSort)
    case download(DownloadSort)
    case favorite(FavoriteSort)

    /// What gets saved; never changes once shipped.
    public var id: String {
        switch self {
        case .song(let o): o.rawValue
        case .album(let o): o.rawValue
        case .artist(let o): o.rawValue
        case .playlist(let o): o.rawValue
        case .download(let o): o.rawValue
        case .favorite(let o): o.rawValue
        }
    }

    public var label: String {
        switch self {
        case .song(let o): o.label
        case .album(let o): o.label
        case .artist(let o): o.label
        case .playlist(let o): o.label
        case .download(let o): o.label
        case .favorite(let o): o.label
        }
    }

    /// Which way it runs when first picked: newest, most or longest first for dates and counts,
    /// A to Z for names.
    public var startsDescending: Bool {
        switch self {
        case .song(let o): o.startsDescending
        case .album(let o): o.startsDescending
        case .artist(let o): o.startsDescending
        case .playlist(let o): o.startsDescending
        case .download(let o): o.startsDescending
        case .favorite(let o): o.startsDescending
        }
    }

    /// Ordered by a name, so the list can be filed under letters.
    public var byName: Bool {
        switch self {
        case .song(let o): o.byName
        case .album(let o): o.byName
        case .artist(let o): o.byName
        case .playlist(let o): o.byName
        case .download(let o): o.byName
        case .favorite(let o): o.byName
        }
    }

    /// Ordered by how much or how lately it was played.
    public var byListening: Bool {
        switch self {
        case .song(let o): o.byListening
        case .album(let o): o.byListening
        case .artist(let o): o.byListening
        default: false
        }
    }

    public var song: SongSort? { if case .song(let o) = self { o } else { nil } }
    public var album: AlbumSort? { if case .album(let o) = self { o } else { nil } }
    public var artist: ArtistSort? { if case .artist(let o) = self { o } else { nil } }
    public var playlist: PlaylistSort? { if case .playlist(let o) = self { o } else { nil } }
    public var download: DownloadSort? { if case .download(let o) = self { o } else { nil } }
    public var favorite: FavoriteSort? { if case .favorite(let o) = self { o } else { nil } }
}

/// An order for a list: what it goes by, and which way it runs.
public struct ListOrder: Hashable, Sendable {
    public var by: SortOption
    public var descending: Bool

    public init(_ by: SortOption, descending: Bool) {
        self.by = by
        self.descending = descending
    }

    /// The order after picking another option, running its usual way.
    public func picking(_ option: SortOption) -> ListOrder {
        option == by ? self : ListOrder(option, descending: option.startsDescending)
    }
}

/// The orders any full list of songs offers.
private let songSorts: [SongSort] = [
    .title, .artist, .album, .recentlyAdded, .year, .length, .mostPlayed, .recentlyPlayed, .rating, .liked,
]

/// Every list that can be ordered: the name its order is saved under, the options it offers,
/// and the order it starts in.
public enum SortList: String, CaseIterable, Sendable {
    case songs, liked, genreSongs, folderSongs, albums, artistAlbums, artists, playlists, downloads, favorites

    public var key: String {
        switch self {
        case .songs: "songs"
        case .liked: "liked"
        case .genreSongs: "genre_songs"
        case .folderSongs: "folder_songs"
        case .albums: "albums"
        case .artistAlbums: "artist_albums"
        case .artists: "artists"
        case .playlists: "playlists"
        case .downloads: "downloads"
        case .favorites: "favourites"
        }
    }

    public var options: [SortOption] {
        switch self {
        case .songs, .genreSongs: songSorts.map(SortOption.song)
        case .liked: [SongSort.dateLiked, .title, .artist, .album, .recentlyAdded].map(SortOption.song)
        case .folderSongs: [SongSort.folderOrder, .title, .artist, .album, .recentlyAdded, .year, .length].map(SortOption.song)
        case .albums: AlbumSort.allCases.map(SortOption.album)
        case .artistAlbums: [AlbumSort.year, .title, .mostPlayed].map(SortOption.album)
        case .artists: ArtistSort.allCases.map(SortOption.artist)
        case .playlists: PlaylistSort.allCases.map(SortOption.playlist)
        case .downloads: DownloadSort.allCases.map(SortOption.download)
        case .favorites: FavoriteSort.allCases.map(SortOption.favorite)
        }
    }

    public var defaultOrder: ListOrder {
        switch self {
        case .songs, .genreSongs: ListOrder(.song(.title), descending: false)
        case .liked: ListOrder(.song(.dateLiked), descending: true)
        case .folderSongs: ListOrder(.song(.folderOrder), descending: false)
        case .albums: ListOrder(.album(.title), descending: false)
        case .artistAlbums: ListOrder(.album(.year), descending: true)
        case .artists: ListOrder(.artist(.name), descending: false)
        case .playlists: ListOrder(.playlist(.recentlyChanged), descending: true)
        case .downloads: ListOrder(.download(.recentlyDownloaded), descending: true)
        case .favorites: ListOrder(.favorite(.dateAdded), descending: true)
        }
    }

    /// Saved as "<option>:asc" or "<option>:desc".
    public func encode(_ order: ListOrder) -> String {
        "\(order.by.id):\(order.descending ? "desc" : "asc")"
    }

    /// A saved order, or the default when nothing is saved or it is not one this list offers.
    public func decode(_ saved: String?) -> ListOrder {
        guard let saved else { return defaultOrder }
        let parts = saved.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2, let option = options.first(where: { $0.id == parts[0] }) else { return defaultOrder }
        switch parts[1] {
        case "asc": return ListOrder(option, descending: false)
        case "desc": return ListOrder(option, descending: true)
        default: return defaultOrder
        }
    }
}

/// What the two directions of an order mean, in words: "A to Z" and "Z to A" for names,
/// "Newest" and "Oldest" for dates, and so on.
public enum SortScale: Sendable {
    case name, date, amount, length, rating, size, liked
    /// An order kept as something else lists it, like a folder's.
    case listed
    /// For an order no plainer word fits.
    case plain

    public var ascending: String {
        switch self {
        case .name: "A to Z"
        case .date: "Oldest"
        case .amount: "Least"
        case .length: "Shortest"
        case .rating: "Lowest"
        case .size: "Smallest"
        case .liked: "Liked last"
        case .listed: "In order"
        case .plain: "Ascending"
        }
    }

    public var descending: String {
        switch self {
        case .name: "Z to A"
        case .date: "Newest"
        case .amount: "Most"
        case .length: "Longest"
        case .rating: "Highest"
        case .size: "Largest"
        case .liked: "Liked first"
        case .listed: "Reversed"
        case .plain: "Descending"
        }
    }

    public func label(descending: Bool) -> String { descending ? self.descending : ascending }
}

/// The words for an option's directions.
public func sortScale(_ option: SortOption) -> SortScale {
    switch option {
    case .song(let o):
        switch o {
        case .title, .artist, .album: .name
        case .recentlyAdded, .year, .recentlyPlayed, .dateLiked: .date
        case .length: .length
        case .mostPlayed: .amount
        case .rating: .rating
        case .liked: .liked
        case .folderOrder: .listed
        }
    case .album(let o):
        switch o {
        case .title, .artist: .name
        case .year, .recentlyAdded, .recentlyPlayed: .date
        case .mostPlayed, .songCount: .amount
        case .length: .length
        }
    case .artist(let o):
        switch o {
        case .name: .name
        case .songCount, .albumCount, .mostPlayed: .amount
        case .recentlyPlayed, .recentlyAdded: .date
        }
    case .playlist(let o):
        switch o {
        case .name: .name
        case .recentlyChanged, .recentlyCreated: .date
        case .songCount: .amount
        }
    case .download(let o):
        switch o {
        case .recentlyDownloaded: .date
        case .title: .name
        case .size: .size
        }
    case .favorite(let o):
        switch o {
        case .dateAdded: .date
        case .name: .name
        }
    }
}

/// One of the two directions offered for an order, and its words.
public struct DirectionChoice: Hashable, Sendable {
    public var descending: Bool
    public var label: String

    public init(descending: Bool, label: String) {
        self.descending = descending
        self.label = label
    }
}

/// The two directions for an option, the way it runs when first picked on the left: "A to Z"
/// before "Z to A", but "Newest" before "Oldest".
public func directionChoices(_ option: SortOption) -> [DirectionChoice] {
    let scale = sortScale(option)
    let first = option.startsDescending
    return [DirectionChoice(descending: first, label: scale.label(descending: first)),
            DirectionChoice(descending: !first, label: scale.label(descending: !first))]
}

/// The saved orders, by list name, that this app can use: a list it has, with an order that
/// list offers.
public func restorableOrders(_ saved: [String: String]) -> [SortList: ListOrder] {
    var kept: [SortList: ListOrder] = [:]
    for list in SortList.allCases {
        guard let value = saved[list.key] else { continue }
        let order = list.decode(value)
        if list.encode(order) == value { kept[list] = order }
    }
    return kept
}
