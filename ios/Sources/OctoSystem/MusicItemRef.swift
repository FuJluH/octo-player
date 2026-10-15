import Foundation

/// A song, album, artist or playlist of the library, or the liked songs, as Siri and Shortcuts
/// name it: its kind and library id in one text, and the words it is shown with.
public struct MusicItemRef: Hashable, Sendable, Codable {
    public enum Kind: String, CaseIterable, Sendable, Codable {
        case song, album, artist, playlist, liked

        /// The word under its name.
        public var label: String {
            switch self {
            case .song: "Song"
            case .album: "Album"
            case .artist: "Artist"
            case .playlist: "Playlist"
            case .liked: "Playlist"
            }
        }
    }

    public var kind: Kind
    /// The library id; empty for the liked songs.
    public var libraryId: String
    public var title: String
    /// The artist for a song or album, the kind for the rest.
    public var subtitle: String

    public init(kind: Kind, libraryId: String, title: String, subtitle: String? = nil) {
        self.kind = kind
        self.libraryId = libraryId
        self.title = title
        self.subtitle = subtitle.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 } ?? kind.label
    }

    /// The liked songs, as one item.
    public static let liked = MusicItemRef(kind: .liked, libraryId: "", title: "Liked songs")

    /// The kind and the library id in one text: "album:<id>", or "liked".
    public var id: String { kind == .liked ? Kind.liked.rawValue : "\(kind.rawValue):\(libraryId)" }

    /// The kind and library id an id names, or nil for anything else.
    public static func parse(_ id: String) -> (kind: Kind, libraryId: String)? {
        if id == Kind.liked.rawValue { return (.liked, "") }
        guard let colon = id.firstIndex(of: ":"), let kind = Kind(rawValue: String(id[..<colon])), kind != .liked else { return nil }
        let libraryId = String(id[id.index(after: colon)...])
        return libraryId.isEmpty ? nil : (kind, libraryId)
    }
}
