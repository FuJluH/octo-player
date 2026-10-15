import AppIntents
import Foundation
import OctoSystem

/// A song, album, artist or playlist of the library, or the liked songs, as Siri and Shortcuts
/// name it.
public struct MusicItemEntity: AppEntity {
    public static var typeDisplayRepresentation: TypeDisplayRepresentation { "Music" }
    public static var defaultQuery: MusicItemQuery { MusicItemQuery() }

    public let id: String
    public let ref: MusicItemRef

    public init(_ ref: MusicItemRef) {
        self.id = ref.id
        self.ref = ref
    }

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(ref.title)", subtitle: "\(ref.subtitle)", image: .init(systemName: symbol))
    }

    private var symbol: String {
        switch ref.kind {
        case .song: "music.note"
        case .album: "square.stack"
        case .artist: "music.mic"
        case .playlist: "music.note.list"
        case .liked: "heart.fill"
        }
    }
}

/// Finds library items by name, for Siri and Shortcuts.
public struct MusicItemQuery: EntityStringQuery {
    public init() {}

    public func entities(for identifiers: [String]) async throws -> [MusicItemEntity] {
        await OctoIntentHost.items(identifiers).map(MusicItemEntity.init)
    }

    public func entities(matching string: String) async throws -> [MusicItemEntity] {
        await OctoIntentHost.find(string).map(MusicItemEntity.init)
    }

    public func suggestedEntities() async throws -> [MusicItemEntity] {
        await OctoIntentHost.suggestions().map(MusicItemEntity.init)
    }
}

/// "Play Nothing Was the Same in Octo": one library item. An album plays in its order, an
/// artist's songs shuffled, a playlist in its order, the liked songs shuffled.
public struct PlayItemIntent: AudioPlaybackIntent {
    public static var title: LocalizedStringResource { "Play in Octo" }
    public static var description: IntentDescription { IntentDescription("Plays a song, album, artist or playlist from your library.") }

    @Parameter(title: "Music", requestValueDialog: IntentDialog("What do you want to play?"))
    public var item: MusicItemEntity

    public static var parameterSummary: some ParameterSummary { Summary("Play \(\.$item)") }

    public init() {}

    public init(item: MusicItemEntity) {
        self.item = item
    }

    public func perform() async throws -> some IntentResult {
        if let words = await OctoIntentHost.play(item.ref) { throw NothingToPlay(words: words) }
        return .result()
    }
}

/// "Play music in Octo": what the words name by the voice rules (an album or artist named
/// exactly, else songs that match), or with no words, everything shuffled.
public struct PlayMusicIntent: AudioPlaybackIntent {
    public static var title: LocalizedStringResource { "Play music" }
    public static var description: IntentDescription {
        IntentDescription("Plays the album, artist or songs your words name; with no words, shuffles everything.")
    }

    @Parameter(title: "Search")
    public var text: String?

    public static var parameterSummary: some ParameterSummary { Summary("Play \(\.$text)") }

    public init() {}

    public init(text: String?) {
        self.text = text
    }

    public func perform() async throws -> some IntentResult {
        if let words = await OctoIntentHost.playMusic(text) { throw NothingToPlay(words: words) }
        return .result()
    }
}

/// "Start radio from Drake in Octo": Octo's radio from a song, an album or an artist.
public struct StartRadioIntent: AudioPlaybackIntent {
    public static var title: LocalizedStringResource { "Start radio" }
    public static var description: IntentDescription { IntentDescription("Plays a song, album or artist, then songs like it.") }

    @Parameter(title: "Music", requestValueDialog: IntentDialog("What should the radio start from?"))
    public var item: MusicItemEntity

    public static var parameterSummary: some ParameterSummary { Summary("Start radio from \(\.$item)") }

    public init() {}

    public init(item: MusicItemEntity) {
        self.item = item
    }

    public func perform() async throws -> some IntentResult {
        if let words = await OctoIntentHost.startRadio(item.ref) { throw NothingToPlay(words: words) }
        return .result()
    }
}
