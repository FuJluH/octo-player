import Foundation
import Observation
import OctoKit

/// The sign-in page's state and rules, the same as the other apps' sign-in.
@MainActor
@Observable
final class SignInModel {
    enum Form: Equatable {
        /// Signing in from scratch, or from Settings.
        case signIn
        /// From the server list: keep another server.
        case add
        /// From the server list: change a kept one.
        case edit(StoredServer)
        /// From the server list: sign in to a kept one again.
        case again(StoredServer)
    }

    struct Header: Identifiable, Equatable {
        let id = UUID()
        var name: String
        var value: String
        /// The value is kept in the keychain and is not shown.
        var saved: Bool
    }

    let form: Form
    var rest = "" { didSet { typed() } }
    private(set) var scheme: ServerAddress.Scheme = .https
    private var schemePicked = false
    var label = ""
    var username = ""
    var password = ""
    var apiKey = ""
    var legacy = false
    var useApiKey = false
    var takesApiKeys: Bool?
    var homeAddress = ""
    var headers: [Header] = []
    var certificate: (name: String, data: Data, password: String)?
    var hadCertificate = false
    var removesCertificate = false
    var advancedOpen = false

    var busy = false
    var error: String?
    var question: ServerTrust.Untrusted?
    private(set) var notice: String?
    private(set) var signedIn = false

    init(form: Form, session: Session) {
        self.form = form
        guard let server = form.server else { return }
        let (scheme, rest) = ServerAddress.split(ServerAddress.shown(server.address))
        self.rest = rest
        self.scheme = scheme ?? .https
        schemePicked = true
        label = server.label ?? ""
        username = server.username
        legacy = server.mode == .legacyPassword
        useApiKey = server.mode == .apiKey
        homeAddress = server.homeAddress.map(ServerAddress.shown) ?? ""
        headers = session.savedHeaderNames(server.id).map { Header(name: $0, value: "", saved: true) }
        hadCertificate = server.hasClientCertificate
        advancedOpen = server.mode != .token || server.homeAddress != nil || !headers.isEmpty || hadCertificate
        takesApiKeys = server.extensions.contains { $0.hasPrefix("apiKeyAuthentication") } ? true : nil
    }

    var editing: Bool { form.server != nil }

    /// The heading for the server list's forms; nil shows Octo's name.
    var heading: String? {
        switch form {
        case .signIn: nil
        case .add: "Add a server"
        case .edit(let server): "Edit \(server.name)"
        case .again(let server): "Sign in to \(server.name)"
        }
    }

    var subheading: String {
        switch form {
        case .signIn: "Sign in to your music server"
        case .add: "Keep another server here and switch to it in one tap."
        case .edit: "Octo signs in with the new details before it saves them."
        case .again(let server): server.account
        }
    }

    var buttonTitle: String {
        switch form {
        case .signIn: "Sign in"
        case .add: "Add"
        case .edit: "Save"
        case .again: "Sign in"
        }
    }

    var url: URL? { ServerAddress.url(scheme, rest) }

    var ready: Bool {
        guard url != nil, !busy else { return false }
        if useApiKey { return !apiKey.isEmpty || editing }
        return !username.trimmingCharacters(in: .whitespaces).isEmpty && (!password.isEmpty || editing)
    }

    /// A scheme typed or pasted moves into the button; until one is picked the scheme follows
    /// the address, http on the home network and https anywhere else.
    private func typed() {
        let (typedScheme, remainder) = ServerAddress.split(rest)
        if let typedScheme {
            scheme = typedScheme
            schemePicked = true
            rest = remainder
            return
        }
        if !schemePicked, !rest.isEmpty { scheme = ServerAddress.automaticScheme(rest) }
    }

    func toggleScheme() {
        scheme = scheme == .https ? .http : .https
        schemePicked = true
    }

    /// How safe the connection is, for the line under the card.
    enum Note: Equatable {
        case encrypted, homeNetwork, legacyInTheOpen, tokenInTheOpen
    }

    var note: Note? {
        guard let url else { return nil }
        if url.scheme == "https" { return .encrypted }
        if ServerAddress.isPrivate(url) { return .homeNetwork }
        return legacy && !useApiKey ? .legacyInTheOpen : .tokenInTheOpen
    }

    func addHeader() {
        headers.append(Header(name: "", value: "", saved: false))
    }

    func renameHeader(_ id: Header.ID, to name: String) {
        guard let index = headers.firstIndex(where: { $0.id == id }) else { return }
        // A renamed saved header no longer has a value to keep.
        if headers[index].saved, headers[index].name != name { headers[index].saved = false }
        headers[index].name = name
    }

    func submit(_ session: Session) async {
        guard ready, let url else { return }
        error = nil
        let home: URL?
        if homeAddress.trimmingCharacters(in: .whitespaces).isEmpty {
            home = nil
        } else {
            guard let parsed = ServerAddress.parse(homeAddress) else {
                error = SignInWords.badHomeAddress
                return
            }
            home = parsed == url ? nil : parsed
        }
        let rows = headers.filter { !($0.name.isEmpty && $0.value.isEmpty && !$0.saved) }
        guard rows.allSatisfy({ HeaderRules.isValidName($0.name) && ($0.saved || HeaderRules.isValidValue($0.value)) && ($0.saved || !$0.value.isEmpty) }) else {
            error = SignInWords.badHeaders
            return
        }
        let mode: AuthMode = useApiKey ? .apiKey : (legacy ? .legacyPassword : .token)
        let fields = Session.Form(
            address: url, homeAddress: home,
            label: label.trimmingCharacters(in: .whitespaces).isEmpty ? nil : label.trimmingCharacters(in: .whitespaces),
            username: username.trimmingCharacters(in: .whitespaces),
            secret: useApiKey ? apiKey : password,
            mode: mode,
            headers: rows.map { ($0.name, $0.saved && $0.value.isEmpty ? nil : $0.value) },
            certificate: certificate.map { ($0.data, $0.password) },
            removesCertificate: removesCertificate)
        let purpose: Session.Purpose = switch form {
        case .signIn, .again: .signIn
        case .add: .add
        case .edit(let server): .edit(server.id)
        }
        busy = true
        defer { busy = false }
        do {
            notice = try await session.keep(fields, for: purpose)
            password = ""
            apiKey = ""
            signedIn = true
        } catch let untrusted as ServerTrust.Untrusted {
            question = untrusted
        } catch OctoError.authUnsupported(41, _) where mode == .token {
            // Servers that check passwords against a directory cannot check a token. Over https or
            // on the home network the password may go as it is, so try that at once.
            if url.scheme == "https" || ServerAddress.isPrivate(url) {
                legacy = true
                advancedOpen = true
                busy = false
                await submit(session)
            } else {
                error = SignInWords.legacyOverHttp
            }
        } catch {
            self.error = error is SignInFailure ? error.localizedDescription : SignInWords.describe(error)
        }
    }

    func trust(_ session: Session) async {
        guard let question else { return }
        ServerTrust.shared.trust(question)
        self.question = nil
        await submit(session)
    }

    func distrust() {
        question = nil
        error = SignInWords.notTrusted
    }
}

extension SignInModel.Form {
    var server: StoredServer? {
        switch self {
        case .edit(let server), .again(let server): server
        case .signIn, .add: nil
        }
    }
}
