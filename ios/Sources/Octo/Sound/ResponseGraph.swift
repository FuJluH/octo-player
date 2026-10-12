import OctoKit
import SwiftUI

/// The live frequency response: a white line with a soft glow and a tint under it while the
/// equalizer is on, grey while it is off. Nodes sit on the curve: up and down sets their gain,
/// and in parametric mode left and right sets their frequency. A double tap puts a node back to
/// 0 dB.
struct SoundResponseGraph: View {
    let settings: SoundSettings
    /// The chosen filter in parametric mode.
    let selected: Int
    let onSelect: (Int) -> Void
    let onPreview: (@escaping (SoundSettings) -> SoundSettings) -> Void
    let onSettle: () -> Void

    /// The node under the finger, while one is dragged.
    @State private var held: Int?
    @State private var drag: Drag?
    @State private var ticks = 0
    @State private var shapes = ShapeCache()

    /// What a drag started from: the node, its own values then, and where the finger came down.
    private struct Drag {
        let index: Int
        let node: GraphNode
        let down: CGPoint
        let free: Bool
        var lastGain: Double
    }

    var body: some View {
        GeometryReader { box in
            let plot = ResponsePlot(width: box.size.width, height: box.size.height)
            let shape = shapes.shape(for: settings)
            let parametric = settings.mode == .parametric
            let nodes = SoundGraph.nodes(settings)
            let points = zip(nodes, shape.nodeGains).map { CGPoint(x: plot.x($0.hz), y: plot.y($1)) }
            let active = held ?? (parametric ? selected : nil)
            ZStack(alignment: .topLeading) {
                SoundGraphDrawing(
                    plot: plot, curve: shape.curve, points: points, active: active,
                    labels: parametric ? SoundGraph.edgeLabelsHz : graphicBands,
                    reading: held.flatMap { i in nodes.indices.contains(i) ? (SoundGraph.reading(nodes[i], parametric: parametric), points[i]) : nil },
                    lit: settings.eqEnabled ? 1 : 0)
                    .animation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.25), value: settings.eqEnabled)
                    .accessibilityElement()
                    .accessibilityLabel("Equalizer curve")
                ForEach(nodes.indices, id: \.self) { i in
                    target(i, node: nodes[i], parametric: parametric)
                        .position(points.indices.contains(i) ? points[i] : .zero)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                SpatialTapGesture(count: 2).onEnded { tap in
                    // Puts the node back to 0 dB, keeping its frequency.
                    guard let index = nodeAt(tap.location, plot: plot, preferred: selected) else { return }
                    onPreview { SoundGraph.moveNode($0, index: index, hz: nil, gainDb: 0) }
                    onSettle()
                }
                .exclusively(before: SpatialTapGesture().onEnded { tap in
                    guard settings.mode == .parametric, let index = nodeAt(tap.location, plot: plot, preferred: selected) else { return }
                    onSelect(index)
                })
            )
            .gesture(SoundPan(shouldBegin: { start, moved in
                // Only a drag that starts on a node is taken; anything else scrolls the page. On
                // the ten bands only an up or down drag picks a node up.
                let free = settings.mode == .parametric
                guard nodeAt(start, plot: plot, preferred: free ? selected : nil) != nil else { return false }
                return free || abs(moved.y) > abs(moved.x)
            }) { phase, location, moved in
                handle(phase, location: location, moved: moved, plot: plot)
            })
        }
        .frame(height: ResponsePlot.height)
        .sensoryFeedback(.selection, trigger: ticks)
    }

    private func nodeAt(_ touch: CGPoint, plot: ResponsePlot, preferred: Int?) -> Int? {
        let points = SoundGraph.points(settings, plot: plot)
        return SoundGraph.nodeAt(points, touch: PlotPoint(x: touch.x, y: touch.y), reach: ResponsePlot.hitRadius, preferred: preferred)
    }

    private func handle(_ phase: SoundPan.Phase, location: CGPoint, moved: CGPoint, plot: ResponsePlot) {
        switch phase {
        case .began:
            let down = CGPoint(x: location.x - moved.x, y: location.y - moved.y)
            let free = settings.mode == .parametric
            let nodes = SoundGraph.nodes(settings)
            guard let index = nodeAt(down, plot: plot, preferred: free ? selected : nil), nodes.indices.contains(index) else { return }
            drag = Drag(index: index, node: nodes[index], down: down, free: free, lastGain: nodes[index].gainDb)
            held = index
            if free { onSelect(index) }
            follow(location, plot: plot)
        case .changed:
            follow(location, plot: plot)
        case .ended, .cancelled:
            guard drag != nil else { return }
            drag = nil
            held = nil
            onSettle()
        }
    }

    /// Moves the held node by how far the finger went, with a light tick on reaching or
    /// crossing 0 dB.
    private func follow(_ location: CGPoint, plot: ResponsePlot) {
        guard var current = drag else { return }
        let gain = SoundGraph.dragGain(start: current.node.gainDb, downY: current.down.y, fingerY: location.y, plot: plot)
        if SoundGraph.ticks(from: current.lastGain, to: gain) { ticks += 1 }
        current.lastGain = gain
        drag = current
        let hz = current.free ? SoundGraph.dragHz(start: current.node.hz, downX: current.down.x, fingerX: location.x, plot: plot) : nil
        let index = current.index
        onPreview { SoundGraph.moveNode($0, index: index, hz: hz, gainDb: gain) }
    }

    /// One target per node for screen readers, with actions in place of dragging.
    private func target(_ i: Int, node: GraphNode, parametric: Bool) -> some View {
        Color.clear
            .frame(width: 32, height: 32)
            .accessibilityElement()
            .accessibilityLabel(SoundEdits.describeNode(hz: node.hz, db: node.gainDb))
            .accessibilityAddTraits(parametric && i == selected ? [.isSelected] : [])
            .accessibilityActions {
                if parametric {
                    Button("Choose") { onSelect(i) }
                }
                Button("Raise 1 dB") { set(i, node.gainDb + 1) }
                Button("Lower 1 dB") { set(i, node.gainDb - 1) }
                Button("Reset to 0 dB") { set(i, 0) }
            }
    }

    private func set(_ index: Int, _ gain: Double) {
        onPreview { SoundGraph.moveNode($0, index: index, hz: nil, gainDb: gain) }
        onSettle()
    }
}

