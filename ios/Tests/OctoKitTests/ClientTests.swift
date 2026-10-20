import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import OctoKit

@Suite struct ServerAddressTests {
    @Test(arguments: [
        ("192.168.50.21:5274", "http://192.168.50.21:5274"),
        ("music.lan", "http://music.lan"),
        ("music.example.com", "https://music.example.com"),
        ("https://music.example.com/", "https://music.example.com"),
        ("https://music.example.com/rest", "https://music.example.com"),
        ("http://me:secret@10.0.0.2:4533/app", "http://10.0.0.2:4533"),
        ("HTTPS://Music.Example.com/sub/path?x=1", "https://Music.Example.com/sub/path"),
    ])
    func typedAddresses(typed: String, expected: String) {
        #expect(ServerAddress.parse(typed).map(ServerAddress.shown) == expected)
    }

    @Test func nothingTypedIsNoAddress() {
        #expect(ServerAddress.parse("   ") == nil)
        #expect(ServerAddress.parse("ftp://x") == nil)
    }
}

@Suite struct SigningTests {
    let client = SubsonicClient(
        baseURL: URL(string: "https://music.example.com/sub")!,
        credentials: Credentials(username: "sam", password: "p&ss=wörd"),
        device: DeviceIdentity(id: "abc", name: "Sam’s iPhone"),
        appVersion: "0.1.0")

    func query(_ url: URL) -> [String: String] {
        Dictionary(uniqueKeysWithValues: URLComponents(url: url, resolvingAgainstBaseURL: false)!
            .queryItems!.map { ($0.name, $0.value ?? "") })
    }

    @Test func aTokenSignedCall() {
        let url = client.url("getAlbum", [("id", "a b&c")])
        #expect(url.path == "/sub/rest/getAlbum")
        let q = query(url)
        #expect(q["u"] == "sam")
        #expect(q["v"] == "1.16.1")
        #expect(q["c"] == "Octo")
        #expect(q["f"] == "json")
        #expect(q["id"] == "a b&c")
        #expect(q["s"]?.count == 16)
        #expect(q["t"] == MD5.hex("p&ss=wörd" + q["s"]!))
        #expect(q["p"] == nil)
    }

    @Test func everyCallHasItsOwnSalt() {
        #expect(query(client.url("ping"))["s"] != query(client.url("ping"))["s"])
    }

    @Test func theLegacyPasswordIsHex() {
        let legacy = client.with(Credentials(username: "sam", password: "ab", mode: .legacyPassword))
        #expect(query(legacy.url("ping"))["p"] == "enc:6162")
    }

    @Test func deviceHeaders() {
        #expect(client.headers["X-Octo-Device-Id"] == "abc")
        #expect(client.headers["X-Octo-Device-Name"] == "Sam%E2%80%99s%20iPhone")
        #expect(client.headers["User-Agent"] == "Octo/0.1.0 (iPhone)")
    }

    /// The server reads the app and the platform from the User-Agent, as Android's
    /// "Octo/1.9.0 (Android)": every request names the iPhone, a stream too.
    @Test func everyRequestNamesTheAppAndTheIPhone() {
        #expect(octoUserAgent("1.9.0") == "Octo/1.9.0 (iPhone)")
        let flac = Song(id: "1", title: "", suffix: "flac")
        #expect(client.request(client.streamURL(for: flac, quality: .original)).value(forHTTPHeaderField: "User-Agent")
            == "Octo/0.1.0 (iPhone)")
        #expect(client.request(client.url("ping")).value(forHTTPHeaderField: "User-Agent") == "Octo/0.1.0 (iPhone)")
        let configuration = URLSessionConfiguration.ephemeral.namingOcto("1.9.0")
        #expect(configuration.httpAdditionalHeaders?["User-Agent"] as? String == "Octo/1.9.0 (iPhone)")
    }

    @Test func streamsAskForWhatThePhoneCanPlay() {
        let flac = Song(id: "1", title: "", suffix: "flac")
        let opus = Song(id: "2", title: "", suffix: "opus")
        #expect(query(client.streamURL(for: flac, quality: .original))["format"] == "raw")
        let converted = query(client.streamURL(for: opus, quality: .original))
        #expect(converted["format"] == "mp3")
        #expect(converted["maxBitRate"] == "320")
        #expect(query(client.streamURL(for: flac, quality: .mp3(kbps: 192)))["maxBitRate"] == "192")
    }

    @Test func coversComeInTheSharedSizes() {
        #expect(query(client.coverURL("al-1", size: 200))["size"] == "300")
        #expect(query(client.coverURL("al-1", size: 5000))["size"] == "1200")
    }
}

@Suite struct DecodingTests {
    @Test func anAlbumWithItsSongs() throws {
        let json = """
        {"subsonic-response":{"status":"ok","version":"1.16.1","type":"octo","openSubsonic":true,
         "album":{"id":"al-1","name":"Blond","artist":"Frank Ocean","songCount":2,"duration":400,"year":2016,
          "song":[{"id":"s1","title":"Nikes","duration":314,"track":1,"suffix":"flac"},
                  {"id":42,"title":"Ivy","duration":"249","isExternal":true}]}}}
        """
        let album: Album = try SubsonicClient.decode(Data(json.utf8), key: "album")
        #expect(album.name == "Blond")
        #expect(album.song.map(\.id) == ["s1", "42"])
        #expect(album.song[1].duration == 249)
        #expect(album.song[1].isExternal)
    }

    @Test func pingIsTheWholeAnswer() throws {
        let json = #"{"subsonic-response":{"status":"ok","version":"1.16.1","type":"octo","serverVersion":"2026.10.11","openSubsonic":true}}"#
        let info: ServerInfo = try SubsonicClient.decode(Data(json.utf8), key: nil)
        #expect(ServerProfile(info: info, extensions: []).isOcto)
        #expect(info.serverVersion == "2026.10.11")
    }

    @Test func aWrongPassword() {
        let json = #"{"subsonic-response":{"status":"failed","version":"1.16.1","error":{"code":40,"message":"Wrong username or password"}}}"#
        #expect(throws: OctoError.wrongCredentials("Wrong username or password")) {
            let _: ServerInfo = try SubsonicClient.decode(Data(json.utf8), key: nil)
        }
    }

    @Test func notAMusicServer() {
        #expect(throws: OctoError.notSubsonic) {
            let _: ServerInfo = try SubsonicClient.decode(Data("<html>".utf8), key: nil)
        }
    }

    @Test func playsCountAtHalfOrFourMinutes() {
        #expect(!PlayRules.countsAsPlay(played: 20, duration: 25))
        #expect(PlayRules.countsAsPlay(played: 60, duration: 120))
        #expect(!PlayRules.countsAsPlay(played: 59, duration: 120))
        #expect(PlayRules.countsAsPlay(played: 240, duration: 900))
    }
}

@Suite struct LyricsTests {
    @Test func lrcLinesWithSeveralStamps() {
        let lyrics = Lrc.parse("[ar:Someone]\n[00:01.50]one\n[00:03.00][00:05.25]two\n")
        #expect(lyrics.synced)
        #expect(lyrics.line.map(\.start) == [1500, 3000, 5250])
        #expect(lyrics.line.map(\.value) == ["one", "two", "two"])
        #expect(lyrics.lineIndex(at: 3.1) == 1)
    }

    @Test func aPositiveOffsetShowsTheWordsSooner() {
        let lyrics = Lrc.parse("[offset:500]\n[00:02.00]late")
        #expect(lyrics.lineIndex(at: 1.6) == 0)
        #expect(lyrics.lineIndex(at: 1.4) == nil)
    }
}
