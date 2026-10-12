import Foundation
import Network
import Observation
import OctoKit
import UIKit

/// The servers kept on this phone and the one in use. Octo works with no server at all (the
/// music on the phone); a server is an add-on whose music joins the library.
@MainActor
@Observable
final class Session {
    private(set) var servers: [StoredServer] = []
    private(set) var activeId: String?
    private(set) var client: SubsonicClient?
    private(set) var profile: ServerProfile?
    /// True while the home network address is the one in use.
    private(set) var atHome = false
    var quality: StreamQuality {
        didSet { Self.store(quality) }
    }

    var active: StoredServer? { servers.first { $0.id == activeId } }
    var isOcto: Bool { profile?.isOcto ?? active?.isOcto ?? false }
    var serverName: String { active?.name ?? "" }

    /// Runs before the server in use changes to another (its id) or none, while the old one is
    /// still the one in use: what plays stops and counts for it, and its queue is put away.
    @ObservationIgnored var leaving: (@MainActor (_ from: StoredServer, _ to: String?) async -> Void)?

    @ObservationIgnored private let trust = ServerTrust.shared
    @ObservationIgnored private let network = NWPathMonitor()
    @ObservationIgnored private var onLocalNetwork = false

    private static let serversKey = "servers"
    private static let activeKey = "servers.active"
    private static let deviceKey = "device.id"
    private static let qualityKey = "stream.quality"

    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    init() {
        quality = Self.storedQuality()
        load()
        network.pathUpdateHandler = { [weak self] path in
            let local = path.usesInterfaceType(.wifi) || path.usesInterfaceType(.wiredEthernet)
            Task { @MainActor in
                guard let self, local != self.onLocalNetwork else { return }
                self.onLocalNetwork = local
                await self.chooseAddress()
            }
        }
        network.start(queue: DispatchQueue(label: "app.winters.octo.network"))
        if let server = active, !server.signedOut { connect(server) }
    }

    // MARK: Signing in

    /// Everything the sign-in page collects.
    struct Form {
        var address: URL
        var homeAddress: URL?
        var label: String?
        var username: String
        /// Empty keeps the saved one, when editing.
        var secret: String
        var mode: AuthMode
        var headers: [(name: String, value: String?)]
        var certificate: (data: Data, password: String)?
        var removesCertificate = false
    }

    enum Purpose: Equatable {
        case signIn
        case add
        case edit(String)
    }

    /// Checks the server and keeps it. Returns the words to show after, if any.
    @discardableResult
    func keep(_ form: Form, for purpose: Purpose) async throws -> String? {
        let editing: StoredServer? = if case .edit(let id) = purpose { servers.first { $0.id == id } } else { nil }
        if let editing, form.address != editing.address || form.username != editing.username,
           let other = servers.first(where: { $0.id != editing.id && $0.address == form.address && $0.username == form.username }) {
            throw SignInFailure.words(SignInWords.alreadyKept(other.name))
        }
        let existing = editing ?? servers.first { $0.address == form.address && $0.username == form.username }
        let id = existing?.id ?? UUID().uuidString

        var secret = form.secret
        if secret.isEmpty, let existing, Self.sameKind(existing.mode, form.mode) {
            secret = Keychain.read(for: Self.secretAccount(id)) ?? ""
        }
        guard !secret.isEmpty else { throw SignInFailure.words(SignInWords.missingSecret) }

        var headers: [String: String] = [:]
        let savedHeaders = existing.map { Self.headers(for: $0.id) } ?? [:]
        for header in form.headers {
            headers[header.name] = header.value ?? savedHeaders[header.name]
        }
        if let certificate = form.certificate {
            try trust.useClientCertificate(certificate.data, password: certificate.password)
        } else if form.removesCertificate {
            try? trust.useClientCertificate(nil, password: "")
        } else if let existing, existing.hasClientCertificate {
            loadCertificate(for: existing.id)
        }

        let credentials = Credentials(username: form.username, password: secret, mode: form.mode)
        var client = makeClient(form.address, credentials, headers)
        var profile: ServerProfile
        do {
            profile = try await reach(client)
        } catch where Self.isUnreachable(error) && form.homeAddress != nil {
            client = client.at(form.homeAddress!)
            profile = try await reach(client)
        }
        var username = form.username
        if form.mode == .apiKey {
            username = try await client.tokenInfo()
            client = client.with(credentials.named(username))
        }
        let octo = await Self.probeOcto(client)

        let server = StoredServer(
            id: id, label: form.label ?? existing?.label, address: form.address, homeAddress: form.homeAddress,
            username: username, mode: form.mode, headerNames: form.headers.map(\.name),
            hasClientCertificate: form.certificate != nil || (existing?.hasClientCertificate == true && !form.removesCertificate),
            serverType: profile.info.type, serverVersion: profile.info.serverVersion,
            isOcto: profile.isOcto || octo, extensions: profile.extensions)
        Keychain.save(secret, for: Self.secretAccount(id))
        Keychain.saveData(try JSONEncoder().encode(headers), for: Self.headersAccount(id))
        if let certificate = form.certificate {
            Keychain.saveData(certificate.data, for: Self.certificateAccount(id))
            Keychain.save(certificate.password, for: Self.certificatePasswordAccount(id))
        } else if form.removesCertificate {
            Keychain.delete(for: Self.certificateAccount(id))
            Keychain.delete(for: Self.certificatePasswordAccount(id))
        }
        let previous = active
        if let index = servers.firstIndex(where: { $0.id == id }) { servers[index] = server } else { servers.append(server) }

        switch purpose {
        case .add:
            save()
            return "Added \(server.name). Switch to it whenever you like."
        case .edit where activeId != id:
            save()
            return "Saved \(server.name)."
        default:
            if let previous, previous.id != id, !previous.signedOut, self.client != nil { await leaving?(previous, id) }
            activeId = id
            save()
            self.client = client
            self.profile = profile
            atHome = client.baseURL == server.homeAddress
            Task { await chooseAddress() }
            guard let previous, previous.id != id else { return nil }
            return "Now on \(server.name)."
        }
    }

