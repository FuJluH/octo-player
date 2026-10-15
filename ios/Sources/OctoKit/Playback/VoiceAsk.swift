import Foundation

/// What a spoken request asks to play, as Siri hands it over: the name said, the artist, album
/// or genre it named, and the kind of thing it heard.
public struct VoiceRequest: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case unknown, song, album, artist, playlist, genre, station, music
    }

    public var name: String?
    public var artist: String?
    public var album: String?
    public var genres: [String]
    public var kind: Kind
    /// "Play this": the song on now.
    public var current: Bool
    /// Asked to carry on rather than to start something.
    public var resume: Bool

    public init(name: String? = nil, artist: String? = nil, album: String? = nil, genres: [String] = [], kind: Kind = .unknown,
                current: Bool = false, resume: Bool = false) {
        self.name = name
        self.artist = artist
        self.album = album
        self.genres = genres
        self.kind = kind
        self.current = current
        self.resume = resume
    }
}

/// What the player does for a spoken request.
public enum VoiceAsk: Sendable, Equatable {
    /// The voice rules: an album or artist named exactly, else songs that match; empty text
    /// shuffles everything.
    case search(String)
    /// Every liked song, shuffled.
    case liked
    /// The playlist with this name, else the voice rules for the same words.
    case playlist(String)
    /// Radio from what this names.
    case radio(String)
    /// Carry on with the queue, or with none, shuffle everything.
    case resume
}

/// The names the liked songs go by when asked for out loud.
private let likedNames: Set<String> = Set([
    "liked songs", "my liked songs", "liked", "my likes", "likes", "liked music", "my liked music",
    "favorites", "my favorites", "favorite songs", "my favorite songs", "loved songs", "my loved songs",
].map(matchKey))

/// Whether the words name the liked songs.
public func namesLikedSongs(_ text: String) -> Bool {
    likedNames.contains(matchKey(text))
}

/// Turns a spoken request into what to play. The thing named is the name said, else the album,
/// the artist or the genre; nothing named shuffles everything, unless the request was to carry
/// on.
public func voiceAsk(_ request: VoiceRequest) -> VoiceAsk {
    if request.current { return .resume }
    let said = [request.name, request.album, request.artist, request.genres.first]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .first { !$0.isEmpty }
    guard let said else { return request.resume ? .resume : .search("") }
    if request.kind == .station { return .radio(said) }
    if [.unknown, .playlist, .music].contains(request.kind), namesLikedSongs(said) { return .liked }
    if request.kind == .playlist { return .playlist(said) }
    return .search(said)
}
