import Foundation

/// A point on the response graph, in points from its top left corner.
public struct PlotPoint: Sendable, Equatable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public func distance(to other: PlotPoint) -> Double {
        ((x - other.x) * (x - other.x) + (y - other.y) * (y - other.y)).squareRoot()
    }
}

/// Where frequencies and gains land on the response graph: frequency on a log scale across,
/// gain from +12 dB at the top to -12 dB at the bottom.
public struct ResponsePlot: Sendable, Equatable {
    /// The plot's height, and the band under it for the frequency labels.
    public static let plotHeight = 220.0
    public static let labelBand = 22.0
    /// Room around the plot so the end nodes are not cut off.
    public static let padAcross = 10.0
    public static let padUpDown = 12.0
    /// How near a node a finger has to land to take hold of it.
    public static let hitRadius = 30.0
    /// The node sizes, at rest and while held or chosen.
    public static let nodeRadius = 5.5
    public static let activeRadius = 8.0
    /// How many points the drawn curve has.
    public static let curvePoints = 192
    /// The whole graph's height.
    public static var height: Double { plotHeight + labelBand }

    public let left: Double
    public let right: Double
    public let top: Double
    public let bottom: Double
    public let pxPerDb: Double

    public init(width: Double, height: Double = ResponsePlot.height) {
        left = Self.padAcross
        right = width - Self.padAcross
        top = Self.padUpDown
        bottom = height - (Self.labelBand + Self.padUpDown)
        pxPerDb = (bottom - top) / (2 * gainRangeDb)
    }

    public func x(_ hz: Double) -> Double {
        left + log(hz / SoundEdits.minHz) / log(SoundEdits.maxHz / SoundEdits.minHz) * (right - left)
    }

    public func hz(_ x: Double) -> Double {
        let fraction = min(1, max(0, (x - left) / (right - left)))
        return SoundEdits.minHz * pow(SoundEdits.maxHz / SoundEdits.minHz, fraction)
    }

    public func y(_ db: Double) -> Double {
        top + (gainRangeDb - min(gainRangeDb, max(-gainRangeDb, db))) * pxPerDb
    }
}

/// A handle on the curve: where it is, and the gain it sets.
public struct GraphNode: Sendable, Equatable {
    public let hz: Double
    public let gainDb: Double

    public init(hz: Double, gainDb: Double) {
        self.hz = hz
        self.gainDb = gainDb
    }
}

/// The response graph's rules, apart from the drawing.
public enum SoundGraph {
    /// Where the gridlines fall, and the labels under a parametric curve.
    public static let gridHz: [Double] = [100, 1_000, 10_000]
    public static let edgeLabelsHz: [Double] = [20, 100, 1_000, 10_000, 20_000]

    /// One node per band in graphic mode, one per filter in parametric mode.
    public static func nodes(_ settings: SoundSettings) -> [GraphNode] {
        switch settings.mode {
        case .graphic: zip(graphicBands, settings.graphicGains).map { GraphNode(hz: $0, gainDb: $1) }
        case .parametric: settings.filters.map { GraphNode(hz: $0.frequency, gainDb: $0.gainDb) }
        }
    }

    /// The filters the equalizer would apply if it were on: the correction, then the own curve.
    public static func shapingFilters(_ settings: SoundSettings) -> [EqFilter] {
        var on = settings
        on.eqEnabled = true
        return on.activeFilters()
    }

    /// The drawn curve's gains at evenly spaced points across the plot.
    public static func curve(_ filters: [EqFilter]) -> [Double] {
        ResponseCurve.curve(filters, points: ResponsePlot.curvePoints)
    }

    /// Each node's height on the combined curve, the correction and every filter together.
    public static func nodeGains(_ settings: SoundSettings, filters: [EqFilter]) -> [Double] {
        nodes(settings).map { ResponseCurve.gainDb(filters, at: $0.hz) }
    }

    /// Where each node is drawn: at its frequency, on the combined curve.
    public static func points(_ settings: SoundSettings, plot: ResponsePlot) -> [PlotPoint] {
        let filters = shapingFilters(settings)
        return nodes(settings).map { PlotPoint(x: plot.x($0.hz), y: plot.y(ResponseCurve.gainDb(filters, at: $0.hz))) }
    }

    /// The node nearest a touch, if one is close enough. The chosen node wins whenever it is in
    /// reach, so stacked filters can still be told apart.
    public static func nodeAt(_ points: [PlotPoint], touch: PlotPoint, reach: Double, preferred: Int?) -> Int? {
        if let preferred, points.indices.contains(preferred), points[preferred].distance(to: touch) <= reach { return preferred }
        var best: (index: Int, distance: Double)?
        for (index, point) in points.enumerated() {
            let distance = point.distance(to: touch)
            if distance <= reach, distance < (best?.distance ?? .infinity) { best = (index, distance) }
        }
        return best?.index
    }

