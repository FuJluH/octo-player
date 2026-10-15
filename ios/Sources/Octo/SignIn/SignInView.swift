import OctoKit
import SwiftUI
import UniformTypeIdentifiers

/// The sign-in page: the octopus over Octo's name, one glass card with the address, username
/// and password, then the button, the connection note and Advanced. Joining a family swaps the
/// username and password for the invite's sign-up or a sign-in handed over from another device.
struct SignInView: View {
    @Environment(Session.self) private var session
    @Environment(ServerSync.self) private var sync
    @Environment(ServerSwitch.self) private var serverSwitch
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

    enum Field: Hashable { case address, label, username, password, apiKey, home, joinName, joinPassword, joinAgain }

    #if DEBUG
    /// Set by a launch step: the next sign-in screen opens with the family QR scanner.
    static var scanOnOpen = false
    #endif

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
                if model.joining {
                    joinButtons
                } else {
                    AccentButton(model.buttonTitle, enabled: model.ready, loading: model.busy, fillWidth: true) {
                        Task { await model.submit(session, sync: sync) }
                    }
                    .padding(.top, 20)
                    if let error = model.error { errorLine(error) }
                    if model.offersScan {
                        GlazeButton("Scan a family QR code", icon: .camera, size: .small) {
                            model.startJoin()
                            model.scanning = true
                        }
                        .padding(.top, 12)
                    }
                    advancedToggle
                        .padding(.top, 20)
                    if model.advancedOpen {
                        advanced
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 60)
            .frame(maxWidth: 420)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background { PageBackdrop(page: glowPage, route: nil) }
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
        .overlay {
            if let question = model.question {
                TrustSheet(question: question) {
                    Task { await model.trust(session, sync: sync) }
                } cancel: {
                    model.distrust()
                }
                .transition(.opacity)
            }
        }
        .overlay {
            if model.scanning {
                QrScanner { link in
                    model.startJoin(link, session: session)
                } cancel: {
                    model.scanning = false
                }
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: model.scanning)
        .animation(.easeOut(duration: 0.2), value: model.question)
        .onAppear {
            model.serverSwitch = serverSwitch
            #if DEBUG
            if Self.scanOnOpen {
                Self.scanOnOpen = false
                model.startJoin()
                model.scanning = true
            }
            #endif
            if case .join(let text) = model.form, let link = parseFamilyLink(text) { model.startJoin(link, session: session) }
        }
        .onDisappear { model.leave() }
        .onChange(of: model.signedIn) { _, signedIn in
            if signedIn {
                done(model.notice)
                dismiss()
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

    /// What kind of page the form is, as the glow sees it: each is a Settings page.
    private var glowPage: AmbientPage {
        switch model.form {
        case .signIn: .signIn
        case .editConnection: .editConnection
        case .add, .edit, .again: .serverForm
        case .join: .familyJoin
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
                .padding(.top, 4)
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
                            .foregroundStyle(model.scheme == .https ? OctoColor.accent : OctoColor.textMuted)
                        Text(model.scheme.prefix).font(.octoBody).foregroundStyle(OctoColor.textMuted)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(model.scheme == .https ? "Encrypted, https" : "Not encrypted, http")
                .accessibilityHint(model.scheme == .https ? "Use http" : "Use https")
                TextField("music.example.com", text: Binding(get: { model.rest }, set: { model.typeAddress($0, session: session) }))
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .focused($focus, equals: .address)
                    .submitLabel(.next)
                    .onSubmit { focus = .username }
            }
            if model.showsName { labelField }
            if model.joining {
                joinFields
            } else {
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
                            .submitLabel(.done)
                            .onSubmit { Task { await model.submit(session, sync: sync) } }
                        RevealToggle(revealed: $reveal)
                    }
                }
            }
        }
        .padding(16)
        .glassEffect(Glass.octo, in: .rect(cornerRadius: 22))
    }

    private func errorLine(_ text: String) -> some View {
        Text(text)
            .font(.octoBodySmall)
            .foregroundStyle(OctoColor.error)
            .multilineTextAlignment(.center)
            .padding(.top, 12)
    }

    // MARK: Join

    /// In place of the username and password: the sign-up for an invite, a sign-in handed over,
    /// or what to do with no link yet.
    @ViewBuilder
    private var joinFields: some View {
        @Bindable var model = model
        if let handOver = model.handOver {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 12) {
                    if model.busy { LoadingSpinner(size: 22) }
                    Text(model.handOverStep ?? "Ready to sign in to \(shownServer(handOver.server))")
                        .font(.octoBody)
                        .foregroundStyle(OctoColor.textPrimary)
                }
                .padding(.vertical, 6)
                Text("On your other device, tap Allow when it asks about this phone.")
                    .font(.octoCaption)
                    .foregroundStyle(OctoColor.textMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if let invite = model.invite {
            Text("You're invited to \(shownServer(invite.server)). Choose your name and a password. Your login then works in Octo and any other music app.")
                .font(.octoBodySmall)
                .foregroundStyle(OctoColor.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            GlassField {
                FieldIcon("person")
                TextField("Your name", text: $model.joinName)
                    .textInputAutocapitalization(.words)
                    .textContentType(.name)
                    .focused($focus, equals: .joinName)
                    .submitLabel(.next)
                    .onSubmit { focus = .joinPassword }
            }
            GlassField {
                FieldIcon("key")
                SecureField("Password, at least \(minPassword) characters", text: $model.joinPassword)
                    .textContentType(.newPassword)
                    .focused($focus, equals: .joinPassword)
                    .submitLabel(.next)
                    .onSubmit { focus = .joinAgain }
            }
            if let strength = model.strength {
                Text(strength).font(.octoCaption).foregroundStyle(OctoColor.textMuted).frame(maxWidth: .infinity, alignment: .leading)
            }
            GlassField {
                FieldIcon("key")
                SecureField("The same password again", text: $model.joinAgain)
                    .textContentType(.newPassword)
                    .focused($focus, equals: .joinAgain)
                    .submitLabel(.done)
                    .onSubmit { Task { await model.signUp(session) } }
            }
        } else {
            Text("Your invite, or Sign in on another device on your other phone or computer, shows a QR code. Scan it, or open its link on this phone.")
                .font(.octoBodySmall)
                .foregroundStyle(OctoColor.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Under the card while joining: the step's own button, the error, the scanner and the way
    /// back to the password form.
    @ViewBuilder
    private var joinButtons: some View {
        if model.invite != nil {
            AccentButton("Sign up", enabled: model.joinMissing == nil, loading: model.busy, fillWidth: true) {
                Task { await model.signUp(session) }
            }
            .padding(.top, 20)
        } else if model.handOver != nil, !model.busy {
            AccentButton("Try again", fillWidth: true) { model.receive(session) }
                .padding(.top, 20)
        }
        if let error = model.error { errorLine(error) }
        if model.handOver == nil {
            GlazeButton("Scan the QR code", icon: .camera, size: .small) { model.scanning = true }
                .padding(.top, 12)
        }
        GlazeButton("Sign in with a password", size: .small) { model.stopJoin() }
            .padding(.top, 12)
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
                GlazeButton("Add header", size: .small, action: model.addHeader)
            }
            Section("Client certificate", "For servers that ask the phone to prove itself with a certificate.") {
                HStack {
                    Text(model.certificateShown ?? "None")
                        .font(.octoBodySmall)
                        .foregroundStyle(model.certificateShown == nil ? OctoColor.textMuted : OctoColor.textPrimary)
                    Spacer()
                    if model.certificateShown != nil {
                        Button("Remove") {
                            model.certificate = nil
                            model.removesCertificate = model.hadCertificate
                        }
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(OctoColor.accent)
                        .buttonStyle(.plain)
                    }
                }
                GlazeButton(model.certificateShown == nil ? "Choose certificate" : "Choose another", size: .small) {
                    certificateError = nil
                    choosingCertificate = true
                }
            }
        }
        .padding(.top, 6)
    }

    private func takeCertificate() {
        guard let pending = pendingCertificate else { return }
        do {
            // Only checked here: the server in use keeps its certificate until this one is saved.
            try CertificateCheck.validate(pending.data, password: certificatePassword)
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
            .foregroundStyle(OctoColor.accent)
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
        .foregroundStyle(color)
        .frame(maxWidth: .infinity)
    }

    private var icon: String { note == .encrypted ? "lock.fill" : "lock.open.fill" }

    /// Red when the password itself travels in the open, secondary for other plain traffic
    /// across the internet, muted otherwise.
    private var color: Color {
        switch note {
        case .legacyInTheOpen: OctoColor.error
        case .tokenInTheOpen: OctoColor.textSecondary
        case .encrypted, .homeNetwork: OctoColor.textMuted
        }
    }

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

    /// Sized to its content when it fits, and scrolling when large text or a small screen would
    /// push the buttons off.
    var body: some View {
        ViewThatFits(in: .vertical) {
            content
            ScrollView { content }
                .scrollBounceBehavior(.basedOnSize)
        }
        .frame(maxWidth: 380)
        .glassEffect(Glass.octo, in: .rect(cornerRadius: 20))
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.45).ignoresSafeArea().onTapGesture(perform: cancel))
        .accessibilityAddTraits(.isModal)
        .accessibilityLabel("Trust this certificate")
    }

    private var content: some View {
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
            HStack(spacing: 10) {
                AccentButton("Trust this certificate", size: .medium, action: trust)
                GlazeButton("Cancel", size: .medium, action: cancel)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension ServerTrust.Untrusted: Identifiable {
    var id: String { host + fingerprint }
}
