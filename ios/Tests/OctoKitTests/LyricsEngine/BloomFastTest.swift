import Foundation
import Testing
@testable import OctoKit

@Suite struct BloomFastTest {
    func near(_ expected: Double, _ actual: Double, _ tolerance: Double) -> Bool { abs(expected - actual) <= tolerance }

    /// A line of words with these lengths, one after another.
    func line(_ lengths: [Double]) -> [SyncWord] {
        var at = 10.0
        return lengths.map { length in
            defer { at += length }
            return SyncWord(text: "word", start: at, end: at + length, trailingSpace: true)
        }
    }

    // MARK: Which words are held

    @Test func inARapLineOnlyTheNoteHeldOutBlooms() {
        let rap = line([0.2, 0.25, 0.2, 0.7, 0.2, 0.3])
        #expect(heldWords(rap, fast: true) == [false, false, false, true, false, false])
        #expect(heldWords(rap, fast: false) == [false, false, false, false, false, false])
    }

    @Test func wordsAllHeldAboutAsLongAsEachOtherDoNotBloom() {
        #expect(!heldWords(line([0.7, 0.75, 0.8, 0.7, 0.8]), fast: true).contains(true))
    }

    @Test func aWordUnderTheShortestHoldNeverBloomsByStandingOut() {
        #expect(!heldWords(line([0.1, 0.5, 0.1]), fast: true).contains(true))
    }

    @Test func aOneWordLineHasNothingToStandOutFrom() {
        #expect(heldWords(line([0.7]), fast: true) == [false])
        #expect(heldWords([], fast: true).isEmpty)
    }

    @Test func aSecondOrMoreAlwaysBlooms() {
        #expect(heldWords(line([1.0, 1.2, 1.1]), fast: true) == [true, true, true])
        #expect(heldDurations([0.2, 1.0, 0.99], fast: false) == [false, true, false])
    }

    @Test func untimedWordsAreLeftOutOfTheMiddle() {
        // Only 0.2 and 0.7 are timed; the middle is 0.7, so nothing stands out.
        #expect(heldDurations([0, 0, 0.2, 0.7], fast: true) == [false, false, false, false])
    }

    // MARK: How a held word blooms

    @Test func aWordNotHeldNeverBlooms() {
        #expect(emphasisFor(2.0, glyphs: 4, last: false, emphasis: 1, glow: 1, fast: true, held: false) == nil)
        #expect(emphasisFor(0.7, glyphs: 0, last: false, emphasis: 1, glow: 1, fast: true, held: true) == nil)
    }

    @Test func aFastHeldWordBloomsAsStronglyAsOneHeldLongerButRunsItsOwnLength() throws {
        let quick = try #require(emphasisFor(0.7, glyphs: 4, last: false, emphasis: 1, glow: 1, fast: true, held: true))
        let long = try #require(emphasisFor(1.6, glyphs: 4, last: false, emphasis: 1, glow: 1, fast: true, held: true))
        #expect(near(long.amount, quick.amount, 1e-12))
        #expect(near(long.glow, quick.glow, 1e-12))
        #expect(near(0.7, quick.run, 1e-12))
        #expect(near(0.7 / 2.5 / 4, quick.stagger, 1e-12))
        let last = try #require(emphasisFor(0.7, glyphs: 4, last: true, emphasis: 1, glow: 1, fast: true, held: true))
        #expect(near(0.84, last.run, 1e-12))
    }

    @Test func fastGlowComesUpSoonerUnderThreeSeconds() throws {
        let plain = try #require(emphasisFor(1.5, glyphs: 4, last: false, emphasis: 1, glow: 1, fast: false, held: true))
        let fast = try #require(emphasisFor(1.5, glyphs: 4, last: false, emphasis: 1, glow: 1, fast: true, held: true))
        #expect(near(0.0625, plain.glow, 1e-12))
        // With fast, the glow is worked out from the 1.6 s floor too.
        let g = 1.6 / 3
        #expect(near(0.5 * g * g.squareRoot(), fast.glow, 1e-12))
    }

    @Test func pastThreeSecondsTheGlowIsTheSameEitherWay() throws {
        let plain = try #require(emphasisFor(4.0, glyphs: 4, last: false, emphasis: 1, glow: 1, fast: false, held: true))
        let fast = try #require(emphasisFor(4.0, glyphs: 4, last: false, emphasis: 1, glow: 1, fast: true, held: true))
        #expect(near(plain.glow, fast.glow, 1e-12))
        #expect(near(plain.amount, fast.amount, 1e-12))
    }

    @Test func withFastOffABloomIsAsBefore() {
        for d in [1.0, 1.5, 2.0, 3.0, 4.0] {
            for last in [false, true] {
                #expect(emphasisFor(d, glyphs: 5, last: last, emphasis: 1, glow: 1, fast: false, held: d >= 1.0)
                    == emphasisFor(d, glyphs: 5, last: last, emphasis: 1, glow: 1))
            }
        }
        #expect(emphasisFor(0.99, glyphs: 4, last: false, emphasis: 1, glow: 1) == nil)
    }

    // MARK: Lift

    @Test func withFastOnSungWordsRiseFurther() {
        #expect(near(0.08, liftHeightEm(background: false, fast: true), 1e-12))
        #expect(near(0.16, liftHeightEm(background: true, fast: true), 1e-12))
        #expect(near(0.05, liftHeightEm(background: false, fast: false), 1e-12))
        #expect(near(0.10, liftHeightEm(background: true, fast: false), 1e-12))
        #expect(near(-0.08, liftEm(9.0, start: 1.0, end: 1.2, background: false, lift: 1.0, fast: true), 1e-12))
        #expect(near(-0.16, liftEm(9.0, start: 1.0, end: 1.2, background: true, lift: 1.0, fast: true), 1e-12))
        #expect(near(-0.05, liftEm(9.0, start: 1.0, end: 1.2, background: false, lift: 1.0, fast: false), 1e-12))
        #expect(near(liftEm(1.5, start: 1.0, end: 1.2, background: false, lift: 1.0) * 0.08 / 0.05,
                     liftEm(1.5, start: 1.0, end: 1.2, background: false, lift: 1.0, fast: true), 1e-12))
    }

    // MARK: The setting

    @Test func bloomFastIsOnByDefaultAndKeptWithTheLook() throws {
        #expect(LyricsLook().bloomFast)
        let old = try JSONDecoder().decode(LyricsLook.self, from: Data(#"{"style":"Flowing","arc":true}"#.utf8))
        #expect(old.bloomFast)
        var off = LyricsLook()
        off.bloomFast = false
        let back = try JSONDecoder().decode(LyricsLook.self, from: JSONEncoder().encode(off))
        #expect(!back.bloomFast)
        #expect(back == off)
    }
}
