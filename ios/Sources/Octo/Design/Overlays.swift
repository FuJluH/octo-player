import Observation
import SwiftUI

/// A sheet opened from code rather than from a page's own control, such as the debug launch
/// steps' samples. The shell shows it as the system's sheet, one at a time.
@MainActor
@Observable
final class Overlays {
    struct Sheet: Identifiable {
        let id: UUID
        var tall: Bool
        var scrolls: Bool
        var content: AnyView
        var dismiss: () -> Void
    }

    private(set) var sheet: Sheet?

    /// Whether a sheet is open that back should close first.
    var hasOpen: Bool { sheet != nil }

    /// Shows `content` in a sheet: `tall` opens it full height, otherwise at half with room to
    /// pull it up; `scrolls` lets content taller than the sheet scroll. `dismiss` runs when it is
    /// pulled away.
    func showSheet(_ id: UUID, tall: Bool, scrolls: Bool, content: AnyView, dismiss: @escaping () -> Void) {
        sheet = Sheet(id: id, tall: tall, scrolls: scrolls, content: content, dismiss: dismiss)
    }

    func hideSheet(_ id: UUID) {
        if sheet?.id == id { sheet = nil }
    }

    /// Back closes the sheet. Answers whether there was one.
    @discardableResult
    func back() -> Bool {
        guard let sheet else { return false }
        sheet.dismiss()
        hideSheet(sheet.id)
        return true
    }
}

/// Shows the sheet opened from code. Put once on the shell.
struct CodeSheetHost: ViewModifier {
    @Environment(Overlays.self) private var overlays

    func body(content: Content) -> some View {
        content.sheet(item: Binding(get: { overlays.sheet }, set: { _ in _ = overlays.back() })) { sheet in
            Group {
                if sheet.scrolls {
                    ScrollView { sheet.content }
                } else {
                    sheet.content
                }
            }
            .padding(.top, 16)
            .presentationDetents(sheet.tall ? [.large] : [.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }
}
