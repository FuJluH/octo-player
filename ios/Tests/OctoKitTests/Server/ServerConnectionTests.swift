import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import OctoKit

/// Where a server's own headers and certificate may go, which failures count as not
/// connecting, and the music folder every library call carries.
@Suite struct ServerConnectionTests {
    let main = URL(string: "https://music.example.com/octo")!
    let home = URL(string: "http://192.168.1.20:4533")!

    @Test func anOriginIsSchemeHostAndPort() {
        #expect(ServerAddress.origin(URL(string: "https://Music.Example.com/rest/ping")!) == "https://music.example.com:443")
        #expect(ServerAddress.origin(URL(string: "http://music.example.com")!) == "http://music.example.com:80")
        #expect(ServerAddress.origin(URL(string: "http://192.168.1.20:4533/x")!) == "http://192.168.1.20:4533")
        #expect(ServerAddress.origin(URL(string: "music.example.com")!) == nil)
    }

    @Test func theScopeCoversOnlyTheServersOwnAddresses() {
        let scope = ServerScope([main, home])
        #expect(scope.covers(URL(string: "https://music.example.com:443/rest/stream")!))
        #expect(scope.covers(URL(string: "http://192.168.1.20:4533/rest/ping")!))
        // Another scheme or port is another origin.
        #expect(!scope.covers(URL(string: "http://music.example.com/rest/ping")!))
        #expect(!scope.covers(URL(string: "http://192.168.1.20:4534/rest/ping")!))
        #expect(!scope.covers(URL(string: "https://cdn.example.net/cover.jpg")!))
        #expect(!scope.covers(nil))
        #expect(!ServerScope().covers(main))
    }

    @Test func theCertificateGoesOnlyToTheServersHosts() {
        let scope = ServerScope([main, home])
        #expect(scope.isOwnHost("music.example.com"))
        #expect(scope.isOwnHost("MUSIC.example.com"))
        #expect(scope.isOwnHost("192.168.1.20"))
        #expect(!scope.isOwnHost("other.example.com"))
        #expect(!scope.isOwnHost(nil))
        #expect(!scope.isOwnHost(""))
        #expect(!ServerScope().isOwnHost("music.example.com"))
    }

    @Test func aRedirectElsewhereLosesTheServersHeaders() {
        let scope = ServerScope([main, home])
        let headers = ["X-Proxy-Token": "secret", "X-Octo-Device-Id": "abc", "X-Octo-Device-Name": "Phone",
                       "User-Agent": "Octo/1.0 (iOS)", "Range": "bytes=0-"]
        let first = URL(string: "https://music.example.com/octo/rest/stream")!
        #expect(scope.headersToDrop(headers, to: URL(string: "https://cdn.example.net/file")!, first: first)
            == ["X-Octo-Device-Id", "X-Octo-Device-Name", "X-Proxy-Token"])
        // Staying at the server's own addresses keeps everything.
        #expect(scope.headersToDrop(headers, to: URL(string: "http://192.168.1.20:4533/rest/stream")!, first: first).isEmpty)
        // Where a request was first sent counts as its own, even with no server in use.
        let join = URL(string: "https://join.example.org/api/join")!
        #expect(ServerScope().headersToDrop(headers, to: URL(string: "https://join.example.org/api/join/2")!, first: join).isEmpty)
        #expect(ServerScope().headersToDrop(headers, to: URL(string: "https://elsewhere.example.org/")!, first: join).count == 3)
    }

    @Test func onlyAFailureToReachCountsAsNotConnecting() {
        for code: URLError.Code in [.cannotConnectToHost, .cannotFindHost, .dnsLookupFailed, .timedOut] {
            #expect(SubsonicError.isConnectionError(URLError(code)))
        }
        for code: URLError.Code in [.notConnectedToInternet, .networkConnectionLost, .cancelled, .badServerResponse,
                                    .serverCertificateUntrusted] {
            #expect(!SubsonicError.isConnectionError(URLError(code)))
        }
    }

    @Test func aScanTimeWithNoZoneCannotBeRead() {
        let now: Int64 = 1_790_683_200_000 // 2026-09-29 12:00 UTC
        let utc = TimeZone(identifier: "UTC")!
        let noZone: ServerScanStatus = decoded(#"{"scanning":false,"count":0,"lastScan":"2026-09-29T09:00:00"}"#)
        #expect(scanWords(noZone, nowMs: now, zone: utc) == nil)
        let offset: ServerScanStatus = decoded(#"{"scanning":false,"count":0,"lastScan":"2026-09-29T11:00:00+02:00"}"#)
        #expect(scanWords(offset, nowMs: now, zone: utc) == "Last read its folders 3 hours ago.")
        let junk: ServerScanStatus = decoded(#"{"scanning":false,"count":0,"lastScan":"yesterday"}"#)
        #expect(scanWords(junk, nowMs: now, zone: utc) == nil)
    }

    @Test func theChosenFolderTravelsWithTheClient() {
        let server = FakeServer()
        let limited = server.client().limited(to: "3")
        #expect(limited.musicFolderId == "3")
        #expect(limited.at(URL(string: "http://192.168.1.20:4533")!).musicFolderId == "3")
        #expect(limited.with(Credentials(username: "sam", password: "new")).musicFolderId == "3")
        #expect(limited.limited(to: nil).musicFolderId == nil)
        #expect(server.client().musicFolderId == nil)
    }

    @Test func everyLibraryCallCarriesTheChosenFolder() async {
        let server = FakeServer()
        let client = server.client().limited(to: "3")
        _ = try? await client.albumList(.newest)
        _ = try? await client.artists()
        _ = try? await client.search("nightcall")
        _ = try? await client.folderTop()
        _ = try? await client.fullArtists()
        _ = try? await client.fullAlbumPage(size: 10, offset: 0)
        _ = try? await client.songPage(size: 10, offset: 0)
        let sent = server.requests
        #expect(sent.map(\.endpoint) == ["getAlbumList2", "getArtists", "search3", "getIndexes", "getArtists", "getAlbumList2", "search3"])
        #expect(sent.allSatisfy { $0.query["musicFolderId"] == "3" })
    }

    @Test func noFolderMeansNoneIsSent() async {
        let server = FakeServer()
        let client = server.client()
        _ = try? await client.albumList(.newest)
        _ = try? await client.artists()
        _ = try? await client.search("nightcall")
        _ = try? await client.folderTop()
        #expect(server.requests.count == 4)
        #expect(server.requests.allSatisfy { $0.query["musicFolderId"] == nil })
    }

    @Test func aFolderAskedForWinsOverTheClients() async {
        let server = FakeServer()
        _ = try? await server.client().limited(to: "3").fullAlbumPage(size: 10, offset: 0, folder: "7")
        #expect(server.requests.first?.query["musicFolderId"] == "7")
    }
}
