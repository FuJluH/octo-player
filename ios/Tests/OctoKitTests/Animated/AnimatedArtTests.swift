import Foundation
import Testing
@testable import OctoKit

@Suite struct AnimatedArtTests {
    let server = FakeServer()

    private func client(_ path: String = "") -> SubsonicClient {
        let base = path.isEmpty ? server.base : server.base.appendingPathComponent(path)
        return SubsonicClient(baseURL: base, credentials: Credentials(username: "winters", password: "secret"),
                              device: DeviceIdentity(id: "test-device", name: "Test phone"), appVersion: "1.0",
                              session: FakeServer.session)
    }

    @Test func bothClipsComeBackWithWholeAddresses() async {
        server.ok(#""animatedArt":{"square":{"video":"https://mvod.itunes.apple.com/a/square.m3u8","poster":"https://is1.mzstatic.com/a/1200x1200.jpg","color":"1a0904","width":3840,"height":3840},"tall":{"video":"https://mvod.itunes.apple.com/a/tall.m3u8","width":2048,"height":2732}}"#)
        guard case .found(let art) = await client().animatedArt("al-1") else {
            Issue.record("no art")
            return
        }
        #expect(art.square?.video == "https://mvod.itunes.apple.com/a/square.m3u8")
        #expect(art.square?.colorRgb == 0x1a0904)
        #expect(art.tall?.poster == nil)
        #expect(art.tall?.colorRgb == nil)
        #expect(art.tall?.height == 2732)

        let request = server.requests[0]
        #expect(request.path == "/rest/getAnimatedArt")
        #expect(request.query["id"] == "al-1")
    }

    @Test func relayedClipsArePutUnderTheServersOwnPath() async {
        server.ok(#""animatedArt":{"square":{"video":"animated/tok/square.m3u8","poster":"animated/tok/square.jpg","width":1,"height":1}}"#)
        guard case .found(let art) = await client("octo/").animatedArt("al-1") else {
            Issue.record("no art")
            return
        }
        #expect(art.square?.video == "https://\(server.host)/octo/animated/tok/square.m3u8")
        #expect(art.square?.poster == "https://\(server.host)/octo/animated/tok/square.jpg")
    }

    @Test func noFieldMeansTheAlbumHasNone() async {
        server.ok()
        #expect(await client().animatedArt("al-1") == .none)
    }

    @Test func anEmptyFieldMeansTheAlbumHasNone() async {
        server.ok(#""animatedArt":{}"#)
        #expect(await client().animatedArt("al-1") == .none)
    }

    @Test func offIsToldApartFromAnOutage() async {
        server.error(0, "Animated art is off on this server")
        #expect(await client().animatedArt("al-1") == .off)
        server.error(0, "Apple Music could not be asked just now; try again later")
        #expect(await client().animatedArt("al-1") == .notNow)
    }

    @Test func anUnknownAlbumHasNone() async {
        server.error(70, "Album not found")
        #expect(await client().animatedArt("al-1") == .none)
    }

    @Test func anUnreachableServerIsAskedAgainLater() async {
        server.enqueue(status: 502, "Bad gateway")
        #expect(await client().animatedArt("al-1") == .notNow)
        server.close()
        #expect(await client().animatedArt("al-1") == .notNow)
    }

    @Test func getAlbumCarriesTheFieldResolved() async throws {
        server.ok(#""album":{"id":"al-1","name":"Short n' Sweet","animatedArt":{"square":{"video":"animated/tok/square.m3u8","width":1,"height":1}},"song":[]}"#)
        let album = try await client().album("al-1")
        #expect(album.animatedArt?.square?.video == "https://\(server.host)/animated/tok/square.m3u8")
    }

    @Test func getAlbumWithoutTheFieldSaysNothing() async throws {
        server.ok(#""album":{"id":"al-1","name":"Short n' Sweet","song":[]}"#)
        #expect(try await client().album("al-1").animatedArt == nil)
    }

    @Test func getAlbumWithAnEmptyFieldSaysNothing() async throws {
        server.ok(#""album":{"id":"al-1","name":"Short n' Sweet","animatedArt":{"square":{"video":" "}},"song":[]}"#)
        #expect(try await client().album("al-1").animatedArt == nil)
    }

    @Test func addressesResolveUnderAnyBase() {
        let bare = URL(string: "https://music.example.com")!
        let pathed = URL(string: "https://music.example.com/octo")!
        #expect(resolveArtAddress("animated/t/tall.m3u8", base: bare)?.absoluteString == "https://music.example.com/animated/t/tall.m3u8")
        #expect(resolveArtAddress("/animated/t/tall.m3u8", base: pathed)?.absoluteString == "https://music.example.com/octo/animated/t/tall.m3u8")
        #expect(resolveArtAddress("https://cdn.example.com/x.m3u8", base: pathed)?.absoluteString == "https://cdn.example.com/x.m3u8")
        #expect(resolveArtAddress("animated/t/tall.m3u8?k=1", base: bare)?.absoluteString == "https://music.example.com/animated/t/tall.m3u8?k=1")
        #expect(resolveArtAddress("ftp://cdn.example.com/x.m3u8", base: bare) == nil)
        #expect(resolveArtAddress("  ", base: bare) == nil)
    }

    @Test func aClipDecodesLeniently() throws {
        let clip = try JSONDecoder().decode(AnimatedClip.self, from: Data(##"{"video":"v.m3u8","width":"486","height":486.0,"color":"#FFAA00"}"##.utf8))
        #expect(clip.width == 486)
        #expect(clip.height == 486)
        #expect(clip.colorRgb == 0xFFAA00)
        #expect(AnimatedClip(color: "12345").colorRgb == nil)
        #expect(AnimatedClip(color: "zzzzzz").colorRgb == nil)
        #expect(AnimatedArt(square: AnimatedClip(video: " ")).isEmpty)
        #expect(!AnimatedArt(tall: AnimatedClip(video: "t.m3u8")).isEmpty)
    }
}
