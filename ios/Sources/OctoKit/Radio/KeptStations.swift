import Foundation

/// The live stations a listener kept on this phone, newest first. Saved as JSON (`encoded`) in
/// the app's own store and its backups, in the shape the other Octo apps write.
public struct KeptStations: Codable, Sendable, Equatable {
    public var stations: [LiveStation]

    public init(stations: [LiveStation] = []) { self.stations = stations }

    enum CodingKeys: String, CodingKey { case stations }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        stations = (try? c.decodeIfPresent([LiveStation].self, forKey: .stations)) ?? []
    }

    public func has(_ uuid: String) -> Bool { stations.contains { $0.uuid == uuid } }

    /// Kept once, at the top; a station kept again moves there with what the catalog says now.
    public func keep(_ station: LiveStation) -> KeptStations {
        var kept = station
        kept.distanceMeters = nil
        return KeptStations(stations: [kept] + stations.filter { $0.uuid != station.uuid })
    }

    public func drop(_ uuid: String) -> KeptStations { KeptStations(stations: stations.filter { $0.uuid != uuid }) }

    /// Kept stations added from a backup after the ones here, each once.
    public func adding(_ more: [LiveStation]) -> KeptStations {
        var seen = Set(stations.map(\.uuid))
        return KeptStations(stations: stations + more.filter { seen.insert($0.uuid).inserted }.map {
            var kept = $0
            kept.distanceMeters = nil
            return kept
        })
    }

    public func encoded() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(self)).map { String(decoding: $0, as: UTF8.self) } ?? "{\"stations\":[]}"
    }

    /// What was saved, or nothing kept when it cannot be read.
    public static func decoded(_ text: String?) -> KeptStations {
        guard let text, let data = text.data(using: .utf8) else { return KeptStations() }
        return (try? JSONDecoder().decode(KeptStations.self, from: data)) ?? KeptStations()
    }
}
