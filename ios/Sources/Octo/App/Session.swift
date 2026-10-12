import Foundation
import Observation
import OctoKit
import UIKit

/// The signed-in server: who we are on it, what it can do, and the client every screen asks.
@MainActor
@Observable
final class Session {
    private(set) var client: SubsonicClient?
    private(set) var profile: ServerProfile?
    var quality: StreamQuality {
        didSet { Self.store(quality) }
    }

    var isOcto: Bool { profile?.isOcto ?? false }
    var serverName: String { client.map { ServerAddress.shown($0.baseURL) } ?? "" }

    private static let addressKey = "server.address"
    private static let usernameKey = "server.username"
    private static let legacyKey = "server.legacyPassword"
    private static let deviceKey = "device.id"
    private static let qualityKey = "stream.quality"

    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    init() {
        quality = Self.storedQuality()
        restore()
    }

    /// Signs in to a typed address. A server that cannot check tokens (error 41) is asked again
    /// with the plain password, but only over https or on the home network.
    func signIn(address typed: String, username: String, password: String) async throws {
        guard let address = ServerAddress.parse(typed) else {
            throw SignInError.badAddress
        }
        var client = SubsonicClient(baseURL: address, credentials: Credentials(username: username, password: password),
                                    device: Self.device(), appVersion: Self.appVersion)
        let profile: ServerProfile
        do {
            profile = try await client.profile()
        } catch OctoError.authUnsupported(41, _) where address.scheme == "https" || ServerAddress.isPrivate(address) {
            client = client.with(Credentials(username: username, password: password, mode: .legacyPassword))
            profile = try await client.profile()
        }
        let defaults = UserDefaults.standard
        defaults.set(address.absoluteString, forKey: Self.addressKey)
        defaults.set(username, forKey: Self.usernameKey)
        defaults.set(client.credentials.mode == .legacyPassword, forKey: Self.legacyKey)
        Keychain.save(password, for: Self.account(address, username))
        self.client = client
        self.profile = profile
    }

    func signOut() {
        if let client {
            Keychain.delete(for: Self.account(client.baseURL, client.credentials.username))
        }
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: Self.addressKey)
        defaults.removeObject(forKey: Self.usernameKey)
        defaults.removeObject(forKey: Self.legacyKey)
        client = nil
        profile = nil
    }

    /// Back to the server signed in last time, at once; what it can do is asked for after.
    private func restore() {
        let defaults = UserDefaults.standard
        guard let text = defaults.string(forKey: Self.addressKey), let address = URL(string: text),
              let username = defaults.string(forKey: Self.usernameKey),
              let password = Keychain.read(for: Self.account(address, username))
        else { return }
        let mode: AuthMode = defaults.bool(forKey: Self.legacyKey) ? .legacyPassword : .token
        let client = SubsonicClient(baseURL: address, credentials: Credentials(username: username, password: password, mode: mode),
                                    device: Self.device(), appVersion: Self.appVersion)
        self.client = client
        Task { self.profile = try? await client.profile() }
    }

    private static func account(_ address: URL, _ username: String) -> String {
        "\(username)@\(ServerAddress.shown(address))"
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

enum SignInError: LocalizedError {
    case badAddress

    var errorDescription: String? {
        switch self {
        case .badAddress: "That doesn't look like a server address."
        }
    }
}
