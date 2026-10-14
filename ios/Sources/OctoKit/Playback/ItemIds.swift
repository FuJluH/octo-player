import Foundation

// An internet radio station in the queue. Its id carries everything needed to play it, so
// nothing about it is stored anywhere else:
//
//   radio:<url-encoded stream address>:<url-encoded station name>[:hls][:<details>]
//
// Encoding turns every ':' into %3A, so the parts split cleanly. The name may be empty; ":hls"
// marks a stream sent as HLS whose address does not say so (the part is empty when it is not,
// and details follow). Details are what the player shows about the station (logo, codec, place,
// website), url-encoded as `key=value&...`; an id without them still plays. The player opens the
// address as it is; a live stream has no length, so it never crossfades and never counts as a
// play.
public let radioPrefix = "radio:"
private let radioHlsMark = "hls"

public func isRadio(_ id: String) -> Bool { id.hasPrefix(radioPrefix) }

public func radioId(_ streamUrl: String, _ name: String = "", hls: Bool = false, details: RadioDetails = RadioDetails()) -> String {
    let base = radioPrefix + javaEncode(streamUrl.trimmingCharacters(in: .whitespacesAndNewlines)) + ":"
        + javaEncode(name.trimmingCharacters(in: .whitespacesAndNewlines))
    let shown = details.encoded()
    if !shown.isEmpty { return base + ":" + (hls ? radioHlsMark : "") + ":" + javaEncode(shown) }
    return hls ? base + ":" + radioHlsMark : base
}

/// What the player shows about a station besides its name: its logo (an address, or a server
/// cover art id in `coverArt`), how it streams, where it is, its website, its genres and its
/// Radio Browser id.
public struct RadioDetails: Sendable, Equatable, Hashable {
    public var logo: String
    public var coverArt: String
    public var codec: String
    public var bitrate: Int
    public var country: String
    public var countryCode: String
    public var state: String
    public var homepage: String
    public var tags: [String]
    public var uuid: String

    public init(logo: String = "", coverArt: String = "", codec: String = "", bitrate: Int = 0, country: String = "",
                countryCode: String = "", state: String = "", homepage: String = "", tags: [String] = [], uuid: String = "") {
        self.logo = logo
        self.coverArt = coverArt
        self.codec = codec
        self.bitrate = bitrate
        self.country = country
        self.countryCode = countryCode
        self.state = state
        self.homepage = homepage
        self.tags = tags
        self.uuid = uuid
    }

