import Foundation

/// What changed in the library database, so pages reading it can read again.
public struct CatalogChange: OptionSet, Sendable, Hashable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    /// The merged library: songs, albums, artists, and what follows them.
    public static let library = CatalogChange(rawValue: 1 << 0)
    public static let likes = CatalogChange(rawValue: 1 << 1)
    public static let ratings = CatalogChange(rawValue: 1 << 2)
    public static let plays = CatalogChange(rawValue: 1 << 3)
    public static let playlists = CatalogChange(rawValue: 1 << 4)
    /// Songs found online and their downloads.
    public static let finds = CatalogChange(rawValue: 1 << 5)
    /// Favorite albums and artists.
    public static let favorites = CatalogChange(rawValue: 1 << 6)
    public static let pins = CatalogChange(rawValue: 1 << 7)
    /// Songs kept on the phone as files.
    public static let downloads = CatalogChange(rawValue: 1 << 8)
    public static let queue = CatalogChange(rawValue: 1 << 9)
    /// What each source has (the copies behind the library).
    public static let sources = CatalogChange(rawValue: 1 << 10)

    public static let all = CatalogChange(rawValue: (1 << 11) - 1)
}

/// The library database: what each source has, the library merged from them, and everything the
/// listener made. One actor owns the connection, so every read and write runs one at a time.
public actor CatalogStore {
    let db: SQLiteDatabase
    private var listeners: [UUID: @Sendable (CatalogChange) -> Void] = [:]
    private var pending: CatalogChange = []
    private var batching = 0

    /// Opens (or makes) the database at `path`; ":memory:" keeps it in memory, for tests.
    public init(path: String) throws {
        db = try SQLiteDatabase(path: path)
        try Schema.open(db)
    }

    /// The database file in the app's support folder.
    public static func defaultPath() -> String {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("catalog.sqlite").path
    }

    /// Calls `listener` (on any thread) after each change. Answers a token for `stopListening`.
    @discardableResult
    public func listen(_ listener: @escaping @Sendable (CatalogChange) -> Void) -> UUID {
        let id = UUID()
        listeners[id] = listener
        return id
    }

    public func stopListening(_ id: UUID) { listeners[id] = nil }

    /// Tells the listeners, or keeps it until the batch running ends.
    func changed(_ change: CatalogChange) {
        guard !change.isEmpty else { return }
        if batching > 0 {
            pending.formUnion(change)
            return
        }
        for listener in listeners.values { listener(change) }
    }

    /// Runs `body` in one transaction and tells the listeners once, at the end.
    func batch<T>(_ body: () throws -> T) throws -> T {
        batching += 1
        defer {
            batching -= 1
            if batching == 0 {
                let change = pending
                pending = []
                changed(change)
            }
        }
        return try db.transaction(body)
    }

    // MARK: Raw reads

    /// Library songs from any query that answers the song table's columns, with an extra text
    /// column `heading` read when the query has one. For list orders built as SQL.
    public func tracks(sql: String, args: [String] = []) throws -> [(track: LibraryTrack, heading: String?)] {
        try db.query(sql, args) { row in (LibraryTrack(row: row), row.has("heading") ? row.optionalString("heading") : nil) }
    }

    /// Library albums from any query that answers the album table's columns, with `heading` as
    /// for `tracks(sql:args:)`.
    public func albums(sql: String, args: [String] = []) throws -> [(album: LibraryAlbum, heading: String?)] {
        try db.query(sql, args) { row in (LibraryAlbum(row: row), row.has("heading") ? row.optionalString("heading") : nil) }
    }

    /// Library artists from any query that answers the artist table's columns, with `heading` as
    /// for `tracks(sql:args:)`.
    public func artists(sql: String, args: [String] = []) throws -> [(artist: LibraryArtist, heading: String?)] {
        try db.query(sql, args) { row in (LibraryArtist(row: row), row.has("heading") ? row.optionalString("heading") : nil) }
    }

    /// Text from a query's first column, such as ids.
    public func strings(sql: String, args: [String] = []) throws -> [String] {
        try db.strings(sql, args)
    }

    /// One number a query answers, such as a count.
    public func count(sql: String, args: [String] = []) throws -> Int {
        Int(try db.scalar(sql, args))
    }
}

/// How many ids go in one lookup, well under what one query can take.
let lookupChunk = 900

/// `?, ?, ?` for a list of values.
func marks(_ count: Int) -> String { Array(repeating: "?", count: count).joined(separator: ", ") }

extension Array {
    /// The list cut into runs of at most `size`.
    func catalogChunks(_ size: Int) -> [ArraySlice<Element>] {
        stride(from: 0, to: count, by: size).map { self[$0..<Swift.min($0 + size, count)] }
    }
}
