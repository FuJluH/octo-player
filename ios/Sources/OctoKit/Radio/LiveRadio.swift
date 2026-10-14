import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

// Live radio stations near a place, from the Radio Browser catalog: where to ask, what to ask,
// how the answers are merged, ordered and kept, and which of them this app can play.

/// A live radio station from the Radio Browser catalog, as an app shows, plays and keeps it.
public struct LiveStation: Codable, Sendable, Hashable, Identifiable {
    public var uuid: String
    public var name: String
    public var streamUrl: String
    public var favicon: String
    public var codec: String
    /// Kilobits a second, 0 when the catalog does not know.
    public var bitrate: Int
    public var hls: Bool
    public var country: String
    public var countryCode: String
    public var state: String
    public var tags: [String]
    /// The station's website, an http(s) address, or empty.
    public var homepage: String
    /// How far from the place asked about, in meters; nil when the catalog does not know where
    /// the station is.
    public var distanceMeters: Double?
    /// How often listeners started it lately, the catalog's measure of how popular it is.
    public var clicks: Int

    public var id: String { uuid }

    public init(uuid: String, name: String, streamUrl: String, favicon: String = "", codec: String = "", bitrate: Int = 0,
                hls: Bool = false, country: String = "", countryCode: String = "", state: String = "", tags: [String] = [],
                homepage: String = "", distanceMeters: Double? = nil, clicks: Int = 0) {
        self.uuid = uuid
        self.name = name
        self.streamUrl = streamUrl
        self.favicon = favicon
        self.codec = codec
        self.bitrate = bitrate
        self.hls = hls
        self.country = country
        self.countryCode = countryCode
        self.state = state
        self.tags = tags
        self.homepage = homepage
        self.distanceMeters = distanceMeters
        self.clicks = clicks
    }

    enum CodingKeys: String, CodingKey {
        case uuid, name, streamUrl, favicon, codec, bitrate, hls, country, countryCode, state, tags, homepage, distanceMeters, clicks
    }

