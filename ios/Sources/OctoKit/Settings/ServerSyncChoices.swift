import Foundation

/// The key a small store keeps one value under in the app's defaults: "<store>.<name>", and
/// "<store>.<name>@<account>" for a value of one account.
public func storeKey(_ store: String, _ name: String, account: String? = nil) -> String {
    "\(store).\(account.map { accountKey(name, $0) } ?? name)"
}

/// The two choices about keeping things on the server, each under one key in the app's own
/// defaults: syncing the play queue (on until turned off) and making new playlists on the
/// server too (off until turned on). PlaylistSync owns the playlist choice and the Server page
/// writes the queue one, which the queue sync follows as it changes; backups read and restore
/// both here.
public struct ServerSyncChoices: @unchecked Sendable {
    public static let playlistsStore = "playlist_sync"
    public static let playlistsName = "new_on_server"
    public static let queueStore = "server_queue"
    public static let queueName = "sync_on"

    public static var newPlaylistsKey: String { storeKey(playlistsStore, playlistsName) }
    public static var syncQueueKey: String { storeKey(queueStore, queueName) }

    private let defaults: UserDefaults

    public init(_ defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var newPlaylistsOnServer: Bool { defaults.object(forKey: Self.newPlaylistsKey) as? Bool ?? false }

    public func setNewPlaylistsOnServer(_ on: Bool) { defaults.set(on, forKey: Self.newPlaylistsKey) }

    public var syncQueue: Bool { defaults.object(forKey: Self.syncQueueKey) as? Bool ?? true }

    public func setSyncQueue(_ on: Bool) { defaults.set(on, forKey: Self.syncQueueKey) }
}
