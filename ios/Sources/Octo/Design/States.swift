import OctoKit
import SwiftUI

/// Where a page's data is: on its way, failed with words to show, or here.
enum LoadState<Value> {
    case loading
    case failed(String)
    case ready(Value)

    var value: Value? {
        if case .ready(let value) = self { return value }
        return nil
    }
}

/// Runs a read and turns any failure into words for the screen. A read that was canceled is
/// not a failure: it gives nil, and the page keeps what it had.
func load<Value>(_ read: () async throws -> Value) async -> LoadState<Value>? {
    do {
        return .ready(try await read())
    } catch {
        guard let words = userMessage(for: error) else { return nil }
        return .failed(words)
    }
}

/// A page's loading and failed states in place of its content: a spinner in the middle while
/// it loads; the failure's words with Try again under them.
struct LoadStateView<Value, Content: View>: View {
    let state: LoadState<Value>
    let retry: () -> Void
    @ViewBuilder let content: (Value) -> Content

    var body: some View {
        switch state {
        case .loading: LoadingView()
        case .failed(let message): FailedView(message: message, retry: retry)
        case .ready(let value): content(value)
        }
    }
}

/// A 28 point accent spinner in the middle of the space.
struct LoadingView: View {
    var body: some View {
        LoadingSpinner(size: 28)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The failure's words in the middle, and 16 points under them the accent button "Try again".
struct FailedView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text(message)
                .font(.octoBodySmall)
                .foregroundStyle(OctoColor.textSecondary)
                .multilineTextAlignment(.center)
            AccentButton("Try again", action: retry)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A quiet note where a list has nothing to show, with ways onward under it: "Nothing here yet"
/// by default, actions 16 points below, wrapping 12 apart.
struct EmptyNote<Actions: View>: View {
    var text = "Nothing here yet"
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(text)
                .font(.octoBodySmall)
                .foregroundStyle(OctoColor.textMuted)
            FlowRow(spacing: 12) { actions }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension EmptyNote where Actions == EmptyView {
    init(_ text: String = "Nothing here yet") {
        self.init(text: text, actions: { EmptyView() })
    }
}

/// Lays its pieces in a row, wrapping onto the next line when they run out of room.
struct FlowRow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var line: CGFloat = 0
        var widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                y += line + spacing
                x = 0
                line = 0
            }
            x += size.width + spacing
            line = max(line, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: min(widest, width), height: subviews.isEmpty ? 0 : y + line)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var line: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                y += line + spacing
                x = bounds.minX
                line = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            line = max(line, size.height)
        }
    }
}

extension EnvironmentValues {
    /// The library's own refresh: rescans the phone, copies the server's library afresh when
    /// signed in, and asks how downloads on their way are going. It answers words to show when
    /// the server copy failed.
    @Entry var refreshLibrary: (@MainActor () async -> String?)? = nil
}

extension View {
    /// Pull down on a library page to refresh it: the page's own reload and the library's
    /// refresh run together, the spinner showing until both are done. A failed server copy is
    /// said in a message.
    func libraryRefreshable(_ own: @escaping @Sendable () async -> Void) -> some View {
        modifier(LibraryRefreshable(own: own))
    }
}

private struct LibraryRefreshable: ViewModifier {
    let own: @Sendable () async -> Void
    @Environment(\.refreshLibrary) private var library
    @Environment(Router.self) private var router

    func body(content: Content) -> some View {
        content.refreshable {
            async let mine: Void = own()
            let words = await library?()
            await mine
            if let words { router.show(words) }
        }
    }
}
