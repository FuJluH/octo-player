import OctoKit
import SwiftUI
import UniformTypeIdentifiers

/// The sign-in page: the octopus over Octo's name, one glass card with the address, username
/// and password, then the button, the connection note and Advanced.
struct SignInView: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var model: SignInModel
    @State private var reveal = false
    @State private var revealKey = false
    @State private var choosingCertificate = false
    @State private var pendingCertificate: (name: String, data: Data)?
    @State private var certificatePassword = ""
    @State private var certificateError: String?
    @FocusState private var focus: Field?
    let done: (String?) -> Void

    enum Field: Hashable { case address, label, username, password, apiKey, home }

    init(form: SignInModel.Form, session: Session, done: @escaping (String?) -> Void = { _ in }) {
        _model = State(initialValue: SignInModel(form: form, session: session))
        self.done = done
    }

    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(spacing: 0) {
                header
                    .padding(.bottom, 28)
                card
                if let note = model.note { ConnectionNoteView(note: note).padding(.top, 12) }
                Button {
                    Task { await model.submit(session) }
                } label: {
                    ZStack {
                        Text(model.buttonTitle).opacity(model.busy ? 0 : 1)
                        if model.busy { ProgressView() }
                    }
                    .font(.octoBody.weight(.semibold))
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .disabled(!model.ready)
                .padding(.top, 20)
                if let error = model.error {
                    Text(error)
                        .font(.octoBodySmall)
                        .foregroundStyle(OctoColor.error)
                        .multilineTextAlignment(.center)
                        .padding(.top, 12)
                }
                advancedToggle
                    .padding(.top, 20)
                if model.advancedOpen {
                    advanced
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 60)
            .frame(maxWidth: 420)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(OctoColor.background)
        .overlay(alignment: .topLeading) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold)).frame(width: 44, height: 44)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .padding(.leading, 16)
            .accessibilityLabel("Back")
        }
        .animation(.snappy, value: model.advancedOpen)
        .onChange(of: model.signedIn) { _, signedIn in
            if signedIn {
                done(model.notice)
                dismiss()
            }
        }
        .sheet(item: $model.question) { question in
            TrustSheet(question: question) {
                Task { await model.trust(session) }
            } cancel: {
                model.distrust()
            }
        }
        .fileImporter(isPresented: $choosingCertificate, allowedContentTypes: [.pkcs12]) { result in
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: url) {
                pendingCertificate = (url.lastPathComponent, data)
                certificatePassword = ""
            }
        }
        .alert("Certificate password", isPresented: Binding(get: { pendingCertificate != nil }, set: { if !$0 { pendingCertificate = nil } })) {
            SecureField("Password", text: $certificatePassword)
            Button("Use It") { takeCertificate() }
            Button("Cancel", role: .cancel) { pendingCertificate = nil }
        } message: {
            Text(certificateError ?? "The password the certificate file was saved with.")
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            OctopusMark()
                .frame(width: 132)
                .shadow(color: OctoColor.accent.opacity(0.35), radius: 36)
                .padding(.top, 56)
                .padding(.bottom, 10)
            if let heading = model.heading {
                Text(heading).font(.octoTitle).multilineTextAlignment(.center)
            } else {
                Text("Octo").font(.octoDisplay)
            }
            Text(model.subheading)
                .font(.octoBodySmall)
                .foregroundStyle(OctoColor.textSecondary)
                .multilineTextAlignment(.center)
        }
    }

    private var card: some View {
        @Bindable var model = model
        return VStack(spacing: 10) {
            GlassField {
                Button(action: model.toggleScheme) {
                    HStack(spacing: 4) {
                        Image(systemName: model.scheme == .https ? "lock.fill" : "lock.open.fill")
                            .font(.system(size: 13, weight: .semibold))
                        Text(model.scheme.prefix).font(.octoBody)
                    }
                    .foregroundStyle(OctoColor.textMuted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(model.scheme == .https ? "Encrypted, https" : "Not encrypted, http")
                .accessibilityHint(model.scheme == .https ? "Use http" : "Use https")
                TextField("music.example.com", text: $model.rest)
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .focused($focus, equals: .address)
                    .submitLabel(.next)
                    .onSubmit { focus = .username }
            }
            if case .add = model.form { labelField } else if case .edit = model.form { labelField }
            GlassField {
                FieldIcon("person")
                TextField(model.useApiKey ? "Username (optional)" : "Username", text: $model.username)
                    .textContentType(.username)
                    .focused($focus, equals: .username)
                    .submitLabel(.next)
                    .onSubmit { focus = model.useApiKey ? nil : .password }
            }
            if !model.useApiKey {
                GlassField {
                    FieldIcon("key")
                    SecretField(model.editing ? "Password (unchanged)" : "Password", text: $model.password, revealed: reveal)
                        .textContentType(.password)
                        .focused($focus, equals: .password)
                        .submitLabel(.go)
                        .onSubmit { Task { await model.submit(session) } }
                    RevealToggle(revealed: $reveal)
                }
            }
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }

    private var labelField: some View {
        @Bindable var model = model
        return GlassField {
            FieldIcon("pencil")
            TextField("Name (optional, like Home or Work)", text: $model.label)
                .textInputAutocapitalization(.words)
                .focused($focus, equals: .label)
        }
    }

    private var advancedToggle: some View {
        Button {
            model.advancedOpen.toggle()
        } label: {
            HStack {
                Text("Advanced").font(.system(size: 13.5, weight: .semibold)).foregroundStyle(OctoColor.textSecondary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(OctoColor.textMuted)
                    .rotationEffect(.degrees(model.advancedOpen ? 90 : 0))
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var advanced: some View {
        @Bindable var model = model
        return VStack(alignment: .leading, spacing: 18) {
            SwitchRow("Legacy sign-in", "Only for older servers that reject the normal sign-in.",
                      isOn: Binding(get: { model.legacy && !model.useApiKey }, set: { model.legacy = $0 }))
                .disabled(model.useApiKey)
            if model.takesApiKeys != false || model.useApiKey {
                VStack(alignment: .leading, spacing: 10) {
                    SwitchRow("Sign in with an API key",
                              model.takesApiKeys == true ? "Your server gives out API keys." : "For servers that give out API keys.",
                              isOn: $model.useApiKey)
                    if model.useApiKey {
                        GlassField {
                            FieldIcon("key")
                            SecretField(model.editing ? "API key (unchanged)" : "API key", text: $model.apiKey, revealed: revealKey)
                                .focused($focus, equals: .apiKey)
                            RevealToggle(revealed: $revealKey)
                        }
                    }
                }
            }
            Section("Home network address", "Optional. On Wi-Fi, Octo uses it when it answers, and the main address otherwise.") {
                GlassField {
                    FieldIcon("house")
                    TextField("Home network address", text: $model.homeAddress)
                        .keyboardType(.URL)
                        .focused($focus, equals: .home)
                }
            }
            Section("Custom headers", "Sent with every request to this server, such as an access token for a proxy in front of it.") {
                ForEach($model.headers) { $header in
                    VStack(spacing: 8) {
                        GlassField {
                            TextField("Header name", text: Binding(get: { header.name }, set: { model.renameHeader(header.id, to: $0) }))
                            Button("Remove") { model.headers.removeAll { $0.id == header.id } }
                                .font(.system(size: 13.5, weight: .semibold))
                                .foregroundStyle(OctoColor.destructive)
                                .buttonStyle(.plain)
                        }
                        GlassField {
                            SecureField(header.saved ? "Value (unchanged)" : "Value", text: $header.value)
                        }
                    }
                }
                Button("Add header", action: model.addHeader)
                    .buttonStyle(.glass)
            }
            Section("Client certificate", "For servers that ask the phone to prove itself with a certificate.") {
                HStack {
                    Text(model.certificate?.name ?? (model.hadCertificate && !model.removesCertificate ? "Saved certificate" : "None"))
                        .font(.octoBodySmall)
                        .foregroundStyle(OctoColor.textPrimary)
                    Spacer()
                    if model.certificate != nil || (model.hadCertificate && !model.removesCertificate) {
                        Button("Remove") {
                            model.certificate = nil
                            model.removesCertificate = model.hadCertificate
                        }
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(OctoColor.destructive)
                        .buttonStyle(.plain)
                    }
                }
                Button(model.certificate == nil && !model.hadCertificate ? "Choose certificate" : "Choose another") {
                    certificateError = nil
                    choosingCertificate = true
                }
                .buttonStyle(.glass)
            }
        }
        .padding(.top, 6)
    }

    private func takeCertificate() {
        guard let pending = pendingCertificate else { return }
        do {
            try ServerTrust.shared.useClientCertificate(pending.data, password: certificatePassword)
            model.certificate = (pending.name, pending.data, certificatePassword)
            model.removesCertificate = false
            pendingCertificate = nil
        } catch {
            certificateError = error.localizedDescription
        }
    }
}

/// One input on the sign-in card: its icon, the field, anything trailing.
struct GlassField<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 10) { content }
            .font(.octoBody)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .padding(.horizontal, 14)
            .frame(minHeight: 50)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct FieldIcon: View {
    let name: String
    init(_ name: String) { self.name = name }

    var body: some View {
        Image(systemName: name)
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(OctoColor.textMuted)
            .frame(width: 22)
    }
}

/// A secret that can be shown.
private struct SecretField: View {
    let title: String
    @Binding var text: String
    let revealed: Bool

    init(_ title: String, text: Binding<String>, revealed: Bool) {
        self.title = title
        _text = text
        self.revealed = revealed
    }

    var body: some View {
        if revealed { TextField(title, text: $text) } else { SecureField(title, text: $text) }
    }
}

private struct RevealToggle: View {
    @Binding var revealed: Bool

    var body: some View {
        Button(revealed ? "Hide" : "Show") { revealed.toggle() }
            .font(.system(size: 13.5, weight: .semibold))
            .foregroundStyle(OctoColor.textSecondary)
            .buttonStyle(.plain)
    }
}

private struct SwitchRow: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool

    init(_ title: String, _ detail: String, isOn: Binding<Bool>) {
        self.title = title
        self.detail = detail
        _isOn = isOn
    }

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.octoBodySmall).foregroundStyle(OctoColor.textPrimary)
                Text(detail).font(.octoCaption).foregroundStyle(OctoColor.textMuted)
            }
        }
        .tint(OctoColor.accent)
    }
}

