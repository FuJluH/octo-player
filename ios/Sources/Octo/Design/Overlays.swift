import Observation
import OctoKit
import SwiftUI

/// What floats over the whole app, above the bar and the player: glass sheets and glass
/// pop-ups. Any page can open one; the shell draws them all in one place, so a sheet covers the
/// bar wherever it was asked for, and a pop-up sits above the sheets and the message line.
@MainActor
@Observable
final class Overlays {
    struct Sheet: Identifiable {
        let id: UUID
        var tall: Bool
        var scrolls: Bool
        var content: AnyView
        var dismiss: () -> Void
        var visible = true
    }

    struct Popup: Identifiable {
        let id: UUID
        var anchor: CGRect?
        var title: String?
        var maxWidth: CGFloat
        var heightShare: Double
        var content: AnyView
        var dismiss: () -> Void
        /// Back first asks this, which answers true when it went back a page instead of closing.
        var back: () -> Bool
        var visible = true
        /// The side it took when it opened, kept while it still fits there.
        let placing = PopupPlacing()
    }

    private(set) var sheets: [Sheet] = []
    private(set) var popups: [Popup] = []

    /// Whether anything is open that back should close first.
    var hasOpen: Bool { sheets.contains(where: \.visible) || popups.contains(where: \.visible) }

    func showSheet(_ id: UUID, tall: Bool, scrolls: Bool, content: AnyView, dismiss: @escaping () -> Void) {
        let sheet = Sheet(id: id, tall: tall, scrolls: scrolls, content: content, dismiss: dismiss)
        if let index = sheets.firstIndex(where: { $0.id == id }) {
            sheets[index] = sheet
        } else {
            sheets.append(sheet)
        }
    }

    /// Starts a sheet leaving; it is taken away once it has gone.
    func hideSheet(_ id: UUID) {
        guard let index = sheets.firstIndex(where: { $0.id == id }), sheets[index].visible else { return }
        sheets[index].visible = false
    }

    func removeSheet(_ id: UUID) {
        sheets.removeAll { $0.id == id && !$0.visible }
    }

    func showPopup(_ id: UUID, anchor: CGRect?, title: String?, maxWidth: CGFloat = CGFloat(PopupMeasures.maxWidth),
                   heightShare: Double = PopupMeasures.heightShare, content: AnyView,
                   dismiss: @escaping () -> Void, back: @escaping () -> Bool = { false }) {
        if let index = popups.firstIndex(where: { $0.id == id }) {
            popups[index].content = content
            popups[index].title = title
            popups[index].dismiss = dismiss
            popups[index].back = back
            if !popups[index].visible {
                popups[index].visible = true
                popups[index].anchor = anchor
                popups[index].placing.keepAbove = nil
            }
        } else {
            popups.append(Popup(id: id, anchor: anchor, title: title, maxWidth: maxWidth, heightShare: heightShare,
                                content: content, dismiss: dismiss, back: back))
        }
    }

    func updatePopup(_ id: UUID, content: AnyView) {
        guard let index = popups.firstIndex(where: { $0.id == id }) else { return }
        popups[index].content = content
    }

    func hidePopup(_ id: UUID) {
        guard let index = popups.firstIndex(where: { $0.id == id }), popups[index].visible else { return }
        popups[index].visible = false
    }

    func removePopup(_ id: UUID) {
        popups.removeAll { $0.id == id && !$0.visible }
    }

    /// Back: the top pop-up goes back a page or closes; else the top sheet closes. Answers
    /// whether anything took it.
    @discardableResult
    func back() -> Bool {
        if let popup = popups.last(where: \.visible) {
            if !popup.back() { popup.dismiss() }
            return true
        }
        if let sheet = sheets.last(where: \.visible) {
            sheet.dismiss()
            return true
        }
        return false
    }
}

/// What a pop-up remembers between layouts: the side it opened on.
final class PopupPlacing {
    var keepAbove: Bool?
}

extension View {
    /// A glass sheet rising from the bottom over a dimmed screen while `isPresented`. Tapping
    /// the dim, pulling the handle down, or back closes it. `tall` lets it grow to the status
    /// bar; `scrolls` false hands the content the room as it is.
    func glassSheet<Content: View>(isPresented: Binding<Bool>, tall: Bool = false, scrolls: Bool = true,
                                   @ViewBuilder content: @escaping () -> Content) -> some View {
        modifier(SheetPresenter(isPresented: isPresented, tall: tall, scrolls: scrolls, content: { AnyView(content()) }))
    }

