import Foundation
import Testing
@testable import OctoKit

@Suite struct ResponsePlotTests {
    let plot = ResponsePlot(width: 390)

    @Test func thePlotSitsInsideItsPadding() {
        #expect(ResponsePlot.height == 242)
        #expect(plot.left == 10)
        #expect(plot.right == 380)
        #expect(plot.top == 12)
        #expect(plot.bottom == 208)
        #expect(plot.bottom - plot.top == 196)
    }

    @Test func frequencyRunsOnALogScaleAndGainFromTopToBottom() {
        #expect(abs(plot.x(20) - plot.left) < 1e-9)
        #expect(abs(plot.x(20_000) - plot.right) < 1e-9)
        #expect(abs(plot.x(632.455532) - (plot.left + plot.right) / 2) < 1e-4)
        #expect(plot.hz(0) == 20)
        #expect(abs(plot.hz(1_000) - 20_000) < 1e-6)
        #expect(plot.y(12) == plot.top)
        #expect(plot.y(-12) == plot.bottom)
        #expect(plot.y(30) == plot.top)
        #expect(abs(plot.y(0) - 110) < 1e-9)
    }

    @Test func nodesSitOnTheCombinedCurve() {
        var s = SoundSettings()
        s.graphicGains = [0, 6, 0, 0, 0, 0, 0, 0, 0, 0]
        let points = SoundGraph.points(s, plot: plot)
        #expect(points.count == 10)
        // The 31 Hz node is lifted by its 62 Hz neighbor though its own gain is 0.
        #expect(points[0].y < plot.y(0) - 1)
        s.mode = .parametric
        s.filters = [EqFilter(frequency: 1_000, gainDb: 0, q: 1)]
        #expect(SoundGraph.points(s, plot: plot).count == 1)
    }
}

@Suite struct GraphTouchTests {
    let points = [PlotPoint(x: 100, y: 100), PlotPoint(x: 110, y: 100), PlotPoint(x: 300, y: 100)]

    @Test func theNearestNodeInReachIsTaken() {
        #expect(SoundGraph.nodeAt(points, touch: PlotPoint(x: 108, y: 102), reach: 30, preferred: nil) == 1)
        #expect(SoundGraph.nodeAt(points, touch: PlotPoint(x: 200, y: 100), reach: 30, preferred: nil) == nil)
    }

    @Test func theChosenFilterWinsWhileInReach() {
        #expect(SoundGraph.nodeAt(points, touch: PlotPoint(x: 108, y: 102), reach: 30, preferred: 0) == 0)
        #expect(SoundGraph.nodeAt(points, touch: PlotPoint(x: 300, y: 110), reach: 30, preferred: 0) == 2)
    }

    @Test func aDragIsRelativeSnapsAndClamps() {
        let plot = ResponsePlot(width: 390)
        #expect(SoundGraph.dragGain(start: 3, downY: 100, fingerY: 100 + plot.pxPerDb * 2, plot: plot) == 1)
        #expect(SoundGraph.dragGain(start: 3, downY: 100, fingerY: 100 + plot.pxPerDb * 2.9, plot: plot) == 0)
        #expect(SoundGraph.dragGain(start: 3, downY: 100, fingerY: 100 - plot.pxPerDb * 20, plot: plot) == 12)
        #expect(SoundGraph.dragHz(start: 1_000, downX: 50, fingerX: 50, plot: plot) == 1_000)
        #expect(SoundGraph.dragHz(start: 1_000, downX: 50, fingerX: -2_000, plot: plot) == 20)
    }

    @Test func aTickOnLandingAtZeroOrCrossingIt() {
        #expect(SoundGraph.ticks(from: 0.5, to: 0))
        #expect(SoundGraph.ticks(from: 1, to: -1))
        #expect(!SoundGraph.ticks(from: 0, to: 0))
        #expect(!SoundGraph.ticks(from: 0, to: 0.5))
        #expect(!SoundGraph.ticks(from: 1, to: 2))
    }

    @Test func movingANodeTurnsTheEqualizerOnAndClearsThePreset() {
        let graphic = SoundGraph.moveNode(SoundSettings(), index: 2, hz: nil, gainDb: 4.04)
        #expect(graphic.eqEnabled)
        #expect(graphic.graphicGains[2] == 4)
        #expect(graphic.preset == nil)
        var s = SoundSettings()
        s.mode = .parametric
        s.filters = [EqFilter(frequency: 500, gainDb: 1, q: 2)]
        let moved = SoundGraph.moveNode(s, index: 0, hz: 25_000, gainDb: -20)
        #expect(moved.filters[0] == EqFilter(frequency: 20_000, gainDb: -12, q: 2))
        #expect(moved.eqEnabled)
        #expect(SoundGraph.moveNode(s, index: 3, hz: nil, gainDb: 1) == s)
    }