    /// Reads what any Octo app wrote: a missing field takes its default.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        uuid = try c.decode(String.self, forKey: .uuid)
        streamUrl = try c.decode(String.self, forKey: .streamUrl)
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
        favicon = (try? c.decodeIfPresent(String.self, forKey: .favicon)) ?? ""
        codec = (try? c.decodeIfPresent(String.self, forKey: .codec)) ?? ""
        bitrate = (try? c.decodeIfPresent(Int.self, forKey: .bitrate)) ?? 0
        hls = (try? c.decodeIfPresent(Bool.self, forKey: .hls)) ?? false
        country = (try? c.decodeIfPresent(String.self, forKey: .country)) ?? ""
        countryCode = (try? c.decodeIfPresent(String.self, forKey: .countryCode)) ?? ""
        state = (try? c.decodeIfPresent(String.self, forKey: .state)) ?? ""
        tags = (try? c.decodeIfPresent([String].self, forKey: .tags)) ?? []
        homepage = (try? c.decodeIfPresent(String.self, forKey: .homepage)) ?? ""
        distanceMeters = try? c.decodeIfPresent(Double.self, forKey: .distanceMeters)
        clicks = (try? c.decodeIfPresent(Int.self, forKey: .clicks)) ?? 0
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(uuid, forKey: .uuid)
        try c.encode(name, forKey: .name)
        try c.encode(streamUrl, forKey: .streamUrl)
        try c.encode(favicon, forKey: .favicon)
        try c.encode(codec, forKey: .codec)
        try c.encode(bitrate, forKey: .bitrate)
        try c.encode(hls, forKey: .hls)
        try c.encode(country, forKey: .country)
        try c.encode(countryCode, forKey: .countryCode)
        try c.encode(state, forKey: .state)
        try c.encode(tags, forKey: .tags)
        try c.encode(homepage, forKey: .homepage)
        try c.encodeIfPresent(distanceMeters, forKey: .distanceMeters)
        try c.encode(clicks, forKey: .clicks)
    }

    /// Whether it streams as HLS: the catalog says so, or its address is a playlist of segments.
    public var isHls: Bool { hls || looksLikeHls(streamUrl) }

    /// The codec and bitrate as a row shows them: "MP3 128k", "AAC+", or nothing.
    public var formatLine: String {
        let name = codec.trimmingCharacters(in: .whitespaces).uppercased()
        let shown = name.isEmpty || name == "UNKNOWN" ? "" : name
        let rate = bitrate > 0 ? "\(bitrate)k" : ""
        return [shown, rate].filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// Where it is, as a row shows it: "Austin, Texas", "Texas, The United States Of America".
    public var placeLine: String {
        [state, country].map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

/// Whether an address names an HLS playlist, by the end of its path.
public func looksLikeHls(_ address: String) -> Bool {
    guard let url = URL(string: address.trimmingCharacters(in: .whitespacesAndNewlines)) else { return false }
    return url.path.lowercased().hasSuffix(".m3u8")
}

/// A place to find stations around: where it is, a name for it, and the names the catalog files
/// stations under when it has no coordinates for them.
public struct LivePlace: Codable, Sendable, Hashable {
    public var latitude: Double
    public var longitude: Double
    public var label: String
    public var state: String
    public var countryCode: String

    public init(latitude: Double, longitude: Double, label: String, state: String = "", countryCode: String = "") {
        self.latitude = latitude
        self.longitude = longitude
        self.label = label
        self.state = state
        self.countryCode = countryCode
    }

    enum CodingKeys: String, CodingKey { case latitude, longitude, label, state, countryCode }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        latitude = try c.decode(Double.self, forKey: .latitude)
        longitude = try c.decode(Double.self, forKey: .longitude)
        label = (try? c.decodeIfPresent(String.self, forKey: .label)) ?? ""
        state = (try? c.decodeIfPresent(String.self, forKey: .state)) ?? ""
        countryCode = (try? c.decodeIfPresent(String.self, forKey: .countryCode)) ?? ""
    }

    /// The same place with its coordinates to two decimals, all that ever leaves the phone.
    public var rounded: LivePlace {
        LivePlace(latitude: roundedCoordinate(latitude), longitude: roundedCoordinate(longitude), label: label, state: state,
                  countryCode: countryCode)
    }
}

/// How the stations found are ordered.
public enum LiveSort: String, Sendable, CaseIterable, Codable {
    case distance = "Distance"
    case popular = "Popular"

    public var label: String {
        switch self {
        case .distance: "Nearest"
        case .popular: "Most popular"
        }
    }
}

/// The radius choices, in the listener's own units.
public let liveRadiusMiles = [10, 25, 50, 100]
public let liveRadiusKm = [15, 40, 80, 160]
public let liveRadiusDefaultIndex = 1
public let mileMeters = 1609.344

/// One radius choice: how far, in the listener's units.
public struct LiveRadius: Sendable, Hashable {
    public var amount: Int
    public var miles: Bool

    public init(amount: Int, miles: Bool) {
        self.amount = amount
        self.miles = miles
    }

    public var meters: Double { Double(amount) * (miles ? mileMeters : 1000) }
    public var label: String { "\(amount) \(miles ? "mi" : "km")" }

    /// The choices for the units, in order.
    public static func choices(miles: Bool) -> [LiveRadius] {
        (miles ? liveRadiusMiles : liveRadiusKm).map { LiveRadius(amount: $0, miles: miles) }
    }

    /// The choice at a kept index, the default for one out of range.
    public static func at(_ index: Int, miles: Bool) -> LiveRadius {
        let all = choices(miles: miles)
        return all.indices.contains(index) ? all[index] : all[liveRadiusDefaultIndex]
    }
}

/// A distance as a row shows it, in the listener's units: "2.4 mi", "18 km".
public func liveDistanceText(_ meters: Double, miles: Bool) -> String {
    // A distance no place on earth can be is not shown.
    guard let meters = trueDistance(meters) else { return "" }
    let amount = meters / (miles ? mileMeters : 1000)
    let unit = miles ? "mi" : "km"
    if amount < 0.1 { return "here" }
    if amount < 10 { return String(format: "%.1f %@", amount, unit) }
    return "\(clampedWhole(amount)) \(unit)"
}

/// The farthest two places on earth are apart, in meters: half its circumference.
public let earthHalfCircumferenceMeters = 20_040_000.0

/// A number from outside as a whole number, held to a billion either way so nothing done with it
/// overflows; 0 for one that is not finite.
public func clampedWhole(_ value: Double) -> Int {
    guard value.isFinite else { return 0 }
    return Int(min(max(value.rounded(), -1e9), 1e9))
}

/// A distance from outside that can be true: finite, not below 0, and no more than half the
/// earth around; nil for any other.
public func trueDistance(_ meters: Double?) -> Double? {
    guard let meters, meters.isFinite, meters >= 0, meters <= earthHalfCircumferenceMeters else { return nil }
    return meters
}

/// A coordinate to two decimals (about a kilometer).
public func roundedCoordinate(_ value: Double) -> Double { (value * 100).rounded() / 100 }

/// How far apart two places are over the earth, in meters.
public func greatCircleMeters(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
    let radius = 6_371_008.8
    let p1 = lat1 * .pi / 180, p2 = lat2 * .pi / 180
    let dp = (lat2 - lat1) * .pi / 180, dl = (lon2 - lon1) * .pi / 180
    let a = sin(dp / 2) * sin(dp / 2) + cos(p1) * cos(p2) * sin(dl / 2) * sin(dl / 2)
    return 2 * radius * atan2(a.squareRoot(), (1 - a).squareRoot())
}

// MARK: The catalog's rows

/// A station row as the catalog sends it. A field of the wrong kind or missing takes its default.
struct CatalogStation: Decodable {
    var uuid = ""
    var name = ""
    var url = ""
    var urlResolved = ""
    var favicon = ""
    var codec = ""
    var bitrate = 0
    var hls = 0
    var country = ""
    var countryCode = ""
    var state = ""
    var tags = ""
    var homepage = ""
    var latitude: Double?
    var longitude: Double?
    var geoDistance: Double?
    var clickCount = 0
    var lastCheckOk = 1

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        func text(_ key: String) -> String { (try? c.decodeIfPresent(String.self, forKey: AnyKey(key))) ?? "" }
        func whole(_ key: String) -> Int? {
            if let value = try? c.decodeIfPresent(Int.self, forKey: AnyKey(key)) { return value }
            if let value = try? c.decodeIfPresent(Double.self, forKey: AnyKey(key)) {
                return value.isFinite ? clampedWhole(value) : nil
            }
            return (try? c.decodeIfPresent(String.self, forKey: AnyKey(key))).flatMap { $0.flatMap { Int($0) } }
                .map { min(max($0, -1_000_000_000), 1_000_000_000) }
        }
        // Only finite numbers: "Infinity" or "nan" written as text is no number.
        func number(_ key: String) -> Double? {
            let value = (try? c.decodeIfPresent(Double.self, forKey: AnyKey(key)))
                ?? (try? c.decodeIfPresent(String.self, forKey: AnyKey(key))).flatMap { $0.flatMap { Double($0) } }
            return value.flatMap { $0.isFinite ? $0 : nil }
        }
        uuid = text("stationuuid")
        name = text("name")
        url = text("url")
        urlResolved = text("url_resolved")
        favicon = text("favicon")
        codec = text("codec")
        bitrate = whole("bitrate") ?? 0
        hls = whole("hls") ?? 0
        country = text("country")
        countryCode = text("countrycode")
        state = text("state")
        tags = text("tags")
        homepage = text("homepage")
        latitude = number("geo_lat")
        longitude = number("geo_long")
        geoDistance = number("geo_distance")
        clickCount = whole("clickcount") ?? 0
        lastCheckOk = whole("lastcheckok") ?? 1
    }

    /// Whether the catalog says where the station is: coordinates on the earth, not 0, 0.
    var placed: Bool {
        guard let latitude, let longitude else { return false }
        return abs(latitude) <= 90 && abs(longitude) <= 180 && (latitude != 0 || longitude != 0)
    }

    /// The station as the app keeps it, its distance from `origin` when the catalog places it.
    /// Nil for a row with no id or stream, or one the catalog found broken at its last check.
    func live(from origin: LivePlace?) -> LiveStation? {
        let stream = (urlResolved.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? url : urlResolved)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !uuid.trimmingCharacters(in: .whitespaces).isEmpty, !stream.isEmpty, lastCheckOk != 0 else { return nil }
        var distance = trueDistance(geoDistance)
        if distance == nil, let origin, placed, let latitude, let longitude {
            distance = trueDistance(greatCircleMeters(origin.latitude, origin.longitude, latitude, longitude))
        }
        var seenTags = Set<String>()
        let tagList = tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && seenTags.insert($0).inserted }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let site = homepage.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowerSite = site.lowercased()
        let website = lowerSite.hasPrefix("http://") || lowerSite.hasPrefix("https://") ? site : ""
        return LiveStation(uuid: uuid, name: trimmedName.isEmpty ? stream : trimmedName, streamUrl: stream,
                           favicon: favicon.trimmingCharacters(in: .whitespacesAndNewlines),
                           codec: codec.trimmingCharacters(in: .whitespaces), bitrate: bitrate, hls: hls == 1,
                           country: country.trimmingCharacters(in: .whitespaces),
                           countryCode: countryCode.trimmingCharacters(in: .whitespaces).uppercased(),
                           state: state.trimmingCharacters(in: .whitespaces), tags: Array(tagList.prefix(6)),
                           homepage: website, distanceMeters: distance, clicks: clickCount)
    }
}