private struct Section<Content: View>: View {
    let title: String
    let detail: String
    @ViewBuilder var content: Content

    init(_ title: String, _ detail: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.detail = detail
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.octoBodySmall).foregroundStyle(OctoColor.textPrimary)
                Text(detail).font(.octoCaption).foregroundStyle(OctoColor.textMuted)
            }
            content
        }
    }
}

/// How safe the connection is.
struct ConnectionNoteView: View {
    let note: SignInModel.Note

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 12, weight: .semibold))
            Text(words).font(.octoCaption).multilineTextAlignment(.center)
        }
        .foregroundStyle(note == .legacyInTheOpen ? OctoColor.error : OctoColor.textMuted)
        .frame(maxWidth: .infinity)
    }

    private var icon: String { note == .encrypted ? "lock.fill" : "lock.open.fill" }

    private var words: String {
        switch note {
        case .encrypted: "Encrypted connection"
        case .homeNetwork: "Not encrypted. Fine on your home network."
        case .legacyInTheOpen: "Not encrypted, and a legacy password travels as it is. Anyone on the way can read it."
        case .tokenInTheOpen: "Not encrypted. Your password goes as a one-time token, but the rest can be read on the way."
        }
    }
}

/// Asks before trusting a certificate the phone does not.
struct TrustSheet: View {
    let question: ServerTrust.Untrusted
    let trust: () -> Void
    let cancel: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Trust this certificate?").font(.octoHeadline)
            Text("This phone doesn't trust the certificate the server showed. If it's your own server's, check the fingerprint matches before you trust it. Octo will trust this one certificate, and only for this host.")
                .font(.octoBodySmall)
                .foregroundStyle(OctoColor.textSecondary)
            VStack(alignment: .leading, spacing: 4) {
                Text("Host").font(.octoCaption).foregroundStyle(OctoColor.textMuted)
                Text(question.host).font(.octoBodySmall)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("SHA-256 fingerprint").font(.octoCaption).foregroundStyle(OctoColor.textMuted)
                Text(question.fingerprint).font(.system(size: 13, design: .monospaced)).textSelection(.enabled)
            }
            Spacer(minLength: 0)
            VStack(spacing: 10) {
                Button {
                    dismiss()
                    trust()
                } label: {
                    Text("Trust this certificate").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                Button {
                    dismiss()
                    cancel()
                } label: {
                    Text("Cancel").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
            }
            .controlSize(.large)
        }
        .padding(24)
        .presentationDetents([.medium])
        .interactiveDismissDisabled()
    }
}

extension ServerTrust.Untrusted: Identifiable {
    var id: String { host + fingerprint }
}