    @Test func theReadingShowsTheNodesOwnValues() {
        #expect(SoundGraph.reading(GraphNode(hz: 62, gainDb: 3.5), parametric: false) == "+3.5 dB")
        #expect(SoundGraph.reading(GraphNode(hz: 1_200, gainDb: -3), parametric: true) == "1.2 kHz   -3 dB")
    }
}

@Suite struct PresetRowTests {
    @Test func customShowsFirstOnlyWhileTheCurveIsCustom() {
        let own = [EqPreset(name: "Mine", gains: Array(repeating: 0, count: 10))]
        let custom = PresetChoice.row(label: SoundEdits.custom, own: own)
        #expect(custom.first == PresetChoice(name: "Custom", own: false))
        #expect(custom.count == 1 + 19 + 1)
        #expect(custom.last?.key == "own:Mine")
        let rock = PresetChoice.row(label: "Rock", own: own)
        #expect(rock.first?.name == "Flat")
        #expect(rock.count == 20)
        #expect(rock.map(\.name).prefix(4) == ["Flat", "Bass Boost", "Bass Reducer", "Treble Boost"])
    }

    @Test func theRowOpensOnTheOneBeforeTheChosen() {
        let row = PresetChoice.row(label: "Rock", own: [])
        #expect(PresetChoice.firstShown(row, label: "Rock") == 5)
        #expect(PresetChoice.firstShown(row, label: "Flat") == 0)
        #expect(PresetChoice.firstShown(row, label: "Gone") == 0)
    }
}

@Suite struct SoundSliderTests {
    @Test func aSpotBecomesAStepInRange() {
        let range = -12.0...6.0
        #expect(SoundSliders.value(fraction: 0.5, step: 0.5, range: range) { SoundSliders.linearValue($0, range: range) } == -3)
        #expect(SoundSliders.value(fraction: 0.51, step: 0.5, range: range) { SoundSliders.linearValue($0, range: range) } == -3)
        #expect(SoundSliders.value(fraction: 1.2, step: 0.5, range: range) { SoundSliders.linearValue($0, range: range) } == 6)
        #expect(SoundSliders.value(fraction: 0.5, step: 1, range: 20...20_000, fromFraction: SoundSliders.hzValue) == 632)
    }

    @Test func logScalesGoBothWays() {
        #expect(abs(SoundSliders.hzFraction(20)) < 1e-12)
        #expect(abs(SoundSliders.hzFraction(20_000) - 1) < 1e-12)
        #expect(abs(SoundSliders.qValue(SoundSliders.qFraction(1.41)) - 1.41) < 1e-9)
        #expect(abs(SoundSliders.qFraction(1) - 0.5) < 1e-12)
    }

    @Test func widthReadsWithTwoDecimals() {
        #expect(SoundSliders.readQ(1.41) == "1.41")
        #expect(SoundSliders.readQ(1) == "1.00")
        #expect(SoundSliders.readQ(0.1) == "0.10")
    }

    @Test func balanceSnapsToTheCenterAndToTwentieths() {
        #expect(SoundSliders.balance(x: 200, width: 400) == 0)
        #expect(SoundSliders.balance(x: 209, width: 400) == 0)
        #expect(SoundSliders.balance(x: 400, width: 400) == 1)
        #expect(SoundSliders.balance(x: -50, width: 400) == -1)
        #expect(SoundSliders.balance(x: 324, width: 400) == 0.6)
        #expect(SoundSliders.balance(x: 210, width: 400) == 0.05)
    }
}

@Suite struct SoundModelExtraTests {
    @Test func aCorrectionsNameDropsTheEndingsFilesUse() {
        #expect(ParametricEqFile.name(from: "Sennheiser HD 650 ParametricEQ.txt") == "Sennheiser HD 650")
        #expect(ParametricEqFile.name(from: "HD 600 - ParametricEQ.txt") == "HD 600")
        #expect(ParametricEqFile.name(from: "Moondrop_ParametricEQ.txt") == "Moondrop")
        #expect(ParametricEqFile.name(from: "-Lead dash.txt") == "-Lead dash")
        #expect(ParametricEqFile.name(from: "no extension") == "no extension")
        #expect(ParametricEqFile.name(from: ".txt") == "Correction")
        #expect(ParametricEqFile.name(from: "a.b.txt") == "a.b")
    }

    @Test func theLevelNowFollowsTheMode() {
        var s = SoundSettings()
        #expect(s.effectivePreampDb() == 0)
        s.eqEnabled = true
        s.autoPreamp = false
        s.preampDb = -3
        s.correction = HeadphoneCorrection(name: "X", source: ParametricEqFile.imported, preampDb: -6, filters: [EqFilter(frequency: 100, gainDb: 3)])
        #expect(s.effectivePreampDb() == -9)
        s.autoPreamp = true
        #expect(s.effectivePreampDb() <= 0)
        #expect(SoundEdits.soundSummary(s) == "Equalizer on, Flat, with X")
    }
}
