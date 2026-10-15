import Observation
import SwiftUI

/// App-wide things any page can ask for: the sign-in page, and a short message at the bottom.
@MainActor
@Observable
final class Router {
    /// The sign-in page, while it is open.
    var signIn: SignInModel.Form?
    /// A page to open on the tab in use, asked for from outside the tabs (the player).
    private(set) var route: Route?

    func go(_ route: Route) { self.route = route }
    func routeTaken() { route = nil }

    /// An account page to open on the Settings tab, asked for from outside it (a family notice,
    /// a family link, a list shared in).
    private(set) var accountRoute: AccountRoute?

    func openInSettings(_ route: AccountRoute) { accountRoute = route }
    func accountRouteTaken() { accountRoute = nil }

    /// A change of screen asked for from outside the pages.
    var drive: DriveRequest?

    enum DriveRequest: Equatable {
        case tab(AppTab)
        case openPlayer, closePlayer, lyrics
        /// The bar's small player shown, the tabs shown again, the tab in use tapped again, back.
        case barPlayer, showTabs, reselect, back
    }

    /// The full player opens on its lyrics when this is set; it clears it.
    var lyricsRequested = false

    /// Words for Search to look for, asked for from outside it (the player); Search takes them.
    var searchText: String?

    /// Opens Search looking for `text`.
    func openSearch(_ text: String) {
        searchText = text
        drive = .tab(.search)
    }

    /// The server downloads sheet, while it is open.
    var serverDownloads: DownloadsSheetPage?

    /// Opens the server downloads sheet: on a song's newest download log, or on the list.
    func showServerDownloads(songId: String? = nil) { serverDownloads = .list(focus: songId) }

    // MARK: Messages

    /// The one short message on screen, above the bar. Only for what the listener did and can
    /// undo, or something they asked for that did or did not happen.
    private(set) var toast: Toast?

    /// One message. Each is its own, so the same words shown twice still count as a new one.
    struct Toast: Identifiable, Equatable {
        let id = UUID()
        let text: String
        var action: String?
        var perform: (@MainActor () -> Void)?
        /// A small white icon before the words.
        var icon: OctoIcon?

        /// A done line carries the check.
        var done: Bool { icon == .check }

        /// How long it stays once it has come in: longer when it offers an action.
        var seconds: Double { action == nil ? 3.5 : 6 }

        static func == (a: Toast, b: Toast) -> Bool { a.id == b.id }
    }

    /// Shows `text`, replacing any message showing. `done` puts a check before the words;
    /// `action` offers a button that runs `perform` and puts the message away.
    func show(_ text: String, done: Bool = false, action: String? = nil, icon: OctoIcon? = nil,
              perform: (@MainActor () -> Void)? = nil) {
        toast = Toast(text: text, action: action, perform: perform, icon: icon ?? (done ? .check : nil))
    }

    /// An undo for something already done.
    func undoable(_ text: String, undo: @escaping @MainActor () -> Void) {
        show(text, action: "Undo", perform: undo)
    }

    /// Something the listener asked for has now happened, with a check.
    func done(_ text: String) { show(text, icon: .check) }

    /// Puts `shown` away, unless a newer message has taken its place.
    func dismiss(_ shown: Toast) {
        if toast?.id == shown.id { toast = nil }
    }

    func dismissToast() { toast = nil }
}

/// What the server downloads sheet shows: the list (on a song's newest download when `focus`
/// names one the server lists), one download's log, or Find songs for one song.
enum DownloadsSheetPage: Hashable {
    case list(focus: String?)
    case log(key: String)
    /// `id` is the song's id on the server; `title` names it until the server answers. `from`
    /// is the log it was opened from, if any.
    case find(id: String, title: String, from: String?)
}