/// The catalog's answer to a search, as stations; an answer that is not a list is none.
func catalogStations(_ data: Data, from origin: LivePlace?) throws -> [LiveStation] {
    try JSONDecoder().decode([CatalogStation].self, from: data).compactMap { $0.live(from: origin) }
}

/// The catalog's answer to the state and country search, around a real place: only the stations
/// it cannot place, since one it places would have been found by distance when near enough.
func regionalStations(_ data: Data) throws -> [LiveStation] {
    try JSONDecoder().decode([CatalogStation].self, from: data).filter { !$0.placed }.compactMap { $0.live(from: nil) }
}

// MARK: Merging and order

/// The stations near a place: those the catalog places within the radius, and those it files
/// under the place's state and country but cannot place, each once.
public func mergeStations(near: [LiveStation], regional: [LiveStation]) -> [LiveStation] {
    var seen = Set<String>()
    return (near + regional.filter { $0.distanceMeters == nil }).filter { seen.insert($0.uuid).inserted }
}

/// Nearest first (the ones the catalog cannot place after, the most played first), or the most
/// played first.
public func sortStations(_ stations: [LiveStation], by sort: LiveSort) -> [LiveStation] {
    switch sort {
    case .distance:
        stations.sorted { a, b in
            if (a.distanceMeters == nil) != (b.distanceMeters == nil) { return a.distanceMeters != nil }
            if let x = a.distanceMeters, let y = b.distanceMeters, x != y { return x < y }
            if a.clicks != b.clicks { return a.clicks > b.clicks }
            return a.name.lowercased() < b.name.lowercased()
        }
    case .popular:
        stations.sorted { a, b in
            if a.clicks != b.clicks { return a.clicks > b.clicks }
            return a.name.lowercased() < b.name.lowercased()
        }
    }
}

