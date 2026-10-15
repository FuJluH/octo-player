import Foundation

/// What a live station has on air, read from its ICY metadata: the song and its artist, the
/// song's artwork, or, while it names no song (between songs, an ad, the station's own spot),
/// nothing but maybe a tagline such as "LA's #1 Hit Music Station". Every Octo app reads a
/// stream's titles with these rules.
public struct OnAir: Sendable, Equatable, Hashable {
    public var title: String
    public var artist: String
    public var artwork: String
    public var tagline: String

    public init(_ title: String = "", _ artist: String = "", _ artwork: String = "", tagline: String = "") {
        self.title = title
        self.artist = artist
        self.artwork = artwork
        self.tagline = tagline
    }

    /// Whether the station names a song now.
    public var named: Bool { !title.isEmpty }

    public static let nothing = OnAir()
}

/// What a station has on air from the title its stream sends (the StreamTitle value) and the
/// address it sends with it (StreamArtwork, or StreamUrl), for a station called `station`.
///
/// - "Artist - Title" splits at the first " - "; a title with no dash is a title alone; "-
///   Advertisement" is a title alone too.
/// - iHeart's `Artist - text="Title" song_spot="M" amgArtworkURL="..." ...` shows only the artist
///   and the text (or `title="..."` and `artist="..."`), with the artwork; a song_spot other than
///   "M" is not a song, and what it says that is not the station's name is its tagline.
/// - Nothing is named by an empty title, one with no letter or digit, the station's own name, a
///   playout cart code ("GWMR0446000") or an ad ("Advertisement").
/// - The address is the artwork when it is an image (Radio Paradise's covers, SomaFM's logos).
public func onAir(_ streamTitle: String?, streamUrl: String? = nil, station: String = "") -> OnAir {
    let raw = String(squash(streamTitle ?? "").prefix(onAirTitleMax))
    if raw.isEmpty { return .nothing }
    let stationKey = plainKey(station)
    let text = raw as NSString
    let pairs = onAirKeyValue.matches(in: raw, range: NSRange(location: 0, length: text.length))
    if let first = pairs.first {
        var keys: [String: String] = [:]
        for pair in pairs {
            keys[text.substring(with: pair.range(at: 1)).lowercased()] = squash(text.substring(with: pair.range(at: 2)))
        }
        let lead = trimEnd(squash(text.substring(to: first.range.location)), "- ").trimmingCharacters(in: .whitespacesAndNewlines)
        let title = nonEmpty(keys["text"]) ?? keys["title"] ?? ""
        let artist = nonEmpty(keys["artist"]) ?? lead
        let spot = (keys["song_spot"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let music = spot.isEmpty || spot.lowercased() == "m"
        let artwork = keys["amgartworkurl"].flatMap { isWebAddress($0) ? sharperArtwork($0) : nil }
            ?? keys["artworkurl"].flatMap { isWebAddress($0) ? $0 : nil }
            ?? imageAddress(streamUrl)
        if !music || namesNothing(title, artist, stationKey) {
            return OnAir(tagline: taglineOf([artist, title], stationKey))
        }
        return OnAir(title, artist, artwork)
    }
    let (artist, title) = splitArtist(raw)
    if namesNothing(title, artist, stationKey) { return .nothing }
    return OnAir(title, artist, imageAddress(streamUrl))
}

/// What a station has on air from one metadata block it sent.
public func onAir(_ meta: IcyMeta?, station: String = "") -> OnAir {
    guard let meta else { return .nothing }
    return onAir(meta.title, streamUrl: meta.url, station: station)
}

/// The longest title read; the rest is cut.
let onAirTitleMax = 1_000

/// The longest side asked of a station's artwork, in pixels.
public let liveArtworkSize = 600

/// iHeart's artwork asked for at the size the player draws: its catalog addresses say
/// `ops=fit(200,200)`, which is blurry on a phone, and it serves any fit up to the original.
/// Other addresses stay as they are.
public func sharperArtwork(_ url: String) -> String {
    guard let mark = url.range(of: "://") else { return url }
    let host = String(url[mark.upperBound...].prefix { $0 != "/" }.prefix { $0 != ":" }).lowercased()
    guard host == "iheart.com" || host.hasSuffix(".iheart.com") else { return url }
    let text = url as NSString
    var out = ""
    var at = 0
    for match in iHeartFit.matches(in: url, range: NSRange(location: 0, length: text.length)) {
        out += text.substring(with: NSRange(location: at, length: match.range.location - at))
        let whole = text.substring(with: match.range)
        if let size = Int(text.substring(with: match.range(at: 1))), size < liveArtworkSize {
            out += "fit(\(liveArtworkSize),\(liveArtworkSize))"
        } else {
            out += whole
        }
        at = match.range.location + match.range.length
    }
    out += text.substring(from: at)
    return out
}

private let iHeartFit = try! NSRegularExpression(pattern: #"fit\((\d+),\s*\d+\)"#)

/// "Artist - Title" at its first " - ", or a title alone.
private func splitArtist(_ text: String) -> (artist: String, title: String) {
    let bare = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if bare.hasPrefix("-") { return ("", trimStart(bare, "- ")) }
    guard let dash = bare.range(of: " - ") else { return ("", bare) }
    let artist = bare[..<dash.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
    let title = trimStart(bare[dash.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines), "- ")
    return (artist, title)
}

private func namesNothing(_ title: String, _ artist: String, _ stationKey: String) -> Bool {
    if !title.contains(where: isLetterOrDigit) { return true }
    let titleKey = plainKey(title)
    if !stationKey.isEmpty && artist.isEmpty && titleKey == stationKey { return true }
    if !stationKey.isEmpty && plainKey("\(artist) \(title)") == stationKey { return true }
    if artist.isEmpty && (onAirAds.contains(titleKey) || isCartCode(title)) { return true }
    return false
}

private func taglineOf(_ parts: [String], _ stationKey: String) -> String {
    parts.first { part in part.contains(where: isLetterOrDigit) && plainKey(part) != stationKey && !isCartCode(part) } ?? ""
}

/// Letters, digits and single spaces only, in lower case, for comparing names.
private func plainKey(_ text: String) -> String {
    text.lowercased().filter { isLetterOrDigit($0) || $0 == " " }.split(separator: " ").joined(separator: " ")
}

private func isLetterOrDigit(_ c: Character) -> Bool { c.isLetter || c.isNumber }

/// Trimmed, with each run of white space one space.
private func squash(_ text: String) -> String {
    text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
}

private func nonEmpty(_ text: String?) -> String? {
    guard let text, !text.isEmpty else { return nil }
    return text
}

private func trimStart(_ text: String, _ characters: String) -> String {
    String(text.drop { characters.contains($0) })
}

private func trimEnd(_ text: String, _ characters: String) -> String {
    var out = Substring(text)
    while let last = out.last, characters.contains(last) { out.removeLast() }
    return String(out)
}

private func isWebAddress(_ text: String) -> Bool {
    let lower = text.lowercased()
    return lower.hasPrefix("https://") || lower.hasPrefix("http://")
}

/// The address when it is a picture's (by the end of its path), else empty.
private func imageAddress(_ address: String?) -> String {
    let text = (address ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    guard isWebAddress(text) else { return "" }
    let path = text.before("?").before("#").lowercased()
    return onAirImageEndings.contains(where: path.hasSuffix) ? text : ""
}

/// One word of capitals and digits with both in it, six or more long: a playout system's cart
/// number, sent where a title would be.
private func isCartCode(_ text: String) -> Bool {
    let scalars = text.unicodeScalars
    guard scalars.count >= 6 else { return false }
    var digit = false
    var capital = false
    for scalar in scalars {
        if ("0"..."9").contains(scalar) {
            digit = true
        } else if ("A"..."Z").contains(scalar) {
            capital = true
        } else if scalar != "_" {
            return false
        }
    }
    return digit && capital
}

/// key="value" pairs, as iHeart puts them after the artist.
private let onAirKeyValue = try! NSRegularExpression(pattern: #"([A-Za-z][A-Za-z0-9_]*)="([^"]*)""#)

private let onAirAds: Set<String> = ["advertisement", "advert", "advertising", "commercial", "commercials", "ad break", "spot break", "adbreak"]

private let onAirImageEndings = [".jpg", ".jpeg", ".png", ".webp", ".gif"]
