import Foundation
import Testing
@testable import OctoKit

/// Reading the loudness tags a song file carries in its own bytes.
@Suite struct LoudnessTagReaderTests {
    private func read(_ bytes: [UInt8]) -> ReplayGainInfo? {
        LoudnessTagReader.loudness(length: Int64(bytes.count)) { offset, count in
            guard offset >= 0, offset <= Int64(bytes.count) else { return nil }
            let start = Int(offset)
            return Array(bytes[start..<min(bytes.count, start + count)])
        }
    }

    private func be(_ value: Int, _ width: Int) -> [UInt8] {
        (0..<width).reversed().map { UInt8((value >> ($0 * 8)) & 0xFF) }
    }

    private func le(_ value: Int, _ width: Int) -> [UInt8] {
        (0..<width).map { UInt8((value >> ($0 * 8)) & 0xFF) }
    }

    private func syncSafe(_ value: Int) -> [UInt8] {
        [UInt8((value >> 21) & 0x7F), UInt8((value >> 14) & 0x7F), UInt8((value >> 7) & 0x7F), UInt8(value & 0x7F)]
    }

    private func id3(major: UInt8, frames: [[UInt8]]) -> [UInt8] {
        let body = frames.flatMap { $0 } + [UInt8](repeating: 0, count: 16)
        return Array("ID3".utf8) + [major, 0, 0] + syncSafe(body.count) + body
    }

    private func frame(_ id: String, _ data: [UInt8], major: UInt8) -> [UInt8] {
        Array(id.utf8) + (major == 4 ? syncSafe(data.count) : be(data.count, 4)) + [0, 0] + data
    }

    private func txxx(_ name: String, _ value: String, major: UInt8) -> [UInt8] {
        frame("TXXX", [3] + Array(name.utf8) + [0] + Array(value.utf8), major: major)
    }

    /// The first frame of an MPEG-1 layer III stream with no encoder header.
    private let plainFrame: [UInt8] = [0xFF, 0xFB, 0x90, 0x00] + [UInt8](repeating: 0, count: 200)

    @Test func readsId3UserTextFramesAndStepsOverPictures() throws {
        let picture = frame("APIC", [0] + Array("image/jpeg".utf8) + [0, 3, 0] + [UInt8](repeating: 0xAB, count: 3_000), major: 3)
        let peak = frame("TXXX", [1, 0xFF, 0xFE] + Array("REPLAYGAIN_TRACK_PEAK".utf16).flatMap { le(Int($0), 2) } + [0, 0, 0xFF, 0xFE]
            + Array("0.988251".utf16).flatMap { le(Int($0), 2) }, major: 3)
        let file = id3(major: 3, frames: [picture, txxx("replaygain_track_gain", "-6.54 dB", major: 3), peak]) + plainFrame
        let info = try #require(read(file))
        #expect(abs(info.trackGain! + 6.54) < 1e-4)
        #expect(abs(info.trackPeak! - 0.988251) < 1e-6)
    }

    @Test func readsVersionFourTags() throws {
        let file = id3(major: 4, frames: [txxx("REPLAYGAIN_ALBUM_GAIN", "-7.10 dB", major: 4)]) + plainFrame
        let info = try #require(read(file))
        #expect(abs(info.albumGain! + 7.1) < 1e-4)
    }

    private func lameFrame(peak: Float, field1: Int, field2: Int) -> [UInt8] {
        var bytes: [UInt8] = [0xFF, 0xFB, 0x90, 0x00] + [UInt8](repeating: 0, count: 32)
        bytes += Array("Info".utf8) + be(0x0F, 4) + be(1_000, 4) + be(400_000, 4) + [UInt8](repeating: 0, count: 100) + be(50, 4)
        bytes += Array("LAME3.99r".utf8) + [0x24, 0x13]
        bytes += be(Int(peak.bitPattern), 4) + be(field1, 2) + be(field2, 2) + [0, 0] + [0x24, 0x05, 0x00]
        return bytes + [UInt8](repeating: 0, count: 100)
    }

