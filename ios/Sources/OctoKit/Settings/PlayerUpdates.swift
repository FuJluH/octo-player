import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The player apps that look for their own releases on the public Octo repository. Each has its
/// own tags there, and never the server's (those are dated, like 2026.09.23, or start with "v").
public enum PlayerApp: CaseIterable, Sendable {
    case desktop, android, ios

    public var tagPrefix: String {
        switch self {
        case .desktop: "desktop-v"
        case .android: "android-v"
        case .ios: "ios-v"
        }
    }

    public var product: String {
        switch self {
        case .desktop: "desktop"
        case .android: "android"
        case .ios: "ios"
        }
    }
}

/// A player version as its tag writes it: 1.2.0, or 1.3.0-beta.1 for an early version. Ordered the
/// way semantic versioning orders them, so an early version comes before the release of the same
/// numbers.
public struct PlayerVersion: Comparable, Hashable, Sendable, CustomStringConvertible {
    public var major: Int
    public var minor: Int
    public var patch: Int
    public var early: [String]

    public init(_ major: Int, _ minor: Int, _ patch: Int, early: [String] = []) {
        self.major = major
        self.minor = minor
        self.patch = patch
        self.early = early
    }

    public var isEarly: Bool { !early.isEmpty }

    public var description: String { "\(major).\(minor).\(patch)" + (early.isEmpty ? "" : "-" + early.joined(separator: ".")) }

    public static func == (a: PlayerVersion, b: PlayerVersion) -> Bool { order(a, b) == 0 }

    public static func < (a: PlayerVersion, b: PlayerVersion) -> Bool { order(a, b) < 0 }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(major)
        hasher.combine(minor)
        hasher.combine(patch)
        hasher.combine(early)
    }

    static func order(_ a: PlayerVersion, _ b: PlayerVersion) -> Int {
        for (x, y) in [(a.major, b.major), (a.minor, b.minor), (a.patch, b.patch)] where x != y { return x < y ? -1 : 1 }
        // A release is newer than any early version of the same numbers.
        if a.early.isEmpty && b.early.isEmpty { return 0 }
        if a.early.isEmpty { return 1 }
        if b.early.isEmpty { return -1 }
        for (x, y) in zip(a.early, b.early) {
            let order: Int
            switch (Int(x), Int(y)) {
            case let (m?, n?): order = m == n ? 0 : (m < n ? -1 : 1)
            case (.some, nil): order = -1
            case (nil, .some): order = 1
            case (nil, nil): order = x == y ? 0 : (x < y ? -1 : 1)
            }
            if order != 0 { return order }
        }
        return a.early.count == b.early.count ? 0 : (a.early.count < b.early.count ? -1 : 1)
    }

    /// The version in some text, or nil when it is not one: a build from source, or a test build.
    public static func parse(_ text: String?) -> PlayerVersion? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        let main: Substring
        var early: [String] = []
        if let dash = text.firstIndex(of: "-") {
            main = text[..<dash]
            let rest = text[text.index(after: dash)...]
            early = rest.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
            let allowed = Set("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-")
            guard !early.isEmpty, early.allSatisfy({ !$0.isEmpty && $0.allSatisfy(allowed.contains) }) else { return nil }
        } else {
            main = Substring(text)
        }
        let numbers = main.split(separator: ".", omittingEmptySubsequences: false)
        guard numbers.count == 3 else { return nil }
        var values: [Int] = []
        for number in numbers {
            guard (1...9).contains(number.count), number.allSatisfy(\.isASCII), number.allSatisfy(\.isNumber),
                  number == "0" || number.first != "0", let value = Int(number)
            else { return nil }
            values.append(value)
        }
        return PlayerVersion(values[0], values[1], values[2], early: early)
    }
}

/// The version a tag names for this app, or nil for any other tag.
public func versionOfTag(_ tag: String, _ app: PlayerApp) -> PlayerVersion? {
    tag.hasPrefix(app.tagPrefix) ? PlayerVersion.parse(String(tag.dropFirst(app.tagPrefix.count))) : nil
}

/// A release on the public Octo repository, as GitHub's API lists it. Only the parts read here.
public struct GitHubRelease: Decodable, Sendable, Equatable {
    public var tag: String
    public var name: String?
    public var draft: Bool
    public var prerelease: Bool
    public var body: String?
    public var page: String?
    public var assets: [GitHubAsset]

    public init(tag: String, draft: Bool = false, prerelease: Bool = false, assets: [GitHubAsset] = [], page: String? = nil) {
        self.tag = tag
        self.draft = draft
        self.prerelease = prerelease
        self.assets = assets
        self.page = page
    }

    enum CodingKeys: String, CodingKey {
        case tag = "tag_name", name, draft, prerelease, body, page = "html_url", assets
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tag = try c.decode(String.self, forKey: .tag)
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? nil
        draft = c.value(.draft, or: false)
        prerelease = c.value(.prerelease, or: false)
        body = (try? c.decodeIfPresent(String.self, forKey: .body)) ?? nil
        page = (try? c.decodeIfPresent(String.self, forKey: .page)) ?? nil
        assets = c.value(.assets, or: [])
    }