    /// Uses a kept server, checking it first with its saved password.
    func switchTo(_ id: String) async throws {
        guard let server = servers.first(where: { $0.id == id }) else {
            throw SignInFailure.words("That server isn't in your list any more.")
        }
        guard !server.signedOut, let secret = Keychain.read(for: Self.secretAccount(id)) else {
            throw SignInFailure.needsPassword(id, "\(server.name) didn't take the saved password. It may have been changed.")
        }
        if server.hasClientCertificate { loadCertificate(for: id) }
        let client = makeClient(server.address, Credentials(username: server.username, password: secret, mode: server.mode),
                                Self.headers(for: id))
        do {
            profile = try await reach(client)
        } catch OctoError.wrongCredentials {
            throw SignInFailure.needsPassword(id, "\(server.name) didn't take the saved password. It may have been changed.")
        } catch {
            throw SignInFailure.words("Couldn't switch to \(server.name). \(SignInWords.describe(error))")
        }
        if let previous = active, previous.id != id, !previous.signedOut, self.client != nil { await leaving?(previous, id) }
        activeId = id
        self.client = client
        atHome = false
        save()
        await chooseAddress()
    }

    /// Keeps the server in the list but forgets its password.
    func signOut(_ id: String) {
        guard let index = servers.firstIndex(where: { $0.id == id }) else { return }
        servers[index].signedOut = true
        Keychain.delete(for: Self.secretAccount(id))
        if activeId == id {
            client = nil
            profile = nil
            atHome = false
        }
        save()
    }

    func remove(_ id: String) {
        signOut(id)
        servers.removeAll { $0.id == id }
        for account in [Self.headersAccount(id), Self.certificateAccount(id), Self.certificatePasswordAccount(id)] {
            Keychain.delete(for: account)
        }
        if activeId == id { activeId = nil }
        save()
    }

    /// Saved custom header names for a server, to show on the edit form.
    func savedHeaderNames(_ id: String) -> [String] {
        Array(Self.headers(for: id).keys).sorted()
    }

    // MARK: Connecting

    private func connect(_ server: StoredServer) {
        guard let secret = Keychain.read(for: Self.secretAccount(server.id)) else { return }
        if server.hasClientCertificate { loadCertificate(for: server.id) }
        client = makeClient(server.address, Credentials(username: server.username, password: secret, mode: server.mode),
                            Self.headers(for: server.id))
        Task {
            await chooseAddress()
            if let client { profile = try? await client.profile() }
        }
    }

    /// On Wi-Fi or Ethernet the home network address is used when it answers within two
    /// seconds; anywhere else, or when it does not answer, the main address.
    func chooseAddress() async {
        guard let server = active, let client else { return }
        var target = server.address
        if onLocalNetwork, let home = server.homeAddress {
            let probe = makeClient(home, client.credentials, client.customHeaders, timeout: 2)
            if (try? await probe.profile()) != nil { target = home }
        }
        guard target != client.baseURL else { return }
        self.client = client.at(target)
        atHome = target == server.homeAddress
    }

    private func makeClient(_ address: URL, _ credentials: Credentials, _ headers: [String: String],
                            timeout: TimeInterval? = nil) -> SubsonicClient {
        SubsonicClient(baseURL: address, credentials: credentials, device: Self.device(), appVersion: Self.appVersion,
                       customHeaders: headers, session: trust.session, timeout: timeout)
    }

