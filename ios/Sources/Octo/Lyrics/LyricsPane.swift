import CoreText
import OctoKit
import SwiftUI
import UIKit

/// The lyrics, filling the player in lyrics mode. Synced lyrics follow the song in the chosen
/// style: flowing, or the classic view with the line being sung in the middle; a tap on a line
/// plays from there. Plain lyrics are text to scroll. The flowing lyrics reach `edgeBleed` past
/// the sides, to the screen's own margins.
struct LyricsPane: View {
    var edgeBleed: CGFloat = 0
    /// The player's word color: dark on a pale background, white otherwise.
    let ink: Color
    @Environment(LyricsStore.self) private var store
    @Environment(Player.self) private var player
    @Environment(\.octoReduceMotion) private var calm
    @Environment(\.scenePhase) private var phase
    @State private var settings = AppSettings.shared
    /// The pane is on screen, and so whether it counts as watching the lyrics.
    @State private var visible = false
    @State private var watching = false
    @State private var timing = LyricsSongTiming.shared
    @State private var refreshHz = 60.0

    var body: some View {
        let state = store.state
        ZStack {
            content(state)
                .id(StateKey(state))
                .transition(.opacity)
        }
        .animation(.octoTween(fixed: 300), value: StateKey(state))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            store.attach(player)
            visible = true
            syncWatch()
        }
        .onDisappear {
            visible = false
            syncWatch()
        }
        // A phone locked or the app put away stops watching, as leaving the screen does.
        .onChange(of: phase) { _, _ in syncWatch() }
        .onChange(of: keepsScreenOn(state), initial: true) { _, on in UIApplication.shared.isIdleTimerDisabled = on }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .background(RefreshRateReader(hz: $refreshHz))
    }

    private func syncWatch() {
        let wanted = visible && phase != .background
        guard wanted != watching else { return }
        watching = wanted
        if wanted { store.watch() } else { store.unwatch() }
    }

    /// The screen stays on while the words are there to read, unless that is switched off.
    private func keepsScreenOn(_ state: LyricsState) -> Bool {
        if case .found = state { return settings.keepScreenOn }
        return false
    }

    @ViewBuilder
    private func content(_ state: LyricsState) -> some View {
        switch state {
        case .found(let trackId, let lyrics):
            let look = settings.lyricsLook
            let flowing = lyrics.synced && !lyrics.instrumental && look.style == .flowing
            let songOffset = timing.offset(trackId)
            let outputOffset = LyricsOutput.viewOffset(refreshHz: refreshHz)
            // Bled first, then faded, so the fade covers the overhang too.
            FadedEdges {
                Group {
                    if lyrics.instrumental {
                        QuietLyrics(text: "Instrumental")
                    } else if lyrics.synced && flowing {
                        FlowingHost(lyrics: lyrics, songOffsetMs: songOffset, outputOffsetMs: outputOffset, ink: ink,
                                    calm: calm)
                    } else if lyrics.synced {
                        ClassicLyrics(lyrics: lyrics, offsetMs: totalOffset(songMs: songOffset, outputMs: outputOffset))
                    } else {
                        PlainLyrics(lyrics: lyrics)
                    }
                }
            }
            .padding(.horizontal, flowing ? -edgeBleed : 0)
        case .none:
            QuietLyrics(text: "No lyrics for this song")
        case .failed(let trackId):
            // Not "no lyrics": the lookup could not finish. It is tried again on its own when the
            // network comes back, or here with a tap.
            QuietLyrics(text: "Couldn't load lyrics, tap to retry") { store.retry(trackId) }
        case .hiddenForSong:
            QuietLyrics(text: "Lyrics are hidden for this song")
        case .loading, .hidden:
            Color.clear
        }
    }
}

/// What the pane cross-fades on: the whole state, so other lyrics for the same song fade too.
private struct StateKey: Hashable {
    let key: String

    init(_ state: LyricsState) {
        switch state {
        case .hidden: key = "hidden"
        case .hiddenForSong: key = "hiddenForSong"
        case .loading: key = "loading"
        case .none: key = "none"
        case .failed(let id): key = "failed:\(id)"
        case .found(let id, let lyrics):
            let whole = (try? JSONEncoder().encode(lyrics)).map { $0.hashValue } ?? 0
            key = "found:\(id):\(whole)"
        }
    }
}

/// The flowing lyrics for one set of lyrics, made afresh for any change to the lyrics.
private struct FlowingHost: View {
    let lyrics: Lyrics
    let songOffsetMs: Int
    let outputOffsetMs: Int
    let ink: Color
    let calm: Bool
    @Environment(Player.self) private var player
    @State private var model: FlowingModel?

