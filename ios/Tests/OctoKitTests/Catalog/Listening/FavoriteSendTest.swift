import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import OctoKit

/// A favorite album or artist made on the phone, as it reaches a server: always a local stand-in,
/// never a real one.
@Suite struct FavoriteSendTest {
    let server = ListeningStub()
    let source = "server:music.example"

    func client() -> SubsonicClient {
        SubsonicClient(baseURL: server.base, credentials: Credentials(username: "winters", password: "secret"),
                       device: DeviceIdentity(id: "test", name: "Test"), appVersion: "test",
                       session: URLSession(configuration: server.configuration))
    }

    func ok() { server.answer(body: #"{"subsonic-response":{"status":"ok","version":"1.16.1"}}"#) }

    func broken() { server.answer(code: 500, body: "") }

    func row(_ native: String) -> String { "\(source):\(native)" }

    /// One try at sending, as the favorites sync makes it: true when it went through.
    func send(_ kind: FavoriteKind, star: Bool, _ ids: [String]) async -> Bool {
        do {
            try await client().favoriteCall(kind, star: star)(ids)
            return true
        } catch {
            return false
        }
    }

    /// A library that is only the server's: every album and artist keeps the server's own id,
    /// with nothing from the phone merged in.
    var albums: [ServerCopy] {
        serverCopiesOf([CopyCount(serverRowId: row("al1"), libraryId: row("al1"), songs: 10)], sourceId: source)
    }

    var artists: [ServerCopy] {
        serverCopiesOf([CopyCount(serverRowId: row("ar1"), libraryId: row("ar1"), songs: 10),
                        CopyCount(serverRowId: row("ar1"), libraryId: row("ar1"), songs: 0)], sourceId: source)
    }

    @Test func aFavoriteAlbumInAServerOnlyLibraryStarsItsAlbumId() async {
        ok()
        let ids = idsToSend(albums, libraryId: row("al1"), liked: true, likedNow: true)
        #expect(ids == ["al1"])
        #expect(await send(.album, star: true, ids))
        let request = server.takeRequest()
        #expect(request.path == "/rest/star")
        #expect(request.query("albumId") == ["al1"])
        #expect(request.query("id").isEmpty)
        #expect(request.query("artistId").isEmpty)
    }

    @Test func aFavoriteArtistInAServerOnlyLibraryStarsItsArtistId() async {
        ok()
        let ids = idsToSend(artists, libraryId: row("ar1"), liked: true, likedNow: true)
        #expect(ids == ["ar1"])
        #expect(await send(.artist, star: true, ids))
        let request = server.takeRequest()
        #expect(request.path == "/rest/star")
        #expect(request.query("artistId") == ["ar1"])
        #expect(request.query("id").isEmpty)
        #expect(request.query("albumId").isEmpty)
    }

    @Test func removingAFavoriteUnstarsIt() async {
        ok()
        #expect(await send(.album, star: false, idsToSend(albums, libraryId: row("al1"), liked: false, likedNow: false)))
        let request = server.takeRequest()
        #expect(request.path == "/rest/unstar")
        #expect(request.query("albumId") == ["al1"])
    }

    @Test func aFailedStarIsSentAgain() async {
        broken()
        broken()
        ok()
        let ids = idsToSend(albums, libraryId: row("al1"), liked: true, likedNow: true)
        #expect(await retriedAfterWaits(favoriteRetryWaits, pause: { _ in }) { await send(.album, star: true, ids) })
        #expect(server.requestCount == 3)
        for _ in 0..<3 {
            let request = server.takeRequest()
            #expect(request.path == "/rest/star")
            #expect(request.query("albumId") == ["al1"])
        }
    }

    @Test func afterTheLastTryItIsLeftToTheNextSync() async {
        for _ in 0..<(favoriteRetryWaits.count + 1) { broken() }
        #expect(!(await retriedAfterWaits(favoriteRetryWaits, pause: { _ in }) { await send(.album, star: true, ["al1"]) }))
        #expect(server.requestCount == favoriteRetryWaits.count + 1)
    }

    @Test func aChangeUndoneBeforeItsTurnSendsNothing() {
        // Hearted, then un-hearted before a retry: the newer change owns it.
        #expect(idsToSend(albums, libraryId: row("al1"), liked: true, likedNow: false).isEmpty)
        #expect(idsToSend(albums, libraryId: row("al1"), liked: false, likedNow: true).isEmpty)
    }

    @Test func anAlbumOnlyOnThePhoneSendsNothing() {
        #expect(idsToSend(albums, libraryId: "device:album:3", liked: true, likedNow: true).isEmpty)
    }

    @Test func eachNewTryWaitsItsTurn() async {
        let waits = BatchLog()
        let sent = await retriedAfterWaits(favoriteRetryWaits, pause: { waits.add(["\($0)"]) }) { false }
        #expect(!sent)
        #expect(waits.batches.flatMap { $0 } == ["5000", "30000", "120000"])
    }
}
