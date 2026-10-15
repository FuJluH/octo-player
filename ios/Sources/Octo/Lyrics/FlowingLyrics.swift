import CoreText
import OctoKit
import QuartzCore
import SwiftUI
import UIKit

// The view fades in over this long once the lyrics are laid out.
private let FADE_IN: Duration = .milliseconds(450)
// After a resize, the lines are laid out again once it has held this long.
private let REMEASURE_AFTER: Duration = .milliseconds(150)
// The time stamp a long press shows stays this long.
private let STAMP_SHOWN: Duration = .milliseconds(1500)
// Backing vocals, the credit, and translations sit quieter than the lead.
private let BACKGROUND_ALPHA: CGFloat = 0.6
private let CREDIT_ALPHA: CGFloat = 0.75
private let EXTRA_ALPHA: CGFloat = 0.7
// Dots across and apart, in em.
private let DOT_EM: CGFloat = 0.34
private let DOT_GAP_EM: CGFloat = 0.22

/// Everything the flowing lyrics move each frame: the engine, the lines as laid out, and the
/// loop that runs it. The loop reads the player's position every display frame; when nothing
/// moved, nothing plays and nobody scrolls, it slows to about 30 frames a second.
@MainActor
@Observable
final class FlowingModel {
    let lines: [SyncLine]
    @ObservationIgnored let engine: LyricEngine
    /// Bumped every frame the engine runs, so the view reads the engine again.
    private(set) var frame = 0
    private(set) var layout: LyricsLayout?
    /// The whole view's fade as it first appears.
    var shown = 0.0

    // What each frame reads, set by the view.
    @ObservationIgnored var position: () -> TimeInterval = { 0 }
    @ObservationIgnored var playing = false
    @ObservationIgnored var rate = 1.0
    @ObservationIgnored var offsetMs = 0
    @ObservationIgnored var outputOffsetMs = 0
    @ObservationIgnored var ink = UIColor.white
    @ObservationIgnored var calm = false

    @ObservationIgnored private var link: CADisplayLink?
    /// The layers the lines are drawn in, placed again every frame.
    @ObservationIgnored weak var surface: FlowingLayerView?
    @ObservationIgnored private var slow = false
    /// The loop stopped because nothing can move: paused, every line in place.
    @ObservationIgnored private var idle = false
    @ObservationIgnored private var measuring: Task<Void, Never>?
    /// The size and text scale last laid out for.
    @ObservationIgnored private var measuredFor: (size: CGSize, textScale: CGFloat)?

    init(_ lines: [SyncLine]) {
        self.lines = lines
        engine = LyricEngine(lines)
    }

