import AppIntents
import Foundation
import OctoSystem

/// Play: carries on with the queue, or with none, shuffles everything. Separate from Pause, so
/// a widget still showing an old state never does the opposite of what its button shows.
public struct PlayIntent: AudioPlaybackIntent {
    public static var title: LocalizedStringResource { "Play" }
    public static var description: IntentDescription { IntentDescription("Carries on with the queue, or with none, shuffles everything.") }
    public static var isDiscoverable: Bool { false }

    public init() {}

    public func perform() async throws -> some IntentResult {
        try await carryOut(.play)
        return .result()
    }
}

public struct PauseIntent: AudioPlaybackIntent {
    public static var title: LocalizedStringResource { "Pause" }
    public static var isDiscoverable: Bool { false }

    public init() {}

    public func perform() async throws -> some IntentResult {
        try await carryOut(.pause)
        return .result()
    }
}

public struct NextIntent: AudioPlaybackIntent {
    public static var title: LocalizedStringResource { "Next" }
    public static var isDiscoverable: Bool { false }

    public init() {}

    public func perform() async throws -> some IntentResult {
        try await carryOut(.next)
        return .result()
    }
}

public struct PreviousIntent: AudioPlaybackIntent {
    public static var title: LocalizedStringResource { "Previous" }
    public static var isDiscoverable: Bool { false }

    public init() {}

    public func perform() async throws -> some IntentResult {
        try await carryOut(.previous)
        return .result()
    }
}

/// "Resume Octo": exactly the play button.
public struct ResumeIntent: AudioPlaybackIntent {
    public static var title: LocalizedStringResource { "Resume" }
    public static var description: IntentDescription { IntentDescription("Carries on with the queue, or with none, shuffles everything.") }

    public init() {}

    public func perform() async throws -> some IntentResult {
        try await carryOut(.quick(.resume))
        return .result()
    }
}

/// Every liked song, shuffled.
public struct PlayLikedIntent: AudioPlaybackIntent {
    public static var title: LocalizedStringResource { "Play Liked songs" }
    public static var description: IntentDescription { IntentDescription("Shuffles every liked song.") }

    public init() {}

    public func perform() async throws -> some IntentResult {
        try await carryOut(.quick(.liked))
        return .result()
    }
}

/// The songs of the ten albums added last, newest first.
public struct PlayRecentlyAddedIntent: AudioPlaybackIntent {
    public static var title: LocalizedStringResource { "Play Recently added" }
    public static var description: IntentDescription { IntentDescription("Plays the newest albums, newest first.") }

    public init() {}

    public func perform() async throws -> some IntentResult {
        try await carryOut(.quick(.recentlyAdded))
        return .result()
    }
}

/// The songs of eight random albums, shuffled together.
public struct PlayAlbumMixIntent: AudioPlaybackIntent {
    public static var title: LocalizedStringResource { "Play an Album mix" }
    public static var description: IntentDescription { IntentDescription("Shuffles a few random albums together.") }

    public init() {}

    public func perform() async throws -> some IntentResult {
        try await carryOut(.quick(.albumMix))
        return .result()
    }
}

/// Carries out a command in the app; nothing to play is said out loud.
private func carryOut(_ command: WidgetCommand) async throws {
    if let words = await OctoIntentHost.run(command) { throw NothingToPlay(words: words) }
}
