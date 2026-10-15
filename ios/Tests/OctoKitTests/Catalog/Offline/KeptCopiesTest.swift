import Foundation
import Testing
@testable import OctoKit

/// Whether a copy kept on the phone is still of the file the server has under the song's id.
@Suite struct KeptCopiesTest {
    @Test func aCopyOfTheFileTheServerHasStays() {
        #expect(checkKeptCopy(keptFor: 31_000_000, serverSize: 31_000_000, copySize: 9_000_000, asIs: false) == .keep)
    }

    @Test func aCopyOfAFileTheServerSwappedIsFetchedAgain() {
        // The same id, a new file: a live take swapped for the studio one.
        #expect(checkKeptCopy(keptFor: 31_000_000, serverSize: 28_500_000, copySize: 31_000_000, asIs: true) == .refetch)
        #expect(checkKeptCopy(keptFor: 31_000_000, serverSize: 28_500_000, copySize: 9_000_000, asIs: false) == .refetch)
    }

    @Test func anOlderCopyOfTheFileAsItIsIsCheckedByItsOwnSize() {
        #expect(checkKeptCopy(keptFor: nil, serverSize: 31_000_000, copySize: 31_000_000, asIs: true) == .note)
        #expect(checkKeptCopy(keptFor: nil, serverSize: 28_500_000, copySize: 31_000_000, asIs: true) == .refetch)
        // A copy cut short never matches.
        #expect(checkKeptCopy(keptFor: nil, serverSize: 28_500_000, copySize: -1, asIs: true) == .refetch)
    }

    @Test func anOlderSmallerCopyIsTakenAsItIs() {
        // A smaller copy's size says nothing about the file it came from.
        #expect(checkKeptCopy(keptFor: nil, serverSize: 31_000_000, copySize: 7_000_000, asIs: false) == .note)
    }

    @Test func aSongWithNoSizeKeepsItsCopy() {
        #expect(checkKeptCopy(keptFor: 31_000_000, serverSize: nil, copySize: 31_000_000, asIs: true) == .keep)
        #expect(checkKeptCopy(keptFor: nil, serverSize: 0, copySize: 5, asIs: true) == .keep)
        // A noted size of nothing counts as none noted.
        #expect(checkKeptCopy(keptFor: 0, serverSize: 31_000_000, copySize: 31_000_000, asIs: true) == .note)
    }

    func done(_ format: String?, _ sizeBytes: Int64, fileSize: Int64?, serverSize: Int64?,
              serverType: String? = "audio/flac") -> DownloadedFile {
        DownloadedFile(sourceId: "server:a", serverId: "tr-1", format: format, sizeBytes: sizeBytes, fileSize: fileSize,
                       serverSize: serverSize, serverType: serverType)
    }

    @Test func aDownloadOfASwappedFileDownloadsAgain() {
        #expect(checkDownload(done("audio/flac", 31_000_000, fileSize: 31_000_000, serverSize: 31_000_000)) == .keep)
        #expect(checkDownload(done("audio/flac", 31_000_000, fileSize: 31_000_000, serverSize: 28_500_000)) == .refetch)
        #expect(checkDownload(done("audio/mpeg", 7_000_000, fileSize: 31_000_000, serverSize: 28_500_000)) == .refetch)
    }

    @Test func anOlderDownloadIsCheckedByItsSizeWhenItIsTheFileAsItIs() {
        #expect(checkDownload(done("audio/flac", 31_000_000, fileSize: nil, serverSize: 31_000_000)) == .note)
        #expect(checkDownload(done("audio/flac", 31_000_000, fileSize: nil, serverSize: 28_500_000)) == .refetch)
        // An MP3 may be the file as it is or a smaller copy: nothing tells.
        #expect(checkDownload(done("audio/mpeg", 7_000_000, fileSize: nil, serverSize: 9_000_000, serverType: "audio/mpeg")) == .note)
        #expect(checkDownload(done("audio/mpeg", 7_000_000, fileSize: nil, serverSize: 31_000_000)) == .note)
        // A server song with no size keeps its download.
        #expect(checkDownload(done("audio/flac", 31_000_000, fileSize: nil, serverSize: nil)) == .keep)
    }

