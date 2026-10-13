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
        // A coordinate on the earth: finite and within `limit` either way.
        func number(_ key: String, limit: Double) throws -> Double {
            let value = (try? c.decodeIfPresent(Double.self, forKey: AnyKey(key)))
                ?? (try? c.decodeIfPresent(String.self, forKey: AnyKey(key))).flatMap { $0.flatMap { Double($0) } }
            guard let value, value.isFinite, abs(value) <= limit else {
                throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: "no \(key) on the earth"))
            }
            return value
        }
        code = text("code")
        name = text("name")
        state = text("state")
        country = text("country").uppercased()
        latitude = try number("latitude", limit: 90)
        longitude = try number("longitude", limit: 180)
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

// MARK: Where a place is looked up

/// Where a place is looked up: on the Octo server, which lists the look-up; on a server that
/// lists it but cannot be reached now (nothing then goes to the phone's place service); or by
/// the phone's own place service.
public enum PlaceLookup: Sendable, Equatable {
    case server
    case serverUnreachable
    case phone

    /// From the server's extensions as last known, and whether it can be asked now.
    public init(extensions: [String], reachable: Bool) {
        if serverLooksUpPlaces(extensions) {
            self = reachable ? .server : .serverUnreachable
        } else {
            self = .phone
        }
    }
}

public enum PlaceProblem: Error, Sendable, Equatable {
    case notFound
    case serverUnreachable
}

/// Finds places by the way `lookup` says, the server's answers by `server` and the phone's by
/// `phoneTyped` and `phoneNear`. A location is rounded to two decimals before anything is asked,
/// and when nothing names it the place is its rounded coordinates alone (stations by radius).
public struct PlaceResolver: Sendable {
    public typealias ServerAsk = @Sendable (PlaceQuery) async throws -> OctoPlace?
    public typealias PhoneTyped = @Sendable (PlaceQuery) async -> LivePlace?
    public typealias PhoneNear = @Sendable (LivePlace) async -> LivePlace?

    public let lookup: PlaceLookup
    private let server: ServerAsk
    private let phoneTyped: PhoneTyped
    private let phoneNear: PhoneNear

    public init(lookup: PlaceLookup, server: @escaping ServerAsk, phoneTyped: @escaping PhoneTyped, phoneNear: @escaping PhoneNear) {
        self.lookup = lookup
        self.server = server
        self.phoneTyped = phoneTyped
        self.phoneNear = phoneNear
    }

    /// A ZIP or postal code, or a city, typed for a country.
    public func typed(_ words: String, country: String) async throws -> LivePlace {
        let clean = words.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw PlaceProblem.notFound }
        let query = PlaceQuery.typed(clean, country: country)
        switch lookup {
        case .serverUnreachable:
            throw PlaceProblem.serverUnreachable
        case .server:
            let found: OctoPlace?
            do {
                found = try await server(query)
            } catch {
                if error is CancellationError { throw error }
                throw PlaceProblem.serverUnreachable
            }
            guard let found else { throw PlaceProblem.notFound }
            return named(found.livePlace, or: clean)
        case .phone:
            guard let found = await phoneTyped(query) else { throw PlaceProblem.notFound }
            return named(found.rounded, or: clean)
        }
    }

    /// A place found for typed words, named by them when nothing else names it.
    private func named(_ place: LivePlace, or words: String) -> LivePlace {
        var named = place
        if named.label.trimmingCharacters(in: .whitespaces).isEmpty { named.label = words }
        return named
    }

    /// The place at a location: its rounded coordinates, named with its state and country when
    /// the server (or, without one, the phone) can name them.
    public func near(latitude: Double, longitude: Double) async -> LivePlace {
        let at = LivePlace(latitude: latitude, longitude: longitude, label: "Your location").rounded
        switch lookup {
        case .serverUnreachable:
            return at
        case .server:
            guard let found = try? await server(.near(latitude: at.latitude, longitude: at.longitude)) else { return at }
            let named = found.livePlace
            return LivePlace(latitude: at.latitude, longitude: at.longitude, label: named.label.isEmpty ? at.label : named.label,
                             state: named.state, countryCode: named.countryCode)
        case .phone:
            guard let named = await phoneNear(at) else { return at }
            return LivePlace(latitude: at.latitude, longitude: at.longitude, label: named.label.isEmpty ? at.label : named.label,
                             state: named.state, countryCode: named.countryCode)
        }
    }
}
