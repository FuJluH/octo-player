import CryptoKit
import Foundation
import Observation
import OctoKit

/// Looks for a newer Octo for iPhone on the public repository a while after start and every six
/// hours, and when asked. A release counts only through its signed manifest. The phone cannot
/// install it itself: Octo is put on an iPhone from a computer, so a found update says where it
/// is, and goes in the way Octo first did.
@MainActor
@Observable
final class AppUpdates {
    static let shared = AppUpdates()

    /// What the About page shows of the updater.
    struct State: Equatable {
        /// Why the updater is off, or nil when it runs.
        var off: String?
        var checking = false
        /// A newer version, checked against its signed manifest.
        var ready: Found?
        /// The last check in a line, said quietly.
        var line: String?
    }

    struct Found: Equatable {
        var version: String
        var notes: String
        var page: URL?
    }

    private(set) var state: State

    @ObservationIgnored private let keys = UpdateFiles.trustedKeys
    @ObservationIgnored private let running = PlayerVersion.parse(Session.appVersion)
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private let session: URLSession = {
        // A session of its own: the system's certificates only, never a server's trusted ones
        // or its headers.
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 60
        return URLSession(configuration: config)
    }()

    /// Where the list of releases is asked for. A test build can point it elsewhere with the
    /// OCTO_UPDATES_API launch variable.
    private static var api: URL {
        #if DEBUG
        if let other = ProcessInfo.processInfo.environment["OCTO_UPDATES_API"], let url = URL(string: other) { return url }
        #endif
        return URL(string: "https://api.github.com/")!
    }