    /// Lays the lines out for a size and text scale, off the main thread; after the first time,
    /// only once they have held still for a moment. Once measured, every line jumps into place.
    func measure(_ size: CGSize, textScale: CGFloat) {
        guard size.width > 0, size.height > 0 else { return }
        if let measuredFor, measuredFor.size == size, measuredFor.textScale == textScale { return }
        measuredFor = (size, textScale)
        measuring?.cancel()
        let first = layout == nil
        let lines = self.lines
        measuring = Task { [weak self] in
            if !first { try? await Task.sleep(for: REMEASURE_AFTER) }
            guard !Task.isCancelled else { return }
            let measured = await Task.detached(priority: .userInitiated) { () -> LyricsLayout in
                let spec = LyricsSpec(width: size.width, textScale: textScale)
                return LyricsLayout(spec: spec, lines: lines.map { measureLine($0, spec) })
            }.value
            guard !Task.isCancelled, let self else { return }
            self.engine.setGeometry(measured.baseHeights(), interludeIdle: Double(measured.spec.interludeIdle),
                                    interludeFull: Double(measured.spec.interludeFull), height: Double(size.height))
            self.layout = measured
            if first {
                withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: FADE_IN.seconds)) { self.shown = 1 }
            }
            self.start()
        }
    }

    /// The loop runs while the view shows and the app is in front; coming back starts it fresh.
    func start() {
        if idle {
            wake()
            return
        }
        guard layout != nil, link == nil else { return }
        engine.restart()
        runLink()
    }

    func stop() {
        idle = false
        link?.invalidate()
        link = nil
    }

    /// The clock takes a fresh anchor: the player played, paused, seeked or changed song.
    func anchor() {
        engine.clock.requestAnchor()
        wake()
    }

    /// The loop again after it rested, where it left off: a finger on the lines, a seek, play, or
    /// anything else that can move them.
    func wake() {
        guard idle else { return }
        idle = false
        guard layout != nil, link == nil else { return }
        engine.clock.requestAnchor()
        runLink()
    }

    private func runLink() {
        let link = CADisplayLink(target: DisplayTarget(self), selector: #selector(DisplayTarget.tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.link = link
        slow = false
    }

    fileprivate func tick(_ link: CADisplayLink) {
        guard let layout else { return }
        #if DEBUG
        FrameProbe.shared.tick(link.timestamp, reported: position(), shown: engine.lyricTime)
        defer { FrameProbe.shared.spent(CACurrentMediaTime() - link.timestamp) }
        #endif
        engine.look = AppSettings.shared.lyricsLook
        engine.reduceMotion = calm
        let fast = engine.look.bloomFast
        let nanos = Int(link.timestamp * 1e9)
        engine.frame(
            nanos,
            Int((position() * 1000).rounded()),
            playing: playing,
            rate: rate,
            offsetMs: offsetMs,
            outputOffsetMs: outputOffsetMs,
            prepare: { [lines] index in layout.prepare(index, lines[index], fast: fast) },
            release: { index in layout.release(index) }
        )
        frame = engine.frames
        surface?.render()
        #if DEBUG
        FrameProbe.shared.trace(engine, time: link.timestamp)
        #endif
        // Paused with every line in place, nobody scrolling and the player at rest: nothing can
        // move until something wakes the loop, so it stops.
        let rest = engine.settled
        if rest && !playing && !PlayerMotion.shared.moving {
            idle = true
            link.invalidate()
            self.link = nil
            return
        }
        // Nothing moved, nothing plays and nobody scrolls: look again about every 32 ms.
        if rest != slow {
            slow = rest
            link.preferredFrameRateRange = rest
                ? CAFrameRateRange(minimum: 30, maximum: 30, preferred: 30)
                : CAFrameRateRange(minimum: 30, maximum: 120, preferred: 120)
        }
    }
}

/// Holds the model weakly, so the display link never keeps it alive.
@MainActor
private final class DisplayTarget: NSObject {
    weak var model: FlowingModel?

    init(_ model: FlowingModel) {
        self.model = model
    }

    @objc func tick(_ link: CADisplayLink) {
        guard let model else {
            link.invalidate()
            return
        }
        model.tick(link)
    }
}

private extension Duration {
    var seconds: Double { Double(components.seconds) + Double(components.attoseconds) / 1e18 }
}

/// Synced lyrics that flow: the line being sung sits a third of the way down, the rest ripple
/// into place around it on springs, each word fills with a soft sweep of light as it is sung, and
/// long notes bloom letter by letter. A drag scrolls them by hand; a tap plays from a line; a long
/// press shows when it is sung.
struct FlowingLyricsView: View {
    let model: FlowingModel
    let songOffsetMs: Int
    let outputOffsetMs: Int
    let ink: Color
    let calm: Bool
    let seek: (TimeInterval) -> Void
    @Environment(Player.self) private var player
    @Environment(\.scenePhase) private var phase
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var stamp: Int?
    @State private var stampToken = 0
    @State private var motion = PlayerMotion.shared