    public func asset(_ name: String) -> GitHubAsset? { assets.first { $0.name == name } }
}

public struct GitHubAsset: Decodable, Sendable, Equatable {
    public var name: String
    public var size: Int64
    public var url: String

    public init(name: String, size: Int64 = 0, url: String) {
        self.name = name
        self.size = size
        self.url = url
    }

    enum CodingKeys: String, CodingKey { case name, size, url = "browser_download_url" }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        size = c.value(.size, or: 0)
        url = try c.decode(String.self, forKey: .url)
    }
}

/// The releases in an answer from GitHub's list of releases, or nil when it is not one.
public func parseReleases(_ data: Data) -> [GitHubRelease]? { try? JSONDecoder().decode([GitHubRelease].self, from: data) }

/// The newest release of this app newer than the one running, or nil when there is none. Drafts
/// never count, and early versions only when the listener asked to try them; GitHub's flag and the
/// tag must agree a release is final. A running early version is still offered its release.
public func newestUpdate(_ releases: [GitHubRelease], app: PlayerApp, running: PlayerVersion, early: Bool) -> (release: GitHubRelease, version: PlayerVersion)? {
    releases
        .filter { !$0.draft }
        .compactMap { release in versionOfTag(release.tag, app).map { (release: release, version: $0) } }
        .filter { early || (!$0.release.prerelease && !$0.version.isEarly) }
        .filter { $0.version > running }
        .max { $0.version < $1.version }
}

/// Every player release carries update.json, naming the version and each file with its size and
/// SHA-256, and update.json.sig, an Ed25519 signature over update.json's exact bytes (base64).
public struct UpdateManifest: Decodable, Sendable, Equatable {
    public var format: Int
    public var product: String
    public var version: String
    public var tag: String
    public var notes: String
    public var assets: [ManifestAsset]

    enum CodingKeys: String, CodingKey { case format, product, version, tag, notes, assets }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        format = try c.decode(Int.self, forKey: .format)
        product = try c.decode(String.self, forKey: .product)
        version = try c.decode(String.self, forKey: .version)
        tag = try c.decode(String.self, forKey: .tag)
        notes = c.value(.notes, or: "")
        assets = c.value(.assets, or: [])
    }
}

/// One file of a release. `os` is windows, macos, linux, android or ios; `kind` the file's type.
public struct ManifestAsset: Decodable, Sendable, Equatable {
    public var name: String
    public var sha256: String
    public var size: Int64
    public var os: String
    public var arch: String
    public var kind: String

    enum CodingKeys: String, CodingKey { case name, sha256, size, os, arch, kind }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        sha256 = try c.decode(String.self, forKey: .sha256)
        size = try c.decode(Int64.self, forKey: .size)
        os = c.value(.os, or: "")
        arch = c.value(.arch, or: "")
        kind = c.value(.kind, or: "")
    }
}

/// Why an update was turned down. Said quietly: nothing is installed.
public struct UpdateRefused: Error, Equatable {
    public var reason: String
    public init(_ reason: String) { self.reason = reason }
}

public enum UpdateFiles {
    public static let manifestName = "update.json"
    public static let signatureName = "update.json.sig"
    public static let manifestFormat = 1
    public static let manifestLimit = 256 * 1024
    public static let signatureLimit = 4 * 1024

    /// The keys this build trusts: one base64 Ed25519 public key a line, "#" starting a comment.
    public static let trustedKeysText = """
    # The keys update manifests are signed with. Each line is one base64 Ed25519 public key.
    M/nLIDZFkukIYfrJGWK+cPmo/asGBkr+SdHPAWOSPp0=
    """

    /// The keys in a list of them, refusing anything that is not a 32-byte key.
    public static func parseKeys(_ text: String) throws -> [Data] {
        try text.split(separator: "\n", omittingEmptySubsequences: false).compactMap { line -> Data? in
            let clean = (line.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first ?? "")
                .trimmingCharacters(in: .whitespaces)
            if clean.isEmpty { return nil }
            guard let key = Data(base64Encoded: clean), key.count == 32 else { throw UpdateRefused("not an Ed25519 public key: \(clean)") }
            return key
        }
    }

    public static var trustedKeys: [Data] { (try? parseKeys(trustedKeysText)) ?? [] }

