import OctoKit
import SwiftUI

/// The current password, then the new one twice. Nothing is sent until the form is right; what
/// the server says comes back in plain words. Made fresh each time its sheet opens.
struct ChangePasswordForm: View {
    let close: () -> Void
    @Environment(Session.self) private var session
    @Environment(Accounts.self) private var accounts
    @Environment(Router.self) private var router
    @State private var draft = PasswordDraft()
    @State private var busy = false
    @State private var problem: String?
    @State private var onCurrent = false
    @State private var onNew = false
    @State private var onAgain = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Change password").font(.octoBody).foregroundStyle(OctoColor.textPrimary)
            Text("Your other apps will ask for the new password the next time they sign in.")
                .font(.octoCaption)
                .foregroundStyle(OctoColor.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            field("Current password", text: $draft.current, at: 0)
            field("New password", text: $draft.new, at: 1)
            field("New password again", text: $draft.confirm, at: 2)
            if let problem {
                Text(problem).font(.octoCaption).foregroundStyle(OctoColor.error).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 12) {
                AccentButton("Change password", size: .medium, loading: busy, action: change)
                GlazeButton("Cancel", size: .medium, enabled: !busy, action: close)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 20)
    }

    /// Next moves on to the following field; Done on the last one changes the password.
    private func field(_ placeholder: String, text: Binding<String>, at index: Int) -> some View {
        GlassInput(placeholder, text: Binding(get: { text.wrappedValue }, set: { text.wrappedValue = $0; problem = nil }), secure: true,
                   submitLabel: index == 2 ? .done : .next, focus: focus(at: index)) {
            switch index {
            case 0: onNew = true
            case 1: onAgain = true
            default: change()
            }
        }
        .textContentType(index == 0 ? .password : .newPassword)
    }

    private func focus(at index: Int) -> Binding<Bool> {
        switch index {
        case 0: $onCurrent
        case 1: $onNew
        default: $onAgain
        }
    }

    private func change() {
        if let problem = passwordDraftProblem(draft) {
            self.problem = problem
            return
        }
        busy = true
        problem = nil
        let draft = draft
        Task {
            let family = accounts.family.model.me?.managed == true
            let result = await session.changePassword(current: draft.current, new: draft.new, family: family)
            busy = false
            if result == .changed {
                close()
                router.show(passwordChangeWords(result), done: true)
            } else {
                problem = passwordChangeWords(result)
            }
        }
    }
}
