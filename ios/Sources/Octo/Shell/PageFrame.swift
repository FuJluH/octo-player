import CoreText
import OctoKit
import SwiftUI
import UIKit

/// A page's big title: 32 point Black, scrolling with the page, with no bar. Always whole:
/// never cut short and never broken inside a word. A long title wraps between its words; a
/// single word too wide for the line on its own is set just small enough to fit (never below
/// half size).
struct ScreenTitle: View {
    let text: String
    @State private var width: CGFloat = 0
    @ScaledMetric(relativeTo: .largeTitle) private var size: CGFloat = 32

    init(_ text: String) { self.text = text }

    var body: some View {
        let scale = TitleFit.scale(text, size: size, weight: .black, tracking: octoDisplayTracking, width: width)
        Text(breakableText(text))
            .font(.system(size: size * scale, weight: .black))
            .tracking(octoDisplayTracking)
            .foregroundStyle(.white)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 16)
            .accessibilityLabel(text)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A section's title inside a page: 18 point Bold, white.
struct SectionTitle: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.octoSection)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .accessibilityAddTraits(.isHeader)
    }
}

/// How small a title's type must be for its widest unbreakable stretch to fit the line.
enum TitleFit {
    static func scale(_ text: String, size: CGFloat, weight: UIFont.Weight, tracking: CGFloat, width: CGFloat) -> CGFloat {
        guard width > 0, !text.isEmpty else { return 1 }
        var scale = 1.0
        // Type does not scale quite evenly, so it is measured again after each step.
        for _ in 0..<3 {
            let font = UIFont.systemFont(ofSize: size * scale, weight: weight)
            let step = fitScale(widest: widestStretch(breakableText(text), font: font, tracking: tracking), width: Double(width))
            if step >= 1 { break }
            scale = max(titleLeastShare, scale * step)
            if scale <= titleLeastShare { break }
        }
        return CGFloat(scale)
    }

    /// The widest stretch of the text a line may not break inside: a word, the part of one a line
    /// may end after (a hyphen's), or one character of a script written without spaces.
    static func widestStretch(_ text: String, font: UIFont, tracking: CGFloat) -> Double {
        let string = text as NSString
        let tokenizer = CFStringTokenizerCreate(nil, string as CFString, CFRange(location: 0, length: string.length),
                                                kCFStringTokenizerUnitLineBreak, nil)
        var widest = 0.0
        var kind = CFStringTokenizerAdvanceToNextToken(tokenizer)
        while kind != [] {
            let range = CFStringTokenizerGetCurrentTokenRange(tokenizer)
            let piece = string.substring(with: NSRange(location: range.location, length: range.length))
                .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{200B}")))
            if !piece.isEmpty {
                let measured = (piece as NSString).size(withAttributes: [.font: font, .kern: tracking]).width
                widest = max(widest, Double(measured))
            }
            kind = CFStringTokenizerAdvanceToNextToken(tokenizer)
        }
        return widest
    }
}

extension View {
    /// A pushed page: no system bar, a floating glass back button at the top left, and room
    /// for it above the content.
    func detailPage() -> some View {
        modifier(DetailPage())
    }

    /// Room under a page's content for the floating bar.
    func barClearance() -> some View {
        contentMargins(.bottom, ShellMeasures.clearance, for: .scrollContent)
    }
}

/// Space a detail page leaves at its top for the back button.
let detailTopGap: CGFloat = 56

/// What going back does on a page that has something to close first, like a selection or a
/// search: set by the page, run by the back button and the edge swipe in place of leaving.
@MainActor
final class BackHandler: Equatable {
    var run: () -> Void = {}

    /// The handler of the page in front, for the edge swipe.
    static weak var current: BackHandler?

    nonisolated static func == (a: BackHandler, b: BackHandler) -> Bool { a === b }
}

struct BackHandlerKey: PreferenceKey {
    static var defaultValue: BackHandler? { nil }

    static func reduce(value: inout BackHandler?, nextValue: () -> BackHandler?) {
        value = nextValue() ?? value
    }
}

extension View {
    /// While `run` is set, going back runs it instead of leaving the page.
    func backAction(_ run: (() -> Void)?) -> some View {
        modifier(BackActionSetter(run: run))
    }
}

private struct BackActionSetter: ViewModifier {
    let run: (() -> Void)?
    @State private var handler = BackHandler()

    func body(content: Content) -> some View {
        if let run { handler.run = run }
        return content.preference(key: BackHandlerKey.self, value: run == nil ? nil : handler)
    }
}

private struct DetailPage: ViewModifier {
    @Environment(\.dismiss) private var dismiss
    @State private var handler: BackHandler?

    func body(content: Content) -> some View {
        content
            .toolbar(.hidden, for: .navigationBar)
            .onPreferenceChange(BackHandlerKey.self) { value in
                Task { @MainActor in
                    handler = value
                    BackHandler.current = value
                }
            }
            .onDisappear { if BackHandler.current === handler { BackHandler.current = nil } }
            .overlay(alignment: .topLeading) {
                GlazedIconButton(.back, label: "Back", size: 40) { if let handler { handler.run() } else { dismiss() } }
                    .padding(.leading, 16)
                    .padding(.top, 8)
            }
    }
}

/// With the system bar hidden, the edge swipe back still works.
extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard viewControllers.count > 1 else { return false }
        if let handler = MainActor.assumeIsolated({ BackHandler.current }) {
            MainActor.assumeIsolated { handler.run() }
            return false
        }
        return true
    }
}
