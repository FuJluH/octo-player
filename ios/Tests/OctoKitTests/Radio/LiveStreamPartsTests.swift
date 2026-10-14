import Foundation
import Testing
@testable import OctoKit

@Suite struct IcyReaderTests {
    /// One metadata block for `text`, its length byte first, padded to 16 bytes.
    func block(_ text: String) -> Data {
        var bytes = Data(text.utf8)
        let blocks = (bytes.count + 15) / 16
        bytes.append(Data(repeating: 0, count: blocks * 16 - bytes.count))
        return Data([UInt8(blocks)]) + bytes
    }

    func sound(_ count: Int, _ value: UInt8) -> Data { Data(repeating: value, count: count) }

    @Test func soundAndTitlesAreSplit() {
        var reader = IcyReader(interval: 8)
        let stream = sound(8, 1) + block("StreamTitle='Artist - Song';StreamUrl='';") + sound(8, 2) + Data([0]) + sound(3, 3)
        let (out, titles) = reader.feed(stream)
        #expect(out == sound(8, 1) + sound(8, 2) + sound(3, 3))
        #expect(titles == [IcyMeta(title: "Artist - Song")])
    }

    @Test func aBlockCutAcrossReadsStillGivesItsTitle() {
        let stream = sound(5, 1) + block("StreamTitle='Don't Stop';") + sound(5, 2) + block("StreamTitle='Next';") + sound(2, 3)
        // Every way of cutting it, down to one byte at a time.
        for size in [1, 2, 3, 7, 16, 100] {
            var reader = IcyReader(interval: 5)
            var out = Data()
            var titles: [IcyMeta] = []
            var at = 0
            while at < stream.count {
                let piece = stream.subdata(in: at..<min(stream.count, at + size))
                let (s, t) = reader.feed(piece)
                out.append(s)
                titles += t
                at += size
            }
            #expect(out == sound(5, 1) + sound(5, 2) + sound(2, 3), "pieces of \(size)")
            #expect(titles.map(\.title) == ["Don't Stop", "Next"], "pieces of \(size)")
        }
    }

    @Test func anEmptyTitleIsKeptSoTheOldSongClears() {
        var reader = IcyReader(interval: 4)
        let (out, titles) = reader.feed(sound(4, 1) + block("StreamTitle='';") + sound(4, 2) + block("StreamTitle='  ';StreamUrl='x';")
                                        + sound(4, 3) + block("StreamUrl='x';"))
        #expect(out == sound(4, 1) + sound(4, 2) + sound(4, 3))
        // A block with no StreamTitle at all says nothing.
        #expect(titles == [IcyMeta(title: ""), IcyMeta(title: "", url: "x")])
        #expect(!onAir(titles[0]).named)
    }