    func song(_ nativeId: String, size: Int64?, mime: String = "audio/flac") -> SourceTrack {
        SourceTrack(id: "server:a:\(nativeId)", sourceId: "server:a", nativeId: nativeId, title: nativeId, searchKey: nativeId,
                    sortKey: nativeId, artist: "", artistId: "", album: "", albumId: "", durationMs: 0, addedAt: 0, mimeType: mime,
                    sizeBytes: size)
    }

    func waiting(_ nativeId: String) -> KeptDownload {
        KeptDownload(trackId: "server:a:\(nativeId)", sourceId: "server:a", serverId: nativeId, addedAt: 0, reason: DownloadReasons.manual,
                     title: nativeId, artist: "")
    }

    @Test func aFinishedDownloadNotesTheServersFileSize() async throws {
        let store = try CatalogStore(path: ":memory:")
        try await store.replaceSource("server:a", tracks: [song("tr-1", size: 31_000_000), song("tr-2", size: 9_000_000)],
                                      albums: [], artists: [])
        try await store.upsertDownloads([waiting("tr-1"), waiting("tr-2")])
        try await store.finishDownload("server:a", "tr-1", path: "/d/1.flac", size: 31_000_000, format: "audio/flac", fileSize: 31_000_000)
        try await store.finishDownload("server:a", "tr-2", path: "/d/2.flac", size: 9_000_000, format: "audio/flac", fileSize: nil)
        let files = try await store.doneFiles("server:a").sorted { $0.serverId < $1.serverId }
        #expect(files.map(\.fileSize) == [31_000_000, nil])
        #expect(files.map(\.serverSize) == [31_000_000, 9_000_000])
        #expect(files.map(checkDownload) == [.keep, .note])
        try await store.noteDownloadFileSize("server:a", "tr-2", fileSize: 9_000_000)
        #expect(try await store.download("server:a", "tr-2")?.fileSize == 9_000_000)
        // The server swaps the first song's file: its download is checked against the new size.
        try await store.replaceSource("server:a", tracks: [song("tr-1", size: 28_500_000), song("tr-2", size: 9_000_000)],
                                      albums: [], artists: [])
        let after = try await store.doneFiles("server:a").sorted { $0.serverId < $1.serverId }
        #expect(after.map(checkDownload) == [.refetch, .keep])
        // Downloads still waiting are not checked.
        try await store.setDownloadState("server:a", "tr-1", state: .queued, progress: 0)
        #expect(try await store.doneFiles("server:a").map(\.serverId) == ["tr-2"])
    }

    @Test func aLibraryFromBeforeSizesWereNotedGainsTheColumn() async throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("octo-kept-\(UUID().uuidString).sqlite").path
        defer { try? FileManager.default.removeItem(atPath: path) }
        do {
            let old = try SQLiteDatabase(path: path)
            try old.execute("""
                CREATE TABLE download (
                    trackId TEXT NOT NULL, sourceId TEXT NOT NULL, serverId TEXT NOT NULL, path TEXT NOT NULL,
                    sizeBytes INTEGER NOT NULL, format TEXT, state TEXT NOT NULL, progress REAL NOT NULL, addedAt INTEGER NOT NULL,
                    reason TEXT NOT NULL, title TEXT NOT NULL, artist TEXT NOT NULL, PRIMARY KEY(sourceId, serverId));
                INSERT INTO download VALUES ('t', 'server:a', 'tr-1', '/d/1.flac', 10, 'audio/flac', 'Done', 1, 0, 'manual', 'One', '');
                """)
            old.userVersion = 1
        }
        let store = try CatalogStore(path: path)
        let kept = try await store.download("server:a", "tr-1")
        #expect(kept?.path == "/d/1.flac")
        #expect(kept?.fileSize == nil)
        try await store.noteDownloadFileSize("server:a", "tr-1", fileSize: 10)
        #expect(try await store.download("server:a", "tr-1")?.fileSize == 10)
    }
}
