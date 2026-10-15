import Foundation
import Testing
@testable import OctoKit

@Suite struct ServerControlsTest {
    @Test func expiryIsNowPlusItsLength() {
        let now: Int64 = 1_000_000
        #expect(shareExpiresAt(.never, now: now) == nil)
        #expect(shareExpiresAt(.day, now: now) == now + 86_400_000)
        #expect(shareExpiresAt(.week, now: now) == now + 7 * 86_400_000)
        #expect(shareExpiresAt(.month, now: now) == now + 30 * 86_400_000)
        #expect(ShareExpiry.allCases.map(\.label) == ["Never", "1 day", "1 week", "1 month"])
    }

    @Test func knowsWhenAServerDoesNotShare() {
        #expect(sharingUnavailable(OctoError.server(code: 50, message: "not authorized")))
        #expect(sharingUnavailable(OctoError.notFound("sharing disabled")))
        #expect(sharingUnavailable(OctoError.http(501)))
        #expect(!sharingUnavailable(OctoError.server(code: 0, message: "busy")))
        #expect(!sharingUnavailable(Unreachable()))
        #expect(!sharingUnavailable(OctoError.http(404)))
    }

    @Test func findsTheServerAlbumBehindALibraryAlbum() {
        #expect(serverAlbumIdOf("server:music.example", "server:music.example:al-1") == "al-1")
        // An album made up from loose songs is not on the server.
        #expect(serverAlbumIdOf("server:music.example", "server:music.example:album:some title") == nil)
        // Nor is another source's.
        #expect(serverAlbumIdOf("server:music.example", "device:123") == nil)
    }

    struct Unreachable: Error {}

    struct Listener: Equatable {
        var user: String
        var player: String?
    }

    func listener(_ user: String, _ player: String?) -> Listener { Listener(user: user, player: player) }

    @Test func listeningNowLeavesOutThisPhone() {
        let entries = [listener("winters", "Octo"), listener("winters", "Desktop"), listener("sam", "Octo"), listener("sam", nil)]
        #expect(othersListening(entries, username: "Winters", ourClient: "Octo", user: \.user, player: \.player)
            == [listener("winters", "Desktop"), listener("sam", "Octo"), listener("sam", nil)])
    }

    @Test func octoStationsCarryTheirOwnIdAsCover() {
        #expect(looksGenerated(stationId: "or123", coverArt: "or123", isOcto: true))
        #expect(!looksGenerated(stationId: "or123", coverArt: "or123", isOcto: false))
        #expect(!looksGenerated(stationId: "r1", coverArt: "ra-r1", isOcto: true))
    }

    func copy(_ nativeId: String, source: String = "server:music.example", album: String = "") -> SourceTrack {
        SourceTrack(id: "\(source):\(nativeId)", sourceId: source, nativeId: nativeId, title: "", searchKey: "", sortKey: "",
                    artist: "", artistId: "", album: "", albumId: album, durationMs: 0, addedAt: 0)
    }

    @Test func aSongIsSharedByItsLowestIdOnTheServerInUse() {
        let copies = [copy("tr-9"), copy("tr-2"), copy("tr-1", source: "server:other")]
        #expect(serverSongId(copies: copies, serverInUse: "server:music.example") == "tr-2")
        #expect(serverSongId(copies: copies, serverInUse: "server:none") == nil)
    }

    @Test func anAlbumIsTheOneMostOfItsSongsAreInOnTheServer() {
        let source = "server:music.example"
        let copies = [copy("1", album: "\(source):al-1"), copy("2", album: "\(source):al-2"), copy("3", album: "\(source):al-2"),
                      copy("4", album: "\(source):album:loose"), copy("5", album: "\(source):album:loose"),
                      copy("6", album: "\(source):album:loose"), copy("7", source: "server:other", album: "server:other:al-3")]
        #expect(serverAlbumId(copies: copies, serverInUse: source) == "al-2")
        // Among equals, the first seen.
        #expect(serverAlbumId(copies: Array(copies.prefix(2)), serverInUse: source) == "al-1")
        #expect(serverAlbumId(copies: [], serverInUse: source) == nil)
    }

    @Test func notScanningIsBelievedOnTheSecondAnswerUntilTheScanIsSeen() {
        func answers(started: Bool, _ scanning: [Bool]) -> [Bool] {
            var poll = ServerScanPoll(started: started)
            return scanning.map { poll.isDone(scanning: $0) }
        }
        #expect(answers(started: false, [false, false]) == [false, true])
        #expect(answers(started: false, [false, true, false]) == [false, false, true])
        #expect(answers(started: true, [false]) == [true])
        #expect(answers(started: true, [true, true, false]) == [false, false, true])
        #expect(serverScanPollMs == 2_000)
    }

    @Test func aFailedScanSaysWhy() {
        #expect(serverScanFailedWords(OctoError.server(code: 50, message: "")) == "Only an admin can scan this server.")
        #expect(serverScanFailedWords(OctoError.server(code: 0, message: "")) == "The scan could not start just now.")
        #expect(serverScanFailedWords(Unreachable()) == "The scan could not start just now.")
    }

    @Test func aRefusedStationChangeMarksItReadOnly() {
        #expect(stationChangeRefused(OctoError.notFound("")))
        #expect(stationChangeRefused(OctoError.server(code: 50, message: "")))
        #expect(!stationChangeRefused(OctoError.server(code: 0, message: "")))
        #expect(!stationChangeRefused(OctoError.http(500)))
        let marked = markingReadOnly(["home": ["a"]], account: "home", stations: ["b"])
        #expect(markingReadOnly(marked, account: "work", stations: ["c"]) == ["home": ["a", "b"], "work": ["c"]])
    }
}