// MARK: What this app plays

/// The codecs the app's own live decoder takes.
public let livePlayableCodecs: Set<String> = ["MP3", "AAC", "AAC+"]

/// Whether this app can play a station: an MP3 or AAC stream, and an HLS one only where the app
/// reads HLS.
public func liveStationPlayable(_ station: LiveStation, hlsPlays: Bool) -> Bool {
    guard livePlayableCodecs.contains(station.codec.trimmingCharacters(in: .whitespaces).uppercased()) else { return false }
    return hlsPlays || !station.isHls
}

/// The stations this app can play, in order, and how many it left out.
public func playableStations(_ stations: [LiveStation], hlsPlays: Bool) -> (stations: [LiveStation], hidden: Int) {
    let shown = stations.filter { liveStationPlayable($0, hlsPlays: hlsPlays) }
    return (shown, stations.count - shown.count)
}

/// The note under the list for the stations left out.
public func hiddenStationsNote(_ hidden: Int) -> String? {
    switch hidden {
    case ...0: nil
    case 1: "1 station here uses a format this app cannot play"
    default: "\(hidden) stations here use a format this app cannot play"
    }
}

/// Whether words typed into Search are likely after a radio station.
public func looksLikeRadioSearch(_ query: String) -> Bool {
    let words = query.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
    return words.contains { ["radio", "radios", "fm", "station", "stations"].contains($0) }
}