    var body: some View {
        Group {
            if let model, !model.lines.isEmpty {
                FlowingLyricsView(model: model, songOffsetMs: songOffsetMs, outputOffsetMs: outputOffsetMs, ink: ink, calm: calm) {
                    player.seek(to: $0)
                }
                .id(ObjectIdentifier(model))
            } else {
                Color.clear
            }
        }
        .onAppear { if model == nil { model = FlowingModel(LyricMapper.map(lyrics)) } }
        .onChange(of: lyrics) { _, new in model = FlowingModel(LyricMapper.map(new)) }
        // A seek, a new song or the same one again, play or pause, or a new speed: the lyrics
        // clock takes a fresh reading.
        .onChange(of: player.timeEvents) { _, _ in model?.anchor() }
    }
}

/// A quiet line in the middle of the pane; a tap does something when it says so.
struct QuietLyrics: View {
    let text: String
    var tap: (() -> Void)?

    var body: some View {
        Group {
            if let tap {
                Button(action: tap) {
                    label.padding(24)
                }
                .buttonStyle(NoPress())
            } else {
                label
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var label: some View {
        Text(text)
            .font(.octoBody)
            .foregroundStyle(OctoColor.textMuted)
            .multilineTextAlignment(.center)
    }
}

/// Lines fade out at the top and bottom edges instead of being cut off: over 32 points, or
/// less on a short pane.
private struct FadedEdges<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        GeometryReader { box in
            let edge = min(32 / max(box.size.height, 1), 0.45)
            content
                .frame(width: box.size.width, height: box.size.height)
                .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: edge),
                                             .init(color: .black, location: 1 - edge), .init(color: .clear, location: 1)],
                                     startPoint: .top, endPoint: .bottom))
        }
    }
}

/// Reads the screen's refresh rate once, for how far ahead the words are drawn.
private struct RefreshRateReader: UIViewRepresentable {
    @Binding var hz: Double

    func makeUIView(context: Context) -> UIView { RateView(hz: $hz) }
    func updateUIView(_ view: UIView, context: Context) {}

    private final class RateView: UIView {
        let hz: Binding<Double>

        init(hz: Binding<Double>) {
            self.hz = hz
            super.init(frame: .zero)
            isUserInteractionEnabled = false
        }

        required init?(coder: NSCoder) { nil }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard let screen = window?.windowScene?.screen else { return }
            let rate = Double(screen.maximumFramesPerSecond)
            DispatchQueue.main.async { [hz] in hz.wrappedValue = rate }
        }
    }
}

// MARK: Plain

/// Lyrics with no timing: text to scroll.
private struct PlainLyrics: View {
    let lyrics: Lyrics
    /// 20 points, following the phone's text size.
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 20

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(lyrics.lines.enumerated()), id: \.offset) { _, line in
                    if line.text.isEmpty {
                        Spacer().frame(height: 18)
                    } else {
                        Text(line.text)
                            .font(.system(size: size, weight: .bold))
                            .tracking(-0.2)
                            .lineSpacing(max(0, size * 1.2 - UIFont.systemFont(ofSize: size, weight: .bold).lineHeight))
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(.vertical, 4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(.vertical, 32)
        }
        .scrollIndicators(.hidden)
    }
}

// MARK: Classic

// Sizes: the line being sung is bigger than the rest.
private let SUNG_LINE_PT: CGFloat = 28
private let OTHER_LINE_PT: CGFloat = 20
// How bright the words are: sung, still to sing, and lines not being sung.
private let SUNG_ALPHA: CGFloat = 0.85
private let UNSUNG_ALPHA: CGFloat = 0.5
private let RESTING_ALPHA: CGFloat = 0.35
// Backing vocals sit quieter than the lead.
private let BACKING_SUNG_ALPHA: CGFloat = 0.55
private let BACKING_ALPHA: CGFloat = 0.3
private let BACKING_RESTING_ALPHA: CGFloat = 0.2
/// How lines move as the song reaches them: damping 0.7, stiffness 80.
private let lineSpring = Animation.interpolatingSpring(mass: 1, stiffness: 80, damping: 2 * 0.7 * 80.0.squareRoot())

private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }

