import Foundation

/// Which kind of result a search shows: everything, or one kind in full.
public enum SearchFilter: Int, CaseIterable, Sendable {
    case all, songs, albums, artists, playlists

    public var label: String {
        switch self {
        case .all: "All"
        case .songs: "Songs"
        case .albums: "Albums"
        case .artists: "Artists"
        case .playlists: "Playlists"
        }
    }
}

/// How many of each kind a search shows. Everything at once shows a few of each; one kind picked
/// shows all of it, up to a limit that keeps the list quick to build.
public struct SearchCaps: Sendable, Equatable {
    public var artists: Int
    public var albums: Int
    public var songs: Int
    public var playlists: Int

    public init(artists: Int, albums: Int, songs: Int, playlists: Int) {
        self.artists = artists
        self.albums = albums
        self.songs = songs
        self.playlists = playlists
    }
}

public func searchCaps(_ filter: SearchFilter) -> SearchCaps {
    switch filter {
    case .all: SearchCaps(artists: 10, albums: 20, songs: 50, playlists: 10)
    case .songs: SearchCaps(artists: 0, albums: 0, songs: 1_000, playlists: 0)
    case .albums: SearchCaps(artists: 0, albums: 500, songs: 0, playlists: 0)
    case .artists: SearchCaps(artists: 500, albums: 0, songs: 0, playlists: 0)
    case .playlists: SearchCaps(artists: 0, albums: 0, songs: 0, playlists: 500)
    }
}

/// How long typing has to pause before the library is searched, and before the server is asked.
public let librarySearchAfterMs = 150
public let discoverAfterMs = 400

/// The finds whose library song is among the songs a search listed, by their find ids.
/// `adoptions` holds each find now in the library, by its id on the server, and the library song
/// it became.
public func listedFinds(_ adoptions: [String: String], songIds: [String]) -> Set<String> {
    if adoptions.isEmpty { return [] }
    let ids = Set(songIds)
    return Set(adoptions.filter { ids.contains($0.value) }.keys.map(findId))
}

extension Discovered {
    /// The songs found online a search shows: all but those already listed as library songs.
    public func without(_ listed: Set<String>) -> Discovered {
        if listed.isEmpty || !songs.contains(where: { listed.contains($0.id) }) { return self }
        var copy = self
        copy.songs = songs.filter { !listed.contains($0.id) }
        return copy
    }

    /// The finds of the kinds a filter shows. Playlists are only ever the listener's own, so that
    /// filter shows none (nil).
    public func only(_ filter: SearchFilter) -> Discovered? {
        switch filter {
        case .playlists: return nil
        case .all: return self
        case .songs: return Discovered(songs: songs, albums: [], artists: [])
        case .albums: return Discovered(songs: [], albums: albums, artists: [], partAlbums: partAlbums)
        case .artists: return Discovered(songs: [], albums: [], artists: artists)
        }
    }
}

/// What searching the server has come to.
public enum DiscoverState: Sendable {
    /// Nothing asked: no server, or too little typed.
    case idle
    case loading
    case done(Discovered)
    case failed

    /// Nothing to show online: not looking, or looked and found nothing.
    public var showsNothing: Bool {
        switch self {
        case .idle: true
        case .done(let found): found.isEmpty
        default: false
        }
    }

    public func only(_ filter: SearchFilter) -> DiscoverState {
        guard case .done(let found) = self else { return filter == .playlists ? .idle : self }
        return found.only(filter).map { .done($0) } ?? .idle
    }

    public func without(_ listed: Set<String>) -> DiscoverState {
        guard case .done(let found) = self, !listed.isEmpty else { return self }
        return .done(found.without(listed))
    }
}

/// Octo's id for something it found online rather than a file in the library.
public func isOnlineId(_ id: String) -> Bool { id.hasPrefix("ext-") }

/// The artist a search names: a library artist, or one the server found.
public struct NamedArtist: Sendable, Equatable {
    public var name: String
    public var libraryId: String?
    public var serverId: String?

    public init(name: String, libraryId: String? = nil, serverId: String? = nil) {
        self.name = name
        self.libraryId = libraryId
        self.serverId = serverId
    }
}

/// The artist `query` names whole, the library's first, then the server's finds; none when it
/// names nobody.
public func namedArtist(_ query: String, library: [LibraryArtist], online: [OnlineArtist]) -> NamedArtist? {
    if let artist = searchedArtist(query, library, name: \.name) { return NamedArtist(name: artist.name, libraryId: artist.id) }
    if let artist = searchedArtist(query, online, name: \.name) { return NamedArtist(name: artist.name, serverId: artist.id) }
    return nil
}

/// How many times the line saying how to add a song shows before it stops.
public let addHintShowings = 5

/// How many times the line has been shown, and whether a song has been added to the library since
/// it first could be.
public struct AddHintState: Sendable, Equatable {
    public var shown: Int
    public var added: Bool

    public init(shown: Int = 0, added: Bool = false) {
        self.shown = shown
        self.added = added
    }
}

/// Whether the line shows. It goes once a song has been added, and after a few showings; once
/// counted on a visit it stays for the rest of it, so it does not vanish while being read.
public func showsAddHint(_ state: AddHintState, countedThisVisit: Bool) -> Bool {
    !state.added && (countedThisVisit || state.shown < addHintShowings)
}