/// The name the catalog files a state under: a US state's two letters as its full name, any
/// other as it is.
public func catalogStateName(_ state: String, countryCode: String) -> String {
    let trimmed = state.trimmingCharacters(in: .whitespaces)
    guard countryCode.uppercased() == "US", trimmed.count == 2 else { return trimmed }
    return usStateNames[trimmed.uppercased()] ?? trimmed
}

private let usStateNames: [String: String] = [
    "AL": "Alabama", "AK": "Alaska", "AZ": "Arizona", "AR": "Arkansas", "CA": "California", "CO": "Colorado",
    "CT": "Connecticut", "DE": "Delaware", "DC": "District of Columbia", "FL": "Florida", "GA": "Georgia", "HI": "Hawaii",
    "ID": "Idaho", "IL": "Illinois", "IN": "Indiana", "IA": "Iowa", "KS": "Kansas", "KY": "Kentucky", "LA": "Louisiana",
    "ME": "Maine", "MD": "Maryland", "MA": "Massachusetts", "MI": "Michigan", "MN": "Minnesota", "MS": "Mississippi",
    "MO": "Missouri", "MT": "Montana", "NE": "Nebraska", "NV": "Nevada", "NH": "New Hampshire", "NJ": "New Jersey",
    "NM": "New Mexico", "NY": "New York", "NC": "North Carolina", "ND": "North Dakota", "OH": "Ohio", "OK": "Oklahoma",
    "OR": "Oregon", "PA": "Pennsylvania", "RI": "Rhode Island", "SC": "South Carolina", "SD": "South Dakota",
    "TN": "Tennessee", "TX": "Texas", "UT": "Utah", "VT": "Vermont", "VA": "Virginia", "WA": "Washington",
    "WV": "West Virginia", "WI": "Wisconsin", "WY": "Wyoming", "PR": "Puerto Rico",
]

// MARK: Asking the catalog

/// The server asked when none can be found.
public let radioBrowserFallbackServer = "de1.api.radio-browser.info"

/// How many stations each search asks for.
public let radioBrowserSearchLimit = 200

/// One of the catalog's servers at random, the fallback when none is known.
public func pickRadioServer(_ servers: [String], random: inout some RandomNumberGenerator) -> String {
    let named = servers.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    return named.randomElement(using: &random) ?? radioBrowserFallbackServer
}

/// A server's address: a name stands for its https address.
public func radioServerBase(_ server: String) -> URL? {
    let address = server.contains("://") ? server : "https://\(server)"
    return URL(string: address.hasSuffix("/") ? String(address.dropLast()) : address)
}

/// A station search with these values, as the catalog asks: working stations only, the most
/// played first, at most 200.
public func radioSearchUrl(_ base: URL, _ params: [(String, String)]) -> URL? {
    let all = params + [("hidebroken", "true"), ("order", "clickcount"), ("reverse", "true"), ("limit", "\(radioBrowserSearchLimit)")]
    let query = all.map { "\($0.0)=\(formEncode($0.1))" }.joined(separator: "&")
    return URL(string: base.absoluteString + "/json/stations/search?" + query)
}