    /// Pings and reads extensions. An untrusted certificate becomes a question for the person.
    private func reach(_ client: SubsonicClient) async throws -> ServerProfile {
        do {
            return try await client.profile()
        } catch let error as URLError where Self.isCertificateFailure(error) {
            if let question = trust.rejection(for: client.baseURL.host) { throw question }
            throw error
        }
    }

    /// Octo's own page answers with an "octo" key; only on the home network, usually.
    private static func probeOcto(_ client: SubsonicClient) async -> Bool {
        let url = client.signed(client.baseURL.appendingPathComponent("api/admin/status"))
        var request = URLRequest(url: url, timeoutInterval: 5)
        for (name, value) in client.headers { request.setValue(value, forHTTPHeaderField: name) }
        guard let (data, _) = try? await ServerTrust.shared.session.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return false }
        return json["octo"] != nil
    }

    private func loadCertificate(for id: String) {
        guard let data = Keychain.readData(for: Self.certificateAccount(id)) else { return }
        try? trust.useClientCertificate(data, password: Keychain.read(for: Self.certificatePasswordAccount(id)) ?? "")
    }

    private static func isUnreachable(_ error: Error) -> Bool {
        guard let error = error as? URLError else { return false }
        return !isCertificateFailure(error)
    }

    private static func isCertificateFailure(_ error: URLError) -> Bool {
        [.serverCertificateUntrusted, .serverCertificateHasBadDate, .serverCertificateHasUnknownRoot,
         .serverCertificateNotYetValid, .secureConnectionFailed, .cancelled].contains(error.code)
    }

    /// A password serves token and legacy sign-in; a key serves only a key.
    private static func sameKind(_ a: AuthMode, _ b: AuthMode) -> Bool {
        (a == .apiKey) == (b == .apiKey)
    }

    // MARK: Storage

    private func load() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: Self.serversKey),
           let kept = try? JSONDecoder().decode([StoredServer].self, from: data) {
            servers = kept
        }
        activeId = defaults.string(forKey: Self.activeKey)
        migrateFirstSignIn()
    }

    /// The first builds kept one server under single keys; it becomes the first kept server.
    private func migrateFirstSignIn() {
        let defaults = UserDefaults.standard
        guard servers.isEmpty, let text = defaults.string(forKey: "server.address"), let address = URL(string: text),
              let username = defaults.string(forKey: "server.username")
        else { return }
        let oldAccount = "\(username)@\(ServerAddress.shown(address))"
        let server = StoredServer(address: address, username: username,
                                  mode: defaults.bool(forKey: "server.legacyPassword") ? .legacyPassword : .token)
        if let secret = Keychain.read(for: oldAccount) {
            Keychain.save(secret, for: Self.secretAccount(server.id))
            Keychain.delete(for: oldAccount)
        }
        servers = [server]
        activeId = server.id
        for key in ["server.address", "server.username", "server.legacyPassword"] { defaults.removeObject(forKey: key) }
        save()
    }

    private func save() {
        let defaults = UserDefaults.standard
        defaults.set(try? JSONEncoder().encode(servers), forKey: Self.serversKey)
        defaults.set(activeId, forKey: Self.activeKey)
    }

    private static func secretAccount(_ id: String) -> String { "server.\(id).secret" }
    private static func headersAccount(_ id: String) -> String { "server.\(id).headers" }
    private static func certificateAccount(_ id: String) -> String { "server.\(id).certificate" }
    private static func certificatePasswordAccount(_ id: String) -> String { "server.\(id).certificate.password" }

    private static func headers(for id: String) -> [String: String] {
        Keychain.readData(for: headersAccount(id)).flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
    }

    /// This install, as the server knows it: an id made once, and the phone's name.
    private static func device() -> DeviceIdentity {
        let defaults = UserDefaults.standard
        let id = defaults.string(forKey: deviceKey) ?? {
            let made = UUID().uuidString.lowercased()
            defaults.set(made, forKey: deviceKey)
            return made
        }()
        return DeviceIdentity(id: id, name: UIDevice.current.name)
    }

    private static func store(_ quality: StreamQuality) {
        let value = switch quality {
        case .original: 0
        case .mp3(let kbps): kbps
        }
        UserDefaults.standard.set(value, forKey: qualityKey)
    }

    private static func storedQuality() -> StreamQuality {
        let value = UserDefaults.standard.integer(forKey: qualityKey)
        return value > 0 ? .mp3(kbps: value) : .original
    }
}

enum SignInFailure: LocalizedError {
    case words(String)
    /// The saved password did not work; the form opens for this server.
    case needsPassword(String, String)

    var errorDescription: String? {
        switch self {
        case .words(let text), .needsPassword(_, let text): text
        }
    }
}
