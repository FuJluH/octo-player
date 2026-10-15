import Foundation

/// How a settings row that another setting can take over shows: whether it can be chosen, the
/// reading on its right, and the line under its title.
public struct RowLook: Equatable, Sendable {
    public var choosable: Bool
    public var value: String
    public var helper: String

    public init(choosable: Bool, value: String, helper: String) {
        self.choosable = choosable
        self.value = value
        self.helper = helper
    }
}

/// What the crossfade curve row says while Smart transitions pick the curves: why it cannot be
/// chosen, and the switch, just below it, that makes it choosable.
public let smartPicksTheCurve = "Smart transitions picks the curve for each blend. Turn off Smart transitions, just below, to choose one."

/// The crossfade curve row's reading while Smart transitions pick the curves.
public let smartCurveValue = "Picked for each blend"

/// The crossfade curve row. Smart transitions shape each blend themselves, so the curve is only
/// chosen with them off.
public func curveRowLook(_ curve: FadeCurve, smartTransitions: Bool) -> RowLook {
    smartTransitions
        ? RowLook(choosable: false, value: smartCurveValue, helper: smartPicksTheCurve)
        : RowLook(choosable: true, value: curve.label, helper: curve.detail)
}

/// The Discovery row. With Library songs only on, no song from outside the library plays
/// anywhere, radio included, so Discovery has no say; the line names that setting and `where` it
/// is (the page of Settings that holds it).
public func discoveryRowLook(_ discovery: RadioDiscovery, libraryOnly: Bool, where place: String) -> RowLook {
    libraryOnly
        ? RowLook(choosable: false, value: RadioDiscovery.libraryOnly.label,
                  helper: "\(LibraryOnlyWords.setting) is on in \(place), so radio keeps to your library. Turn it off there to choose.")
        : RowLook(choosable: true, value: discovery.label, helper: discovery.detail)
}

/// The two parts of Settings > Radio, as every Octo app names them.
public enum RadioWords {
    /// Radio Octo mixes from your music.
    public static let songRadio = "Song radio"
    /// What the Song radio part is, in a line.
    public static let songRadioAbout = "Radio started from a song, album or artist, and Autoplay when the queue ends, mixed from your music."
    /// The stations on the air.
    public static let liveRadio = "Live radio"
    /// What the Live radio part is, in a line.
    public static let liveRadioAbout = "Stations on the air: the ones your server keeps, and ones near you."
    /// The line under Find stations near you.
    public static let findNearHelp = "Stations on the air around a place, to play or keep."
    /// The line under Stations on your server, signed in.
    public static let stationsHelp = "Play them, and add or change them as an admin."
    /// The line under Stations on your server with no server connected.
    public static let stationsSignedOut = "Connect a server to see the stations it keeps."
    /// Why the stations list has no Add or Edit for someone who is not an admin.
    public static let stationsNotAdmin = "Only an admin of your server can add or change stations."
    /// The Favorites more often switch's line.
    public static let favoritesHelp = "Songs you hearted or rated 4 or 5 stars come around more often."
}