    private static var cacheFile: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("updates/releases.json")
    }

    private init() {
        #if DEBUG
        let debug = true
        #else
        let debug = false
        #endif
        state = State(off: Self.updaterOff(debug: debug, version: Session.appVersion, hasKeys: !UpdateFiles.trustedKeys.isEmpty))
    }

    /// Whether this build looks for updates, and if not, why not.
    static func updaterOff(debug: Bool, version: String, hasKeys: Bool) -> String? {
        if PlayerVersion.parse(version) == nil { return "This is a test build, so it doesn't update itself." }
        if !hasKeys { return "This build has no key to check updates with." }
        if debug { return "This is a test build, so it doesn't update itself." }
        return nil
    }

    /// The first check waits 90 seconds after start so opening the app stays quick; then every
    /// six hours, or longer when GitHub asked to come back later. Each turn checks only while
    /// "Check for updates automatically" is on.
    func start() {
        guard state.off == nil, loop == nil else { return }
        loop = Task {
            try? await Task.sleep(for: .milliseconds(UpdateTiming.firstCheckDelayMs))
            while !Task.isCancelled {
                let retryAt = AppSettings.shared.checkUpdatesAutomatically ? await check() : nil
                let now = Int64(Date().timeIntervalSince1970 * 1000)
                try? await Task.sleep(for: .milliseconds(UpdateTiming.nextWait(now: now, retryAt: retryAt)))
            }
        }
    }

    /// Checks now, whether or not automatic checks are on.
    func checkNow() {
        Task { await check() }
    }

    #if DEBUG
    /// Lets a test build show the update controls and check, for looking at them.
    func showControls() {
        state.off = nil
    }
    #endif

    /// One check. Answers when GitHub asked to come back, if it did.
    @discardableResult
    private func check() async -> Int64? {
        guard state.off == nil, let running, !state.checking else { return nil }
        state.checking = true
        let result = await find(running: running, early: AppSettings.shared.earlyVersions)
        switch result {
        case .available(let version, _, let notes, let page):
            state.ready = Found(version: version.description, notes: notes, page: page.flatMap(URL.init(string:)))
            state.line = nil
        case .upToDate:
            state.ready = nil
            state.line = "Octo is up to date."
        case .noInstaller(let version):
            state.line = "Octo \(version) is out, but not yet for phones."
        case .refused:
            state.ready = nil
            state.line = "An update didn't pass its safety check, so it was deleted. Octo will look again later."
        case .unavailable:
            state.line = "Couldn't check for updates just now. Octo will try again later."
        }
        state.checking = false
        if case .unavailable(_, let retryAt) = result { return retryAt }
        return nil
    }

    private func find(running: PlayerVersion, early: Bool) async -> UpdateCheck {
        let releases: [GitHubRelease]
        switch await feed() {
        case .wait(let reason, let retryAt): return .unavailable(reason: reason, retryAt: retryAt)
        case .releases(let list, _): releases = list
        }
        guard let candidate = newestUpdate(releases, app: .ios, running: running, early: early) else { return .upToDate }
        let tag = candidate.release.tag
        do {
            guard let manifestAsset = candidate.release.asset(UpdateFiles.manifestName) else {
                throw UpdateRefused("the release has no \(UpdateFiles.manifestName)")
            }
            guard let signatureAsset = candidate.release.asset(UpdateFiles.signatureName) else {
                throw UpdateRefused("the release has no \(UpdateFiles.signatureName)")
            }
            guard let bytes = try await fetchSmall(manifestAsset.url, limit: UpdateFiles.manifestLimit),
                  let signatureBytes = try await fetchSmall(signatureAsset.url, limit: UpdateFiles.signatureLimit)
            else { return .unavailable(reason: "the download stopped", retryAt: nil) }
            let manifest = try UpdateFiles.verifiedManifest(bytes, signature: String(decoding: signatureBytes, as: UTF8.self), keys: keys,
                                                            app: .ios, tag: tag, verify: Self.verify)
            guard let file = manifest.assets.first(where: { $0.os == "ios" && $0.kind == "ipa" }) else {
                return .noInstaller(version: candidate.version)
            }
            guard let listed = candidate.release.asset(file.name), listed.size == file.size else {
                throw UpdateRefused("the release is missing \(file.name)")
            }
            return .available(version: candidate.version, tag: tag, notes: manifest.notes, page: candidate.release.page)
        } catch let refused as UpdateRefused {
            return .refused(reason: refused.reason)
        } catch {
            return .unavailable(reason: "the download stopped", retryAt: nil)
        }
    }

    /// GitHub's list of releases, remembered with its ETag so an unchanged list costs nothing
    /// against the rate limit.
    private func feed() async -> ReleaseFeedAnswer {
        let cached = try? Data(contentsOf: Self.cacheFile)
        let saved = cached.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: String] }
        var request = URLRequest(url: releasesURL(api: Self.api))
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Octo/\(Session.appVersion) (ios)", forHTTPHeaderField: "User-Agent")
        if let etag = saved?["etag"] { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        guard let (data, response) = try? await session.data(for: request), let http = response as? HTTPURLResponse else {
            return ReleaseFeedAnswer.of(status: nil, headers: [:], body: Data(), cached: nil, nowMs: now)
        }
        var headers: [String: String] = [:]
        for (key, value) in http.allHeaderFields {
            if let key = key as? String, let value = value as? String { headers[key] = value }
        }
        let answer = ReleaseFeedAnswer.of(status: http.statusCode, headers: headers, body: data,
                                          cached: saved?["body"].map { Data($0.utf8) }, nowMs: now)
        if case .releases(_, let keep?) = answer {
            let record = ["etag": keep.etag, "body": String(decoding: keep.body, as: UTF8.self)]
            if let bytes = try? JSONSerialization.data(withJSONObject: record) {
                try? FileManager.default.createDirectory(at: Self.cacheFile.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? bytes.write(to: Self.cacheFile, options: .atomic)
            }
        }
        return answer
    }

    /// A small file (the manifest or its signature), refusing one too big. Nil when it could not
    /// be fetched.
    private func fetchSmall(_ address: String, limit: Int) async throws -> Data? {
        guard let url = URL(string: address), let (data, response) = try? await session.data(from: url),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode)
        else { return nil }
        if data.count > limit { throw UpdateRefused("a release file is far bigger than it should be") }
        return data
    }

    /// An Ed25519 signature check: a 32-byte key, a message and a 64-byte signature.
    nonisolated static func verify(_ key: Data, _ message: Data, _ signature: Data) -> Bool {
        guard let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: key) else { return false }
        return publicKey.isValidSignature(signature, for: message)
    }
}
