import Foundation

/// A song as the radio sees it, from either app: what it is, who made it, and how the listener
/// has treated it. Each app turns its own songs into these. `album` is any id or name that is the
/// same for every song of one album; `durationMs` is 0 when the length is not known.
public final class RadioSong: @unchecked Sendable {
    public let id: String
    public let title: String
    public let artists: [String]
    public let album: String?
    public let genres: [String]
    public let year: Int?
    public let durationMs: Int
    public let composers: [String]
    public let liked: Bool
    public let rating: Int
    public let plays: Int
    public let lastPlayedAt: Int?

    public init(id: String, title: String, artists: [String], album: String? = nil, genres: [String] = [], year: Int? = nil,
                durationMs: Int = 0, composers: [String] = [], liked: Bool = false, rating: Int = 0, plays: Int = 0,
                lastPlayedAt: Int? = nil) {
        self.id = id
        self.title = title
        self.artists = artists
        self.album = album
        self.genres = genres
        self.year = year
        self.durationMs = durationMs
        self.composers = composers
        self.liked = liked
        self.rating = rating
        self.plays = plays
        self.lastPlayedAt = lastPlayedAt
    }

    /// The same song marked liked, or not.
    public func liked(_ on: Bool) -> RadioSong {
        RadioSong(id: id, title: title, artists: artists, album: album, genres: genres, year: year, durationMs: durationMs,
                  composers: composers, liked: on, rating: rating, plays: plays, lastPlayedAt: lastPlayedAt)
    }

    // What the radio compares songs by, worked out when first needed.
    lazy var artistKeys: [String] = distinctInOrder(artists.compactMap(artistKey))
    lazy var composerKeys: [String] = distinctInOrder(composers.compactMap(artistKey))
    lazy var genreKeys: [String] = distinctInOrder(genres.map(searchKey).filter { !$0.isEmpty })
    lazy var titleKey: String = searchKey(SongIdentity.parseTitle(title).core)
}

/// One spelling per artist: the main name of a credit, lowercase, accents gone.
func artistKey(_ name: String) -> String? {
    let key = searchKey(SongIdentity.primaryArtist(name))
    return key.isEmpty ? nil : key
}

/// A server's song as the radio sees it. `rating` is the one on screen, which can be newer than
/// the server's; `plays` and `lastPlayedAt` what the library knows of its listening.
public func radioSong(_ song: Song, rating: Int = 0, plays: Int = 0, lastPlayedAt: Int? = nil, composers: [String] = []) -> RadioSong {
    let artists = [song.artist ?? song.displayArtist].compactMap { $0 }.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    let genre = song.genre?.trimmingCharacters(in: .whitespaces)
    return RadioSong(
        id: song.id, title: song.title,
        artists: artists.isEmpty ? [song.artistId].compactMap { $0 } : artists,
        album: song.albumId ?? song.album,
        genres: genre.map { $0.isEmpty ? [] : [$0] } ?? [],
        year: song.year,
        durationMs: Int(knownLengthMs(song)),
        composers: composers.flatMap { $0.split(whereSeparator: { ",;/".contains($0) }).map { $0.trimmingCharacters(in: .whitespaces) } }
            .filter { !$0.isEmpty },
        liked: song.starred != nil,
        rating: rating,
        plays: plays,
        lastPlayedAt: lastPlayedAt)
}

private let shortestMs = 45_000
private let longestMs = 45 * 60_000
private let shortPieceMs = 4 * 60_000

// Whole words, with the edges spelled out, so every app and the server agree.
private let talk = try! NSRegularExpression(pattern: #"(?<![\p{L}\p{N}])(interview|podcast)(?![\p{L}\p{N}])"#, options: [.caseInsensitive])
private let filler = try! NSRegularExpression(pattern: #"(?<![\p{L}\p{N}])(intro|introduction|skit|interlude)(?![\p{L}\p{N}])"#,
                                              options: [.caseInsensitive])
private let talkGenres: Set<String> = ["podcast", "podcasts", "audiobook", "audiobooks"]

private func matches(_ regex: NSRegularExpression, _ text: String) -> Bool {
    regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
}

/// Songs a radio leaves out: shorter than 45 seconds or longer than 45 minutes, an interview or a
/// podcast, or an intro, skit or interlude of four minutes or less. A length of 0 is unknown and
/// not held against it.
public func isRadioFiller(_ title: String, durationMs: Int, genres: [String] = []) -> Bool {
    if (1..<shortestMs).contains(durationMs) || durationMs > longestMs { return true }
    if matches(talk, title) { return true }
    if genres.contains(where: { talkGenres.contains(searchKey($0)) }) { return true }
    return (1...shortPieceMs).contains(durationMs) && matches(filler, title)
}