/// The search for stations within `radiusMeters` of a place, by its rounded coordinates.
public func radioNearbyUrl(_ base: URL, place: LivePlace, radiusMeters: Double) -> URL? {
    let at = place.rounded
    return radioSearchUrl(base, [("geo_lat", "\(at.latitude)"), ("geo_long", "\(at.longitude)"),
                                 ("geo_distance", "\(clampedWhole(radiusMeters))")])
}

/// The search for stations filed under the place's country and state; nil without a country.
public func radioRegionalUrl(_ base: URL, place: LivePlace) -> URL? {
    let country = place.countryCode.trimmingCharacters(in: .whitespaces).uppercased()
    guard !country.isEmpty else { return nil }
    let state = catalogStateName(place.state, countryCode: country)
    return radioSearchUrl(base, [("countrycode", country)] + (state.isEmpty ? [] : [("state", state)]))
}

/// What the catalog is told when a listener starts a station.
public func radioClickUrl(_ base: URL, uuid: String) -> URL? {
    URL(string: base.absoluteString + "/json/url/" + formEncode(uuid))
}

/// What the answers for a place and radius are kept under: the rounded place, the radius in
/// meters, and the state and country the regional search used.
public func liveCacheKey(_ place: LivePlace, radiusMeters: Double) -> String {
    let at = place.rounded
    return "\(at.latitude),\(at.longitude),\(clampedWhole(radiusMeters)),\(place.state),\(place.countryCode)"
}

/// How long the stations found for a place are kept: six hours.
public let liveCacheMs: Int64 = 6 * 60 * 60 * 1000

/// The stations found lately, by place and radius, each for six hours.
public struct LiveStationCache: Sendable {
    private var entries: [String: (at: Int64, stations: [LiveStation])] = [:]

    public init() {}

    public func get(_ key: String, now: Int64) -> [LiveStation]? {
        guard let entry = entries[key], now - entry.at < liveCacheMs, now >= entry.at else { return nil }
        return entry.stations
    }

    public mutating func put(_ key: String, _ stations: [LiveStation], now: Int64) {
        entries = entries.filter { now - $0.value.at < liveCacheMs }
        entries[key] = (now, stations)
    }
}

/// The catalog failed to answer.
public struct RadioBrowserError: Error, Sendable, Equatable {
    public var status: Int?
}

/// The Radio Browser catalog of live radio stations. It is asked through one of its servers,
/// picked at random once, with the app's own name, so its keepers know who asks; a server that
/// fails is let go, and another picked next time. Answers are kept for six hours per place and
/// radius. `userAgent` is like "Octo/1.7 (iPhone)".
public actor RadioBrowser {
    public typealias Fetch = @Sendable (URLRequest) async throws -> (Data, Int)

    private let userAgent: String
    private let servers: @Sendable () async -> [String]
    private let fetch: Fetch
    private let now: @Sendable () -> Int64
    private var chosen: String?
    private var cache = LiveStationCache()

    public init(userAgent: String, servers: @escaping @Sendable () async -> [String] = { await radioBrowserServers() },
                fetch: @escaping Fetch = RadioBrowser.urlSessionFetch, now: @escaping @Sendable () -> Int64 = { msSince1970() }) {
        self.userAgent = userAgent
        self.servers = servers
        self.fetch = fetch
        self.now = now
    }

    /// Every station near `place` within `radiusMeters`, those the catalog places nearest first,
    /// then those it files under the place's state and country.
    public func near(_ place: LivePlace, radiusMeters: Double) async throws -> [LiveStation] {
        let key = liveCacheKey(place, radiusMeters: radiusMeters)
        if let kept = cache.get(key, now: now()) { return kept }
        let at = place.rounded
        let base = try await self.base()
        guard let nearUrl = radioNearbyUrl(base, place: at, radiusMeters: radiusMeters) else { throw RadioBrowserError() }
        let near = try read(try await get(nearUrl)) { try catalogStations($0, from: at) }
        var regional: [LiveStation] = []
        var whole = true
        if let regionalUrl = radioRegionalUrl(base, place: at) {
            do {
                regional = try read(try await get(regionalUrl), regionalStations)
            } catch {
                if error is CancellationError { throw error }
                // Shown without them, and asked for again next time rather than kept.
                whole = false
            }
        }
        let all = sortStations(mergeStations(near: near, regional: regional), by: .distance)
        if whole { cache.put(key, all, now: now()) }
        return all
    }

    /// Tells the catalog a listener started a station, as its keepers ask, so popular stations
    /// rise for everyone. A failure is of no matter.
    public func started(_ uuid: String) async {
        guard let base = try? await base(), let url = radioClickUrl(base, uuid: uuid) else { return }
        _ = try? await get(url)
    }

    /// The server in use, picked at random the first time.
    public func base() async throws -> URL {
        let server: String
        if let chosen {
            server = chosen
        } else {
            var random = SystemRandomNumberGenerator()
            server = pickRadioServer(await servers(), random: &random)
            chosen = server
        }
        guard let url = radioServerBase(server) else {
            chosen = nil
            throw RadioBrowserError()
        }
        return url
    }

    /// An answer read as stations; one that cannot be read lets the server go, like a failure.
    private func read(_ data: Data, _ stations: (Data) throws -> [LiveStation]) throws -> [LiveStation] {
        do {
            return try stations(data)
        } catch {
            chosen = nil
            throw RadioBrowserError()
        }
    }

    private func get(_ url: URL) async throws -> Data {
        try Task.checkCancellation()
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        do {
            let (data, status) = try await fetch(request)
            guard (200..<300).contains(status) else {
                chosen = nil
                throw RadioBrowserError(status: status)
            }
            return data
        } catch {
            if !(error is CancellationError) { chosen = nil }
            throw error
        }
    }

    public static let urlSessionFetch: Fetch = { request in
        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }
}

