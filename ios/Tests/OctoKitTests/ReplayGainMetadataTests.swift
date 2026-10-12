import Foundation
import Testing
@testable import OctoKit

@Suite struct ReplayGainMetadataTests {
    @Test func readsId3UserTextFrames() throws {
        let info = try #require(ReplayGainTags.read([
            .id3UserText(description: "replaygain_track_gain", value: "-6.54 dB"),
            .id3UserText(description: "REPLAYGAIN_TRACK_PEAK", value: "0.988251"),
            .id3UserText(description: "REPLAYGAIN_ALBUM_GAIN", value: "-7.10 dB"),
            .id3UserText(description: nil, value: "A title"),
        ]))
        #expect(abs(info.trackGain! + 6.54) < 1e-4)
        #expect(abs(info.trackPeak! - 0.988251) < 1e-6)
        #expect(abs(info.albumGain! + 7.10) < 1e-4)
        #expect(info.albumPeak == nil)
    }

    @Test func readsVorbisCommentsWithCommaDecimals() throws {
        let info = try #require(ReplayGainTags.read([
            .vorbisComment(key: "REPLAYGAIN_ALBUM_GAIN", value: "-8,25 dB"),
            .vorbisComment(key: "replaygain_album_peak", value: "1,02"),
            .vorbisComment(key: "TITLE", value: "A title"),
        ]))
        #expect(abs(info.albumGain! + 8.25) < 1e-4)
        #expect(abs(info.albumPeak! - 1.02) < 1e-4)
        #expect(info.trackGain == nil)
    }

    @Test func r128GainsAreMovedToTheStandardLevel() throws {
        // -1792 / 256 = -7 dB against -23 LUFS, which is -2 dB against -18.
        let info = try #require(ReplayGainTags.read([
            .vorbisComment(key: "R128_TRACK_GAIN", value: "-1792"),
            .vorbisComment(key: "R128_ALBUM_GAIN", value: "256"),
        ]))
        #expect(abs(info.trackGain! + 2) < 1e-4)
        #expect(abs(info.albumGain! - 6) < 1e-4)
    }

    @Test func readsMp4FreeFormTagsOnlyFromItunes() throws {
        let info = try #require(ReplayGainTags.read([
            .mp4FreeForm(domain: "com.apple.iTunes", name: "replaygain_track_gain", value: "+1.20 dB"),
            .mp4FreeForm(domain: "COM.APPLE.ITUNES", name: "replaygain_track_peak", value: "0.5"),
            .mp4FreeForm(domain: "com.example.other", name: "replaygain_album_gain", value: "-9 dB"),
        ]))
        #expect(abs(info.trackGain! - 1.2) < 1e-4)
        #expect(abs(info.trackPeak! - 0.5) < 1e-4)
        #expect(info.albumGain == nil)
    }

    @Test func theMp3HeaderIsOnlyALastResort() throws {
        // Radio (track) gain of -3.0 dB: name 1, originator 3, sign bit set, 30 tenths.
        let header = try #require(Mp3InfoReplayGain.parse(peak: 0.9, field1: (1 << 13) | (3 << 10) | (1 << 9) | 30, field2: 0))
        let alone = try #require(ReplayGainTags.read([.mp3Header(header)]))
        #expect(abs(alone.trackGain! + 3) < 1e-4)
        #expect(abs(alone.trackPeak! - 0.9) < 1e-4)
        let tagged = try #require(ReplayGainTags.read([.mp3Header(header), .id3UserText(description: "REPLAYGAIN_TRACK_GAIN", value: "-5 dB")]))
        #expect(abs(tagged.trackGain! + 5) < 1e-4)
        #expect(Mp3InfoReplayGain.parse(peak: 0, field1: 0, field2: 0) == nil)
    }

    @Test func songsWithoutTagsHaveNoInfo() {
        #expect(ReplayGainTags.read(nil) == nil)
        #expect(ReplayGainTags.read([.vorbisComment(key: "TITLE", value: "A title")]) == nil)
    }

    @Test func anAlbumIsItsIdOrItsNames() {
        #expect(albumKey(albumId: "al-1", albumTitle: "Nightcall", albumArtist: nil, artist: "Kavinsky") == "al-1")
        #expect(albumKey(albumId: nil, albumTitle: " Nightcall ", albumArtist: nil, artist: "Kavinsky") == "Nightcall/Kavinsky")
        #expect(albumKey(albumId: nil, albumTitle: "Nightcall", albumArtist: "Various", artist: "Kavinsky") == "Nightcall/Various")
        #expect(albumKey(albumId: nil, albumTitle: "  ", albumArtist: nil, artist: "Kavinsky") == nil)
    }
}

