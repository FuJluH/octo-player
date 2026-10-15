import Foundation

/// What the player knows about the music, cut down to what a home screen widget can show. No
/// value at all means nothing is loaded.
public struct WidgetPlayback: Codable, Sendable, Equatable {
    public var title: String?
    public var artist: String?
    public var isPlaying: Bool

    public init(title: String?, artist: String?, isPlaying: Bool) {
        self.title = title
        self.artist = artist
        self.isPlaying = isPlaying
    }
}

/// The three shapes of the Now playing widget.
public enum WidgetSize: String, CaseIterable, Sendable {
    case small, medium, large

    /// Widths and heights, in points, where each shape starts. Anything narrower than medium is
    /// small, even when tall, since three buttons need the width.
    public static let mediumMinWidth = 200.0
    public static let largeMinHeight = 100.0
    public static let smallMinWidth = 110.0
    public static let smallMinHeight = 40.0

    /// The largest shape that fits a widget drawn this wide and this high.
    public init(width: Double, height: Double) {
        if width < Self.mediumMinWidth {
            self = .small
        } else if height < Self.largeMinHeight {
            self = .medium
        } else {
            self = .large
        }
    }
}

/// Exactly what one shape of the Now playing widget draws.
public struct NowPlayingFace: Sendable, Equatable {
    public var title: String
    /// Hidden when nil.
    public var artist: String?
    public var titleLines: Int
    /// Shows pause while playing, play otherwise.
    public var playing: Bool
    public var showSkips: Bool
    /// Nothing loaded: the play button picks up the saved queue.
    public var empty: Bool
}

/// The words the widgets show and say.
public enum WidgetWords {
    public static let nothingPlaying = "Nothing playing"
    public static let unknownSong = "Unknown song"
    public static let openPlayer = "Open the player"
    public static let play = "Play"
    public static let pause = "Pause"
    public static let previous = "Previous"
    public static let next = "Next"
    public static let nowPlaying = "Now playing"
    public static let nowPlayingDescription = "The song that is on, with play, pause and skip."
    public static let quickPlay = "Quick play"
    public static let quickPlayDescription = "Liked songs, the newest albums, an album mix or the last queue, in one tap."
}

/// The widgets' kinds, as WidgetKit knows them.
public enum WidgetKind {
    public static let nowPlaying = "NowPlaying"
    public static let quickPlay = "QuickPlay"
}

/// Longer text is cut here before it reaches a widget; the widget then cuts whatever still does
/// not fit with an ellipsis.
public let widgetTextLimit = 80

/// What a shape of the Now playing widget shows for the music as it is.
public func nowPlayingFace(_ playback: WidgetPlayback?, _ size: WidgetSize) -> NowPlayingFace {
    guard let playback else {
        return NowPlayingFace(title: WidgetWords.nothingPlaying, artist: nil, titleLines: 1, playing: false, showSkips: false, empty: true)
    }
    let title = widgetClip(playback.title) ?? WidgetWords.unknownSong
    let artist = widgetClip(playback.artist)
    switch size {
    case .small:
        // Only room for the title beside the button.
        return NowPlayingFace(title: title, artist: nil, titleLines: 1, playing: playback.isPlaying, showSkips: false, empty: false)
    case .medium:
        return NowPlayingFace(title: title, artist: artist, titleLines: 1, playing: playback.isPlaying, showSkips: true, empty: false)
    case .large:
        // Long titles get a second line.
        return NowPlayingFace(title: title, artist: artist, titleLines: 2, playing: playback.isPlaying, showSkips: true, empty: false)
    }
}

/// Blank text counts as missing; runs of spaces become one; very long text is cut with an
/// ellipsis.
public func widgetClip(_ text: String?, limit: Int = widgetTextLimit) -> String? {
    guard let text else { return nil }
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    if trimmed.isEmpty { return nil }
    guard trimmed.count > limit else { return trimmed }
    var cut = String(trimmed.prefix(limit - 1))
    while cut.last?.isWhitespace == true { cut.removeLast() }
    return cut + "…"
}

/// The four starts on the Quick play widget: liked songs shuffled, the newest albums, a few
/// random albums shuffled together, and the last queue. The raw value is the name a command
/// carries.
public enum QuickPick: String, CaseIterable, Sendable, Codable {
    case liked = "Liked"
    case recentlyAdded = "RecentlyAdded"
    case albumMix = "AlbumMix"
    case resume = "Resume"

    /// How many albums Recently added and Album mix take.
    public static let recentAlbums = 10
    public static let mixAlbums = 8

    public var label: String {
        switch self {
        case .liked: "Liked songs"
        case .recentlyAdded: "Recently added"
        case .albumMix: "Album mix"
        case .resume: "Resume"
        }
    }

    /// The SF Symbol on its square.
    public var symbol: String {
        switch self {
        case .liked: "heart.fill"
        case .recentlyAdded: "square.stack.fill"
        case .albumMix: "shuffle"
        case .resume: "music.note.list"
        }
    }
}
