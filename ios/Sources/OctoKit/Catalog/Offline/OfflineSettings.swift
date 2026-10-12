import Foundation

/// How much room recently played server songs may take on the phone, so they play again without
/// the network. Off keeps nothing. Stored by its raw name.
public enum CacheSize: String, Sendable, Codable, CaseIterable {
    case off = "Off"
    case gb1 = "Gb1"
    case gb2 = "Gb2"
    case gb5 = "Gb5"
    case gb10 = "Gb10"

    /// The room in bytes, in binary gigabytes.
    public var bytes: Int64 {
        switch self {
        case .off: 0
        case .gb1: 1 << 30
        case .gb2: 2 << 30
        case .gb5: 5 << 30
        case .gb10: 10 << 30
        }
    }

    /// "Off", or the size like "2 GB".
    public var label: String { self == .off ? "Off" : "\(bytes >> 30) GB" }
}

/// The range each "songs ahead" count can be set to.
public let prefetchRange: ClosedRange<Int> = 0...10

/// A "songs ahead" count held within its range.
public func prefetchClamped(_ count: Int) -> Int { min(max(count, prefetchRange.lowerBound), prefetchRange.upperBound) }

/// What to keep on the phone for playing without a connection. The defaults are what a new
/// install gets. Stored as JSON under these field names; a missing or unknown value reads as
/// its default.
public struct OfflinePrefs: Sendable, Hashable, Codable {
    public var cacheSize: CacheSize
    /// How many songs ahead in the queue to fetch while one plays, on Wi-Fi and on mobile data.
    public var prefetchWifi: Int
    public var prefetchMobile: Int
    /// Downloads come as the server's file unless a smaller MP3 is chosen.
    public var downloadQuality: StreamQuality
    public var wifiOnly: Bool
    /// Stream on Wi-Fi even when a downloaded copy is on the phone.
    public var streamOnWifi: Bool
    public var keepLiked: Bool
    /// Playlists whose songs are kept downloaded, by id.
    public var keptPlaylists: Set<String>

    public init(cacheSize: CacheSize = .gb2, prefetchWifi: Int = 3, prefetchMobile: Int = 1,
                downloadQuality: StreamQuality = .original, wifiOnly: Bool = true, streamOnWifi: Bool = false,
                keepLiked: Bool = false, keptPlaylists: Set<String> = []) {
        self.cacheSize = cacheSize
        self.prefetchWifi = prefetchWifi
        self.prefetchMobile = prefetchMobile
        self.downloadQuality = downloadQuality
        self.wifiOnly = wifiOnly
        self.streamOnWifi = streamOnWifi
        self.keepLiked = keepLiked
        self.keptPlaylists = keptPlaylists
    }

    /// Keeps or stops keeping a playlist's songs downloaded.
    public mutating func setPlaylistKept(_ id: String, _ kept: Bool) {
        if kept { keptPlaylists.insert(id) } else { keptPlaylists.remove(id) }
    }

    /// Stops every rule at once, for "Remove all".
    public mutating func clearRules() {
        keepLiked = false
        keptPlaylists = []
    }

    /// The settings from a backup, put back in one go. Its kept playlists join the ones already
    /// kept here.
    public func restoring(_ backup: OfflinePrefs) -> OfflinePrefs {
        OfflinePrefs(cacheSize: backup.cacheSize, prefetchWifi: prefetchClamped(backup.prefetchWifi),
                     prefetchMobile: prefetchClamped(backup.prefetchMobile), downloadQuality: backup.downloadQuality,
                     wifiOnly: backup.wifiOnly, streamOnWifi: backup.streamOnWifi, keepLiked: backup.keepLiked,
                     keptPlaylists: keptPlaylists.union(backup.keptPlaylists))
    }

    enum CodingKeys: String, CodingKey {
        case cacheSize, prefetchWifi, prefetchMobile, downloadQuality, wifiOnly, streamOnWifi, keepLiked, keptPlaylists
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = OfflinePrefs()
        let size: String? = try? c.decodeIfPresent(String.self, forKey: .cacheSize)
        cacheSize = size.flatMap(CacheSize.init(rawValue:)) ?? defaults.cacheSize
        let wifi: Int? = try? c.decodeIfPresent(Int.self, forKey: .prefetchWifi)
        prefetchWifi = prefetchClamped(wifi ?? defaults.prefetchWifi)
        let mobile: Int? = try? c.decodeIfPresent(Int.self, forKey: .prefetchMobile)
        prefetchMobile = prefetchClamped(mobile ?? defaults.prefetchMobile)
        let quality: String? = try? c.decodeIfPresent(String.self, forKey: .downloadQuality)
        downloadQuality = StreamQuality.choices.first { offlineQualityName($0) == quality } ?? defaults.downloadQuality
        let onlyWifi: Bool? = try? c.decodeIfPresent(Bool.self, forKey: .wifiOnly)
        wifiOnly = onlyWifi ?? defaults.wifiOnly
        let streamWifi: Bool? = try? c.decodeIfPresent(Bool.self, forKey: .streamOnWifi)
        streamOnWifi = streamWifi ?? defaults.streamOnWifi
        let liked: Bool? = try? c.decodeIfPresent(Bool.self, forKey: .keepLiked)
        keepLiked = liked ?? defaults.keepLiked
        let playlists: [String]? = try? c.decodeIfPresent([String].self, forKey: .keptPlaylists)
        keptPlaylists = Set(playlists ?? [])
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(cacheSize.rawValue, forKey: .cacheSize)
        try c.encode(prefetchWifi, forKey: .prefetchWifi)
        try c.encode(prefetchMobile, forKey: .prefetchMobile)
        try c.encode(offlineQualityName(downloadQuality), forKey: .downloadQuality)
        try c.encode(wifiOnly, forKey: .wifiOnly)
        try c.encode(streamOnWifi, forKey: .streamOnWifi)
        try c.encode(keepLiked, forKey: .keepLiked)
        try c.encode(keptPlaylists.sorted { $0.utf16.lexicographicallyPrecedes($1.utf16) }, forKey: .keptPlaylists)
    }
}

/// A stream size as it is stored: "Original", or "Kbps" and its number, like "Kbps320".
private func offlineQualityName(_ quality: StreamQuality) -> String {
    switch quality {
    case .original: "Original"
    case .mp3(let kbps): "Kbps\(kbps)"
    }
}
