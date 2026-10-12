import OctoKit
import SwiftUI

/// The first page: the octopus, the app's name, and the three things a server needs.
struct SignInView: View {
    @Environment(Session.self) private var session
    @State private var address = ""
    @State private var username = ""
    @State private var password = ""
    @State private var busy = false
    @State private var error: String?
    @FocusState private var focus: Field?

    enum Field { case address, username, password }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                VStack(spacing: 14) {
                    OctopusMark()
                        .frame(width: 150)
                        .shadow(color: OctoColor.lavender.opacity(0.35), radius: 40)
                    Text("Octo")
                        .font(.octoDisplay)
                    Text("Sign in to your music server")
                        .font(.octoBody)
                        .foregroundStyle(OctoColor.textSecondary)
                }
                .padding(.top, 48)

                VStack(spacing: 12) {
                    field("Server address", text: $address, as: .address)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                    field("Username", text: $username, as: .username)
                        .textContentType(.username)
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .focused($focus, equals: .password)
                        .submitLabel(.go)
                        .onSubmit { Task { await signIn() } }
                        .modifier(FieldStyle())
                }

                if let error {
                    Text(error)
                        .font(.octoBodySmall)
                        .foregroundStyle(OctoColor.error)
                        .multilineTextAlignment(.center)
                }

                Button {
                    Task { await signIn() }
                } label: {
                    Text(busy ? "Signing in…" : "Sign in")
                        .font(.octoBody.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .disabled(busy || address.isEmpty || username.isEmpty)
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(OctoColor.background)
    }

    private func field(_ title: String, text: Binding<String>, as field: Field) -> some View {
        TextField(title, text: text)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .focused($focus, equals: field)
            .submitLabel(.next)
            .onSubmit { focus = field == .address ? .username : .password }
            .modifier(FieldStyle())
    }

    private func signIn() async {
        guard !busy else { return }
        busy = true
        error = nil
        defer { busy = false }
        do {
            try await session.signIn(address: address, username: username, password: password)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct FieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.octoBody)
            .padding(.horizontal, 16)
            .frame(height: 52)
            .background(OctoColor.surfaceRaised, in: RoundedRectangle(cornerRadius: OctoRadius.row, style: .continuous))
    }
}