    @Test func theReaderCarriesTheArtworkAddress() {
        var reader = IcyReader(interval: 4)
        let soma = "StreamTitle='Reef Project - True Clown';StreamUrl='https://somafm.com/logos/512/groovesalad512.jpg';"
        let (_, titles) = reader.feed(sound(4, 1) + block(soma) + sound(4, 2) + block("StreamTitle='GWMR0446000';StreamUrl='';StreamArtwork='';"))
        #expect(titles == [IcyMeta(title: "Reef Project - True Clown", url: "https://somafm.com/logos/512/groovesalad512.jpg"),
                           IcyMeta(title: "GWMR0446000")])
        #expect(onAir(titles[0], station: "Groove Salad") == OnAir("True Clown", "Reef Project", "https://somafm.com/logos/512/groovesalad512.jpg"))
        #expect(!onAir(titles[1], station: "181.FM").named)
    }

    @Test func eachTitleSaysWhereItSatInTheSound() {
        var reader = IcyReader(interval: 4)
        let (out, marks) = reader.feedMarked(sound(4, 1) + block("StreamTitle='A - B';") + sound(4, 2) + block("StreamTitle='C - D';") + sound(2, 3))
        #expect(out.count == 10)
        #expect(marks == [IcyMark(at: 4, meta: IcyMeta(title: "A - B")), IcyMark(at: 8, meta: IcyMeta(title: "C - D"))])
    }

    @Test func titlesWaitForTheSoundBeforeThemToBeRead() {
        var queue = IcyTitleQueue()
        queue.hold(IcyMeta(title: "A - B"), at: 1_000)
        queue.hold(IcyMeta(title: "C - D"), at: 5_000)
        #expect(queue.due(read: 999).isEmpty)
        #expect(queue.due(read: 1_000) == [IcyMeta(title: "A - B")])
        #expect(queue.due(read: 4_000).isEmpty)
        queue.hold(IcyMeta(title: ""), at: 6_000)
        #expect(queue.due(read: 9_000) == [IcyMeta(title: "C - D"), IcyMeta(title: "")])
        #expect(queue.isEmpty)
    }

    @Test func theReaderKeepsQuotesInsideNames() {
        var reader = IcyReader(interval: 2)
        let (_, titles) = reader.feed(sound(2, 1) + block("StreamTitle='AEROSMITH - I DON'T WANNA MISS A THING';") + sound(2, 2))
        #expect(titles == [IcyMeta(title: "AEROSMITH - I DON'T WANNA MISS A THING")])
    }

    @Test func titlesReadAsUtf8OrElseLatin1() {
        #expect(icyMeta(Data("StreamTitle='Beyoncé - Halo';".utf8))?.title == "Beyoncé - Halo")
        #expect(icyMeta(Data([0x53, 0x74, 0x72, 0x65, 0x61, 0x6D, 0x54, 0x69, 0x74, 0x6C, 0x65, 0x3D, 0x27, 0x43, 0x61, 0x66, 0xE9, 0x27, 0x3B]))?.title
                == "Café")
        #expect(icyMeta(Data("StreamTitle='No end".utf8))?.title == "No end")
        #expect(icyMeta(Data("StreamTitle='Padded';".utf8) + Data(repeating: 0, count: 9))?.title == "Padded")
        #expect(icyMeta(Data("StreamUrl='x';".utf8)) == nil)
    }

    @Test func reconnectsWaitLongerEachTime() {
        #expect(liveReconnectDelays == [1, 2, 4, 8])
        #expect(liveStatusRetries(503) && liveStatusRetries(429) && !liveStatusRetries(404) && !liveStatusRetries(403))
        #expect(stationFailureWords(PlayError(.networkConnectionFailed)) == "The station stopped sending and did not come back.")
    }
}

@Suite struct HlsTests {
    let base = URL(string: "https://radio.example/live/master.m3u8")!

