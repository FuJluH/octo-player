import Foundation

/// The one line under each category on the front page, saying how it is set now. Parts are
/// joined with a middle dot, and the most telling come first.
public enum SettingsSummaries {
    static let dot = " · "
    static let minuteMs: Int64 = 60_000
    static let hourMs = 60 * minuteMs
    static let dayMs = 24 * hourMs

    /// At most this many parts, so the line stays one line.
    static let mostParts = 3

    static func line(_ parts: String?...) -> String {
        parts.compactMap { $0 }.prefix(mostParts).joined(separator: dot)
    }

    /// "1 song", or "2,357 songs" with the thousands grouped.
    public static func count(_ n: Int, one: String, many: String) -> String {
        n == 1 ? "1 \(one)" : "\(grouped(n)) \(many)"
    }

    /// A number with its thousands grouped by the phone's own separator: "2,357", or "2.357" on a
    /// German phone.
    public static func grouped(_ n: Int, locale: Locale = .current) -> String {
        let separator = locale.groupingSeparator ?? ","
        let digits = String(n.magnitude)
        var out = ""
        for (i, ch) in digits.enumerated() {
            if i > 0, (digits.count - i) % 3 == 0 { out += separator }
            out.append(ch)
        }
        return (n < 0 ? "-" : "") + out
    }

    public static func playback(_ prefs: PlayerPrefs) -> String {
        line(
            prefs.crossfade ? "Crossfade \(prefs.crossfadeSeconds) s" : "Gapless",
            prefs.paceIsDefault ? nil : Pace.speedLabel(prefs.speed),
            prefs.autoplay ? "Autoplay" : nil,
            prefs.skipSilence ? "Skip silence" : nil
        )
    }

    /// Radio's two parts, with how song radio is tuned when it is not as it came.
    public static func radio(_ prefs: PlayerPrefs) -> String {
        line(
            prefs.libraryOnly || prefs.radioDiscovery == .libraryOnly
                ? "Song radio from your library" : "Song radio \(prefs.radioDiscovery.label.lowercased())",
            RadioWords.liveRadio
        )
    }

    public static func appearance(_ ambient: AmbientPrefs, liveBackground: Bool) -> String {
        let glow = switch ambient.strength {
        case .off: "No glow"
        case .subtle: "Subtle glow"
        case .rich: "Rich glow"
        }
        return line(glow, liveBackground ? "Live background" : nil)
    }

    public static func library(_ access: PhoneAccess, songs: Int, folders: [MusicFolder]) -> String {
        if access != .granted { return "Music on this phone not allowed yet" }
        let left = folders.filter { !$0.included }.count
        return line(count(songs, one: "song", many: "songs"), left > 0 ? count(left, one: "folder", many: "folders") + " left out" : nil)
    }

    /// The phone's part of the account card.
    public static func phoneLine(_ access: PhoneAccess, songs: Int) -> String {
        access == .granted ? count(songs, one: "song", many: "songs") + " on this phone" : "Allow access to the music on this phone"
    }

    /// How long ago something happened, in words: "Just now", "5 min ago". Times are in ms.
    public static func timeAgo(_ at: Int64, now: Int64) -> String {
        let gone = max(now - at, 0)
        if gone < minuteMs { return "Just now" }
        if gone < hourMs { return "\(gone / minuteMs) min ago" }
        if gone < dayMs { return "\(gone / hourMs) hr ago" }
        if gone < 2 * dayMs { return "Yesterday" }
        return "\(gone / dayMs) days ago"
    }

    /// When the library was last copied from the server, in words.
    public static func syncedAgo(_ at: Int64, now: Int64) -> String {
        let ago = timeAgo(at, now: now)
        return "Synced " + ago.prefix(1).lowercased() + ago.dropFirst()
    }

    /// How the server is doing, for the account card and its category: syncing, or where it is
    /// reached from and how fresh the copy is. Place is nil when the server has one address.
    public static func serverStatus(syncing: Bool, place: ServerPlace?, syncedAt: Int64?, now: Int64) -> String {
        if syncing { return "Syncing…" }
        let where_: String? = switch place {
        case .home: "Connected at home"
        case .away: "Connected away"
        case nil: nil
        }
        return line(where_, syncedAt.map { syncedAgo($0, now: now) } ?? "Not synced yet")
    }

    public static func streaming(_ stream: StreamPrefs, _ offline: OfflinePrefs) -> String {
        line(
            "Wi-Fi \(stream.wifi.label)",
            "mobile \(stream.mobile.label)",
            offline.cacheSize == .off ? "no cache" : "\(offline.cacheSize.label) cache"
        )
    }

    public static func lyrics(online: Bool, keepScreenOn: Bool) -> String {
        line(online ? "Found online" : "From your music only", keepScreenOn ? "Screen stays on" : nil)
    }

    public static func scrobbling(_ prefs: ListenBrainzPrefs) -> String {
        if !prefs.enabled { return "Off" }
        if !prefs.connected { return "Not connected yet" }
        if prefs.needsAttention { return "Needs a new token" }
        return "ListenBrainz as \(prefs.user ?? "")"
    }

    public static let backup = "Settings, playlists, likes and favorites"

    public static let audioQuality = "At home, away, on Wi-Fi and on mobile data"

    public static func about(version: String, updateReady: String? = nil) -> String {
        updateReady.map { "Update ready: \($0)" } ?? "Version \(version)"
    }
}

/// Words the settings pages print for sizes and counts.
public enum SettingsWords {
    /// A size in the units people read: "850 KB", "12.4 MB", "3.1 GB".
    public static func sizeLabel(_ bytes: Int64) -> String {
        if bytes >= 1 << 30 { return String(format: "%.1f GB", locale: Locale(identifier: "en_US_POSIX"), Double(bytes) / Double(1 << 30)) }
        if bytes >= 1 << 20 { return String(format: "%.1f MB", locale: Locale(identifier: "en_US_POSIX"), Double(bytes) / Double(1 << 20)) }
        return "\((bytes + 1023) / 1024) KB"
    }

    /// How many songs ahead: "Off", "1 song", "3 songs".
    public static func ahead(_ count: Int) -> String {
        switch count {
        case 0: "Off"
        case 1: "1 song"
        default: "\(count) songs"
        }
    }

    /// The counts the fetch ahead lists offer, with a stored one not among them put in its place.
    public static func aheadCounts(including current: Int) -> [Int] {
        let counts = [0, 1, 2, 3, 5, 10]
        return counts.contains(current) ? counts : (counts + [current]).sorted()
    }

    /// The speed as the Playback page's row shows it: "1x", or "1.25x, voices keep their pitch".
    public static func paceLabel(_ prefs: PlayerPrefs) -> String {
        var text = Pace.speedLabel(prefs.speed)
        if prefs.speed != 1 { text += prefs.keepPitch ? ", voices keep their pitch" : ", pitch follows the speed" }
        if prefs.pitchSemitones != 0 { text += ", shifted \(prefs.pitchSemitones) st" }
        return text
    }

    /// A download size's line in its list: about how big a 4 minute song is.
    public static func downloadDetail(_ quality: StreamQuality) -> String? {
        quality.kbps.map { "About \(Int((Double($0) * 0.03).rounded())) MB for a 4 minute song" }
    }

    /// A stream size's line in its list: about how much data an hour uses.
    public static func streamDetail(_ quality: StreamQuality) -> String? {
        quality.kbps.map { "MP3, about \(Int((Double($0) * 0.45).rounded())) MB an hour" }
    }
}