/// The classic view: the line being sung in the middle, growing as it is reached, its words
/// brightening as they are sung. A drag stops it following the song until three seconds after
/// the finger lifts.
private struct ClassicLyrics: View {
    let lyrics: Lyrics
    let offsetMs: Int
    @Environment(Player.self) private var player
    @State private var following = true
    @State private var placed = false
    @State private var resume: Task<Void, Never>?
    @State private var heldAt: Int?

    var body: some View {
        let lines = lyrics.shownLines()
        // Paused, nothing moves until a seek, which redraws the lines at once.
        let _ = player.timeEvents
        GeometryReader { box in
            TimelineView(.animation(paused: !player.isPlaying && heldAt == nil)) { time in
                let position = heldAt ?? lyricsClock(Int((player.livePosition * 1000).rounded()), offsetMs)
                let current = lines.lineAt(position)
                ScrollViewReader { reader in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(lines.indices, id: \.self) { index in
                                ClassicRow(line: lines[index], end: lines.endOf(index), active: current == index, position: position,
                                           width: box.size.width) { at in seek(at) }
                                    .id(index)
                            }
                        }
                        .padding(.vertical, box.size.height / 2)
                    }
                    .scrollIndicators(.hidden)
                    // A drag stops following; it resumes three seconds after the finger lifts.
                    .onScrollPhaseChange { old, phase in
                        if phase == .interacting {
                            resume?.cancel()
                            following = false
                        } else if old == .interacting, !following {
                            resume?.cancel()
                            resume = Task {
                                try? await Task.sleep(for: .seconds(3))
                                if !Task.isCancelled { following = true }
                            }
                        }
                    }
                    .onChange(of: following ? max(current, 0) : nil, initial: true) { _, index in
                        guard let index else { return }
                        if placed {
                            withAnimation(lineSpring) { reader.scrollTo(index, anchor: .center) }
                        } else {
                            reader.scrollTo(index, anchor: .center)
                            placed = true
                        }
                    }
                }
                .onChange(of: time.date) { _, _ in
                    if let held = heldAt, abs(Int((player.livePosition * 1000).rounded()) - (held + offsetMs)) < 500 { heldAt = nil }
                }
            }
        }
    }

    /// A tap plays from where the line is heard, not where it is written.
    private func seek(_ at: Int) {
        heldAt = at
        following = true
        player.seek(to: Double(heardAt(at, offsetMs)) / 1000)
        Task {
            try? await Task.sleep(for: .seconds(1))
            heldAt = nil
        }
    }
}

/// One classic line: its size and brightness follow `emphasis`, which springs to 1 while it is
/// the line being sung.
private struct ClassicRow: View {
    let line: LyricLine
    let end: Int?
    let active: Bool
    let position: Int
    let width: CGFloat
    let seek: (Int) -> Void
    @State private var emphasis: CGFloat = 0
    @State private var placed = false

    var body: some View {
        ClassicRowBody(line: line, end: end, active: active, position: position, width: width, seek: seek, emphasis: emphasis)
            .onChange(of: active, initial: true) { _, now in
                // The first look shows the line as it is; only later changes move.
                guard placed else {
                    emphasis = now ? 1 : 0
                    placed = true
                    return
                }
                withAnimation(lineSpring) { emphasis = now ? 1 : 0 }
            }
    }
}

private struct ClassicRowBody: View, Animatable {
    let line: LyricLine
    let end: Int?
    let active: Bool
    let position: Int
    let width: CGFloat
    let seek: (Int) -> Void
    var emphasis: CGFloat

    nonisolated var animatableData: CGFloat {
        get { emphasis }
        set { emphasis = newValue }
    }

