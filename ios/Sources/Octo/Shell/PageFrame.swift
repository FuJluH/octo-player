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

private struct DetailPage: ViewModifier {
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content
            .toolbar(.hidden, for: .navigationBar)
            .overlay(alignment: .topLeading) {
                Button { dismiss() } label: {
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
        viewControllers.count > 1
    }
}
