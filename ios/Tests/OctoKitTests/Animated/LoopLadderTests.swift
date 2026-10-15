import Foundation
import Testing
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import OctoKit

// Playlists shaped like Apple's (Verified 2026-10-15 on Short n' Sweet).
private let master = """
#EXTM3U
#EXT-X-VERSION:7
#EXT-X-INDEPENDENT-SEGMENTS

#EXT-X-I-FRAME-STREAM-INF:AVERAGE-BANDWIDTH=173473,BANDWIDTH=186220,VIDEO-RANGE=SDR,CODECS="avc1.64001f",RESOLUTION=486x486,URI="https://cdn.example.com/a/trick_486.m3u8"

#EXT-X-STREAM-INF:AVERAGE-BANDWIDTH=2186028,BANDWIDTH=2425166,VIDEO-RANGE=SDR,CLOSED-CAPTIONS=NONE,CODECS="avc1.64001f",FRAME-RATE=24.000,RESOLUTION=768x768,STABLE-VARIANT-ID="a2"
https://cdn.example.com/b/video_768.m3u8
#EXT-X-STREAM-INF:AVERAGE-BANDWIDTH=1578939,BANDWIDTH=1909638,VIDEO-RANGE=SDR,CLOSED-CAPTIONS=NONE,CODECS="hvc1.2.20000000.L123.B0",FRAME-RATE=24.000,RESOLUTION=768x768
https://cdn.example.com/c/video_hevc_768.m3u8
#EXT-X-STREAM-INF:AVERAGE-BANDWIDTH=773877,BANDWIDTH=859244,CODECS="avc1.64001f",FRAME-RATE=24.000,RESOLUTION=486x486
https://cdn.example.com/d/video_486_low.m3u8
#EXT-X-STREAM-INF:AVERAGE-BANDWIDTH=1531650,BANDWIDTH=1702562,CODECS="avc1.64001f",FRAME-RATE=24.000,RESOLUTION=486x486
video_486_high.m3u8
#EXT-X-STREAM-INF:AVERAGE-BANDWIDTH=6788272,BANDWIDTH=7671972,CODECS="avc1.640020",FRAME-RATE=24.000,RESOLUTION=1080x1080
https://cdn.example.com/e/video_1080_top.m3u8
#EXT-X-STREAM-INF:AVERAGE-BANDWIDTH=3952898,BANDWIDTH=4341150,CODECS="avc1.640020",FRAME-RATE=24.000,RESOLUTION=1080x1080
https://cdn.example.com/f/video_1080.m3u8
"""

private let media = """
#EXTM3U
#EXT-X-TARGETDURATION:4
#EXT-X-VERSION:7
#EXT-X-MEDIA-SEQUENCE:0
#EXT-X-PLAYLIST-TYPE:VOD
#EXT-X-INDEPENDENT-SEGMENTS
#EXT-X-MAP:URI="loop-.mp4",BYTERANGE="899@0"
#EXTINF:4.00000,
#EXT-X-BYTERANGE:1875981@899
loop-.mp4
#EXTINF:4.00000,
#EXT-X-BYTERANGE:2007629@1876880
loop-.mp4
#EXT-X-ENDLIST
"""

@Suite struct LoopLadderTests {
    let masterUrl = URL(string: "https://cdn.example.com/m/default.m3u8")!

    private func last(_ variant: LoopVariant?) -> String? { variant?.url.lastPathComponent }

    @Test func theLadderListsEveryVersionButTheStills() {
        let ladder = parseLoopLadder(master, playlistUrl: masterUrl)
        #expect(ladder.count == 6)
        #expect(ladder[3].url.absoluteString == "https://cdn.example.com/m/video_486_high.m3u8")
        #expect(ladder[1].codec == .hevc)
        #expect(ladder[0].width == 768)
        #expect(ladder[0].bandwidth == 2425166)
    }

    @Test func theSmallestVersionThatNeedsNoEnlargingIsPicked() {
        let ladder = parseLoopLadder(master, playlistUrl: masterUrl)
        // A 450 px cover: the better of the two 486 versions.
        #expect(last(pickLoopVariant(ladder, width: 450, height: 450)) == "video_486_high.m3u8")
        // 700 px: the H.264 768, not the HEVC one.
        #expect(last(pickLoopVariant(ladder, width: 700, height: 700)) == "video_768.m3u8")
        // Where HEVC plays, still the best of that size.
        #expect(last(pickLoopVariant(ladder, width: 700, height: 700, codecs: [.avc, .hevc])) == "video_768.m3u8")
        // HEVC alone: the HEVC one.
        #expect(last(pickLoopVariant(ladder, width: 700, height: 700, codecs: [.hevc])) == "video_hevc_768.m3u8")
        // Larger than any: the largest, at the highest rate under the cap.
        #expect(last(pickLoopVariant(ladder, width: 2000, height: 2000)) == "video_1080.m3u8")
        // A tall space on a square loop: covering the height decides.
        #expect(last(pickLoopVariant(ladder, width: 600, height: 900)) == "video_1080.m3u8")
        #expect(pickLoopVariant(ladder, width: 100, height: 100, codecs: []) == nil)
    }

    @Test func overTheCapTheLowestOfThatSizeIsPicked() {
        let url = URL(string: "https://cdn.example.com/x.m3u8")!
        let ladder = [LoopVariant(url: url, bandwidth: 9_000_000, width: 2160, height: 2160, codecs: "avc1.640033"),
                      LoopVariant(url: url.deletingLastPathComponent().appendingPathComponent("y.m3u8"), bandwidth: 7_000_000,
                                  width: 2160, height: 2160, codecs: "avc1.640033")]
        #expect(last(pickLoopVariant(ladder, width: 2000, height: 2000)) == "y.m3u8")
    }