    /// The manifest in these bytes, once the signature is one of the trusted keys' and the
    /// manifest is for this app's release under this tag. The manifest is not read at all until
    /// the signature holds. `verify` checks an Ed25519 signature (key, message, signature).
    public static func verifiedManifest(_ bytes: Data, signature: String, keys: [Data], app: PlayerApp, tag: String,
                                        verify: (Data, Data, Data) -> Bool) throws -> UpdateManifest {
        if keys.isEmpty { throw UpdateRefused("this build has no key to check updates with") }
        let cleaned = signature.components(separatedBy: .whitespacesAndNewlines).joined()
        guard let raw = Data(base64Encoded: cleaned) else { throw UpdateRefused("the signature is not readable") }
        guard raw.count == 64, keys.contains(where: { $0.count == 32 && verify($0, bytes, raw) }) else {
            throw UpdateRefused("the signature does not match")
        }
        guard let manifest = try? JSONDecoder().decode(UpdateManifest.self, from: bytes) else { throw UpdateRefused("the manifest is not readable") }
        if manifest.format != manifestFormat { throw UpdateRefused("the manifest is a newer kind") }
        if manifest.product != app.product { throw UpdateRefused("the manifest is for another app") }
        if manifest.tag != tag { throw UpdateRefused("the manifest is for another release") }
        guard let named = versionOfTag(tag, app), PlayerVersion.parse(manifest.version) == named else {
            throw UpdateRefused("the manifest names another version")
        }
        let hex = Set("0123456789abcdef")
        for asset in manifest.assets {
            let name = asset.name.trimmingCharacters(in: .whitespaces)
            if asset.sha256.count != 64 || !asset.sha256.allSatisfy(hex.contains) || asset.size <= 0 || name.isEmpty
                || asset.name.contains("/") || asset.name.contains("\\") {
                throw UpdateRefused("the manifest lists a file badly")
            }
        }
        return manifest
    }
}

/// When the checks run: a while after start, so opening the app stays quick, then every six
/// hours, or later when GitHub asked to come back later.
public enum UpdateTiming {
    public static let firstCheckDelayMs: Int64 = 90_000
    public static let intervalMs: Int64 = 6 * 60 * 60 * 1000

    public static func nextWait(now: Int64, retryAt: Int64?) -> Int64 { max(intervalMs, (retryAt ?? 0) - now) }
}

/// What a check found.
public enum UpdateCheck: Equatable, Sendable {
    /// Nothing newer than the version running.
    case upToDate
    /// A newer version, its manifest checked: where to get it, and its notes.
    case available(version: PlayerVersion, tag: String, notes: String, page: String?)
    /// A newer version with nothing for this system.
    case noInstaller(version: PlayerVersion)
    /// The release failed a check.
    case refused(reason: String)
    /// GitHub could not be reached, or asked to wait until `retryAt` (ms).
    case unavailable(reason: String, retryAt: Int64?)
}

/// GitHub's answer to the list of releases, made sense of: the releases, or a wait. `cached` is
/// the list kept from before, used for a 304.
public enum ReleaseFeedAnswer: Equatable, Sendable {
    case releases([GitHubRelease], keep: (etag: String, body: Data)?)
    case wait(reason: String, retryAt: Int64?)

    public static func == (a: ReleaseFeedAnswer, b: ReleaseFeedAnswer) -> Bool {
        switch (a, b) {
        case let (.releases(x, k1), .releases(y, k2)): x == y && k1?.etag == k2?.etag
        case let (.wait(r1, t1), .wait(r2, t2)): r1 == r2 && t1 == t2
        default: false
        }
    }

    public static func of(status: Int?, headers: [String: String], body: Data, cached: Data?, nowMs: Int64) -> ReleaseFeedAnswer {
        func header(_ name: String) -> String? {
            headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value.trimmingCharacters(in: .whitespaces)
        }
        guard let status else { return .wait(reason: "GitHub could not be reached", retryAt: nil) }
        if status == 304, let cached {
            guard let releases = parseReleases(cached) else { return .wait(reason: "GitHub's answer was not readable", retryAt: nil) }
            return .releases(releases, keep: nil)
        }
        if (200..<300).contains(status) {
            guard let releases = parseReleases(body) else { return .wait(reason: "GitHub's answer was not readable", retryAt: nil) }
            return .releases(releases, keep: header("ETag").map { ($0, body) })
        }
        if status == 403 || status == 429 {
            let retryAfter = header("Retry-After").flatMap { Int64($0) }.map { nowMs + $0 * 1000 }
            let reset = header("X-RateLimit-Remaining") == "0" ? header("X-RateLimit-Reset").flatMap { Int64($0) }.map { $0 * 1000 } : nil
            return .wait(reason: "GitHub asked Octo to wait", retryAt: retryAfter ?? reset)
        }
        return .wait(reason: "GitHub answered \(status)", retryAt: nil)
    }
}

/// The public repository the players' releases are published on.
public let octoRepository = "winters27/octo"

/// The address of GitHub's list of the repository's releases.
public func releasesURL(api: URL = URL(string: "https://api.github.com/")!, repository: String = octoRepository) -> URL {
    var parts = URLComponents(url: api.appendingPathComponent("repos/\(repository)/releases"), resolvingAgainstBaseURL: false)!
    parts.queryItems = [URLQueryItem(name: "per_page", value: "100")]
    return parts.url!
}
