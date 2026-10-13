import Foundation

/// What song rows show about copies kept on the phone: which songs are downloaded, and, with no
/// connection, which server songs cannot play.
public struct OfflineMarks: Sendable, Hashable {
    /// Library songs downloaded and ready to play.
    public var downloaded: Set<String>
    public var offline: Bool
    /// Server songs saved whole, as "<server>|<song id there>".
    public var saved: Set<String>

    public init(downloaded: Set<String> = [], offline: Bool = false, saved: Set<String> = []) {
        self.downloaded = downloaded
        self.offline = offline
        self.saved = saved
    }

    public func isDownloaded(_ track: LibraryTrack) -> Bool { downloaded.contains(track.id) }

    /// A song that cannot play right now: no connection, and neither on the phone, downloaded
    /// nor saved from an earlier play.
    public func isOutOfReach(_ track: LibraryTrack) -> Bool {
        offline && !track.onPhone && !downloaded.contains(track.id) && !saved.contains(savedSong(track.sourceId, track.nativeId))
    }
}

/// A server song as the saved songs know it: "<server>|<song id there>".
public func savedSong(_ sourceId: String, _ serverId: String) -> String { "\(sourceId)|\(serverId)" }

/// The song a saved key is for: the key less its type, request and file size.
public func savedSongOf(_ key: String) -> String { savedBeforeLastBar(savedBeforeLastBar(cacheKeyWithoutSize(key))) }

/// The text before the last "|", or all of it when there is none.
private func savedBeforeLastBar(_ text: String) -> String {
    guard let bar = text.lastIndex(of: "|") else { return text }
    return String(text[..<bar])
}
