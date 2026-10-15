import OctoKit
import SwiftUI

// The frame of the library's song pages: their rows in a plain system list, so each row can carry
// the system's swipe actions, and the page's name shown small at the top once its big title has
// scrolled away.

private struct InLibraryListKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Whether the rows sit in a `LibraryList`, which gives them the system's swipe actions.
    var inLibraryList: Bool {
        get { self[InLibraryListKey.self] }
        set { self[InLibraryListKey.self] = newValue }
    }
}

/// A page's rows as a plain list. Each row draws itself edge to edge, as it would in a stack: no
/// inset, separator or background from the list, and buttons that act on their own taps. Section
/// headers stay pinned at the top while their rows scroll under them.
struct LibraryList<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        List {
            Group { content }
                .plainListRow()
                .buttonStyle(.borderless)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 0)
        .environment(\.inLibraryList, true)
    }
}

extension View {
    /// A list row drawn as it is: no inset, separator or background from the list.
    func plainListRow() -> some View {
        listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listSectionSeparator(.hidden)
            .listRowBackground(Color.clear)
    }

    /// The row's swipes. In a `LibraryList` they are the system's swipe actions: from the left
    /// edge, Play next; from the right edge, the row's removal. Elsewhere the row follows the
    /// finger itself (`rowSwipe`).
    func songSwipes(_ swipe: RowSwipe, enabled: Bool) -> some View {
        modifier(SongSwipes(swipe: swipe, enabled: enabled))
    }
}

private struct SongSwipes: ViewModifier {
    let swipe: RowSwipe
    let enabled: Bool
    @Environment(\.inLibraryList) private var inList

    func body(content: Content) -> some View {
        if inList {
            content
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    if enabled, case .playNext(let run) = swipe {
                        Button(action: run) { Label("Play next", systemImage: OctoIcon.playNext.symbol) }
                            .tint(OctoColor.accent)
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    if enabled, case .remove(let run) = swipe {
                        Button(role: .destructive, action: run) { Label("Remove", systemImage: OctoIcon.delete.symbol) }
                    }
                }
        } else {
            content.rowSwipe(swipe, enabled: enabled)
        }
    }
}

// MARK: A new order

/// Where a list's first row sits on screen, by its top edge.
@MainActor
@Observable
final class FirstRowWatch {
    var y: CGFloat = .greatestFiniteMagnitude
}

extension View {
    /// When the list shows up in a new `order`, it starts again from its first row (marked with
    /// `FirstRowMark`) by `scroll`, rather than following the row that was at the top to its new
    /// place. A page scrolled only within its header stays put.
    func topOnNewOrder<Order: Equatable>(_ order: Order?, scroll: @escaping () -> Void) -> some View {
        modifier(TopOnNewOrder(order: order, scroll: scroll))
    }
}

private struct TopOnNewOrder<Order: Equatable>: ViewModifier {
    let order: Order?
    let scroll: () -> Void
    @State private var watch = FirstRowWatch()
    @State private var shown: Order?
    @Environment(TitleWatch.self) private var title: TitleWatch?

    func body(content: Content) -> some View {
        content
            .environment(watch)
            .onChange(of: order, initial: true) { _, now in
                guard let now else { return }
                defer { shown = now }
                guard let before = shown, before != now else { return }
                if watch.y <= (title?.top ?? 0) + 1 { scroll() }
            }
    }
}

/// Marks the top of a list's first row, for `topOnNewOrder`. Once it has scrolled out of a lazy
/// list it counts as above the top.
struct FirstRowMark: View {
    @Environment(FirstRowWatch.self) private var watch: FirstRowWatch?

    var body: some View {
        Color.clear
            .frame(height: 0)
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { watch?.y = $0 }
            .onDisappear { watch?.y = -.greatestFiniteMagnitude }
            .accessibilityHidden(true)
    }
}

// MARK: Inline title

/// Where a page's big title is on screen, against the page's top.
@MainActor
@Observable
final class TitleWatch {
    /// The bottom of the big title, and the top of the page, on screen.
    var bottom: CGFloat = .greatestFiniteMagnitude
    var top: CGFloat = 0

    /// The big title has gone under the top, where the back button sits.
    var gone: Bool { bottom < top + 48 }
}

extension View {
    /// A page with a big title (marked with `bigTitle()`): once that title has scrolled under the
    /// top, the page's name shows small in the middle of the top, beside the back button, over a
    /// soft blur, as a page's inline title does. Scrolling back down hands it back to the big one.
    func inlineTitle(_ title: String) -> some View {
        modifier(InlineTitle(title: title))
    }

    /// Marks the page's big title, or the header holding it, for `inlineTitle`.
    func bigTitle() -> some View {
        modifier(BigTitle())
    }
}

private struct InlineTitle: ViewModifier {
    let title: String
    @State private var watch = TitleWatch()

    func body(content: Content) -> some View {
        content
            .environment(watch)
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { watch.top = $0 }
            .overlay(alignment: .top) { InlineTitleBar(title: title, shown: watch.gone) }
    }
}

private struct BigTitle: ViewModifier {
    @Environment(TitleWatch.self) private var watch: TitleWatch?

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxY } action: { watch?.bottom = $0 }
            // A title row leaves a list once it has scrolled away above the top.
            .onDisappear { watch?.bottom = -.greatestFiniteMagnitude }
    }
}

/// The page's name, small and whole, in the middle of the top over a blur that fades downward.
private struct InlineTitleBar: View {
    let title: String
    let shown: Bool

    var body: some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, 64)
            .frame(maxWidth: .infinity, minHeight: 40)
            .padding(.top, 8)
            .padding(.bottom, 14)
            .background {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.6),
                                                 .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
                    .ignoresSafeArea(edges: .top)
            }
            .opacity(shown ? 1 : 0)
            .animation(.easeOut(duration: 0.2), value: shown)
            .allowsHitTesting(false)
            .accessibilityHidden(!shown)
            .accessibilityAddTraits(.isHeader)
    }
}