    @Test func aMasterPlaylistListsItsStreams() throws {
        let text = """
        #EXTM3U
        #EXT-X-STREAM-INF:BANDWIDTH=64000,CODECS="mp4a.40.5"
        low/index.m3u8
        #EXT-X-STREAM-INF:BANDWIDTH=128000,CODECS="mp4a.40.2"
        https://cdn.example/high.m3u8
        #EXT-X-STREAM-INF:BANDWIDTH=900000,CODECS="avc1.4d401f,mp4a.40.2"
        video.m3u8
        """
        guard case .master(let variants, let audio) = try #require(parseHlsPlaylist(text, base: base)) else {
            Issue.record("not a master playlist")
            return
        }
        #expect(variants.map(\.uri.absoluteString) == ["https://radio.example/live/low/index.m3u8", "https://cdn.example/high.m3u8",
                                                       "https://radio.example/live/video.m3u8"])
        #expect(audio.isEmpty)
        #expect(hlsPickStream(variants, audio: audio)?.absoluteString == "https://cdn.example/high.m3u8")
        #expect(hlsPickStream(Array(variants.suffix(1)), audio: [])?.absoluteString == "https://radio.example/live/video.m3u8")
    }

    @Test func aMediaPlaylistListsItsSegments() throws {
        let text = """
        #EXTM3U
        #EXT-X-TARGETDURATION:10
        #EXT-X-MEDIA-SEQUENCE:120
        #EXTINF:9.98,
        seg120.ts
        #EXTINF:10.0, title
        seg121.ts
        #EXTINF:10,
        seg122.aac
        #EXTINF:10,
        seg123.aac
        """
        guard case .media(let media) = try #require(parseHlsPlaylist(text, base: base)) else {
            Issue.record("not a media playlist")
            return
        }
        #expect(media.targetSeconds == 10 && !media.ended && !media.encrypted && !media.fragmentedMp4)
        #expect(media.segments.map(\.sequence) == [120, 121, 122, 123])
        #expect(media.segments[1].uri.absoluteString == "https://radio.example/live/seg121.ts")
        #expect(hlsNextSegments(media, after: nil).map(\.sequence) == [121, 122, 123])
        #expect(hlsNextSegments(media, after: 122).map(\.sequence) == [123])
        #expect(hlsNextSegments(media, after: 123).isEmpty)
        #expect(hlsNextSegments(media, after: 50).map(\.sequence) == [121, 122, 123])
    }

    @Test func encryptedAndFragmentedPlaylistsAreMarked() throws {
        let text = "#EXTM3U\n#EXT-X-TARGETDURATION:6\n#EXT-X-KEY:METHOD=AES-128,URI=\"k\"\n#EXT-X-MAP:URI=\"init.mp4\"\n#EXTINF:6,\na.m4s\n#EXT-X-ENDLIST\n"
        guard case .media(let media) = try #require(parseHlsPlaylist(text, base: base)) else { return }
        #expect(media.encrypted && media.fragmentedMp4 && media.ended)
        #expect(parseHlsPlaylist("<html>", base: base) == nil)
    }

    @Test func attributesKeepCommasInsideQuotes() {
        #expect(hlsAttributes(#"BANDWIDTH=1,CODECS="avc1,mp4a",NAME=x"#) == ["BANDWIDTH": "1", "CODECS": "avc1,mp4a", "NAME": "x"])
    }

    @Test func packedSoundLosesItsId3Tag() throws {
        let id3 = Data([0x49, 0x44, 0x33, 4, 0, 0, 0, 0, 0, 3]) + Data([1, 2, 3])
        let adts = Data([0xFF, 0xF1, 0x50, 0x80, 0x01, 0x7F, 0xFC])
        let found = try #require(hlsSegmentSound(id3 + adts))
        #expect(found.sound == adts && found.kind == .aac)
        let mp3 = Data([0xFF, 0xFB, 0x90, 0x64])
        #expect(hlsSegmentSound(mp3)?.kind == .mpeg)
        #expect(hlsSegmentSound(Data("ftypiso6".utf8)) == nil)
    }

    /// One transport stream packet on `pid`, its payload padded to fill it.
    func packet(_ pid: Int, start: Bool, _ payload: [UInt8]) -> [UInt8] {
        var bytes: [UInt8] = [0x47, UInt8((start ? 0x40 : 0) | (pid >> 8)), UInt8(pid & 0xFF)]
        let room = 184
        if payload.count < room {
            // An adaptation field of stuffing makes up the difference.
            let fill = room - payload.count - 1
            bytes.append(0x30)
            bytes.append(UInt8(fill))
            if fill > 0 { bytes += [0x00] + [UInt8](repeating: 0xFF, count: fill - 1) }
        } else {
            bytes.append(0x10)
        }
        return bytes + payload
    }

    func transportStream(_ sound: [UInt8], type: UInt8 = 0x0F) -> Data {
        let pat: [UInt8] = [0x00, 0x00, 0xB0, 0x0D, 0x00, 0x01, 0xC1, 0x00, 0x00, 0x00, 0x01, 0xF0, 0x00, 0, 0, 0, 0]
        let pmt: [UInt8] = [0x00, 0x02, 0xB0, 0x12, 0x00, 0x01, 0xC1, 0x00, 0x00, 0xE1, 0x00, 0xF0, 0x00,
                            type, 0xE1, 0x01, 0xF0, 0x00, 0, 0, 0, 0]
        let pes: [UInt8] = [0x00, 0x00, 0x01, 0xC0, 0x00, 0x00, 0x80, 0x80, 0x05, 0x21, 0x00, 0x01, 0x00, 0x01]
        let first = Array(sound.prefix(100))
        let rest = Array(sound.dropFirst(100))
        var bytes = packet(0, start: true, pat) + packet(0x1000, start: true, pmt) + packet(0x101, start: true, pes + first)
        bytes += packet(0x102, start: true, [1, 2, 3])
        if !rest.isEmpty { bytes += packet(0x101, start: false, rest) }
        return Data(bytes)
    }

    @Test func aTransportStreamGivesItsSound() throws {
        let sound = (0..<250).map { UInt8($0 % 256) }
        let found = try #require(hlsSegmentSound(transportStream(sound)))
        #expect(found.kind == .aac)
        #expect([UInt8](found.sound) == sound)
        #expect(hlsSegmentSound(transportStream(sound, type: 0x03))?.kind == .mpeg)
        #expect(hlsSegmentSound(transportStream(sound, type: 0x81)) == nil)
    }

    @Test func aTransportStreamCutAnywhereGivesTheSameSound() {
        let sound = (0..<280).map { UInt8(($0 * 7) % 256) }
        let stream = transportStream(sound)
        for size in [1, 100, 188, 200, 1000] {
            var demuxer = TransportDemuxer()
            var out = Data()
            var at = 0
            while at < stream.count {
                out.append(demuxer.feed(stream.subdata(in: at..<min(stream.count, at + size))))
                at += size
            }
            #expect([UInt8](out) == sound, "pieces of \(size)")
        }
    }
}