    var body: some View {
        if line.isGap {
            GapDots(line: line, end: end, active: active, emphasis: emphasis, position: position) { seek(line.startMs) }
        } else {
            let shown = min(max(emphasis, 0), 1)
            let size = lerp(OTHER_LINE_PT, SUNG_LINE_PT, emphasis)
            let alignRight = line.duet
            VStack(alignment: alignRight ? .trailing : .leading, spacing: 0) {
                if line.background {
                    TimedText(text: line.text, words: line.words, size: size * 0.8, alignRight: alignRight, emphasis: shown, lineEnd: end,
                              position: position, width: width, sung: BACKING_SUNG_ALPHA, unsung: BACKING_ALPHA, resting: BACKING_RESTING_ALPHA) {
                        seek($0?.startMs ?? line.startMs)
                    }
                } else {
                    TimedText(text: line.text, words: line.words, size: size, alignRight: alignRight, emphasis: shown, lineEnd: end,
                              position: position, width: width, sung: SUNG_ALPHA, unsung: UNSUNG_ALPHA, resting: RESTING_ALPHA) {
                        seek($0?.startMs ?? line.startMs)
                    }
                }
                if !line.backingText.trimmingCharacters(in: .whitespaces).isEmpty {
                    TimedText(text: line.backingText, words: line.backing, size: size * 0.7, alignRight: alignRight, emphasis: shown,
                              lineEnd: end, position: position, width: width, sung: BACKING_SUNG_ALPHA, unsung: BACKING_ALPHA,
                              resting: BACKING_RESTING_ALPHA) {
                        seek($0?.startMs ?? line.startMs)
                    }
                    .padding(.top, 2)
                }
                if let translation = line.translation {
                    Text(translation)
                        .font(.octoBody)
                        .foregroundStyle(.white.opacity(Double(lerp(0.3, 0.6, shown))))
                        .multilineTextAlignment(alignRight ? .trailing : .leading)
                        .frame(maxWidth: .infinity, alignment: alignRight ? .trailing : .leading)
                        .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: alignRight ? .trailing : .leading)
            .padding(.vertical, 10)
        }
    }
}

/// A line of lyrics drawn by hand, so the part already sung can be brighter than the rest: every
/// word that has ended, and the share of the word being sung that has gone by, with a hard edge.
private struct TimedText: View {
    let text: String
    let words: [LyricWord]
    let size: CGFloat
    let alignRight: Bool
    let emphasis: CGFloat
    let lineEnd: Int?
    let position: Int
    let width: CGFloat
    let sung: CGFloat
    let unsung: CGFloat
    let resting: CGFloat
    let tap: (LyricWord?) -> Void

    var body: some View {
        let block = ClassicBlock(text, size: size, width: width, alignRight: alignRight)
        Canvas { context, _ in
            context.withCGContext { cg in draw(block, cg) }
        }
        .frame(width: width, height: block.height)
        .contentShape(Rectangle())
        .onTapGesture { at in
            let index = block.characterAt(at)
            tap(index.flatMap { c in words.first { c >= $0.from && c < $0.to } })
        }
        .accessibilityElement()
        .accessibilityLabel(text)
        .accessibilityAddTraits(.isButton)
    }

    private func draw(_ block: ClassicBlock, _ cg: CGContext) {
        let base = lerp(resting, words.isEmpty ? sung : unsung, emphasis)
        if words.isEmpty || emphasis <= 0.01 {
            block.draw(cg, alpha: base)
            return
        }
        let area = sungArea(block)
        cg.saveGState()
        let outside = CGMutablePath()
        outside.addRect(CGRect(x: -width, y: -block.height, width: width * 3, height: block.height * 3))
        outside.addPath(area)
        cg.addPath(outside)
        cg.clip(using: .evenOdd)
        block.draw(cg, alpha: base)
        cg.restoreGState()
        cg.saveGState()
        cg.addPath(area)
        cg.clip()
        block.draw(cg, alpha: lerp(resting, sung, emphasis))
        cg.restoreGState()
    }

    /// The part of the text sung by now: every word that has ended, and the share of the word
    /// being sung that has gone by.
    private func sungArea(_ block: ClassicBlock) -> CGPath {
        let length = text.utf16.count
        var sungTo = 0
        var partial: (LyricWord, CGFloat)?
        for (index, word) in words.enumerated() {
            if position < word.startMs { break }
            let end = word.endMs ?? (index + 1 < words.count ? words[index + 1].startMs : nil) ?? lineEnd ?? (word.startMs + 1000)
            if position >= end {
                sungTo = min(word.to, length)
            } else {
                partial = (word, min(max(CGFloat(position - word.startMs) / CGFloat(max(end - word.startMs, 1)), 0), 1))
                break
            }
        }
        let area = CGMutablePath()
        if sungTo > 0 { for rect in block.rects(0, sungTo) { area.addRect(rect) } }
        if let (word, share) = partial {
            let from = min(max(word.from, 0), length)
            let to = min(max(word.to, from), length)
            if to > from {
                let box = block.rects(from, to).reduce(CGRect.null) { $0.union($1) }
                let width = box.width * share
                let rightToLeft = isRtl(String(text.utf16.dropFirst(from).prefix(to - from)) ?? "")
                area.addRect(rightToLeft ? CGRect(x: box.maxX - width, y: box.minY, width: width, height: box.height)
                                         : CGRect(x: box.minX, y: box.minY, width: width, height: box.height))
            }
        }
        return area
    }
}

/// A classic line's text, wrapped to the pane's width at one size, to draw and to find where a
/// tap landed.
private struct ClassicBlock {
    let frame: CTFrame
    let lines: [CTLine]
    let origins: [CGPoint]
    let height: CGFloat
    let lineHeight: CGFloat

