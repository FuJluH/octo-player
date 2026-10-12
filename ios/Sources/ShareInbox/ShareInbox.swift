import Foundation

/// A list shared to Octo from another app, as the share extension leaves it for the app: the
/// text itself (a list, or a link to one), or a file with its name and type.
public struct ShareDrop: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable {
        case text, file
    }

    public var kind: Kind
    /// The shared text, for a text share.
    public var text: String?
    /// The share's subject for text, or the file's name as the other app gave it.
    public var name: String?
    /// The file's type, as a MIME type.
    public var type: String?
    /// The file was over the limit, so its bytes were not kept.
    public var tooBig: Bool

    public init(kind: Kind, text: String? = nil, name: String? = nil, type: String? = nil, tooBig: Bool = false) {
        self.kind = kind
        self.text = text
        self.name = name
        self.type = type
        self.tooBig = tooBig
    }

    public static func text(_ text: String, subject: String?) -> ShareDrop {
        ShareDrop(kind: .text, text: text, name: subject)
    }

    public static func file(name: String?, type: String?, tooBig: Bool = false) -> ShareDrop {
        ShareDrop(kind: .file, name: name, type: type, tooBig: tooBig)
    }
}

/// Where the share extension leaves one shared list for the app, in the folder the two share.
/// A newer share replaces one still waiting, and the app takes each one once.
public struct ShareInbox: Sendable {
    /// The most of a file Import takes: 64 MB.
    public static let maxBytes = 64 * 1024 * 1024

    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    var noteURL: URL { directory.appendingPathComponent("shared-list.json") }
    var bytesURL: URL { directory.appendingPathComponent("shared-list.data") }

    /// Whether a share is waiting.
    public var waiting: Bool { FileManager.default.fileExists(atPath: noteURL.path) }

    /// Leaves a share for the app, replacing one still waiting. The bytes go first, so the app
    /// never finds a note without them.
    public func put(_ drop: ShareDrop, bytes: Data? = nil) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: noteURL)
        try? FileManager.default.removeItem(at: bytesURL)
        if let bytes { try bytes.write(to: bytesURL, options: .atomic) }
        try JSONEncoder().encode(drop).write(to: noteURL, options: .atomic)
    }

    /// The share waiting, once: reading it takes it out of the inbox.
    public func take() -> (drop: ShareDrop, bytes: Data?)? {
        guard let note = try? Data(contentsOf: noteURL) else { return nil }
        let bytes = try? Data(contentsOf: bytesURL)
        try? FileManager.default.removeItem(at: noteURL)
        try? FileManager.default.removeItem(at: bytesURL)
        guard let drop = try? JSONDecoder().decode(ShareDrop.self, from: note) else { return nil }
        return (drop, bytes)
    }

    /// Reads a file up to the limit, 64 KiB at a time, stopping as soon as it goes past.
    /// Answers nil when it cannot be read, and `tooBig` when it is over the limit.
    public static func read(_ url: URL, limit: Int = maxBytes) -> (bytes: Data, tooBig: Bool)? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var data = Data()
        do {
            while let chunk = try handle.read(upToCount: 64 * 1024), !chunk.isEmpty {
                data.append(chunk)
                if data.count > limit { return (Data(), true) }
            }
        } catch {
            return nil
        }
        return (data, false)
    }
}

/// The App Group the app and its share extension share, for the share inbox.
public enum OctoAppGroup {
    /// The group as the app asks for it.
    public static let name = "group.app.winters.octo"
    /// The prefix xtool's signing gives every identifier: "XTL-" and part of the signing
    /// identity, then the identifier asked for.
    static let signedPrefix = "XTL-"

    /// The group this build was signed with: the one its provisioning profile names, else the
    /// one its bundle id implies, else the group as asked for.
    public static func signed(profile: Data?, bundleID: String?) -> String {
        if let profile, let group = fromProfile(profile) { return group }
        return fromBundleID(bundleID)
    }

    /// The first app group a provisioning profile grants. The profile is signed data with the
    /// property list inside it.
    static func fromProfile(_ data: Data) -> String? {
        guard let start = data.range(of: Data("<?xml".utf8)), let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex),
              let plist = try? PropertyListSerialization.propertyList(from: data[start.lowerBound..<end.upperBound], format: nil) as? [String: Any],
              let entitlements = plist["Entitlements"] as? [String: Any],
              let groups = entitlements["com.apple.security.application-groups"] as? [String]
        else { return nil }
        return groups.first { $0.hasSuffix(String(name.dropFirst("group.".count))) } ?? groups.first
    }

    /// The group a signed bundle id implies: "XTL-1A2B3C4D.app.winters.octo" (or its share
    /// extension, one part longer) means "group.XTL-1A2B3C4D.app.winters.octo".
    static func fromBundleID(_ bundleID: String?) -> String {
        guard let bundleID, bundleID.hasPrefix(signedPrefix), let prefix = bundleID.split(separator: ".").first else { return name }
        return "group.\(prefix).\(name.dropFirst("group.".count))"
    }

    #if os(iOS) || os(macOS)
    /// The shared folder for this build, or nil when it was signed without the group.
    public static func container(bundle: Bundle = .main) -> URL? {
        let profile = bundle.url(forResource: "embedded", withExtension: "mobileprovision").flatMap { try? Data(contentsOf: $0) }
        let group = signed(profile: profile, bundleID: bundle.bundleIdentifier)
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
    }

    /// The share inbox in the shared folder, or nil without one.
    public static func inbox(bundle: Bundle = .main) -> ShareInbox? {
        container(bundle: bundle).map { ShareInbox(directory: $0.appendingPathComponent("ShareInbox", isDirectory: true)) }
    }
    #endif
}
