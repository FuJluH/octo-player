import Foundation
import Testing
@testable import OctoKit

// Where the word fill's soft edge is, and when a word lights. A typical sung word: 0.3 s long,
// 60 px wide, on a 30 sp line at 2.625 px a dp.
@Suite struct WordFillTest {
    private let width = 60.0
    private let lineHeight = 30 * 2.625
    private var shape: MaskShape { maskShape(wordWidth: width, lineHeight: lineHeight, softness: 1.0) }

    // The soft edge's width in pixels.
    private var edge: Double { shape.edge * width }

    // The middle of the soft edge, from the word's left edge, this far through the fill.
    private func middle(_ progress: Double) -> Double {
        maskLeft(progress, wordLeft: 0.0, wordWidth: width, shape: shape, rtl: false) + shape.size * width / 2
    }

    // How much of the word is lit, 0 to 1: bright left of the edge, dark right of it, a straight
    // ramp across it.
    private func lit(_ progress: Double) -> Double {
        let mid = middle(progress)
        let edge = self.edge
        let steps = 6000
        var sum = 0.0
        for i in 0..<steps {
            let x = (Double(i) + 0.5) * width / Double(steps)
            sum += ((mid + edge / 2 - x) / edge).clamped(0.0, 1.0)
        }
        return sum / Double(steps)
    }

    @Test func theEdgesMiddleRunsFromHalfAnEdgeBeforeTheWordToHalfAnEdgePastIt() {
        // x(q) = -e/2 + q * (W + e): the mask's path, which the lead leaves alone.
        #expect(near(-edge / 2, middle(0.0), 1e-9))
        #expect(near(width / 2, middle(0.5), 1e-9))
        #expect(near(width + edge / 2, middle(1.0), 1e-9))
        #expect(near(0.5, lit(0.5), 1e-3))
    }

    @Test func aWordLightsFromItsFirstLetterAsItStarts() {
        let start = 10.0
        let end = 10.3
        let lead = fillLead(start, end: end, edge: shape.edge)
        // About 59 ms for this word: the time the edge takes to cross half of itself.
        #expect(near(0.0594, lead, 0.0005))
        // As the word starts, the middle of the edge is on its first letter.
        #expect(near(0.0, middle(fillProgress(start, start: start, end: end, edge: shape.edge)), 1e-9))
        // Without the lead it was still half an edge short, and got there only this far into the
        // word.
        let short = middle(wordProgress(start, start: start, end: end))
        #expect(near(-edge / 2, short, 1e-9))
        // By the middle of the word it is mostly lit, where it was half lit.
        let halfway = start + 0.15
        #expect(lit(fillProgress(halfway, start: start, end: end, edge: shape.edge)) > 0.8)
        #expect(near(0.5, lit(wordProgress(halfway, start: start, end: end)), 1e-3))
        // It is whole by the lead before its end, and dark until the lead before its start.
        #expect(near(1.0, fillProgress(end - lead, start: start, end: end, edge: shape.edge), 1e-9))
        #expect(near(0.0, fillProgress(start - lead, start: start, end: end, edge: shape.edge), 1e-9))
    }

    @Test func theLeadIsKeptSmallForLongNarrowWords() {
        let narrow = maskShape(wordWidth: 12.0, lineHeight: lineHeight, softness: 1.0)
        #expect(near(FILL_LEAD_MAX_S, fillLead(0.0, end: 3.0, edge: narrow.edge), 0.0))
        // No edge or no length, no lead.
        #expect(near(0.0, fillLead(1.0, end: 1.0, edge: shape.edge), 0.0))
        #expect(near(0.0, fillLead(1.0, end: 2.0, edge: 0.0), 0.0))
        // Always inside the half second a line's words start moving before it.
        #expect(FILL_LEAD_MAX_S < 0.5)
    }
}
