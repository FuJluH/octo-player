import Foundation
import Network
import Observation
import OctoKit
import UIKit

/// The servers kept on this phone and the one in use. Octo works with no server at all (the
/// music on the phone); a server is an add-on whose music joins the library. Several can be
/// kept, with one in use: signing in, adding another, switching between them, editing, signing
/// out and removing all go through here. Secrets live only in the keychain.
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

    /// Runs before the server in use changes to another (its id) or none, while the old one is
    /// still the one in use: what plays stops and counts for it, and its queue is put away.
    @ObservationIgnored var leaving: (@MainActor (_ from: StoredServer, _ to: String?) async -> Void)?

    var active: StoredServer? { servers.first { $0.id == activeId } }
    var isOcto: Bool { profile?.isOcto ?? active?.isOcto ?? false }
    var serverName: String { active?.name ?? "" }

    /// The extensions the server in use lists, as last read.
    var extensions: [String] { active?.extensions ?? profile?.extensions ?? [] }

    /// Whether the server in use runs Octo: its status page answered at sign-in, it calls itself
    /// Octo, or it lists an Octo extension.
    var runsOcto: Bool {
        guard let active else { return false }
        return isOctoServer(probed: active.isOcto, serverType: active.serverType ?? profile?.info.type, extensions: extensions)
    }

    /// Whether the server in use has Family on.
    var family: Bool { client != nil && extensions.contains("\(octoFamily):1") }

    /// Where the server in use is reached from, when it has a home address.
    var place: ServerPlace? {
        guard client != nil, active?.homeAddress != nil else { return nil }
        return atHome ? .home : .away
    }

    @ObservationIgnored private let trust = ServerTrust.shared
    @ObservationIgnored private let network = NWPathMonitor()
    @ObservationIgnored private var onLocalNetwork = false
    @ObservationIgnored private var lastFailureCheck = Date.distantPast
    @ObservationIgnored private let prefs = UserDefaults.standard

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
            let lost = path.status != .satisfied
            Task { @MainActor in
                guard let self else { return }
                if lost || local != self.onLocalNetwork {
                    self.onLocalNetwork = local
                    await self.chooseAddress()
                }
            }
        }
        network.start(queue: DispatchQueue(label: "app.winters.octo.network"))
        restore()
    }

    // MARK: Signing in

    /// Everything the sign-in page collects.
    struct Form {
        var address: URL
        var homeAddress: URL?
        /// The name to give the server; nil keeps the saved one, and empty clears it.
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
        /// Signs in and makes the server the one in use.
        case signIn
        /// Keeps another server without leaving the one in use.
        case add
        /// Changes a kept server; the one in use is signed in to again.
        case edit(String)
    }

    /// What a finished keep came to: the server kept, and whether its main address changed.
    struct Kept {
        var server: StoredServer
        var addressChanged: Bool
    }

    /// Checks the server and keeps it. Throws `SignInFailure` with words, or the certificate
    /// question as `ServerTrust.Untrusted`.
    @discardableResult
    func keep(_ form: Form, for purpose: Purpose) async throws -> String? {
        let kept = try await keepServer(form, for: purpose)
        switch purpose {
        case .add: return "Added \(kept.server.name). Switch to it whenever you like."
        case .edit: return "Saved \(kept.server.name)."
        case .signIn: return nil
        }
    }

    func keepServer(_ form: Form, for purpose: Purpose) async throws -> Kept {
        var base: StoredServer?
        if case .edit(let id) = purpose {
            guard let found = servers.first(where: { $0.id == id }) else { throw SignInFailure.words(SignInWords.gone) }
            base = found
        }
        let main = form.address
        let home = form.homeAddress.flatMap { $0 == main ? nil : $0 }
        let username = form.username.trimmingCharacters(in: .whitespacesAndNewlines)
        let twin = servers.first { $0.address == main && $0.username == username && $0.id != base?.id }
        if base != nil, let twin { throw SignInFailure.words(SignInWords.alreadyKept(twin.name)) }
        let before = base ?? twin

        var secret = form.secret
        if secret.isEmpty, let before, Self.sameKind(before.mode, form.mode), !before.signedOut {
            secret = Keychain.read(for: Self.secretAccount(before.id)) ?? ""
        }
        guard !secret.isEmpty else { throw SignInFailure.words(SignInWords.missingSecret) }

        let headers = Self.cleanHeaders(form.headers, saved: before.map { Self.headers(for: $0.id) } ?? [:])
        if let certificate = form.certificate {
            try trust.useClientCertificate(certificate.data, password: certificate.password)
        } else if form.removesCertificate {
            try? trust.useClientCertificate(nil, password: "")
        } else if let before, before.hasClientCertificate {
            loadCertificate(for: before.id)
        }

        let use: Bool = switch purpose {
        case .signIn: true
        case .add: false
        case .edit(let id): id == activeId && client != nil
        }
        var credentials = Credentials(username: username, password: secret, mode: form.mode)
        var client = makeClient(main, credentials, headers)
        let profile: ServerProfile
        do {
            let reached = try await reach(client, main: main, home: home)
            client = reached.0
            profile = reached.1
            // A home address with a certificate the phone does not trust is asked about now.
            if let home, client.baseURL != home {
                do {
                    _ = try await makeClient(home, credentials, headers, timeout: 2).ping()
                } catch {
                    if case .unreachable = SubsonicError(error), let question = trust.rejection(for: home.host) { throw question }
                }
            }
        } catch {
            restoreSecurity()
            throw error
        }
        if form.mode == .apiKey, let owner = try? await client.tokenInfo(), !owner.isEmpty {
            credentials = credentials.named(owner)
            client = client.with(credentials)
        }
        let probed = await Self.probeOcto(client)
        let taken = Set(servers.map(\.id)).subtracting([before?.id].compactMap { $0 })
        let id: String = if let before, before.username == credentials.username {
            before.id
        } else {
            freshServerId(username: credentials.username, address: ServerAddress.written(main), taken: taken)
        }
        let label = form.label.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } ?? before?.label
        let server = StoredServer(
            id: id, label: label, address: main, homeAddress: home,
            username: credentials.username, mode: form.mode, headerNames: Array(headers.keys).sorted(),
            hasClientCertificate: form.certificate != nil || (before?.hasClientCertificate == true && !form.removesCertificate),
            serverType: profile.info.type, serverVersion: profile.info.serverVersion,
            isOcto: probed, extensions: profile.extensions)
        Keychain.save(secret, for: Self.secretAccount(id))
        Keychain.saveData(try JSONEncoder().encode(headers), for: Self.headersAccount(id))
        if let certificate = form.certificate {
            Keychain.saveData(certificate.data, for: Self.certificateAccount(id))
            Keychain.save(certificate.password, for: Self.certificatePasswordAccount(id))
        } else if form.removesCertificate {
            Keychain.delete(for: Self.certificateAccount(id))
            Keychain.delete(for: Self.certificatePasswordAccount(id))
        } else if let before, before.id != id, before.hasClientCertificate {
            Keychain.saveData(Keychain.readData(for: Self.certificateAccount(before.id)) ?? Data(), for: Self.certificateAccount(id))
            Keychain.save(Keychain.read(for: Self.certificatePasswordAccount(before.id)) ?? "", for: Self.certificatePasswordAccount(id))
        }
        if let before, before.id != id { forgetSecrets(before.id) }
        let addressChanged = before.map { $0.address != main } ?? false
        if addressChanged { prefs.removeObject(forKey: Self.folderKey(id)) }

        guard use else {
            restoreSecurity()
            if let before, let index = servers.firstIndex(where: { $0.id == before.id }) { servers[index] = server } else { servers.append(server) }
            save()
            return Kept(server: server, addressChanged: addressChanged)
        }
        let from = self.client == nil ? nil : active.flatMap { $0.id == id || $0.id == before?.id || $0.signedOut ? nil : $0 }
        if let from { await leaving?(from, id) }
        if let before, let index = servers.firstIndex(where: { $0.id == before.id }) { servers[index] = server } else { servers.append(server) }
        activate(server, client: client, profile: profile)
        return Kept(server: server, addressChanged: addressChanged)
    }

    /// Gives a kept server a name of its own; an empty one shows its host.
    func rename(_ id: String, label: String) {
        guard let index = servers.firstIndex(where: { $0.id == id }) else { return }
        servers[index].label = label.trimmingCharacters(in: .whitespacesAndNewlines)
        save()
    }

    // MARK: Switching

    /// How moving to another kept server went.
    enum SwitchResult: Equatable {
        case done
        /// Its password is not kept here, or the server no longer takes it.
        case needsPassword(StoredServer, String?)
        case failed(String)
    }

    /// Makes another kept server the one in use, signed in with its saved secret. It is asked
    /// first with a client of its own, so one out of reach leaves everything as it was.
    private func switchServer(_ id: String) async -> SwitchResult {
        guard let server = servers.first(where: { $0.id == id }) else { return .failed(SignInWords.gone) }
        let from = client == nil ? nil : active
        if from?.id == id { return .done }
        guard !server.signedOut, let secret = Keychain.read(for: Self.secretAccount(id)), !secret.isEmpty else {
            return .needsPassword(server, nil)
        }
        if server.hasClientCertificate { loadCertificate(for: id) }
        let headers = Self.headers(for: id)
        let credentials = Credentials(username: server.username, password: secret, mode: server.mode)
        let own = makeClient(server.address, credentials, headers, timeout: 6)
        let reached: (SubsonicClient, ServerProfile)
        do {
            reached = try await reach(own, main: server.address, home: server.homeAddress, timeout: 6)
        } catch {
            restoreSecurity()
            if case .wrongCredentials = SubsonicError(error) {
                return .needsPassword(server, passwordRefusedWords(name: server.name))
            }
            return .failed(switchFailedWords(name: server.name, why: failureWords(error)))
        }
        var fresh = server
        fresh.serverType = reached.1.info.type ?? server.serverType
        fresh.serverVersion = reached.1.info.serverVersion ?? server.serverVersion
        if !reached.1.extensions.isEmpty { fresh.extensions = reached.1.extensions }
        if let from, !from.signedOut { await leaving?(from, id) }
        if let index = servers.firstIndex(where: { $0.id == id }) { servers[index] = fresh }
        let client = makeClient(server.address, credentials, headers).at(reached.0.baseURL)
        activate(fresh, client: client, profile: reached.1)
        return .done
    }

    /// Uses a kept server, checking it first with its saved password. The servers list switches
    /// through `ServerSwitch`, which says how it went.
    func switchTo(_ id: String) async throws {
        switch await switchServer(id) {
        case .done: return
        case .needsPassword(let server, let note): throw SignInFailure.needsPassword(server.id, note ?? passwordRefusedWords(name: server.name))
        case .failed(let words): throw SignInFailure.words(words)
        }
    }

    /// How a kept server answers a quick look, with a client of its own. One signed out of is not asked.
    func check(_ id: String) async -> ServerCheck {
        guard let server = servers.first(where: { $0.id == id }) else { return ServerCheck(.unknown) }
        let asked: SubsonicClient
        if id == activeId, let client {
            asked = client
        } else {
            guard !server.signedOut, let secret = Keychain.read(for: Self.secretAccount(id)), !secret.isEmpty else { return ServerCheck(.unknown) }
            asked = makeClient(server.address, Credentials(username: server.username, password: secret, mode: server.mode),
                               Self.headers(for: id), timeout: 6)
        }
        let start = Date()
        do {
            _ = try await asked.ping()
            return ServerCheck(.answers, Int64(Date().timeIntervalSince(start) * 1_000))
        } catch {
            if case .wrongCredentials = SubsonicError(error) { return ServerCheck(.wrongPassword) }
            return ServerCheck(.unreachable)
        }
    }

    // MARK: Signing out and removing

    /// Signs out of a kept server, the one in use when `id` is nil. It stays in the list without
    /// its password, so signing in again needs only that; its header values stay. What plays is
    /// put away first by `ServerSwitch`, which the pages sign out through.
    func signOut(_ id: String? = nil) {
        guard let id = id ?? activeId, let index = servers.firstIndex(where: { $0.id == id }) else { return }
        servers[index].signedOut = true
        Keychain.delete(for: Self.secretAccount(id))
        if id == activeId { leaveSession() }
        save()
    }

    /// Takes a server off the list, with its password. Its music and playlists stay on the server.
    /// Answers the server removed, if it was kept. `ServerSwitch` puts away what plays first and
    /// removes its copy of the library after.
    @discardableResult
    func remove(_ id: String) -> StoredServer? {
        guard let server = servers.first(where: { $0.id == id }) else { return nil }
        servers.removeAll { $0.id == id }
        forgetSecrets(id)
        prefs.removeObject(forKey: Self.folderKey(id))
        if id == activeId { leaveSession() }
        save()
        return server
    }

    private func leaveSession() {
        activeId = nil
        client = nil
        profile = nil
        atHome = false
        restoreSecurity()
    }

    /// Saved custom header names for a server, to show on the edit form.
    func savedHeaderNames(_ id: String) -> [String] {
        Array(Self.headers(for: id).keys).sorted()
    }

    // MARK: The server in use

    /// Changes the signed-in user's password on the server. The current one is checked first; on
    /// success the new one is kept in place of the old, and the client signs in with it.
    func changePassword(current: String, new: String, family: Bool = false) async -> PasswordChange {
        guard let client, let id = activeId else { return .failed("Connect a server first.") }
        let result = await changeOwnPassword(client, current: current, new: new, family: family)
        guard result == .changed else { return result }
        Keychain.save(new, for: Self.secretAccount(id))
        if self.activeId == id, let now = self.client {
            self.client = now.with(Credentials(username: now.credentials.username, password: new, mode: now.credentials.mode))
        }
        return result
    }

    /// How quickly the server in use answers, in milliseconds, and how its folders scan stands.
    func look() async -> (answerMs: Int64?, scan: ServerScanStatus?) {
        guard let client else { return (nil, nil) }
        let start = Date()
        let answered = (try? await client.ping()) != nil
        let ms = answered ? Int64(Date().timeIntervalSince(start) * 1_000) : nil
        return (ms, try? await client.serverScanStatus())
    }

    /// The music folder the library is limited to on a kept server, when one is chosen.
    func folder(for id: String) -> (id: String, name: String)? {
        guard let saved = prefs.array(forKey: Self.folderKey(id)) as? [String], saved.count == 2 else { return nil }
        return (saved[0], saved[1])
    }

    /// Keeps the chosen folder's name to show; nil for all of them.
    func setFolder(_ folder: ServerMusicFolder?, for id: String) {
        if let folder { prefs.set([folder.id, folder.name], forKey: Self.folderKey(id)) } else { prefs.removeObject(forKey: Self.folderKey(id)) }
    }

    // MARK: Connecting

    /// At app start, the server in use signs in again with its saved secret. One whose secret can
    /// no longer be read stays in the list signed out, and nothing is in use.
    private func restore() {
        guard let server = active else { return }
        if server.signedOut {
            activeId = nil
            save()
            return
        }
        guard let secret = Keychain.read(for: Self.secretAccount(server.id)), !secret.isEmpty else {
            if let index = servers.firstIndex(where: { $0.id == server.id }) { servers[index].signedOut = true }
            activeId = nil
            save()
            return
        }
        if server.hasClientCertificate { loadCertificate(for: server.id) }
        client = makeClient(server.address, Credentials(username: server.username, password: secret, mode: server.mode),
                            Self.headers(for: server.id))
        let id = server.id
        Task {
            await chooseAddress()
            guard let client, activeId == id, let read = try? await client.profile() else { return }
            profile = read
            refreshExtensions(read.extensions, for: id)
        }
    }

    /// A server gains extensions over time, so each start asks again and keeps what it says when
    /// it lists some and they differ from the saved ones.
    private func refreshExtensions(_ fresh: [String], for id: String) {
        guard !fresh.isEmpty, activeId == id, let index = servers.firstIndex(where: { $0.id == id }),
              Set(fresh) != Set(servers[index].extensions)
        else { return }
        servers[index].extensions = fresh
        save()
    }

    private func activate(_ server: StoredServer, client: SubsonicClient, profile: ServerProfile) {
        activeId = server.id
        self.client = client
        self.profile = profile
        atHome = server.homeAddress != nil && client.baseURL == server.homeAddress
        save()
        Task { await chooseAddress() }
    }

    /// On Wi-Fi or Ethernet the home network address is used when it answers within two
    /// seconds; anywhere else, or when it does not answer, the main address.
    func chooseAddress() async {
        guard let server = active, let client else { return }
        var answered = false
        if onLocalNetwork, let home = server.homeAddress, home != server.address {
            answered = await Self.answers(makeClient(home, client.credentials, client.customHeaders, timeout: 2))
        }
        let place = choosePlace(hasHome: server.homeAddress != nil, onLocalNetwork: onLocalNetwork, homeAnswered: answered)
        let target = place == .home ? server.homeAddress ?? server.address : server.address
        guard self.client != nil, activeId == server.id else { return }
        if target != client.baseURL { self.client = client.at(target) }
        atHome = place == .home
    }

    /// After a call to the server could not connect: looks at the home address again, at most
    /// once every five seconds.
    func callFailedToConnect() {
        guard Date().timeIntervalSince(lastFailureCheck) >= 5 else { return }
        lastFailureCheck = Date()
        Task { await chooseAddress() }
    }

    /// Whether an address answers like the server: an error from the server itself still means
    /// it is there; only no connection, or not a music server, is a no.
    private static func answers(_ client: SubsonicClient) async -> Bool {
        do {
            _ = try await client.ping()
            return true
        } catch {
            switch SubsonicError(error) {
            case .unreachable, .notSubsonic: return false
            default: return true
            }
        }
    }

    private func makeClient(_ address: URL, _ credentials: Credentials, _ headers: [String: String],
                            timeout: TimeInterval? = nil) -> SubsonicClient {
        SubsonicClient(baseURL: address, credentials: credentials, device: Self.device(), appVersion: Self.appVersion,
                       customHeaders: headers, session: trust.session, timeout: timeout)
    }

    /// Pings the main address and reads extensions; when it cannot connect and there is a home
    /// address, the home one instead. An untrusted certificate becomes a question for the person.
    private func reach(_ client: SubsonicClient, main: URL, home: URL?, timeout: TimeInterval? = nil) async throws -> (SubsonicClient, ServerProfile) {
        do {
            return (client, try await client.profile())
        } catch let error as URLError {
            if isCertificateFailure(error, host: main.host) {
                if let question = trust.rejection(for: main.host) { throw question }
                throw error
            }
            guard let home else { throw error }
            let atHome = client.at(home)
            do {
                return (atHome, try await atHome.profile())
            } catch let homeError as URLError where isCertificateFailure(homeError, host: home.host) {
                if let question = trust.rejection(for: home.host) { throw question }
                throw error
            } catch {
                throw error
            }
        }
    }

    /// A refused certificate shows as the call being cancelled, since the trust check cancels it.
    private func isCertificateFailure(_ error: URLError, host: String?) -> Bool {
        SubsonicError.isCertificate(error) || (error.code == .cancelled && trust.rejection(for: host) != nil)
    }

    /// Octo's own page answers with an "octo" key; only on the home network, usually.
    private static func probeOcto(_ client: SubsonicClient) async -> Bool {
        let url = client.baseURL.appendingPathComponent("api/admin/status")
        var request = URLRequest(url: url, timeoutInterval: 5)
        for (name, value) in client.headers { request.setValue(value, forHTTPHeaderField: name) }
        guard let (data, response) = try? await ServerTrust.shared.session.data(for: request),
              (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? false,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return false }
        return json["octo"] != nil
    }

    private func loadCertificate(for id: String) {
        guard let data = Keychain.readData(for: Self.certificateAccount(id)) else { return }
        try? trust.useClientCertificate(data, password: Keychain.read(for: Self.certificatePasswordAccount(id)) ?? "")
    }

    /// Puts the client certificate of the server in use back, so a failed or side try never
    /// disturbs it.
    private func restoreSecurity() {
        if let active, client != nil, active.hasClientCertificate {
            loadCertificate(for: active.id)
        } else {
            try? trust.useClientCertificate(nil, password: "")
        }
    }

    /// A password serves token and legacy sign-in; a key serves only a key.
    private static func sameKind(_ a: AuthMode, _ b: AuthMode) -> Bool {
        (a == .apiKey) == (b == .apiKey)
    }

    /// The headers worth keeping: named, with a value, each name once (the last one typed wins).
    /// A saved header left without a value keeps its saved one.
    static func cleanHeaders(_ typed: [(name: String, value: String?)], saved: [String: String]) -> [String: String] {
        var out: [String: String] = [:]
        var order: [String: String] = [:]
        for header in typed {
            let name = header.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let savedValue = saved.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
            let value = (header.value ?? savedValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard HeaderRules.isValidName(name), !value.isEmpty, HeaderRules.isValidValue(value) else { continue }
            if let earlier = order[name.lowercased()] { out[earlier] = nil }
            order[name.lowercased()] = name
            out[name] = value
        }
        return out
    }

    // MARK: Storage

    private func load() {
        if let data = prefs.data(forKey: Self.serversKey),
           let kept = try? JSONDecoder().decode([StoredServer].self, from: data) {
            servers = kept
        }
        activeId = prefs.string(forKey: Self.activeKey)
        migrateFirstSignIn()
    }

    /// The first builds kept one server under single keys; it becomes the first kept server.
    private func migrateFirstSignIn() {
        guard servers.isEmpty, let text = prefs.string(forKey: "server.address"), let address = URL(string: text),
              let username = prefs.string(forKey: "server.username")
        else { return }
        let oldAccount = "\(username)@\(ServerAddress.shown(address))"
        let server = StoredServer(id: freshServerId(username: username, address: ServerAddress.written(address), taken: []),
                                  address: address, username: username,
                                  mode: prefs.bool(forKey: "server.legacyPassword") ? .legacyPassword : .token)
        if let secret = Keychain.read(for: oldAccount) {
            Keychain.save(secret, for: Self.secretAccount(server.id))
            Keychain.delete(for: oldAccount)
        }
        servers = [server]
        activeId = server.id
        for key in ["server.address", "server.username", "server.legacyPassword"] { prefs.removeObject(forKey: key) }
        save()
    }

    private func save() {
        prefs.set(try? JSONEncoder().encode(servers), forKey: Self.serversKey)
        prefs.set(activeId, forKey: Self.activeKey)
    }

    private func forgetSecrets(_ id: String) {
        for account in [Self.secretAccount(id), Self.headersAccount(id), Self.certificateAccount(id), Self.certificatePasswordAccount(id)] {
            Keychain.delete(for: account)
        }
    }

    private static func secretAccount(_ id: String) -> String { "server.\(id).secret" }
    private static func headersAccount(_ id: String) -> String { "server.\(id).headers" }
    private static func certificateAccount(_ id: String) -> String { "server.\(id).certificate" }
    private static func certificatePasswordAccount(_ id: String) -> String { "server.\(id).certificate.password" }
    private static func folderKey(_ id: String) -> String { "server.folder@\(id)" }

    private static func headers(for id: String) -> [String: String] {
        Keychain.readData(for: headersAccount(id)).flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
    }

    /// This install, as the server knows it: an id made once, and the phone's name.
    static func device() -> DeviceIdentity {
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

extension SignInWords {
    static let gone = "That server isn't in your list any more."
}