    /// The same edit to a node, whichever kind of curve it is on. The equalizer comes on too,
    /// so the change is heard.
    public static func moveNode(_ settings: SoundSettings, index: Int, hz: Double?, gainDb: Double) -> SoundSettings {
        var moved: SoundSettings
        switch settings.mode {
        case .graphic:
            moved = SoundEdits.withBandGain(settings, band: index, gainDb: gainDb)
        case .parametric:
            guard settings.filters.indices.contains(index) else { return settings }
            var filter = settings.filters[index]
            filter.frequency = hz ?? filter.frequency
            filter.gainDb = gainDb
            moved = SoundEdits.withFilter(settings, index: index, filter)
        }
        moved.eqEnabled = true
        return moved
    }

    /// The gain while a node is dragged: its own gain at touch-down, moved by how far the
    /// finger went, so the node does not jump to the finger.
    public static func dragGain(start: Double, downY: Double, fingerY: Double, plot: ResponsePlot) -> Double {
        SoundEdits.cleanGain(start - (fingerY - downY) / plot.pxPerDb)
    }

    /// The frequency while a parametric node is dragged sideways, in whole hertz.
    public static func dragHz(start: Double, downX: Double, fingerX: Double, plot: ResponsePlot) -> Double {
        Double(SoundEdits.roundHalfUp(plot.hz(plot.x(start) + fingerX - downX)))
    }

    /// Whether a drag from `last` to `gain` lands on 0 dB or crosses it, for a light tick.
    public static func ticks(from last: Double, to gain: Double) -> Bool {
        (last != 0 && gain == 0) || last * gain < 0
    }

    /// The reading shown beside a held node.
    public static func reading(_ node: GraphNode, parametric: Bool) -> String {
        parametric ? "\(SoundEdits.readHz(node.hz))   \(SoundEdits.readDb(node.gainDb))" : SoundEdits.readDb(node.gainDb)
    }
}

/// One preset in the preset row, and whether it is the listener's own.
public struct PresetChoice: Sendable, Hashable {
    public let name: String
    public let own: Bool

    public init(name: String, own: Bool) {
        self.name = name
        self.own = own
    }

    /// Keeps own and built-in presets apart when they share a name.
    public var key: String { (own ? "own:" : "built:") + name }

    /// The row in order: "Custom" first while the curve is custom, then the built-in presets,
    /// then the listener's own.
    public static func row(label: String, own: [EqPreset]) -> [PresetChoice] {
        var row: [PresetChoice] = []
        if label == SoundEdits.custom { row.append(PresetChoice(name: SoundEdits.custom, own: false)) }
        row += eqPresets.map { PresetChoice(name: $0.name, own: false) }
        row += own.map { PresetChoice(name: $0.name, own: true) }
        return row
    }

    /// The item the row opens on, so the chosen one shows second (or first).
    public static func firstShown(_ row: [PresetChoice], label: String) -> Int {
        max(0, (row.firstIndex { $0.name == label } ?? 0) - 1)
    }
}

/// The rules of the Sound page's sliders.
public enum SoundSliders {
    /// A spot on a slider as a value: moved in `step`s and kept in range.
    public static func value(fraction: Double, step: Double, range: ClosedRange<Double>, fromFraction: (Double) -> Double) -> Double {
        let picked = Double(SoundEdits.roundHalfUp(fromFraction(fraction) / step)) * step
        return min(range.upperBound, max(range.lowerBound, picked))
    }

    /// A value's place on an even slider.
    public static func linearFraction(_ value: Double, range: ClosedRange<Double>) -> Double {
        (value - range.lowerBound) / (range.upperBound - range.lowerBound)
    }

    public static func linearValue(_ fraction: Double, range: ClosedRange<Double>) -> Double {
        range.lowerBound + fraction * (range.upperBound - range.lowerBound)
    }

    /// Frequency on a log scale from 20 Hz to 20 kHz.
    public static func hzFraction(_ hz: Double) -> Double { log(hz / SoundEdits.minHz) / log(SoundEdits.maxHz / SoundEdits.minHz) }
    public static func hzValue(_ fraction: Double) -> Double { SoundEdits.minHz * pow(SoundEdits.maxHz / SoundEdits.minHz, fraction) }

    /// Width on a log scale from 0.1 to 10.
    public static func qFraction(_ q: Double) -> Double { log(q / SoundEdits.minQ) / log(SoundEdits.maxQ / SoundEdits.minQ) }
    public static func qValue(_ fraction: Double) -> Double { SoundEdits.minQ * pow(SoundEdits.maxQ / SoundEdits.minQ, fraction) }

    /// A width as a reading: two decimals, always with a dot.
    public static func readQ(_ q: Double) -> String { ParametricEqFile.decimal(q, 2) }

    /// How close to the middle the balance snaps to center.
    public static let centerDetent = 0.05

    /// A spot across the balance slider as a balance, snapping to the center and moving in
    /// steps of 0.05.
    public static func balance(x: Double, width: Double) -> Double {
        let raw = min(1, max(-1, (x / width) * 2 - 1))
        return abs(raw) < centerDetent ? 0 : Double(SoundEdits.roundHalfUp(raw * 20)) / 20
    }
}
