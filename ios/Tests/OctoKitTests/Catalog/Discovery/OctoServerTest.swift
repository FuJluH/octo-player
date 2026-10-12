import Foundation
import Testing
@testable import OctoKit

@Suite struct OctoServerTest {
    @Test func octoAwayFromHomeIsKnownByItsExtensions() {
        #expect(isOctoServer(probed: false, serverType: "navidrome", extensions: ["octoAcquisitions:1"]))
        #expect(isOctoServer(probed: false, serverType: "navidrome", extensions: ["octoLyrics:1"]))
    }

    @Test func octoAtHomeIsKnownByItsStatusPage() {
        #expect(isOctoServer(probed: true, serverType: "navidrome", extensions: [String]()))
    }

    @Test func aServerCallingItselfOctoIsOcto() {
        #expect(isOctoServer(probed: false, serverType: "Octo", extensions: [String]()))
    }

    @Test func plainNavidromeIsNotOcto() {
        let navidrome = ["songLyrics:1", "transcodeOffset:1", "formPost:1", "apiKeyAuthentication:1"]
        #expect(!isOctoServer(probed: false, serverType: "navidrome", extensions: navidrome))
        #expect(!isOctoServer(probed: false, serverType: nil, extensions: [String]()))
    }

    @Test func aKeptServerRunsOctoByTheSameRule() throws {
        let address = try #require(URL(string: "https://music.example.com"))
        #expect(StoredServer(address: address, username: "me", serverType: "navidrome", extensions: ["octoLists:1"]).runsOcto)
        #expect(StoredServer(address: address, username: "me", isOcto: true).runsOcto)
        #expect(!StoredServer(address: address, username: "me", serverType: "navidrome", extensions: ["songLyrics:1"]).runsOcto)
    }
}
