import Foundation
import Testing
@testable import OctoKit

@Suite struct StartAfterTest {
    @Test func theChoicesGrowAndTheDefaultIsOneSecond() {
        #expect(StartAfter.allCases.map(\.ms) == [250, 1_000, 2_500, 5_000, 10_000])
        #expect(StartAfter.short.label == "1 second")
    }

    @Test func theWordsHaveNoDashes() {
        for words in StartAfter.allCases.map(\.label) + [StartAfter.settingName, StartAfter.help] {
            #expect(!words.unicodeScalars.contains { $0.value == 0x2014 || $0.value == 0x2013 })
        }
    }
}

@Suite struct PlayRulesTest {
    @Test func whatIsLeftIsHalfTheSongOrFourMinutes() {
        #expect(msLeftToCount(playedMs: 0, durationMs: 200_000) == 100_000)
        #expect(msLeftToCount(playedMs: 60_000, durationMs: 200_000) == 40_000)
        #expect(msLeftToCount(playedMs: 150_000, durationMs: 200_000) == 0)
        #expect(msLeftToCount(playedMs: 0, durationMs: 3_600_000) == 240_000)
    }

    @Test func clipsAndUnknownLengthsNeverCount() {
        #expect(msLeftToCount(playedMs: 0, durationMs: 20_000) == nil)
        #expect(msLeftToCount(playedMs: 0, durationMs: 0) == nil)
    }
}

@Suite struct SongLengthTest {
    @Test func thePlayersMeasureWinsOnceItHasOne() {
        #expect(playingLengthMs(listedMs: 296_000, playerMs: 291_000) == 291_000)
        #expect(playingLengthMs(listedMs: 296_000, playerMs: 301_000) == 301_000)
        #expect(playingLengthMs(listedMs: 296_000, playerMs: nil) == 296_000)
        #expect(playingLengthMs(listedMs: 0, playerMs: nil) == 0)
        #expect(playingLengthMs(listedMs: -5, playerMs: nil) == 0)
    }

    @Test func aPlaceholderOrNonsenseIsNotAMeasure() {
        #expect(measuredLengthMs(0) == nil)
        #expect(measuredLengthMs(-1) == nil)
        #expect(measuredLengthMs(Int.min + 1) == nil)
        #expect(measuredLengthMs(400) == nil)
        #expect(measuredLengthMs(25 * 60 * 60_000) == nil)
        #expect(playingLengthMs(listedMs: 296_000, playerMs: 0) == 296_000)
        #expect(measuredLengthMs(1_000) == 1_000)
    }

    @Test func aMeasureTheSongPlayedPastIsNotBelieved() {
        #expect(playingLengthMs(listedMs: 296_000, playerMs: 10_000, positionMs: 10_500) == 10_000)
        #expect(playingLengthMs(listedMs: 296_000, playerMs: 10_000, positionMs: 12_000) == 296_000)
        #expect(playingLengthMs(listedMs: 0, playerMs: 10_000, positionMs: 12_000) == 0)
    }

    @Test func aSongPlayingPastItsListingIsAtLeastThatLong() {
        #expect(playingLengthMs(listedMs: 291_000, playerMs: nil, positionMs: 290_000) == 291_000)
        #expect(playingLengthMs(listedMs: 291_000, playerMs: nil, positionMs: 293_500) == 293_500)
        #expect(playingLengthMs(listedMs: 0, playerMs: nil, positionMs: 293_500) == 0)
    }

    @Test func aListingWithinASecondIsRight() {
        #expect(correctedLengthMs(listedMs: 291_000, playerMs: 291_600) == nil)
        #expect(correctedLengthMs(listedMs: 291_000, playerMs: 290_000) == nil)
        #expect(correctedLengthMs(listedMs: 291_000, playerMs: 289_900) == 289_900)
        #expect(correctedLengthMs(listedMs: 296_000, playerMs: 291_000) == 291_000)
        #expect(correctedLengthMs(listedMs: 0, playerMs: 291_000) == 291_000)
        #expect(correctedLengthMs(listedMs: 296_000, playerMs: nil) == nil)
        #expect(correctedLengthMs(listedMs: 296_000, playerMs: 0) == nil)
    }

