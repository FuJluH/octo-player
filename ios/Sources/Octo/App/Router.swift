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
    private(set) var toast: Toast?

    struct Toast: Identifiable, Equatable {
        let id = UUID()
        let text: String
        var done = false
        var action: String?
        var perform: (@MainActor () -> Void)?

        static func == (a: Toast, b: Toast) -> Bool { a.id == b.id }
    }

    func show(_ text: String, done: Bool = false, action: String? = nil, perform: (@MainActor () -> Void)? = nil) {
        let toast = Toast(text: text, done: done, action: action, perform: perform)
        self.toast = toast
        let seconds = action == nil ? 3.5 : 6
        Task {
            try? await Task.sleep(for: .seconds(seconds))
            if self.toast?.id == toast.id { self.toast = nil }
        }
    }

    func dismissToast() { toast = nil }
}

extension SignInModel.Form: Identifiable {
    var id: String {
        switch self {
        case .signIn: "signIn"
        case .add: "add"
        case .edit(let server): "edit." + server.id
        case .again(let server): "again." + server.id
        }
    }
}
