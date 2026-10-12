import Foundation

/// How an Octo server with Family on sends a stream for an account: the file as it is, or a
/// smaller one at a bitrate.
public enum AccountStreamQuality: String, StoredChoice, Codable {
    case original = "Original"
    case high = "High"
    case standard = "Standard"
    case dataSaver = "DataSaver"

    /// 0 is the file as it is.
    public var kbps: Int {
        switch self {
        case .original: 0
        case .high: 256
        case .standard: 160
        case .dataSaver: 96
        }
    }

    public var name: String {
        switch self {
        case .original: "Original"
        case .high: "High"
        case .standard: "Standard"
        case .dataSaver: "Data saver"
        }
    }

    public var line: String {
        switch self {
        case .original: AccountQualityWords.originalLine
        case .high: "256 kbps"
        case .standard: "160 kbps"
        case .dataSaver: "96 kbps, for slow or metered connections"
        }
    }
}

/// The account's own audio quality at home and away, and the family's limits on it (0 for
/// none), as the server keeps them.
public struct AccountQuality: Sendable, Equatable, Decodable {
    public var home: AccountStreamQuality = .original
    public var away: AccountStreamQuality = .original
    public var familyLimitKbps = 0
    public var familyAwayLimitKbps = 0

    public init(home: AccountStreamQuality = .original, away: AccountStreamQuality = .original, familyLimitKbps: Int = 0,
                familyAwayLimitKbps: Int = 0) {
        self.home = home
        self.away = away
        self.familyLimitKbps = familyLimitKbps
        self.familyAwayLimitKbps = familyAwayLimitKbps
    }

    enum CodingKeys: String, CodingKey { case home, away, familyLimitKbps, familyAwayLimitKbps }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        home = c.choice(.home, or: .original)
        away = c.choice(.away, or: .original)
        familyLimitKbps = c.value(.familyLimitKbps, or: 0)
        familyAwayLimitKbps = c.value(.familyAwayLimitKbps, or: 0)
    }

    /// The limit at home: the family's limit.
    public var homeLimit: Int { familyLimitKbps }

    /// The limit away: the home limit unless the family set a lower one for away.
    public var awayLimit: Int {
        if familyAwayLimitKbps <= 0 { return familyLimitKbps }
        if familyLimitKbps <= 0 { return familyAwayLimitKbps }
        return min(familyLimitKbps, familyAwayLimitKbps)
    }

    /// The family's limits, in plain words, or nothing when there are none.
    public var limitLines: [String] {
        var lines: [String] = []
        if familyLimitKbps > 0 { lines.append("Your family plan limits listening to \(familyLimitKbps) kbps") }
        if familyAwayLimitKbps > 0, familyLimitKbps <= 0 || familyAwayLimitKbps < familyLimitKbps {
            lines.append("Your family plan limits away listening to \(familyAwayLimitKbps) kbps")
        }
        return lines
    }
}

/// Who picks a device's audio quality: the account's own setting, or the app on the device.
public enum QualityFollows: String, StoredChoice, Codable {
    case account = "Account"
    case app = "App"

    public var name: String {
        switch self {
        case .account: "Use my account setting"
        case .app: "Let this app decide"
        }
    }

    public var line: String {
        switch self {
        case .account: "The server sends what you chose above, at home and away."
        case .app: "This app's own quality setting decides, within any family limit."
        }
    }
}

/// One quality as its list shows it under a family limit: a bitrate above the limit plays at the
/// limit, and Original cannot be picked under a limit, `blocked` saying why.
public struct AccountQualityOption: Sendable, Equatable {
    public var quality: AccountStreamQuality
    public var limited: Bool
    public var blocked: String?

    public var name: String { quality.name }
    public var line: String { blocked ?? quality.line }
    public var enabled: Bool { blocked == nil }
}

public enum AccountQualityWords {
    public static let pageTitle = "Audio quality"
    public static let atHome = "At home"
    public static let away = "Away from home"
    public static let onThisDevice = "Quality on this device"
    public static let originalLine = "As the file is, FLAC stays FLAC"
    public static let originalLabel = "Original (as the file is, FLAC stays FLAC)"

    /// Why Original cannot be picked under a family limit, or nil when it can.
    public static func originalBlocked(by limitKbps: Int) -> String? {
        limitKbps > 0 ? "Your family plan streams up to \(limitKbps) kbps" : nil
    }

    /// Every quality, Original first, under a family limit (0 for none).
    public static func options(limitKbps: Int) -> [AccountQualityOption] {
        AccountStreamQuality.allCases.map { quality in
            let original = quality.kbps == 0
            return AccountQualityOption(quality: quality, limited: limitKbps > 0 && (original || quality.kbps > limitKbps),
                                        blocked: original ? originalBlocked(by: limitKbps) : nil)
        }
    }

    /// Whether this app's own stream size applies: always without a family, and with one only
    /// when the device is left to the app.
    public static func appPicksQuality(familyOn: Bool, follows: QualityFollows?) -> Bool {
        !familyOn || follows == .app
    }
}

/// The extension an Octo server lists while Family is on.
public let octoFamilyExtension = "octoFamily"

/// One of the account's devices as the quality page needs it.
public struct QualityDevice: Sendable, Equatable, Decodable {
    public var id: String
    /// Whether this is the device asking.
    public var current: Bool
    public var quality: QualityFollows

    enum CodingKeys: String, CodingKey { case id, current, quality }

    public init(id: String, current: Bool, quality: QualityFollows) {
        self.id = id
        self.current = current
        self.quality = quality
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, or: "")
        current = c.value(.current, or: false)
        quality = c.choice(.quality, or: .account)
    }
}

private struct FamilyAnswer: Decodable {
    struct Family: Decodable {
        struct Me: Decodable {
            var quality: AccountQuality?
        }
        var me: Me?
    }
    var family: Family?
}

private struct DevicesAnswer: Decodable {
    struct Devices: Decodable {
        var device: [QualityDevice]?
    }
    var familyDevices: Devices?
}

private struct QualityAnswer: Decodable {
    var quality: AccountQuality?
}

extension SubsonicClient {
    /// The signed-in account's own quality at home and away, and the family's limits on it.
    public func accountQuality() async throws -> AccountQuality {
        let answer: FamilyAnswer = try await get("getFamily", key: nil)
        return answer.family?.me?.quality ?? AccountQuality()
    }

    /// The signed-in account's devices, with who picks each one's quality.
    public func qualityDevices() async throws -> [QualityDevice] {
        let answer: DevicesAnswer = try await get("getFamilyDevices", key: nil)
        return answer.familyDevices?.device ?? []
    }

    /// Sets the account's quality at home or away; left out keeps what it is. Answers the
    /// quality as the server now has it.
    public func setAccountQuality(home: AccountStreamQuality? = nil, away: AccountStreamQuality? = nil) async throws -> AccountQuality {
        var params: [(String, String)] = []
        if let home { params.append(("home", home.storedName)) }
        if let away { params.append(("away", away.storedName)) }
        let answer: QualityAnswer = try await get("setFamilyQuality", params, key: nil)
        return answer.quality ?? AccountQuality(home: home ?? .original, away: away ?? .original)
    }

    /// Sets who picks one of the account's devices' quality.
    public func setQualityFollows(deviceId: String, _ follows: QualityFollows) async throws {
        try await call("setFamilyDeviceQuality", [("id", deviceId), ("mode", follows.storedName)])
    }
}
