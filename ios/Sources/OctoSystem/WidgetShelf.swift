import Foundation
import ShareInbox

/// What the app leaves for the Now playing widget, in the folder the two share: the song, its
/// artist, whether it plays, and the song's cover as a small picture.
public struct WidgetShelf: Sendable {
    /// What one write left.
    public struct Shelved: Codable, Sendable, Equatable {
        /// Nil while nothing is loaded.
        public var playback: WidgetPlayback?
        /// The cover's file name in the folder, when the song has one.
        public var cover: String?
        /// Seconds since 1970 when it was written.
        public var writtenAt: Double

        public init(playback: WidgetPlayback?, cover: String?, writtenAt: Double) {
            self.playback = playback
            self.cover = cover
            self.writtenAt = writtenAt
        }
    }

    /// The cover that goes with a write.
    public enum Cover: Sendable {
        /// The cover already on the shelf stays.
        case keep
        /// No cover.
        case none
        /// A new picture, as image file bytes.
        case new(Data)
    }

    /// The most a cover is across, in pixels.
    public static let coverPixels = 300

    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    var noteURL: URL { directory.appendingPathComponent("now-playing.json") }

    /// What the shelf holds, or nil when nothing was ever written.
    public func read() -> Shelved? {
        guard let data = try? Data(contentsOf: noteURL) else { return nil }
        return try? JSONDecoder().decode(Shelved.self, from: data)
    }

    /// Where the shelf's cover is, while it has one.
    public func coverURL(_ shelved: Shelved) -> URL? {
        guard let name = shelved.cover else { return nil }
        let url = directory.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Puts the music as it is on the shelf. A new cover gets a new file name, so a widget never
    /// shows an old picture under a new song; covers no longer named are taken away.
    @discardableResult
    public func write(_ playback: WidgetPlayback?, cover: Cover, now: Date = Date()) throws -> Shelved {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var name: String?
        switch cover {
        case .keep: name = read()?.cover
        case .none: name = nil
        case .new(let bytes):
            let fresh = "cover-\(UUID().uuidString).jpg"
            try bytes.write(to: directory.appendingPathComponent(fresh), options: .atomic)
            name = fresh
        }
        let shelved = Shelved(playback: playback, cover: name, writtenAt: now.timeIntervalSince1970)
        try JSONEncoder().encode(shelved).write(to: noteURL, options: .atomic)
        let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        for file in files where file.hasPrefix("cover-") && file != name {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(file))
        }
        return shelved
    }

    #if os(iOS) || os(macOS)
    /// The shelf in the folder the app and its widgets share, or nil when this build has none.
    public static func shared(bundle: Bundle = .main) -> WidgetShelf? {
        OctoAppGroup.container(bundle: bundle).map { WidgetShelf(directory: $0.appendingPathComponent("Widgets", isDirectory: true)) }
    }
    #endif
}

/// What a provisioning profile grants, read from the property list inside it.
public enum ProvisioningProfile {
    /// The entitlements a profile's bytes grant (those set to false left out), or none when
    /// there is no profile.
    public static func grants(_ data: Data?) -> Set<String> {
        guard let data, let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex),
              let plist = try? PropertyListSerialization.propertyList(from: data[start.lowerBound..<end.upperBound], format: nil) as? [String: Any],
              let entitlements = plist["Entitlements"] as? [String: Any]
        else { return [] }
        return Set(entitlements.compactMap { key, value in (value as? Bool) == false ? nil : key })
    }

    /// The entitlements this build's own profile grants. A build from TestFlight or the App Store
    /// carries no profile: it was signed with every entitlement the app asks for.
    public static func grants(bundle: Bundle = .main) -> Set<String> {
        guard let url = bundle.url(forResource: "embedded", withExtension: "mobileprovision") else { return distributed }
        return grants(try? Data(contentsOf: url))
    }

    /// The entitlements a TestFlight or App Store build is signed with.
    public static let distributed: Set<String> = ["com.apple.developer.siri", "com.apple.security.application-groups"]
}