    var body: some View {
        GeometryReader { box in
            ZStack(alignment: .topLeading) {
                if model.layout != nil {
                    FlowingLayers(model: model, ink: ink, calm: calm, tap: tap, hold: hold,
                                  press: { index, down in
                                      model.wake()
                                      model.engine.press(index, down: down)
                                  },
                                  dragStart: {
                                      model.wake()
                                      model.engine.dragStart()
                                  },
                                  dragBy: {
                                      model.wake()
                                      model.engine.dragBy($0)
                                  },
                                  dragEnd: {
                                      model.wake()
                                      model.engine.dragEnd()
                                  })
                    if let stamp, let layout = model.layout, model.engine.states.indices.contains(stamp) {
                        FrameFollower(model: model) {
                            TimeStampPill(engine: model.engine, index: stamp, spec: layout.spec,
                                          text: asClock(max(heardAt(Int((model.lines[stamp].start * 1000).rounded()), songOffsetMs + outputOffsetMs), 0) / 1000))
                        }
                    }
                }
            }
            .frame(width: box.size.width, height: box.size.height, alignment: .topLeading)
            .opacity(model.shown)
            .onAppear { model.measure(box.size, textScale: UIFontMetrics.default.scaledValue(for: 1)) }
            .onChange(of: box.size) { _, size in model.measure(size, textScale: UIFontMetrics.default.scaledValue(for: 1)) }
            .onChange(of: typeSize) { _, _ in model.measure(box.size, textScale: UIFontMetrics.default.scaledValue(for: 1)) }
        }
        .clipped()
        .onAppear(perform: sync)
        .onChange(of: songOffsetMs) { _, _ in sync() }
        .onChange(of: outputOffsetMs) { _, _ in sync() }
        .onChange(of: calm) { _, _ in sync() }
        .onChange(of: player.isPlaying) { _, _ in sync(); model.anchor() }
        .onChange(of: player.current?.id) { _, _ in model.anchor() }
        .onChange(of: motion.moving) { _, now in if now { model.wake() } }
        .onChange(of: player.speed) { _, _ in sync(); model.anchor() }
        // The loop rests only while the app is out of sight; Control Center and the like leave
        // it running.
        .onChange(of: phase) { _, now in
            if now == .background { model.stop() } else { model.start() }
        }
        .onDisappear { model.stop() }
        .task(id: stampToken) {
            guard stamp != nil else { return }
            try? await Task.sleep(for: STAMP_SHOWN)
            if !Task.isCancelled { stamp = nil }
        }
    }

    /// Hands the frame loop what it reads every frame.
    private func sync() {
        let player = self.player
        model.position = { player.livePosition }
        model.playing = player.isPlaying
        model.rate = Double(player.speed)
        model.offsetMs = songOffsetMs
        model.outputOffsetMs = outputOffsetMs
        model.ink = UIColor(ink)
        model.calm = calm
        if phase != .background { model.start() }
    }

    private func tap(_ index: Int) {
        let line = model.lines[index]
        // A line faded right out is not there to tap.
        guard !line.isCredit, model.engine.states[index].opacity >= 0.05 else { return }
        // Played from where it is heard, with both timings, so the line is just starting when
        // the tap lands.
        let target = heardAt(Int((line.start * 1000).rounded()), totalOffset(songMs: songOffsetMs, outputMs: outputOffsetMs))
        model.wake()
        model.engine.tapped(index, playerTarget: Double(target) / 1000)
        seek(Double(target) / 1000)
        UIAccessibility.post(notification: .announcement, argument: NSAttributedString(
            string: "Playing from \(asClock(max(target, 0) / 1000))",
            attributes: [.accessibilitySpeechAnnouncementPriority: UIAccessibilityPriority.low]))
    }

    private func hold(_ index: Int) {
        stamp = index
        stampToken += 1
    }
}

/// The time a long-pressed line starts, in a small pill just above it, following the line but
/// not scaled, blurred or faded with it.
private struct TimeStampPill: View {
    let engine: LyricEngine
    let index: Int
    let spec: LyricsSpec
    let text: String

    var body: some View {
        let st = engine.states[index]
        let top = st.y.value() + engine.scrollOffset
        let right = st.line.alignRight
        Text(text)
            .font(.system(size: UIFontMetrics.default.scaledValue(for: 11.52), weight: .bold).monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color(hex: 0x121214, opacity: Double(0x52) / 255), in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.16), lineWidth: 0.5))
            .fixedSize()
            .frame(width: spec.width - (right ? spec.right : spec.left), height: 0, alignment: right ? .bottomTrailing : .bottomLeading)
            .offset(x: right ? 0 : spec.left, y: top - 4)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Reads the frame counter, so what it holds follows the lines every frame.
