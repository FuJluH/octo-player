import Foundation
import Testing
@testable import OctoKit

/// The two server sync choices live under one key each, the one PlaylistSync and the Server
/// page write and backups read.
@Suite struct ServerSyncChoicesTests {
    func defaults() -> (UserDefaults, String) {
        let name = "octo-test-" + UUID().uuidString
        return (UserDefaults(suiteName: name) ?? .standard, name)
    }

    @Test func eachChoiceHasOneKeyLaidOutLikeTheSmallStores() {
        #expect(ServerSyncChoices.newPlaylistsKey == "playlist_sync.new_on_server")
        #expect(ServerSyncChoices.syncQueueKey == "server_queue.sync_on")
        #expect(storeKey("playlist_sync", "linked_by", account: "a1") == "playlist_sync.linked_by@a1")
    }

    @Test func theBackupReadsWhatPlaylistSyncWrote() {
        let (store, name) = defaults()
        defer { store.removePersistentDomain(forName: name) }
        let choices = ServerSyncChoices(store)
        #expect(!choices.newPlaylistsOnServer)
        #expect(choices.syncQueue)
        // PlaylistSync keeps its choice through its small store, under this same key.
        store.set(true, forKey: storeKey(ServerSyncChoices.playlistsStore, ServerSyncChoices.playlistsName))
        #expect(ServerSyncChoices(store).newPlaylistsOnServer)
    }

    @Test func aRestoreLandsWherePlaylistSyncReads() {
        let (store, name) = defaults()
        defer { store.removePersistentDomain(forName: name) }
        let choices = ServerSyncChoices(store)
        choices.setNewPlaylistsOnServer(true)
        choices.setSyncQueue(false)
        #expect(store.object(forKey: "playlist_sync.new_on_server") as? Bool == true)
        #expect(store.object(forKey: "server_queue.sync_on") as? Bool == false)
        #expect(!ServerSyncChoices(store).syncQueue)
    }
}
