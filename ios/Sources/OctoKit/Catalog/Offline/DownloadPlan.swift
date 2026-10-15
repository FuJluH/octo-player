import Foundation

/// Why a download is kept: asked for by hand, a liked song while Liked songs are kept, or a song
/// of a playlist that is kept. Saved in one column, comma separated; playlist ids never hold a
/// comma.
public enum DownloadReasons {
    public static let manual = "manual"
    public static let liked = "liked"
    private static let playlistPrefix = "playlist:"

    public static func playlist(_ id: String) -> String { playlistPrefix + id }

    /// The playlist a reason is for, or nil for any other reason.
    public static func playlistOf(_ reason: String) -> String? {
        reason.hasPrefix(playlistPrefix) ? String(reason.dropFirst(playlistPrefix.count)) : nil
    }

    public static func parse(_ text: String) -> Set<String> {
        Set(text.split(separator: ",", omittingEmptySubsequences: false).map(String.init).filter { !trimmed($0).isEmpty })
    }

    /// The reasons in one column: sorted, comma separated.
    public static func join(_ reasons: Set<String>) -> String {
        reasons.sorted { $0.utf16.lexicographicallyPrecedes($1.utf16) }.joined(separator: ",")
    }
}

extension KeptDownload {
    /// The reasons this download is kept, split out.
    public var reasons: Set<String> { DownloadReasons.parse(reason) }
}

/// A finished download beside its server song as the last sync saw it.
public struct DownloadedFile: Sendable, Equatable {
    public var sourceId: String
    public var serverId: String
    /// What the file is: the server's type, or MP3 when a smaller one was asked for.
    public var format: String?
    /// The size of the file on the phone.
    public var sizeBytes: Int64
    /// The server's size for the file the download was made from, when it was noted.
    public var fileSize: Int64?
    /// The server's size and type for the song's file now.
    public var serverSize: Int64?
    public var serverType: String?

    public init(sourceId: String, serverId: String, format: String?, sizeBytes: Int64, fileSize: Int64?, serverSize: Int64?,
                serverType: String?) {
        self.sourceId = sourceId
        self.serverId = serverId
        self.format = format
        self.sizeBytes = sizeBytes
        self.fileSize = fileSize
        self.serverSize = serverSize
        self.serverType = serverType
    }
}

/// What to do with a finished download, now the server may have swapped the song's file for
/// another: see `checkKeptCopy`. A download is the file as it is when it has the server's type,
/// unless that type is MP3, which smaller downloads are made as too.
public func checkDownload(_ file: DownloadedFile) -> KeptCopyCheck {
    checkKeptCopy(keptFor: file.fileSize, serverSize: file.serverSize, copySize: file.sizeBytes,
                  asIs: file.format != nil && file.format == file.serverType && file.format != "audio/mpeg")
}

/// What changes to bring the downloads in step with the rules: songs to start downloading, songs
/// whose reasons change, and songs to let go, all by library id.
public struct DownloadPlan: Sendable, Equatable {
    public var add: [String: Set<String>]
    public var change: [String: Set<String>]
    public var remove: Set<String>

    public init(add: [String: Set<String>] = [:], change: [String: Set<String>] = [:], remove: Set<String> = []) {
        self.add = add
        self.change = change
        self.remove = remove
    }

    public var isEmpty: Bool { add.isEmpty && change.isEmpty && remove.isEmpty }
}

/// The songs the rules want kept, each with the rules that want it.
public func wantedByRules(keepLiked: Bool, liked: some Collection<String>,
                          playlistSongs: some Collection<PlaylistMember>) -> [String: Set<String>] {
    var wanted: [String: Set<String>] = [:]
    if keepLiked {
        for trackId in liked { wanted[trackId, default: []].insert(DownloadReasons.liked) }
    }
    for member in playlistSongs { wanted[member.trackId, default: []].insert(DownloadReasons.playlist(member.playlistId)) }
    return wanted
}

/// Brings what is kept (`held`, each song with its reasons) in step with what the rules want. A
/// download asked for by hand stays until it is removed by hand. A rule's reason goes only when
/// the rule no longer wants the song, so a song that is briefly missing from the library, as
/// during a sync, is not deleted. A song is newly downloaded only if it can be: on a server and
/// not already on the phone.
public func planDownloads(held: [String: Set<String>], wanted: [String: Set<String>], downloadable: Set<String>) -> DownloadPlan {
    var change: [String: Set<String>] = [:]
    var remove: Set<String> = []
    for (trackId, reasons) in held {
        let kept = reasons.filter { $0 == DownloadReasons.manual }.union(wanted[trackId] ?? [])
        if kept.isEmpty {
            remove.insert(trackId)
        } else if kept != reasons {
            change[trackId] = kept
        }
    }
    let add = wanted.filter { held[$0.key] == nil && downloadable.contains($0.key) }
    return DownloadPlan(add: add, change: change, remove: remove)
}