private struct FrameFollower<Content: View>: View {
    let model: FlowingModel
    @ViewBuilder let content: Content

    var body: some View {
        let _ = model.frame
        content
    }
}

/// Draws one flowing line with Core Text.
struct LyricPainter {
    let engine: LyricEngine
    let layout: LyricsLayout
    let index: Int
    let ink: UIColor
    let calm: Bool

    func draw(_ cg: CGContext) {
        let st = engine.states[index]
        let line = st.line
        let box = layout.lines[index]
        if line.isInterlude {
            drawDots(cg, st)
            return
        }
        let pair = st.brightness()
        let voice: CGFloat = line.isBackground ? BACKGROUND_ALPHA : 1
        if let piece = box.block {
            let alpha = line.isCredit ? CREDIT_ALPHA : CGFloat(pair.bright) * voice
            drawBlock(cg, piece, alpha: alpha)
        }
        if !box.words.isEmpty {
            drawWords(cg, st, box, bright: CGFloat(pair.bright) * voice, dark: CGFloat(pair.dark) * voice)
        }
        for extra in box.extras { drawBlock(cg, extra, alpha: EXTRA_ALPHA) }
    }

    private func drawBlock(_ cg: CGContext, _ piece: TextPiece, alpha: CGFloat) {
        cg.saveGState()
        cg.textMatrix = .identity
        cg.translateBy(x: piece.x, y: piece.y + piece.block.size.height + 1)
        cg.scaleBy(x: 1, y: -1)
        cg.setFillColor(ink.withAlphaComponent(alpha).cgColor)
        CTFrameDraw(piece.block.frame, cg)
        cg.restoreGState()
    }

    private func drawWords(_ cg: CGContext, _ st: LineState, _ box: LineBox, bright: CGFloat, dark: CGFloat) {
        let line = st.line
        let look = engine.look
        let t = engine.lyricTime
        // Sung long ago: drawn bright and risen, with nothing left to move.
        let cold = st.status == .passed && !st.live
        let lift = calm ? 0 : look.fraction(.lift)
        let letters = calm || !st.live ? nil : box.glyphs
        let fast = look.bloomFast
        let held = letters == nil ? [] : heldWords(line.words, fast: fast)
        let lastGroup = (line.words.dropLast().lastIndex { $0.trailingSpace } ?? -1) + 1
        for (j, word) in line.words.enumerated() where j < box.words.count {
            let wb = box.words[j]
            var rise = 0.0
            if lift != 0 {
                rise = cold ? -liftHeightEm(background: line.isBackground, fast: fast) * lift
                    : liftEm(t, start: word.start, end: word.end, background: line.isBackground, lift: lift, fast: fast)
            }
            let riseY = CGFloat(rise) * box.em
            let shape = maskShape(wordWidth: Double(wb.width), lineHeight: Double(wb.rowHeight), softness: look.fraction(.fade))
            let progress = cold ? 1.0 : fillProgress(t, start: word.start, end: word.end, edge: shape.edge)
            let glyphs = letters.flatMap { j < $0.count ? $0[j] : nil }
            let bloom = glyphs.flatMap { found in
                emphasisFor(word.end - word.start, glyphs: found.count, last: j >= lastGroup,
                            emphasis: look.fraction(.emphasis), glow: look.fraction(.glow), fast: fast, held: j < held.count && held[j])
            }
            let paint: (CGFloat) -> Void = { alpha in
                paintWord(cg, wb, glyphs, bloom, word, t: t, rise: riseY, em: box.em, lift: lift, background: line.isBackground, alpha: alpha)
            }
            if progress <= 0 {
                paint(dark)
            } else if progress >= 1 {
                paint(bright)
            } else {
                fillWord(cg, wb, em: box.em, progress: progress, shape: shape, rtl: line.rtl, bright: bright, dark: dark, paint: paint)
            }
        }
    }