    @Test func aCorrectedSongCarriesWholeSeconds() {
        let song = Song(id: "s", title: "Song", duration: 296)
        #expect(song.withLength(ms: 291_000).duration == 291)
        #expect(song.withLength(ms: 291_499).duration == 291)
        #expect(song.withLength(ms: 291_500).duration == 292)
    }

    @Test func aWrongListingIsCorrectedEverywhereItIsRead() {
        let lengths = RealLengths()
        let listed = Song(id: "s", title: "Song", duration: 296)
        #expect(lengths.applyTo(listed) == listed)
        #expect(lengths.lengthMs("s", listedMs: 296_000) == 296_000)
        #expect(lengths.learn("s", listedMs: 296_000, playerMs: 291_000) == 291_000)
        #expect(lengths.corrected == ["s": 291_000])
        #expect(lengths.lengthMs("s", listedMs: 296_000) == 291_000)
        #expect(lengths.applyTo(listed).duration == 291)
        #expect(lengths.learn("s", listedMs: 291_000, playerMs: 291_200) == nil)
        #expect(lengths.corrected == ["s": 291_000])
        #expect(lengths.lengthMs("t", listedMs: 200_000) == 200_000)
    }

    @Test func aRightListingIsNotRecorded() {
        let lengths = RealLengths()
        #expect(lengths.learn("s", listedMs: 291_000, playerMs: 291_400) == nil)
        #expect(lengths.learn("s", listedMs: 291_000, playerMs: nil) == nil)
        #expect(lengths.corrected.isEmpty)
    }
}

@Suite struct CrossfadeTest {
    let song = FadeSong(albumId: "a", albumOrder: 3, durationMs: 200_000)
    let otherAlbum = FadeSong(albumId: "b", albumOrder: 0, durationMs: 180_000)

    func length(_ a: FadeSong, _ b: FadeSong?, _ fade: Int, repeatOne: Bool = false, stop: Bool = false) -> Int {
        crossfadeLength(a, b, fadeMs: fade, repeatOne: repeatOne, stopAtEndOfSong: stop)
    }

    @Test func songsFromDifferentAlbumsBlend() { #expect(length(song, otherAlbum, 6_000) == 6_000) }

    @Test func theNextSongOfTheSameAlbumStaysGapless() {
        #expect(length(song, FadeSong(albumId: "a", albumOrder: 4, durationMs: 190_000), 6_000) == 0)
    }

    @Test func theSameAlbumOutOfOrderStillBlends() {
        #expect(length(song, FadeSong(albumId: "a", albumOrder: 9, durationMs: 190_000), 6_000) == 6_000)
    }

    @Test func songsWithNoAlbumBlend() {
        let loose = FadeSong(albumId: nil, albumOrder: nil, durationMs: 190_000)
        #expect(length(loose, loose, 6_000) == 6_000)
    }

    @Test func offWhenTurnedOffOrNothingFollows() {
        #expect(length(song, otherAlbum, 0) == 0)
        #expect(length(song, nil, 6_000) == 0)
    }

    @Test func repeatOneAndTheSleepTimerEndOfSongNeverBlend() {
        #expect(length(song, otherAlbum, 6_000, repeatOne: true) == 0)
        #expect(length(song, otherAlbum, 6_000, stop: true) == 0)
    }

    @Test func unknownLengthsNeverBlend() {
        let unknown = FadeSong(albumId: "c", albumOrder: 0, durationMs: 0)
        #expect(length(unknown, otherAlbum, 6_000) == 0)
        #expect(length(song, unknown, 6_000) == 0)
    }

    @Test func aShortSongShrinksTheFadeToHalfItsLength() {
        let short = FadeSong(albumId: "c", albumOrder: 0, durationMs: 8_000)
        #expect(length(short, otherAlbum, 12_000) == 4_000)
        #expect(length(song, short, 12_000) == 4_000)
    }

    @Test func aTinySongGetsNoFadeAtAll() {
        #expect(length(FadeSong(albumId: "c", albumOrder: 0, durationMs: 800), otherAlbum, 6_000) == 0)
    }

    @Test func theFadeKeepsLoudnessEven() {
        for step in 0...20 {
            let progress = Float(step) / 20
            let out = fadeOutVolume(progress), into = fadeInVolume(progress)
            #expect(abs(out * out + into * into - 1) < 0.0001)
        }
    }

    @Test func theFadeStartsAndEndsCleanlyAndClamps() {
        #expect(abs(fadeOutVolume(0) - 1) < 0.0001)
        #expect(abs(fadeInVolume(0)) < 0.0001)
        #expect(abs(fadeOutVolume(1)) < 0.0001)
        #expect(abs(fadeInVolume(1) - 1) < 0.0001)
        #expect(abs(fadeInVolume(3) - 1) < 0.0001)
        #expect(abs(fadeOutVolume(-1) - 1) < 0.0001)
    }
}

@Suite struct SleepPlanTest {
    @Test func theFadeIsFullUntilTheLastThirtySecondsThenSquared() {
        #expect(sleepFade(10 * 60_000) == 1)
        #expect(sleepFade(sleepFadeMs) == 1)
        #expect(abs(sleepFade(15_000) - 0.25) < 0.0001)
        #expect(abs(sleepFade(3_000) - 0.01) < 0.0001)
        #expect(sleepFade(0) == 0)
        #expect(sleepFade(-5) == 0)
    }