/// The curve and node heights, worked out again only when the filters change.
private final class ShapeCache {
    struct Shape {
        let curve: [Double]
        let nodeGains: [Double]
    }

    private var filters: [EqFilter]?
    private var nodes: [GraphNode] = []
    private var cached = Shape(curve: [], nodeGains: [])

    func shape(for settings: SoundSettings) -> Shape {
        let next = SoundGraph.shapingFilters(settings)
        let nodes = SoundGraph.nodes(settings)
        if next != filters {
            cached = Shape(curve: SoundGraph.curve(next), nodeGains: nodes.map { ResponseCurve.gainDb(next, at: $0.hz) })
        } else if nodes != self.nodes {
            cached = Shape(curve: cached.curve, nodeGains: nodes.map { ResponseCurve.gainDb(next, at: $0.hz) })
        }
        filters = next
        self.nodes = nodes
        return cached
    }
}

/// The graph's drawing. `lit` runs from 0 (equalizer off: grey, no glow) to 1 (on).
private struct SoundGraphDrawing: View, Animatable {
    let plot: ResponsePlot
    let curve: [Double]
    let points: [CGPoint]
    let active: Int?
    let labels: [Double]
    let reading: (String, CGPoint)?
    var lit: Double

    nonisolated var animatableData: Double {
        get { lit }
        set { lit = newValue }
    }

    @Environment(\.displayScale) private var scale

    /// The line's color: grey when off, white when on.
    private var line: Color {
        let t = min(1, max(0, lit))
        func mix(_ from: Double) -> Double { from / 255 + (1 - from / 255) * t }
        return Color(.sRGB, red: mix(0x6B), green: mix(0x70), blue: mix(0x75), opacity: 1)
    }

    var body: some View {
        Canvas { context, size in
            grid(&context)
            drawCurve(&context)
            for (i, point) in points.enumerated() { node(&context, at: point, big: i == active) }
            drawLabels(&context, size: size)
            if let reading { pill(&context, text: reading.0, at: reading.1, size: size) }
        }
    }