    /// A word part sung: drawn in full into its own layer, then an alpha mask slid across it
    /// keeps the sung side bright and the rest dark.
    private func fillWord(_ cg: CGContext, _ wb: WordBox, em: CGFloat, progress: Double, shape: MaskShape, rtl: Bool,
                          bright: CGFloat, dark: CGFloat, paint: (CGFloat) -> Void) {
        guard wb.width > 0 else { return }
        let margin = 0.5 * em
        let area = CGRect(x: wb.x - margin, y: wb.rowTop - margin, width: wb.width + 2 * margin, height: wb.rowHeight + 2 * margin)
        let left = CGFloat(maskLeft(progress, wordLeft: Double(wb.x), wordWidth: Double(wb.width), shape: shape, rtl: rtl))
        let right = left + CGFloat(shape.size) * wb.width
        let near = CGFloat(shape.brightStop), far = CGFloat(shape.darkStop)
        let lit = UIColor.black.withAlphaComponent(bright).cgColor
        let unlit = UIColor.black.withAlphaComponent(dark).cgColor
        let colors = rtl ? [unlit, unlit, lit, lit] : [lit, lit, unlit, unlit]
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, near, far, 1]) else {
            paint(bright)
            return
        }
        cg.saveGState()
        cg.beginTransparencyLayer(in: area, auxiliaryInfo: nil)
        paint(1)
        cg.setBlendMode(.destinationIn)
        cg.clip(to: area)
        cg.drawLinearGradient(gradient, start: CGPoint(x: left, y: 0), end: CGPoint(x: right, y: 0),
                              options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        cg.endTransparencyLayer()
        cg.restoreGState()
    }

    /// A word at one brightness: whole, or letter by letter while it blooms.
    private func paintWord(_ cg: CGContext, _ wb: WordBox, _ glyphs: [GlyphBox]?, _ bloom: Emphasis?, _ word: SyncWord,
                           t: Double, rise: CGFloat, em: CGFloat, lift: Double, background: Bool, alpha: CGFloat) {
        guard let glyphs, let bloom else {
            drawRun(cg, wb.run, x: wb.x, top: wb.top + rise, alpha: alpha, glow: nil)
            return
        }
        for (k, glyph) in glyphs.enumerated() {
            let pose = glyphPose(t, wordStart: word.start, emphasis: bloom, i: k, glyphs: glyphs.count)
            let bob = CGFloat(bobEm(t, wordStart: word.start, emphasis: bloom, i: k, lift: lift, background: background)) * em
            let x = wb.x + glyph.x + CGFloat(pose.dxEm) * em
            let y = wb.top + rise + CGFloat(pose.dyEm) * em + bob
            let radius = CGFloat(bloom.glowRadiusEm) * em
            let glow: (CGFloat, CGFloat)? = pose.glowAlpha > 0.01 && radius > 0.5 ? (radius, CGFloat(min(pose.glowAlpha, 1))) : nil
            let scale = CGFloat(pose.scale)
            cg.saveGState()
            cg.translateBy(x: x + glyph.width / 2, y: y + glyph.run.height / 2)
            cg.scaleBy(x: scale, y: scale)
            drawRun(cg, glyph.run, x: -glyph.width / 2, top: -glyph.run.height / 2, alpha: alpha, glow: glow)
            cg.restoreGState()
        }
    }

    /// One run of text with its top-left at (`x`, `top`), in the ink at `alpha`, with a white
    /// glow around it when asked.
    private func drawRun(_ cg: CGContext, _ run: TextRun, x: CGFloat, top: CGFloat, alpha: CGFloat, glow: (radius: CGFloat, alpha: CGFloat)?) {
        cg.saveGState()
        if let glow {
            // White even on a pale background.
            cg.setShadow(offset: .zero, blur: glow.radius, color: UIColor.white.withAlphaComponent(glow.alpha).cgColor)
        }
        cg.textMatrix = .identity
        cg.translateBy(x: x, y: top + run.ascent)
        cg.scaleBy(x: 1, y: -1)
        cg.textPosition = .zero
        cg.setFillColor(ink.withAlphaComponent(alpha).cgColor)
        CTLineDraw(run.line, cg)
        cg.restoreGState()
    }

    /// The three dots of an interlude, centered in its current height.
    private func drawDots(_ cg: CGContext, _ st: LineState) {
        guard st.status == .active else { return }
        let line = st.line
        let spec = layout.spec
        let pose = calm ? StillDots : dotsPose(engine.lyricTime - line.start, f: line.end - line.start, grown: st.grownIn)
        let dot = DOT_EM * spec.em
        let gap = DOT_GAP_EM * spec.em
        let across = 3 * dot + 2 * gap
        let startX = line.alignRight ? spec.left + spec.available - across : spec.left
        let middle = CGFloat(st.height / 2)
        for k in 0..<3 {
            let radius = dot / 2 * CGFloat(pose.scale)
            let alpha = CGFloat(min(max(pose.opacity * pose.lights[k], 0), 1))
            let center = CGPoint(x: startX + dot / 2 + CGFloat(k) * (dot + gap), y: middle)
            cg.setFillColor(ink.withAlphaComponent(alpha).cgColor)
            cg.fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        }
    }
}

