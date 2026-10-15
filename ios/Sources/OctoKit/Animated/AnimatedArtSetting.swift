import Foundation

/// How an album's animated art (Apple Music's animated covers, through an Octo server) shows in
/// the app. Kept under `prefKey` by its key, the same on every app.
public enum AnimatedArtSetting: String, StoredChoice, Codable {
    case square = "square"
    case fullScreen = "full_screen"
    case off = "off"

    /// Where the choice is kept, and what it is called.
    public static let prefKey = "animated_art"
    public static let title = "Animated art"
    public static let about = "Apple Music's animated album covers, on Octo servers that offer them."

    public static let standard = AnimatedArtSetting.square

    public var key: String { rawValue }

    public var label: String {
        switch self {
        case .square: "Square"
        case .fullScreen: "Full screen"
        case .off: "Off"
        }
    }

    public var detail: String {
        switch self {
        case .square: "Plays in place of the cover on the player and on album pages."
        case .fullScreen: "Fills the player when the album has a tall version, otherwise plays in place of the cover."
        case .off: "Always shows the still cover."
        }
    }

    public static func from(key: String?) -> AnimatedArtSetting { stored(key, or: standard) }
}

/// Where the player shows an album's animated art.
public enum PlayerLoop: Sendable, Equatable {
    /// The square loop, in place of the cover.
    case cover(AnimatedClip)
    /// The tall loop, filling the player behind the controls.
    case backdrop(AnimatedClip)
    /// The still cover.
    case none

    /// The clip it plays, if any.
    public var clip: AnimatedClip? {
        switch self {
        case .cover(let clip), .backdrop(let clip): clip
        case .none: nil
        }
    }
}

extension AnimatedArtSetting {
    /// What the player shows for `art` with this setting: the tall loop behind everything when the
    /// setting is Full screen and the album has one, else the square loop in place of the cover.
    public func inPlayer(_ art: AnimatedArt?) -> PlayerLoop {
        guard self != .off, let art else { return .none }
        let tall = art.tall.flatMap { $0.playable ? $0 : nil }
        let square = art.square.flatMap { $0.playable ? $0 : nil }
        if self == .fullScreen, let tall { return .backdrop(tall) }
        if let square { return .cover(square) }
        return .none
    }

    /// The loop an album page's header plays in place of its cover, if any.
    public func onAlbumPage(_ art: AnimatedArt?) -> AnimatedClip? {
        guard self != .off, let square = art?.square, square.playable else { return nil }
        return square
    }
}
