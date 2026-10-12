import SwiftUI
import UIKit

/// A page's big title, the way the other apps draw it: it scrolls with the page, with no bar.
struct ScreenTitle: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.octoDisplay)
            .tracking(-0.5)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 16)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A section's title inside a page.
struct SectionTitle: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.octoSection)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .accessibilityAddTraits(.isHeader)
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
        contentMargins(.bottom, OctoBar.clearance, for: .scrollContent)
    }
}

/// Space a detail page leaves at its top for the back button.
let detailTopGap: CGFloat = 56

/// What going back does on a page that has something to close first, like a selection or a
/// search: set by the page, run by the back button and the edge swipe in place of leaving.
@MainActor
final class BackHandler: Equatable {
    var run: @MainActor @Sendable () -> Void = {}

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
    func backAction(_ run: (@MainActor @Sendable () -> Void)?) -> some View {
        modifier(BackActionSetter(run: run))
    }
}

private struct BackActionSetter: ViewModifier {
    let run: (@MainActor @Sendable () -> Void)?
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
                Button { if let handler { handler.run() } else { dismiss() } } label: {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .circle)
                .padding(.leading, 16)
                .padding(.top, 8)
                .accessibilityLabel("Back")
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