/// Which loudness a song plays at: the tags in its sound, the values its source kept, or
/// neither, which leaves the fallback level.
@Suite struct StoredReplayGainTests {
    let tags = ReplayGainInfo(trackGain: -6, trackPeak: 0.9, albumGain: -7, albumPeak: 0.95)
    let stored = ReplayGainInfo(trackGain: -8.4, trackPeak: 0.98, albumGain: -7.9, albumPeak: 1)

    var settings: SoundSettings {
        var s = SoundSettings()
        s.replayGain = .track
        s.preventClipping = false
        return s
    }

    @Test func tagsInTheSoundWin() {
        #expect(ReplayGainTags.choose(stream: tags, stored: stored) == tags)
        #expect(ReplayGainTags.choose(stream: tags, stored: nil) == tags)
    }

    @Test func storedValuesStandInWhenTheSoundHasNone() {
        #expect(ReplayGainTags.choose(stream: nil, stored: stored) == stored)
        // A stream with only a peak says nothing about how loud to play.
        #expect(ReplayGainTags.choose(stream: ReplayGainInfo(trackPeak: 0.7), stored: stored) == stored)
        // An album gain alone is still a gain.
        let albumOnly = ReplayGainInfo(albumGain: -3)
        #expect(ReplayGainTags.choose(stream: albumOnly, stored: stored) == albumOnly)
    }

    @Test func withNeitherTheFallbackLevelApplies() {
        #expect(ReplayGainTags.choose(stream: nil, stored: nil) == nil)
        let peakOnly = ReplayGainInfo(trackPeak: 0.7)
        #expect(ReplayGainTags.choose(stream: peakOnly, stored: nil) == peakOnly)
        var fallback = settings
        fallback.replayGainFallbackDb = -6
        let level = replayGainFactor(fallback, SongLoudness(ReplayGainTags.choose(stream: nil, stored: nil), followsSameAlbum: false))
        #expect(abs(level - 0.501) < 0.001)
    }

    @Test func storedValuesSetTheLevel() {
        let chosen = ReplayGainTags.choose(stream: nil, stored: stored)
        #expect(abs(replayGainFactor(settings, SongLoudness(chosen, followsSameAlbum: false)) - 0.380) < 0.001)
    }

    @Test func theCopyPlayingGivesItsValuesAndOthersFillIn() {
        let phone = SongCopy(id: "p", sourceId: "device", nativeId: "p", durationMs: 258_000)
        let server = SongCopy(id: "s", sourceId: "server:music.example", nativeId: "s", durationMs: 258_000, trackGain: -8.4, trackPeak: 0.98)
        let other = SongCopy(id: "o", sourceId: "server:music.example", nativeId: "o", durationMs: 258_000, trackGain: -2)
        #expect(storedLoudness(server, [phone, server, other])?.trackGain == -8.4)
        // A phone file with no stored values borrows the server copy's.
        #expect(storedLoudness(phone, [phone, server, other])?.trackGain == -8.4)
        #expect(storedLoudness(phone, [phone]) == nil)
        #expect(storedLoudness(nil, []) == nil)
    }

    @Test func storedValuesAreCheckedLikeTags() {
        #expect(ReplayGainTags.stored(trackGain: nil, trackPeak: 0.9, albumGain: nil, albumPeak: 1) == nil)
        #expect(ReplayGainTags.stored(trackGain: .nan, trackPeak: nil, albumGain: 99, albumPeak: nil) == nil)
        #expect(ReplayGainTags.stored(trackGain: -5, trackPeak: 0, albumGain: 70, albumPeak: 0.8)
            == ReplayGainInfo(trackGain: -5, trackPeak: nil, albumGain: nil, albumPeak: 0.8))
    }
}