    func encoded() -> String {
        let pairs: [(String, String)] = [
            ("logo", logo),
            ("cover", coverArt),
            ("codec", codec),
            ("kbps", bitrate > 0 ? String(bitrate) : ""),
            ("country", country),
            ("cc", countryCode),
            ("state", state),
            ("home", homepage),
            ("tags", tags.joined(separator: ",")),
            ("uuid", uuid),
        ]
        return pairs.filter { !$0.1.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { $0.0 + "=" + javaEncode($0.1.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .joined(separator: "&")
    }

    static func decoded(_ text: String) -> RadioDetails {
        var values: [String: String] = [:]
        for pair in text.split(separator: "&", omittingEmptySubsequences: false) {
            guard let eq = pair.firstIndex(of: "="), eq != pair.startIndex else { continue }
            values[String(pair[..<eq])] = javaDecode(String(pair[pair.index(after: eq)...]))
        }
        return RadioDetails(
            logo: values["logo"] ?? "",
            coverArt: values["cover"] ?? "",
            codec: values["codec"] ?? "",
            bitrate: values["kbps"].flatMap { Int($0) } ?? 0,
            country: values["country"] ?? "",
            countryCode: values["cc"] ?? "",
            state: values["state"] ?? "",
            homepage: values["home"] ?? "",
            tags: (values["tags"] ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty },
            uuid: values["uuid"] ?? "")
    }
}

/// The parts of a station's id after its prefix.
private func radioParts(_ id: String) -> [String] {
    String(id.dropFirst(radioPrefix.count)).split(separator: ":", omittingEmptySubsequences: false).map(String.init)
}

/// What a station's id says about it beyond its address and name; empty details when it says
/// nothing more.
public func radioDetailsOf(_ id: String) -> RadioDetails {
    guard isRadio(id) else { return RadioDetails() }
    let parts = radioParts(id)
    guard parts.count > 3 else { return RadioDetails() }
    return RadioDetails.decoded(javaDecode(parts[3]))
}

/// Whether a station's id says it streams as HLS.
public func radioIsHls(_ id: String) -> Bool {
    guard isRadio(id) else { return false }
    let parts = radioParts(id)
    return parts.count > 2 && parts[2] == radioHlsMark
}

/// The station's stream address and name, or nil when the id is not one.
public func radioOf(_ id: String) -> (stream: String, name: String)? {
    guard isRadio(id) else { return nil }
    let parts = String(id.dropFirst(radioPrefix.count)).split(separator: ":", omittingEmptySubsequences: false).map(String.init)
    guard let first = parts.first, let stream = Optional(javaDecode(first)),
          !stream.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
    return (stream, parts.count > 1 ? javaDecode(parts[1]) : "")
}

/// A station's title as the lock screen and queue show it: its name, else its address.
public func radioTitle(_ id: String) -> String? {
    guard let (stream, name) = radioOf(id) else { return nil }
    return name.isEmpty ? stream : name
}

/// The artist line of a station.
public let radioArtist = "Radio"

// An audio file opened with Octo from another app that is not a song in the library. Like a
// radio station, its id carries everything needed to play it:
//
//   file:<url-encoded address>:<url-encoded title>:<url-encoded artist>
public let openedFilePrefix = "file:"

public func isOpenedFile(_ id: String) -> Bool { id.hasPrefix(openedFilePrefix) }

/// What an opened file's id holds.
public struct OpenedFile: Sendable, Equatable {
    public var uri: String
    public var title: String
    public var artist: String

    public init(uri: String, title: String, artist: String) {
        self.uri = uri
        self.title = title
        self.artist = artist
    }

    /// The title shown: its own, else the address's last part, else "Audio file".
    public var shownTitle: String {
        if !title.isEmpty { return title }
        let last = URL(string: uri)?.lastPathComponent ?? ""
        return last.isEmpty || last == "/" ? "Audio file" : last
    }
}

public func openedFileId(_ uri: String, _ title: String = "", _ artist: String = "") -> String {
    openedFilePrefix + javaEncode(uri.trimmingCharacters(in: .whitespacesAndNewlines)) + ":"
        + javaEncode(title.trimmingCharacters(in: .whitespacesAndNewlines)) + ":"
        + javaEncode(artist.trimmingCharacters(in: .whitespacesAndNewlines))
}

/// The file's address, title and artist, or nil when the id is not one.
public func openedFileOf(_ id: String) -> OpenedFile? {
    guard isOpenedFile(id) else { return nil }
    let parts = String(id.dropFirst(openedFilePrefix.count)).split(separator: ":", omittingEmptySubsequences: false).map(String.init)
    let uri = parts.first.map(javaDecode) ?? ""
    guard !uri.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
    return OpenedFile(uri: uri, title: parts.count > 1 ? javaDecode(parts[1]) : "", artist: parts.count > 2 ? javaDecode(parts[2]) : "")
}

/// The song a find plays as: the library song it became once downloaded, while the library has
/// it, or else the find itself, streamed.
public func playsAs(findId: String, adoptedId: String, library: Set<String>) -> String {
    library.contains(adoptedId) ? adoptedId : findId
}

/// Where a list asked for starts once its songs are turned into playable ones (`played`, one for
/// each asked, nil for any gone): the song chosen, found by its place, since a find plays under
/// its library song's id and a list may hold a song twice. The first song when the chosen one is
/// gone.
public func chosenStart<T>(_ played: [T?], _ startIndex: Int) -> Int {
    guard played.indices.contains(startIndex), played[startIndex] != nil else { return 0 }
    return played[0..<startIndex].filter { $0 != nil }.count
}

/// UTF-8 form encoding, as Java writes it: letters, digits and `.-*_` as they are, a space as
/// `+`, everything else as %XX.
func javaEncode(_ text: String) -> String { formEncode(text).replacingOccurrences(of: "%20", with: "+") }

/// Reads form encoding back; text that cannot be read is empty.
func javaDecode(_ text: String) -> String { formDecode(text) ?? "" }