    @Test func fadeIsFullUntilTheLastThirtySecondsThenFallsToSilence() {
        #expect(sleepFade(60_000) == 1)
        #expect(sleepFade(30_000) == 1)
        #expect(abs(sleepFade(15_000) - 0.25) < 0.0001)
        #expect(sleepFade(0) == 0)
    }

    @Test func ticksLandOnWholeSecondsThenTenTimesASecond() {
        #expect(untilNextSleepTick(60_000) == 1_000)
        #expect(untilNextSleepTick(59_500) == 500)
        #expect(untilNextSleepTick(45_001) == 1)
        #expect(untilNextSleepTick(sleepFadeMs) == 100)
        #expect(untilNextSleepTick(1_030) == 30)
    }

    @Test func aTimerReadsInPlainWords() {
        #expect(sleepSummary(.off) == "Off")
        #expect(sleepSummary(.counting(remainingMs: 14 * 60_000 + 1)) == "15 min left")
        #expect(sleepSummary(.counting(remainingMs: 5_000)) == "1 min left")
        #expect(sleepSummary(.endOfSong) == "At the end of this song")
        #expect(sleepSummary(.songs(left: 3)) == "After 3 songs")
        #expect(sleepSummary(.afterSong(key: "q:4", title: "Song 4")) == "After Song 4")
    }

    @Test func theChoicesAreThePhones() {
        #expect(sleepMinutes == [5, 15, 30, 45, 60])
        #expect(sleepSongCounts == [1, 2, 3, 5])
        #expect(maxSleepMinutes == 720)
    }
}

@Suite struct PlayFailureWordsTest {
    @Test func aMissingSongIsToldApartFromARefusal() {
        #expect(playFailureOf(.badHttpStatus, httpStatus: 404) == .missing)
        #expect(playFailureOf(.badHttpStatus, httpStatus: 403) == .refused)
        #expect(playFailureOf(.fileNotFound) == .missing)
    }

    @Test func aNotFoundOnAnOutsideSongIsARefusal() {
        #expect(playFailureOf(.badHttpStatus, httpStatus: 404, outside: true) == .refused)
        #expect(playFailureOf(.badHttpStatus, httpStatus: 410, outside: true) == .refused)
        #expect(playFailureOf(.badHttpStatus, httpStatus: 404, outside: false) == .missing)
        #expect(playFailureOf(.badHttpStatus, httpStatus: 404, outside: true).words == "The server wouldn't send that song.")
    }

    @Test func eachKindOfFailureHasItsWords() {
        #expect(playFailureOf(.networkConnectionFailed) == .unreachable)
        #expect(playFailureOf(.decodingFormatUnsupported) == .unsupported)
        #expect(playFailureOf(.parsingContainerMalformed) == .damaged)
        #expect(playFailureOf(.audioTrackInitFailed) == .device)
        #expect(playFailureOf(.unspecified) == .other)
    }

    @Test func theLineNamesTheSongAndTheReason() {
        #expect(skippedLine("Airbag", PlayFailure.missing.words) == "Skipped Airbag. That song isn't on the server any more.")
    }
}