    @Test func theMp3EncoderHeaderGivesItsGainsWhenNoTagDoes() throws {
        // Radio (track) gain of -3.0 dB, set by the encoder's user: name 1, originator 3.
        let radio = (1 << 13) | (3 << 10) | (1 << 9) | 30
        let alone = try #require(read(lameFrame(peak: 0.9, field1: radio, field2: 0)))
        #expect(abs(alone.trackGain! + 3) < 1e-4)
        #expect(abs(alone.trackPeak! - 0.9) < 1e-6)
        let tagged = try #require(read(id3(major: 3, frames: [txxx("REPLAYGAIN_TRACK_GAIN", "-5 dB", major: 3)])
            + lameFrame(peak: 0.9, field1: radio, field2: 0)))
        #expect(abs(tagged.trackGain! + 5) < 1e-4)
        #expect(read(lameFrame(peak: 0.9, field1: 0, field2: 0)) == nil)
    }

    private func vorbisBlock(_ comments: [String]) -> [UInt8] {
        let vendor = Array("reference libFLAC 1.4.3".utf8)
        return le(vendor.count, 4) + vendor + le(comments.count, 4) + comments.flatMap { le($0.utf8.count, 4) + Array($0.utf8) }
    }

    @Test func readsTheVorbisCommentsOfAFlacFile() throws {
        let comments = vorbisBlock(["TITLE=A title", "REPLAYGAIN_ALBUM_GAIN=-8,25 dB", "replaygain_album_peak=1,02"])
        let file = Array("fLaC".utf8) + [0x00] + be(34, 3) + [UInt8](repeating: 0, count: 34)
            + [0x06] + be(2_000, 3) + [UInt8](repeating: 0xCD, count: 2_000)
            + [0x84] + be(comments.count, 3) + comments + [0xFF, 0xF8]
        let info = try #require(read(file))
        #expect(abs(info.albumGain! + 8.25) < 1e-4)
        #expect(abs(info.albumPeak! - 1.02) < 1e-4)
    }

    private func oggPage(_ packets: [[UInt8]], serial: Int, sequence: Int, continued: Bool = false) -> [UInt8] {
        var lacing: [UInt8] = []
        for packet in packets {
            var left = packet.count
            while left >= 255 {
                lacing.append(255)
                left -= 255
            }
            lacing.append(UInt8(left))
        }
        return Array("OggS".utf8) + [0, continued ? 1 : 0] + be(0, 8) + le(serial, 4) + le(sequence, 4) + be(0, 4)
            + [UInt8(lacing.count)] + lacing + packets.flatMap { $0 }
    }

    @Test func readsTheOpusTagsOfAnOggFile() throws {
        let head = Array("OpusHead".utf8) + [1, 2, 0x38, 0x01, 0x80, 0xBB, 0, 0, 0, 0, 0]
        let tags = Array("OpusTags".utf8) + vorbisBlock(["R128_TRACK_GAIN=-1792", "R128_ALBUM_GAIN=256"])
        let file = oggPage([head], serial: 7, sequence: 0) + oggPage([tags], serial: 7, sequence: 1)
        let info = try #require(read(file))
        #expect(abs(info.trackGain! + 2) < 1e-4)
        #expect(abs(info.albumGain! - 6) < 1e-4)
    }

    @Test func aCommentPacketCanRunOverSeveralPages() throws {
        let head = [1] + Array("vorbis".utf8) + [UInt8](repeating: 0, count: 23)
        let comments = [3] + Array("vorbis".utf8) + vorbisBlock(["COMMENT=" + String(repeating: "x", count: 600), "REPLAYGAIN_TRACK_GAIN=+2.1dB"]) + [1]
        // The comment packet is split: 510 bytes on one page, the rest on the next.
        let first = Array(comments[0..<510])
        let rest = Array(comments[510...])
        let page2 = Array("OggS".utf8) + [0, 0] + be(0, 8) + le(9, 4) + le(1, 4) + be(0, 4) + [2, 255, 255] + first
        let file = oggPage([head], serial: 9, sequence: 0) + page2 + oggPage([rest], serial: 9, sequence: 2, continued: true)
        let info = try #require(read(file))
        #expect(abs(info.trackGain! - 2.1) < 1e-4)
    }

    private func box(_ type: String, _ body: [UInt8]) -> [UInt8] {
        be(body.count + 8, 4) + Array(type.utf8) + body
    }

    private func freeForm(_ domain: String, _ name: String, _ value: String) -> [UInt8] {
        box("----", box("mean", [0, 0, 0, 0] + Array(domain.utf8)) + box("name", [0, 0, 0, 0] + Array(name.utf8))
            + box("data", [0, 0, 0, 1, 0, 0, 0, 0] + Array(value.utf8)))
    }

    @Test func readsMp4FreeFormTagsWhereverTheMovieBoxIs() throws {
        let title = box("data", [0, 0, 0, 1, 0, 0, 0, 0] + Array("A title".utf8))
        let list = box("ilst", be(title.count + 8, 4) + [0xA9] + Array("nam".utf8) + title
            + box("covr", box("data", [0, 0, 0, 13, 0, 0, 0, 0] + [UInt8](repeating: 0xEE, count: 4_000)))
            + freeForm("com.apple.iTunes", "replaygain_track_gain", "+1.20 dB")
            + freeForm("com.example.other", "replaygain_album_gain", "-9 dB"))
        let meta = box("meta", [0, 0, 0, 0] + box("hdlr", [UInt8](repeating: 0, count: 25)) + list)
        let moov = box("moov", box("mvhd", [UInt8](repeating: 0, count: 100)) + box("udta", meta))
        let ftyp = box("ftyp", Array("M4A ".utf8) + be(0, 4))
        let mdat = box("mdat", [UInt8](repeating: 0x11, count: 5_000))
        for file in [ftyp + moov + mdat, ftyp + mdat + moov] {
            let info = try #require(read(file))
            #expect(abs(info.trackGain! - 1.2) < 1e-4)
            #expect(info.albumGain == nil)
        }
    }

    @Test func aFileWithoutTagsHasNoLoudness() {
        #expect(read(plainFrame) == nil)
        #expect(read(id3(major: 3, frames: [frame("TIT2", [0] + Array("A title".utf8), major: 3)]) + plainFrame) == nil)
        #expect(read([UInt8](repeating: 0, count: 64)) == nil)
        #expect(read([]) == nil)
    }
}
