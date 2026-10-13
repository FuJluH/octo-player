import Foundation

/// The OpenSubsonic extension an Octo server lists when it looks up places itself, so a place
/// typed or found on the phone never goes to Apple's place service.
public let octoPlaces = "octoPlaces"

/// A place as the server knows it: its postal code when it has one, its name, state and country
/// (ISO alpha-2), and where it is, to two decimals.
public struct OctoPlace: Decodable, Sendable, Equatable {
    public var code: String
    public var name: String
    public var state: String
    public var country: String
    public var latitude: Double
    public var longitude: Double

    public init(code: String = "", name: String, state: String = "", country: String, latitude: Double, longitude: Double) {
        self.code = code
        self.name = name
        self.state = state
        self.country = country
        self.latitude = latitude
        self.longitude = longitude
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        func text(_ key: String) -> String { (try? c.decodeIfPresent(String.self, forKey: AnyKey(key))) ?? "" }
        func number(_ key: String) throws -> Double {
            if let value = try? c.decodeIfPresent(Double.self, forKey: AnyKey(key)) { return value }
            if let text = try? c.decodeIfPresent(String.self, forKey: AnyKey(key)), let value = Double(text) { return value }
            throw DecodingError.keyNotFound(AnyKey(key), .init(codingPath: c.codingPath, debugDescription: "no \(key)"))
        }
        code = text("code")
        name = text("name")
        state = text("state")
        country = text("country").uppercased()
        latitude = try number("latitude")
        longitude = try number("longitude")
    }

    /// The place to find stations around, named "City, State", its state as the radio catalog
    /// files it.
    public var livePlace: LivePlace {
        let label = [name, state].map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: ", ")
        return LivePlace(latitude: latitude, longitude: longitude, label: label.isEmpty ? code : label,
                         state: catalogStateName(state, countryCode: country), countryCode: country).rounded
    }
}

/// What a place is looked up by.
public enum PlaceQuery: Sendable, Equatable {
    /// A ZIP or postal code in a country.
    case code(String, country: String)
    /// A city, with its state when known, in a country.
    case city(String, state: String, country: String)
    /// The nearest place to these coordinates, sent to two decimals.
    case near(latitude: Double, longitude: Double)

    /// Words typed for a place: a postal code when they hold a digit, else a city, "Austin, TX"
    /// giving the state after the comma.
    public static func typed(_ words: String, country: String) -> PlaceQuery {
        let clean = words.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.contains(where: \.isNumber) { return .code(clean, country: country) }
        let parts = clean.split(separator: ",", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        return .city(parts.first ?? clean, state: parts.count > 1 ? parts[1] : "", country: country)
    }

    /// What the server is sent.
    public var params: [(String, String)] {
        switch self {
        case .code(let code, let country): [("code", code), ("country", country.uppercased())]
        case .city(let name, let state, let country): [("name", name), ("state", state), ("country", country.uppercased())]
        case .near(let latitude, let longitude):
            [("latitude", "\(roundedCoordinate(latitude))"), ("longitude", "\(roundedCoordinate(longitude))")]
        }
    }
}

/// Whether the server lists the place look-up, by its extensions ("name:version").
public func serverLooksUpPlaces(_ extensions: [String]) -> Bool {
    extensions.contains { $0 == octoPlaces || $0.hasPrefix(octoPlaces + ":") }
}

extension SubsonicClient {
    /// The place the server finds for a query; nil when it knows none (error 70).
    public func place(_ query: PlaceQuery) async throws -> OctoPlace? {
        do {
            return try await get("getPlace", query.params, key: "place", as: OctoPlace.self, timeout: 15)
        } catch OctoError.notFound {
            return nil
        }
    }
}