    @Test func attributesKeepQuotedCommas() {
        let found = hlsAttributes(#"BANDWIDTH=1,CODECS="avc1.64001f,mp4a.40.2",RESOLUTION=2x3"#)
        #expect(found["CODECS"] == "avc1.64001f,mp4a.40.2")
        #expect(found["RESOLUTION"] == "2x3")
        #expect(found["BANDWIDTH"] == "1")
    }

    @Test func aVersionKeptInOneFileIsThatFile() throws {
        let playlistUrl = URL(string: "https://cdn.example.com/b/video_768.m3u8")!
        let file = try #require(parseLoopFile(media, playlistUrl: playlistUrl))
        #expect(file.url.absoluteString == "https://cdn.example.com/b/loop-.mp4")
        #expect(abs(file.seconds - 8.0) < 0.001)
        // Parts from two files cannot be kept as one.
        let mixed = media.replacingOccurrences(of: "2007629@1876880\nloop-.mp4", with: "2007629@1876880\nother.mp4")
        #expect(parseLoopFile(mixed, playlistUrl: playlistUrl) == nil)
    }

    @Test func aLoopIsLocatedAndFetchedOnce() async throws {
        let server = FakeServer()
        let body = Data((0..<4096).map { UInt8($0 & 0xFF) })
        let masterHere = master.replacingOccurrences(of: "https://cdn.example.com/d/video_486_low.m3u8", with: "low.m3u8")
        server.route { request in
            switch request.path {
            case "/m/default.m3u8": FakeServer.Reply(status: 200, body: Data(masterHere.utf8))
            case "/m/video_486_high.m3u8": FakeServer.Reply(status: 200, body: Data(media.utf8))
            case "/m/loop-.mp4": FakeServer.Reply(status: 200, body: body, headers: ["Content-Length": "\(body.count)"])
            default: FakeServer.Reply(status: 404, body: Data())
            }
        }
        let fetcher = LoopFetcher(session: FakeServer.session) { url in
            url.host == server.host ? ["X-Token": "abc"] : [:]
        }
        let clip = AnimatedClip(video: server.base.appendingPathComponent("m/default.m3u8").absoluteString)
        let file = try #require(await fetcher.locate(clip, width: 450, height: 450))
        #expect(file.url.absoluteString == "https://\(server.host)/m/loop-.mp4")
        #expect(server.requests.map(\.path) == ["/m/default.m3u8", "/m/video_486_high.m3u8"])
        #expect(server.requests[0].headers["X-Token"] == "abc")

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("loops-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let target = dir.appendingPathComponent("one.mp4")
        #expect(await fetcher.fetch(file, to: target))
        #expect(try Data(contentsOf: target) == body)
        #expect(!FileManager.default.fileExists(atPath: target.path + ".part"))
        // Already there: not fetched again.
        #expect(await fetcher.fetch(file, to: target))
        #expect(server.requestCount == 3)
    }

    @Test func aFailedFetchLeavesNothingBehind() async {
        let server = FakeServer()
        server.enqueue(status: 404, "")
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("loops-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let target = dir.appendingPathComponent("gone.mp4")
        let fetched = await LoopFetcher(session: FakeServer.session).fetch(
            LoopFile(url: server.base.appendingPathComponent("x.mp4"), seconds: 1), to: target)
        #expect(!fetched)
        #expect(!FileManager.default.fileExists(atPath: target.path))
        #expect(!FileManager.default.fileExists(atPath: target.path + ".part"))
    }

    @Test func aPlaylistThatIsNotOneIsRefused() async {
        let server = FakeServer()
        server.enqueue("<html>no</html>")
        let clip = AnimatedClip(video: server.base.appendingPathComponent("m.m3u8").absoluteString)
        #expect(await LoopFetcher(session: FakeServer.session).locate(clip, width: 1, height: 1) == nil)
    }

    @Test func theShelfDropsTheLeastLatelyUsedFirst() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("shelf-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let shelf = LoopShelf(dir: dir, maxBytes: 250)
        func put(_ name: String, _ stamp: TimeInterval) throws -> URL {
            let file = shelf.file(for: URL(string: "https://cdn.example.com/\(name).mp4")!)
            try Data(count: 100).write(to: file)
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: stamp)], ofItemAtPath: file.path)
            return file
        }
        let old = try put("old", 1_000)
        let kept = try put("kept", 2_000)
        let new = try put("new", 3_000)
        shelf.trim(keep: [old])
        #expect(FileManager.default.fileExists(atPath: old.path))
        #expect(!FileManager.default.fileExists(atPath: kept.path))
        #expect(FileManager.default.fileExists(atPath: new.path))
    }

    @Test func offlineLoopsAreNamedByAlbumAndShape() {
        let dir = URL(fileURLWithPath: "/tmp/loops")
        let square = offlineLoopFile(dir: dir, albumId: "al-1", shape: "square")
        #expect(square.lastPathComponent.hasSuffix("-square.mp4"))
        #expect(square.lastPathComponent.count == 32 + "-square.mp4".count)
        #expect(offlineLoopPoster(dir: dir, albumId: "al-1", shape: "tall").lastPathComponent
            == square.lastPathComponent.replacingOccurrences(of: "-square.mp4", with: "-tall.jpg"))
        #expect(offlineLoopFile(dir: dir, albumId: "al-2", shape: "square") != square)
        // The first 16 bytes of the SHA-256 of "abc".
        #expect(loopHash("abc") == "ba7816bf8f01cfea414140de5dae2223")
    }
}
