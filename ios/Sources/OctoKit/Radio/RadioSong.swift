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

/// A server's song as the radio sees it: its artists from the artist list, else its artist or
/// display artist, else the artist id; its album id, else the album name; its genre list, else
/// its genre; its composers split on `,` `;` `/`; liked when starred; its plays and last play
/// from the server. `rating` is the one on screen, which can be newer than the server's.
public func radioSong(_ song: ServerSong, rating: Int? = nil) -> RadioSong {
    var artists = song.artists.map(\.name).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    if artists.isEmpty { artists = [song.artist ?? song.displayArtist].compactMap { $0 } }
    if artists.isEmpty { artists = [song.artistId].compactMap { $0 } }
    let genre = song.genre?.trimmingCharacters(in: .whitespacesAndNewlines)
    let composers = (song.displayComposer ?? "").split(whereSeparator: { ",;/".contains($0) })
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    return RadioSong(
        id: song.id, title: song.title, artists: artists, album: song.albumId ?? song.album,
        genres: song.genres.isEmpty ? [genre].compactMap { $0 }.filter { !$0.isEmpty } : song.genres,
        year: song.year, durationMs: Int(knownLengthMs(Song(id: song.id, title: song.title, duration: song.duration))),
        composers: composers, liked: song.starred != nil, rating: rating ?? song.userRating ?? 0,
        plays: Int(song.playCount ?? 0), lastPlayedAt: serverTime(song.played))
}

/// A phone song as the radio sees it: its artist, else its artist id; its album id; its genre
/// when it has one; liked when among `liked`; its plays and last play from `played`.
public func radioSong(_ track: LibraryTrack, liked: Set<String>, played: PlayedTrack?) -> RadioSong {
    let artists = [track.artist].filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    return RadioSong(
        id: track.id, title: track.title, artists: artists.isEmpty ? [track.artistId] : artists, album: track.albumId,
        genres: track.genre.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? [] : [track.genre], year: track.year,
        durationMs: Int(track.durationMs), liked: liked.contains(track.id), rating: track.rating,
        plays: played?.plays ?? 0, lastPlayedAt: played.map { Int($0.lastPlayedAt) })
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
