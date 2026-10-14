import Foundation

// What the player shows and does while a live station plays: its id with the station's details,
// the stations Back and Next step through, the lines under the title, the codec pill, how long
// the listener has been on, and the song the heart stars for what is on air.

extension LiveStation {
    /// The station's queue id, with what the live player shows about it.
    public func radioId() -> String { OctoKit.radioId(streamUrl, name, hls: isHls, details: radioDetails()) }

    public func radioDetails() -> RadioDetails {
        RadioDetails(logo: favicon, codec: codec, bitrate: bitrate, country: country, countryCode: countryCode, state: state,
                     tags: tags, uuid: uuid)
    }
}

/// A stream address as a key for "the same stream": the scheme (http and https alike), the host
/// in lower case and the path without a trailing slash, the rest as written.
public func liveStreamKey(_ url: String) -> String {
    let text = url.trimmingCharacters(in: .whitespacesAndNewlines)
    let scheme: String
    let rest: Substring
    if let mark = text.range(of: "://") {
        scheme = text[..<mark.lowerBound].lowercased()
        rest = text[mark.upperBound...]
    } else {
        scheme = ""
        rest = Substring(text)
    }
    let hostEnd = rest.firstIndex { $0 == "/" || $0 == "?" || $0 == "#" } ?? rest.endIndex
    let host = rest[..<hostEnd].lowercased()
    var path = Substring(rest[hostEnd...])
    while path.last == "/" { path.removeLast() }
    let kind = scheme == "http" || scheme == "https" || scheme.isEmpty ? "" : "\(scheme)://"
    return kind + host + path
}

/// The stations a live station was started from, as the queue holds them: Back and Next step
/// through them in order and stop at the ends.
public struct LiveLineup: Sendable, Equatable {
    public let ids: [String]
    public let index: Int

    public init(ids: [String], index: Int) {
        self.ids = ids
        self.index = index
    }

    /// Whether Back and Next show: only for more than one station.
    public var shows: Bool { ids.count > 1 }
    public var hasPrevious: Bool { index > 0 }
    public var hasNext: Bool { index < ids.count - 1 }
    public var previous: Int? { hasPrevious ? index - 1 : nil }
    public var next: Int? { hasNext ? index + 1 : nil }
}

/// The lineup of a queue whose `current` entry is a live station: the queue itself when every
/// entry in it is a station, else that station alone.
public func liveLineup(_ queueIds: [String], current: Int) -> LiveLineup? {
    guard queueIds.indices.contains(current) else { return nil }
    let id = queueIds[current]
    guard isRadio(id) else { return nil }
    if queueIds.allSatisfy(isRadio) { return LiveLineup(ids: queueIds, index: current) }
    return LiveLineup(ids: [id], index: 0)
}

/// The stations of a list as the queue plays them, each once by its stream (the first kept), and
/// where the one tapped is among them.
public func lineupOf<T>(_ stations: [T], tapped: Int, stream: (T) -> String, id: (T) -> String) -> (ids: [String], index: Int) {
    var seen = Set<String>()
    let tappedKey = stations.indices.contains(tapped) ? liveStreamKey(stream(stations[tapped])) : nil
    let kept = stations.filter { seen.insert(liveStreamKey(stream($0))).inserted }
    let index = kept.firstIndex { liveStreamKey(stream($0)) == tappedKey } ?? 0
    return (kept.map(id), index)
}

/// The line under a live station's title when it names nothing.
public let liveRadioLine = "Live radio"

/// The line a live station shows under its title: while it names a song, "Artist · Station";
/// while it names none, its tagline, else where it is and what it plays ("California, The United
/// States Of America · Pop").
public func liveSubtitle(_ onAir: OnAir, station: String, details: RadioDetails) -> String {
    func blank(_ text: String) -> Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    if onAir.named { return [onAir.artist, station].filter { !blank($0) }.joined(separator: " · ") }
    if !blank(onAir.tagline) { return onAir.tagline }
    var places: [String] = []
    for part in [details.state, blank(details.country) ? details.countryCode : details.country] where !blank(part) && !places.contains(part) {
        places.append(part)
    }
    let genre = details.tags.first.map { $0.prefix(1).uppercased() + $0.dropFirst() } ?? ""
    let line = [places.joined(separator: ", "), genre].filter { !blank($0) }.joined(separator: " · ")
    return line.isEmpty ? liveRadioLine : line
}

/// The title a live station shows: the song on air, else the station's name, else its address.
public func liveTitle(_ onAir: OnAir, station: String, streamUrl: String) -> String {
    func blank(_ text: String) -> Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    if !blank(onAir.title) { return onAir.title }
    return blank(station) ? streamUrl : station
}

/// The station's codec and bitrate, as the codec pill shows them: "AAC 128 kbps", "MP3", or
/// nothing.
public func liveCodecLine(_ details: RadioDetails) -> String {
    let name = details.codec.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    let codec = name == "UNKNOWN" ? "" : name
    let rate = details.bitrate > 0 ? "\(details.bitrate) kbps" : ""
    return [codec, rate].filter { !$0.isEmpty }.joined(separator: " ")
}