    private func grid(_ context: inout GraphicsContext) {
        let hair = 1 / max(scale, 1)
        for hz in SoundGraph.gridHz {
            let x = plot.x(hz)
            context.stroke(segment(CGPoint(x: x, y: plot.top), CGPoint(x: x, y: plot.bottom)), with: .color(.white.opacity(0.06)), lineWidth: hair)
        }
        let zero = plot.y(0)
        context.stroke(segment(CGPoint(x: plot.left, y: zero), CGPoint(x: plot.right, y: zero)), with: .color(.white.opacity(0.14)), lineWidth: hair)
    }

    private func drawCurve(_ context: inout GraphicsContext) {
        guard curve.count > 1 else { return }
        var path = Path()
        let step = (plot.right - plot.left) / Double(curve.count - 1)
        for (i, db) in curve.enumerated() {
            let point = CGPoint(x: plot.left + step * Double(i), y: plot.y(db))
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        // The tint under the line.
        var fill = path
        fill.addLine(to: CGPoint(x: plot.right, y: plot.bottom))
        fill.addLine(to: CGPoint(x: plot.left, y: plot.bottom))
        fill.closeSubpath()
        context.fill(fill, with: .linearGradient(
            Gradient(colors: [line.opacity(0.05 + 0.09 * lit), line.opacity(0.01)]),
            startPoint: CGPoint(x: 0, y: plot.top), endPoint: CGPoint(x: 0, y: plot.bottom)))
        let style = StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
        // The glow, only while the equalizer is on: three soft passes of the same line.
        if lit > 0 {
            for spread in [2.5, 1, 0.3] {
                context.drawLayer { layer in
                    layer.addFilter(.blur(radius: SoundStyle.pixelBlur(12 * spread)))
                    layer.stroke(path, with: .color(.white.opacity(0.4 * lit / 3)), style: style)
                }
            }
        }
        context.stroke(path, with: .color(line), style: style)
    }

    private func node(_ context: inout GraphicsContext, at point: CGPoint, big: Bool) {
        let radius = big ? ResponsePlot.activeRadius : ResponsePlot.nodeRadius
        if big && lit > 0 { context.fill(circle(point, radius * 2), with: .color(.white.opacity(0.18 * lit))) }
        // A dark edge so a node stands out against the line through it.
        context.fill(circle(point, radius + 1.5 / max(scale, 1)), with: .color(.black.opacity(0.45)))
        context.fill(circle(point, radius), with: .color(line))
    }

    private func drawLabels(_ context: inout GraphicsContext, size: CGSize) {
        let y = plot.bottom + ResponsePlot.padUpDown + 4
        for hz in labels {
            let text = context.resolve(Text(SoundEdits.shortHz(hz)).font(.system(size: 10).monospacedDigit()).foregroundStyle(OctoColor.textMuted))
            let measured = text.measure(in: size)
            let x = min(max(0, plot.x(hz) - measured.width / 2), size.width - measured.width)
            context.draw(text, in: CGRect(x: x, y: y, width: measured.width, height: measured.height))
        }
    }

    /// The value of the node being dragged, in a small dark pill above it, or below it near the
    /// top.
    private func pill(_ context: inout GraphicsContext, text: String, at point: CGPoint, size: CGSize) {
        let resolved = context.resolve(Text(text).font(.system(size: 11).monospacedDigit()).foregroundStyle(.white))
        let measured = resolved.measure(in: size)
        let width = measured.width + 16
        let height = measured.height + 6
        let above = point.y - 16 - height
        let top = above >= 0 ? above : point.y + 16
        let left = min(max(0, point.x - width / 2), size.width - width)
        let rect = CGRect(x: left, y: top, width: width, height: height)
        context.fill(Path(roundedRect: rect, cornerRadius: height / 2), with: .color(.black.opacity(0.72)))
        context.draw(resolved, in: CGRect(x: left + 8, y: top + 3, width: measured.width, height: measured.height))
    }

    private func segment(_ a: CGPoint, _ b: CGPoint) -> Path {
        var path = Path()
        path.move(to: a)
        path.addLine(to: b)
        return path
    }

    private func circle(_ center: CGPoint, _ radius: Double) -> Path {
        Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    }
}