    /// A glass sheet for `item` while it is not nil.
    func glassSheet<Item: Identifiable, Content: View>(item: Binding<Item?>, tall: Bool = false, scrolls: Bool = true,
                                                       @ViewBuilder content: @escaping (Item) -> Content) -> some View {
        modifier(ItemSheetPresenter(item: item, tall: tall, scrolls: scrolls, content: { AnyView(content($0)) }))
    }

    /// A glass pop-up beside the control just pressed (or `anchor`), or in the middle of the
    /// screen when none was, while `isPresented`. A tap off the card or back closes it.
    /// `usesPressSpot` false keeps it to `anchor` alone, in the middle when that is nil.
    func glassPopup<Content: View>(isPresented: Binding<Bool>, title: String? = nil, anchor: CGRect? = nil,
                                   usesPressSpot: Bool = true, revision: AnyHashable? = nil,
                                   maxWidth: CGFloat = CGFloat(PopupMeasures.maxWidth),
                                   heightShare: Double = PopupMeasures.heightShare,
                                   onBack: @escaping () -> Bool = { false },
                                   @ViewBuilder content: @escaping () -> Content) -> some View {
        modifier(PopupPresenter(isPresented: isPresented, title: title, anchor: anchor, usesPressSpot: usesPressSpot,
                                revision: revision, maxWidth: maxWidth,
                                heightShare: heightShare, onBack: onBack, content: { AnyView(content()) }))
    }
}

private struct SheetPresenter: ViewModifier {
    @Binding var isPresented: Bool
    let tall: Bool
    let scrolls: Bool
    let content: () -> AnyView
    @Environment(Overlays.self) private var overlays
    @State private var id = UUID()

    func body(content view: Content) -> some View {
        view
            .onChange(of: isPresented, initial: true) { _, shown in
                if shown {
                    overlays.showSheet(id, tall: tall, scrolls: scrolls, content: content()) { isPresented = false }
                } else {
                    overlays.hideSheet(id)
                }
            }
            .onDisappear { if isPresented { isPresented = false } }
    }
}

private struct ItemSheetPresenter<Item: Identifiable>: ViewModifier {
    @Binding var item: Item?
    let tall: Bool
    let scrolls: Bool
    let content: (Item) -> AnyView
    @Environment(Overlays.self) private var overlays
    @State private var id = UUID()

    func body(content view: Content) -> some View {
        view
            .onChange(of: item?.id, initial: true) { _, _ in
                if let item {
                    overlays.showSheet(id, tall: tall, scrolls: scrolls, content: content(item)) { self.item = nil }
                } else {
                    overlays.hideSheet(id)
                }
            }
            .onDisappear { if item != nil { item = nil } }
    }
}

private struct PopupPresenter: ViewModifier {
    @Binding var isPresented: Bool
    let title: String?
    let anchor: CGRect?
    let usesPressSpot: Bool
    /// A new revision while it is open shows the content afresh.
    let revision: AnyHashable?
    let maxWidth: CGFloat
    let heightShare: Double
    let onBack: () -> Bool
    let content: () -> AnyView
    @Environment(Overlays.self) private var overlays
    @Environment(PressSpots.self) private var spots
    @State private var id = UUID()

    func body(content view: Content) -> some View {
        view
            .onChange(of: isPresented, initial: true) { _, shown in
                if shown {
                    overlays.showPopup(id, anchor: anchor ?? (usesPressSpot ? spots.recent() : nil), title: title, maxWidth: maxWidth,
                                       heightShare: heightShare, content: content(),
                                       dismiss: { isPresented = false }, back: onBack)
                } else {
                    overlays.hidePopup(id)
                }
            }
            .onChange(of: revision) { _, _ in
                if isPresented { overlays.updatePopup(id, content: content()) }
            }
            .onDisappear { if isPresented { isPresented = false } }
    }
}

/// Draws every open sheet and pop-up, in the order they opened. The shell puts the sheets
/// above the bar and the player, and the pop-ups above the message line.
struct SheetsLayer: View {
    @Environment(Overlays.self) private var overlays

    var body: some View {
        ZStack {
            ForEach(overlays.sheets) { sheet in
                GlassSheetFrame(visible: sheet.visible, tall: sheet.tall, scrolls: sheet.scrolls,
                                onDismiss: sheet.dismiss, onGone: { overlays.removeSheet(sheet.id) }) {
                    sheet.content
                }
            }
        }
    }
}

struct PopupsLayer: View {
    @Environment(Overlays.self) private var overlays

    var body: some View {
        ZStack {
            ForEach(overlays.popups) { popup in
                GlassPopupFrame(popup: popup, onGone: { overlays.removePopup(popup.id) })
            }
        }
    }
}
