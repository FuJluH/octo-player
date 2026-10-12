import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// One chart the server's country has. `label` is the chip's word ("Top songs", "Hip-Hop/Rap"),
/// `name` the playlist's ("Top Hip-Hop/Rap"), `kind` overall, new, trending or genre, `on`
/// whether it is a playlist for everyone, and `playlist` this listener's playlist id while it is
/// one.
public struct ChartChoice: Decodable, Sendable, Equatable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var label: String
    public var kind: String
    public var playlist: String?
    public var on: Bool

    enum CodingKeys: String, CodingKey { case id, name, label, kind, playlist, on }

    public init(id: String, name: String = "", label: String = "", kind: String = "", playlist: String? = nil, on: Bool = false) {
        self.id = id
        self.name = name
        self.label = label
        self.kind = kind
        self.playlist = playlist
        self.on = on
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.string(.id) ?? ""
        name = c.string(.name) ?? ""
        label = c.string(.label) ?? ""
        kind = c.string(.kind) ?? ""
        playlist = c.string(.playlist)
        on = c.bool(.on) ?? false
    }
}

/// The charts the server's country has, Popular right now first.
public struct ChartChoices: Decodable, Sendable, Equatable {
    public var country: String?
    public var chart: [ChartChoice]

    enum CodingKeys: String, CodingKey { case country, chart }

    public init(country: String? = nil, chart: [ChartChoice] = []) {
        self.country = country
        self.chart = chart
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        country = c.string(.country)
        chart = (try? c.decodeIfPresent([ChartChoice].self, forKey: .chart)) ?? []
    }
}

extension TopSong {
    /// A ranked entry made here rather than read from the server.
    public init(rank: Int, plays: Int? = nil, inLibrary: Bool = false, song: Song?) {
        self.rank = rank
        self.plays = plays
        self.inLibrary = inLibrary
        self.song = song
    }
}

extension SubsonicClient {
    /// The charts the server's country has. Only for servers that list octoTopSongs version 2.
    public func charts() async throws -> ChartChoices {
        try await get("getCharts", key: "charts")
    }
}