/// How long the listener has been on a station: "0:42", "12:04", "1:02:03".
public func listenedFor(_ ms: Int) -> String {
    let total = max(ms, 0) / 1_000
    let hours = total / 3_600
    let minutes = (total % 3_600) / 60
    let seconds = total % 60
    func two(_ n: Int) -> String { n < 10 ? "0\(n)" : "\(n)" }
    return hours > 0 ? "\(hours):\(two(minutes)):\(two(seconds))" : "\(minutes):\(two(seconds))"
}

/// A song a search found, as the live heart weighs it.
public struct HeartCandidate: Sendable, Equatable {
    public var id: String
    public var title: String
    public var artist: String
    public var inLibrary: Bool

    public init(id: String, title: String, artist: String, inLibrary: Bool) {
        self.id = id
        self.title = title
        self.artist = artist
        self.inLibrary = inLibrary
    }
}

/// The search to run for the song on air.
public func heartQuery(_ onAir: OnAir) -> String {
    [onAir.artist, onAir.title].filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.joined(separator: " ")
}

/// How sure a comparison must be before the heart stars a song.
let heartConfidence = 0.85

/// The one song the heart stars for what is on air, or nil when no search result is surely it:
/// the title and the artist must both agree (case, punctuation, accents and "feat." credits
/// aside), and a different version (a remix, a live take) never counts. A song in the library
/// wins over one from outside it.
public func heartMatch(_ onAir: OnAir, _ candidates: [HeartCandidate]) -> HeartCandidate? {
    func blank(_ text: String) -> Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    guard onAir.named, !blank(onAir.artist) else { return nil }
    let sure = candidates.enumerated().compactMap { place, candidate -> (HeartCandidate, Double, Int)? in
        guard !blank(candidate.title), !blank(candidate.artist) else { return nil }
        let match = SongIdentity.same(onAir.title, onAir.artist, candidate.title, candidate.artist)
        guard match.verdict == .same, match.confidence >= heartConfidence else { return nil }
        return (candidate, match.confidence, place)
    }
    return sure.min { a, b in
        if a.0.inLibrary != b.0.inLibrary { return a.0.inLibrary }
        if a.1 != b.1 { return a.1 > b.1 }
        return a.2 < b.2
    }?.0
}

/// What the live player shows for a station: its title and the line under it, the station's
/// name and stream, what is on air, and the station's details.
public struct LiveShown: Sendable, Equatable {
    public let title: String
    public let subtitle: String
    public let station: String
    public let streamUrl: String
    public let onAir: OnAir
    public let details: RadioDetails

    /// The cover to show: the song's artwork, else the station's logo; empty for the station's
    /// server cover or the drawn one.
    public var cover: String { onAir.artwork.isEmpty ? details.logo : onAir.artwork }
}

/// What the live player shows for the item `id`, from what its stream named last.
public func liveShown(_ id: String, streamTitle: String?, streamUrl: String? = nil) -> LiveShown? {
    guard let (stream, station) = radioOf(id) else { return nil }
    let details = radioDetailsOf(id)
    let name = station.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? stream : station
    let air = onAir(streamTitle, streamUrl: streamUrl, station: name)
    return LiveShown(title: liveTitle(air, station: name, streamUrl: stream), subtitle: liveSubtitle(air, station: name, details: details),
                     station: name, streamUrl: stream, onAir: air, details: details)
}

/// What the live player shows for the item `id`, from the metadata block its stream sent last.
public func liveShown(_ id: String, _ meta: IcyMeta?) -> LiveShown? {
    liveShown(id, streamTitle: meta?.title, streamUrl: meta?.url)
}

/// The lock screen's and headset's buttons for what plays now. A live station has no length and
/// no seeking; its Next and Previous step through the stations it was started from, and stop at
/// the ends. A song keeps every button.
public struct RemoteButtons: Sendable, Equatable {
    public var live: Bool
    /// Whether the lock screen is given a length.
    public var showsDuration: Bool
    public var seek: Bool
    public var changePosition: Bool
    public var skipInterval: Bool
    public var next: Bool
    public var previous: Bool

    public init(live: Bool, showsDuration: Bool, seek: Bool, changePosition: Bool, skipInterval: Bool, next: Bool, previous: Bool) {
        self.live = live
        self.showsDuration = showsDuration
        self.seek = seek
        self.changePosition = changePosition
        self.skipInterval = skipInterval
        self.next = next
        self.previous = previous
    }

    /// The buttons for the queue `queueIds` playing the entry at `current`.
    public static func of(_ queueIds: [String], current: Int) -> RemoteButtons {
        guard let lineup = liveLineup(queueIds, current: current) else {
            return RemoteButtons(live: false, showsDuration: true, seek: true, changePosition: true, skipInterval: false, next: true, previous: true)
        }
        return RemoteButtons(live: true, showsDuration: false, seek: false, changePosition: false, skipInterval: false,
                             next: lineup.hasNext, previous: lineup.hasPrevious)
    }
}