    init(_ text: String, size: CGFloat, width: CGFloat, alignRight: Bool) {
        let font = UIFont.systemFont(ofSize: size, weight: .bold)
        lineHeight = 1.2 * size
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = lineHeight
        paragraph.maximumLineHeight = lineHeight
        paragraph.alignment = alignRight ? .right : .left
        let attributed = NSAttributedString(string: text, attributes: [
            .font: font, .paragraphStyle: paragraph, .kern: -0.2,
            NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
        ])
        let setter = CTFramesetterCreateWithAttributedString(attributed)
        let fit = CTFramesetterSuggestFrameSizeWithConstraints(setter, CFRange(location: 0, length: 0), nil,
                                                              CGSize(width: max(width, 1), height: .greatestFiniteMagnitude), nil)
        height = max(ceil(fit.height), lineHeight)
        frame = CTFramesetterCreateFrame(setter, CFRange(location: 0, length: 0),
                                         CGPath(rect: CGRect(x: 0, y: 0, width: max(width, 1), height: height + 1), transform: nil), nil)
        lines = (CTFrameGetLines(frame) as? [CTLine]) ?? []
        var origins = [CGPoint](repeating: .zero, count: lines.count)
        CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)
        // From the frame's bottom-up space to the view's top-down one.
        let top = height + 1
        self.origins = origins.map { CGPoint(x: $0.x, y: top - $0.y) }
    }

    func draw(_ cg: CGContext, alpha: CGFloat) {
        cg.saveGState()
        cg.textMatrix = .identity
        cg.translateBy(x: 0, y: height + 1)
        cg.scaleBy(x: 1, y: -1)
        cg.setFillColor(UIColor.white.withAlphaComponent(alpha).cgColor)
        CTFrameDraw(frame, cg)
        cg.restoreGState()
    }

    /// The boxes the characters from `from` to `to` take, one per line they sit on.
    func rects(_ from: Int, _ to: Int) -> [CGRect] {
        var found: [CGRect] = []
        for (line, origin) in zip(lines, origins) {
            let range = CTLineGetStringRange(line)
            let start = max(from, range.location), end = min(to, range.location + range.length)
            guard start < end else { continue }
            let a = CTLineGetOffsetForStringIndex(line, start, nil)
            let b = CTLineGetOffsetForStringIndex(line, end, nil)
            let top = origin.y - lineHeight * 0.8
            found.append(CGRect(x: origin.x + min(a, b), y: top, width: abs(b - a), height: lineHeight))
        }
        return found
    }

    /// The character a tap at this point landed on.
    func characterAt(_ point: CGPoint) -> Int? {
        for (line, origin) in zip(lines, origins) where point.y >= origin.y - lineHeight * 0.8 && point.y < origin.y + lineHeight * 0.2 {
            let index = CTLineGetStringIndexForPosition(line, CGPoint(x: point.x - origin.x, y: 0))
            return index == kCFNotFound ? nil : index
        }
        return nil
    }
}

/// A wait where nobody sings: three dots that bounce while it lasts and fill in as it runs out.
private struct GapDots: View {
    let line: LyricLine
    let end: Int?
    let active: Bool
    let emphasis: CGFloat
    let position: Int
    let tap: () -> Void

    var body: some View {
        let shown = min(max(emphasis, 0), 1)
        TimelineView(.animation(paused: !active)) { time in
            let beat = active ? time.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.4) / 1.4 : 0
            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { dot in
                    let phase = active ? (beat - Double(dot) * 0.15) * 2 * .pi : 0
                    let gone = end.map { stop in CGFloat(position - line.startMs) / CGFloat(max(stop - line.startMs, 1)) } ?? 0
                    let lit = gone >= CGFloat(dot + 1) / 3
                    Circle()
                        .fill(.white)
                        .frame(width: 8, height: 8)
                        .scaleEffect(lerp(0.75, 1, shown))
                        .offset(y: -abs(sin(phase)) * 4 * shown)
                        .opacity(Double(lerp(0.25, lit ? SUNG_ALPHA : UNSUNG_ALPHA, shown)))
                }
            }
        }
        .frame(height: lerp(12, 28, shown))
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture(perform: tap)
        .accessibilityLabel("Instrumental")
        .accessibilityAddTraits(.isButton)
    }
}
