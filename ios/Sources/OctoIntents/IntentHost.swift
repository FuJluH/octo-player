import Foundation
import OctoSystem

/// What the app does for the intents. The app hands one to `OctoIntentHost` as it starts; an
/// intent run where there is none (a widget's own process) does nothing.
@MainActor
public protocol OctoIntentHandling: AnyObject {
    /// Carries out a widget button or a quick play start. Answers the words to say when there
    /// was nothing to play.
    func run(_ command: WidgetCommand) async -> String?
    /// Plays what the words name by the voice rules; nil or empty words shuffle everything.
    func playMusic(_ text: String?) async -> String?
    /// Plays one library item.
    func play(_ item: MusicItemRef) async -> String?
    /// Starts radio from one library item.
    func startRadio(_ item: MusicItemRef) async -> String?
    /// Library items whose names hold the words.
    func find(_ text: String) async -> [MusicItemRef]
    /// The items Siri should know by name.
    func suggestions() async -> [MusicItemRef]
    /// The items with these ids, those still in the library.
    func items(_ ids: [String]) async -> [MusicItemRef]
}

/// Where the intents reach the app.
@MainActor
public enum OctoIntentHost {
    public static weak var handler: (any OctoIntentHandling)?

    /// The handler, waiting up to three seconds for an app started for the intent to be ready.
    static func ready() async -> (any OctoIntentHandling)? {
        var waits = 0
        while handler == nil && waits < 30 {
            try? await Task.sleep(for: .milliseconds(100))
            waits += 1
        }
        return handler
    }

    static func run(_ command: WidgetCommand) async -> String? { await ready()?.run(command) }
    static func playMusic(_ text: String?) async -> String? { await ready()?.playMusic(text) }
    static func play(_ item: MusicItemRef) async -> String? { await ready()?.play(item) }
    static func startRadio(_ item: MusicItemRef) async -> String? { await ready()?.startRadio(item) }
    static func find(_ text: String) async -> [MusicItemRef] { await ready()?.find(text) ?? [] }
    static func suggestions() async -> [MusicItemRef] { await ready()?.suggestions() ?? [] }
    static func items(_ ids: [String]) async -> [MusicItemRef] { await ready()?.items(ids) ?? [] }
}

/// Nothing to play: the words Siri says instead.
struct NothingToPlay: Error, CustomLocalizedStringResourceConvertible {
    let words: String

    var localizedStringResource: LocalizedStringResource { LocalizedStringResource(stringLiteral: words) }
}