#if DEBUG
import os

/// Counts the lyrics loop's frames and logs, every two seconds, how even they came and how long
/// each frame's own work took, for checking smoothness on a device.
@MainActor
final class FrameProbe {
    static let shared = FrameProbe()
    private let log = Logger(subsystem: "app.winters.octo", category: "lyrics")
    private var last: CFTimeInterval?
    private var since: CFTimeInterval = 0
    private var count = 0
    private var longest: CFTimeInterval = 0
    private var late = 0
    private var work: CFTimeInterval = 0

    private var lastReported = -1.0
    private var changes = 0
    private var biggestStep = 0.0
    private var lastShown = -1.0
    private var backSteps = 0

    func tick(_ time: CFTimeInterval, reported: Double, shown: Double) {
        if reported != lastReported {
            if lastReported >= 0 { biggestStep = max(biggestStep, reported - lastReported) }
            changes += 1
            lastReported = reported
        }
        if lastShown >= 0 && shown < lastShown - 0.001 { backSteps += 1 }
        lastShown = shown
        if let last {
            let gap = time - last
            longest = max(longest, gap)
            if gap > 1.0 / 50 { late += 1 }
        } else {
            since = time
        }
        last = time
        count += 1
        if time - since >= 2 {
            let fps = Double(count) / (time - since)
            log.notice("frames \(fps, format: .fixed(precision: 1)) fps, longest \(self.longest * 1000, format: .fixed(precision: 1)) ms, late \(self.late), position changes \(self.changes), biggest step \(self.biggestStep * 1000, format: .fixed(precision: 0)) ms, shown went back \(self.backSteps), work \(self.work / Double(max(self.count, 1)) * 1000, format: .fixed(precision: 2)) ms")
            since = time
            count = 0
            longest = 0
            late = 0
            work = 0
            changes = 0
            biggestStep = 0
            backSteps = 0
        }
    }

    func spent(_ seconds: CFTimeInterval) { work += seconds }

    private var lastFocus = -1
    private var traceUntil: CFTimeInterval = 0

    /// For a second after the sung line changes, logs every frame where that line sits and how
    /// far the lines have scrolled.
    func trace(_ engine: LyricEngine, time: CFTimeInterval) {
        guard ProcessInfo.processInfo.environment["OCTO_DRIVE"]?.contains("lyricstrace") == true else { return }
        let focus = engine.focus
        if focus != lastFocus {
            lastFocus = focus
            traceUntil = time + 1
        }
        guard time < traceUntil, engine.states.indices.contains(focus) else { return }
        let y = engine.states[focus].y.value()
        log.notice("trace t \(time, format: .fixed(precision: 3)) focus \(focus) y \(y, format: .fixed(precision: 1)) scroll \(engine.scrollOffset, format: .fixed(precision: 1)) lyric \(engine.lyricTime, format: .fixed(precision: 3))")
    }
}
#endif
