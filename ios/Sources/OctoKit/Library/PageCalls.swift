import Foundation

// The server calls behind the library pages' folders and the actions an Octo server takes on its
// files.

/// A folder on the server, as its folder calls list it.
public struct ServerFolderRef: Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var coverArt: String?
    public var songCount: Int?

    public init(id: String, name: String, coverArt: String? = nil, songCount: Int? = nil) {
        self.id = id
        self.name = name
        self.coverArt = coverArt
        self.songCount = songCount
    }
}

/// One folder's insides: the folders in it and its songs, in the server's order.
public struct ServerFolderListing: Sendable {
    public var folders: [ServerFolderRef]
    public var songs: [Song]

    public init(folders: [ServerFolderRef], songs: [Song]) {
        self.folders = folders
        self.songs = songs
    }
}

/// What the server lets the signed-in user do to the library's files.
public struct FileActions: Decodable, Sendable, Equatable {
    public var enabled: Bool
    public var allowed: Bool
    public var dryRun: Bool
    public var actions: [String]
    public var keepDays: Int
    public var upgradeSource: String?
    public var admin: Bool

    enum CodingKeys: String, CodingKey { case enabled, allowed, dryRun, actions, keepDays, upgradeSource, admin }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = c.bool(.enabled) ?? false
        allowed = c.bool(.allowed) ?? false
        dryRun = c.bool(.dryRun) ?? true
        actions = (try? c.decodeIfPresent([String].self, forKey: .actions)) ?? []
        keepDays = c.int(.keepDays) ?? 0
        upgradeSource = c.string(.upgradeSource)
        admin = c.bool(.admin) ?? true
    }

    public init(enabled: Bool = false, allowed: Bool = false, dryRun: Bool = true, actions: [String] = [], keepDays: Int = 0,
                upgradeSource: String? = nil, admin: Bool = true) {
        self.enabled = enabled
        self.allowed = allowed
        self.dryRun = dryRun
        self.actions = actions
        self.keepDays = keepDays
        self.upgradeSource = upgradeSource
        self.admin = admin
    }

    private var real: Bool { enabled && allowed && admin && !dryRun }
    public var canRemove: Bool { real && actions.contains("remove") }
    public var canRestore: Bool { real && actions.contains("restore") }
    public var canEdit: Bool { real && actions.contains("retag") && actions.contains("undo") }
    public var canJoinAlbums: Bool { real && actions.contains("joinAlbum") }
    public var canLookUp: Bool { real && actions.contains("lookup") }
    public var canAddCover: Bool { real && actions.contains("cover") }
    public var canUpgrade: Bool { enabled && allowed && !dryRun && actions.contains("upgrade") }
}

/// How one file action went, as the server tells it.
public struct FileActionResult: Decodable, Sendable {
    public var id: String
    public var action: String
    public var state: String
    public var detail: String?

    enum CodingKeys: String, CodingKey { case id, action, state, detail }

    public init(id: String, action: String, state: String, detail: String? = nil) {
        self.id = id
        self.action = action
        self.state = state
        self.detail = detail
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.string(.id) ?? ""
        action = c.string(.action) ?? ""
        state = c.string(.state) ?? ""
        detail = c.string(.detail)
    }
}

/// The extension an Octo server lists when it can act on the library's files.
public let fileActionsExtension = "octoLibraryActions"

/// A folder listing's children, split into folders and songs.
private struct DirectoryBody: Decodable {
    let folders: [ServerFolderRef]
    let songs: [Song]

    private struct Child: Decodable {
        let ref: ServerFolderRef?
        let song: Song?

        private enum Keys: String, CodingKey { case isDir, id, title, name, coverArt, songCount }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Keys.self)
            if c.bool(.isDir) == true, let id = c.string(.id) {
                ref = ServerFolderRef(id: id, name: c.string(.title) ?? c.string(.name) ?? "", coverArt: c.string(.coverArt),
                                      songCount: c.int(.songCount))
                song = nil
            } else {
                ref = nil
                song = try? Song(from: decoder)
            }
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        let children = (try? c.decodeIfPresent([Child].self, forKey: AnyKey("child"))) ?? []
        folders = children.compactMap(\.ref)
        songs = children.compactMap(\.song)
    }
}

private struct IndexesBody: Decodable {
    let folders: [ServerFolderRef]
    let songs: [Song]

    private struct Index: Decodable {
        let refs: [ServerFolderRef]
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: AnyKey.self)
            refs = ((try? c.decodeIfPresent([Ref].self, forKey: AnyKey("artist"))) ?? []).compactMap(\.ref)
        }
    }

    private struct Ref: Decodable {
        let ref: ServerFolderRef?
        private enum Keys: String, CodingKey { case id, name, coverArt }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Keys.self)
            ref = c.string(.id).map { ServerFolderRef(id: $0, name: c.string(.name) ?? "", coverArt: c.string(.coverArt)) }
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        let indexes = (try? c.decodeIfPresent([Index].self, forKey: AnyKey("index"))) ?? []
        let loose = try DirectoryBody(from: decoder)
        folders = indexes.flatMap(\.refs) + loose.folders
        songs = loose.songs
    }
}

extension SubsonicClient {
    /// The server's folders from the top: its music folders' indexes, then loose songs.
    public func folderTop() async throws -> ServerFolderListing {
        let body: IndexesBody = try await get("getIndexes", inFolder([], nil), key: "indexes")
        return ServerFolderListing(folders: body.folders, songs: body.songs)
    }

    /// One folder on the server and what it holds.
    public func folder(_ id: String) async throws -> ServerFolderListing {
        let body: DirectoryBody = try await get("getMusicDirectory", [("id", id)], key: "directory")
        return ServerFolderListing(folders: body.folders, songs: body.songs)
    }

    /// What the signed-in user may do to the library's files.
    public func fileActions() async throws -> FileActions {
        try await get("getLibraryActions", key: "libraryActions")
    }

    /// Asks the server to act on one library song's file: "remove" moves it into the server's
    /// trash, "upgrade" queues a look for a lossless copy.
    public func fileAction(_ id: String, action: String, with extra: [(String, String)] = []) async throws -> FileActionResult {
        try await get("libraryAction", [("id", id), ("action", action)] + extra, key: "libraryAction")
    }
}
