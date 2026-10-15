import Foundation
import Testing
@testable import OctoKit

/// Opening a library database written by a newer Octo.
@Suite struct SchemaVersionTests {
    private func tempPath() -> String {
        FileManager.default.temporaryDirectory.appendingPathComponent("schema-\(UUID().uuidString).sqlite").path
    }

    private func tables(_ db: SQLiteDatabase) throws -> [String] {
        try db.strings("SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name")
    }

    @Test func aVersionTwoFileOpenedByAVersionOneSchemaIsLeftAsItIs() throws {
        let path = tempPath()
        defer { for end in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: path + end) } }
        do {
            let db = try SQLiteDatabase(path: path)
            try db.execute("CREATE TABLE marker (x INTEGER); INSERT INTO marker VALUES (7);")
            db.userVersion = 2
        }
        do {
            let db = try SQLiteDatabase(path: path)
            #expect(throws: NewerCatalogFile(found: 2, known: 1)) {
                try Schema.open(db, version: 1, migrations: [:])
            }
        }
        let reopened = try SQLiteDatabase(path: path)
        #expect(reopened.userVersion == 2)
        #expect(try tables(reopened) == ["marker"])
        #expect(try reopened.scalar("SELECT x FROM marker") == 7)
    }

    @Test func theStoreThrowsForANewerFileSoTheAppOpensAFreshOne() throws {
        let path = tempPath()
        defer { for end in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: path + end) } }
        do {
            let db = try SQLiteDatabase(path: path)
            db.userVersion = Schema.version + 1
        }
        #expect(throws: NewerCatalogFile(found: Schema.version + 1, known: Schema.version)) {
            _ = try CatalogStore(path: path)
        }
        #expect(try SQLiteDatabase(path: path).userVersion == Schema.version + 1)
    }
}