/// The catalog's servers, by name: every address all.api.radio-browser.info stands for, named
/// again by a reverse lookup, as its keepers ask apps to find them; else the list its own
/// servers give; none when both fail, and the fallback server is used.
public func radioBrowserServers() async -> [String] {
    // The look-up blocks, so it runs on a queue of its own, never on a task's thread.
    let looked = await withCheckedContinuation { continuation in
        DispatchQueue.global(qos: .utility).async { continuation.resume(returning: lookUpRadioServers()) }
    }
    if !looked.isEmpty { return looked }
    guard let url = URL(string: "https://all.api.radio-browser.info/json/servers"),
          let (data, response) = try? await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 10)),
          ((response as? HTTPURLResponse)?.statusCode ?? 0) == 200 else { return [] }
    return radioServerNames(data)
}

/// The server names in the catalog's own list of its servers.
public func radioServerNames(_ data: Data) -> [String] {
    struct Server: Decodable { var name: String? }
    var seen = Set<String>()
    return ((try? JSONDecoder().decode([Server].self, from: data)) ?? []).compactMap(\.name)
        .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        .filter { $0.hasSuffix(".radio-browser.info") && seen.insert($0).inserted }
}

/// Each address all.api.radio-browser.info stands for, named again by a reverse lookup.
private func lookUpRadioServers() -> [String] {
    var hints = addrinfo()
    hints.ai_family = AF_UNSPEC
    #if canImport(Darwin)
    hints.ai_socktype = SOCK_STREAM
    #else
    hints.ai_socktype = Int32(SOCK_STREAM.rawValue)
    #endif
    var first: UnsafeMutablePointer<addrinfo>?
    guard getaddrinfo("all.api.radio-browser.info", "443", &hints, &first) == 0, let first else { return [] }
    defer { freeaddrinfo(first) }
    var names: [String] = []
    var next: UnsafeMutablePointer<addrinfo>? = first
    while let info = next {
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        if getnameinfo(info.pointee.ai_addr, info.pointee.ai_addrlen, &host, socklen_t(host.count), nil, 0, NI_NAMEREQD) == 0 {
            let name = String(decoding: host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self).lowercased()
            let clean = name.hasSuffix(".") ? String(name.dropLast()) : name
            if clean.hasSuffix(".radio-browser.info"), !names.contains(clean) { names.append(clean) }
        }
        next = info.pointee.ai_next
    }
    return names
}
