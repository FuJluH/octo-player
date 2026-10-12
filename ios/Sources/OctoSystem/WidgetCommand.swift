import Foundation

/// What a widget button asks the player to do. Play and pause are separate, so a widget still
/// showing an old state can never do the opposite of what its button shows.
public enum WidgetCommand: Hashable, Sendable {
    case play
    case pause
    case next
    case previous
    case quick(QuickPick)

    private static let quickPrefix = "quick:"

    /// How the command travels in a link.
    public var encoded: String {
        switch self {
        case .play: "play"
        case .pause: "pause"
        case .next: "next"
        case .previous: "previous"
        case .quick(let pick): Self.quickPrefix + pick.rawValue
        }
    }

    /// The command a text names, or nil for anything else.
    public init?(encoded text: String?) {
        guard let text else { return nil }
        switch text {
        case "play": self = .play
        case "pause": self = .pause
        case "next": self = .next
        case "previous": self = .previous
        default:
            guard text.hasPrefix(Self.quickPrefix), let pick = QuickPick(rawValue: String(text.dropFirst(Self.quickPrefix.count))) else {
                return nil
            }
            self = .quick(pick)
        }
    }

    /// Every command, each button's own.
    public static var all: [WidgetCommand] { [.play, .pause, .next, .previous] + QuickPick.allCases.map(WidgetCommand.quick) }
}

/// The octo:// links the widgets open the app with: the app as it was, the full player, or a
/// button's command carried out by the app.
public enum OctoLink: Hashable, Sendable {
    case open
    case player
    case command(WidgetCommand)

    public static let scheme = "octo"

    public var url: URL {
        var parts = URLComponents()
        parts.scheme = Self.scheme
        switch self {
        case .open: parts.host = "open"
        case .player: parts.host = "player"
        case .command(let command):
            parts.host = "widget"
            parts.queryItems = [URLQueryItem(name: "command", value: command.encoded)]
        }
        // Built from fixed parts and a command's own words, so it always forms.
        return parts.url ?? URL(fileURLWithPath: "/")
    }

    /// The link an address is, or nil when it is not one of these.
    public init?(_ url: URL) {
        guard url.scheme?.lowercased() == Self.scheme else { return nil }
        switch url.host?.lowercased() {
        case "open": self = .open
        case "player": self = .player
        case "widget":
            let parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
            guard let command = WidgetCommand(encoded: parts?.queryItems?.first(where: { $0.name == "command" })?.value) else { return nil }
            self = .command(command)
        default: return nil
        }
    }
}
