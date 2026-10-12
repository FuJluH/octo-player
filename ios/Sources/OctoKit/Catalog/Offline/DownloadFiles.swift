import Foundation

/// Longest a name's readable part may be, in UTF-16 units, so the whole name stays well under
/// what file systems allow.
public let downloadNameChars = 80

/// The file a downloaded song is saved as: "Artist - Title [a1b2c3d4].flac". Characters no file
/// system takes are replaced, and the part in brackets comes from the server and the song's id
/// there, so two songs never share a name even when their titles match.
public func downloadFileName(artist: String, title: String, sourceId: String, serverId: String, format: String?) -> String {
    let readable = [artist, title].map(downloadSafePart).filter { !$0.isEmpty }.joined(separator: " - ")
    let stem = downloadTrimEnd(downloadPrefix(readable.isEmpty ? "Song" : readable, utf16Units: downloadNameChars))
    return "\(stem) [\(downloadShortHash("\(sourceId)|\(serverId)"))].\(downloadExtension(for: format))"
}

/// The file ending for a type of audio.
public func downloadExtension(for mimeType: String?) -> String {
    let type = mimeType.map { trimmed($0.lowercased().before(";")) }
    switch type {
    case "audio/mpeg", "audio/mp3": return "mp3"
    case "audio/flac", "audio/x-flac": return "flac"
    case "audio/mp4", "audio/x-m4a", "audio/m4a", "audio/alac": return "m4a"
    case "audio/aac", "audio/aacp": return "aac"
    case "audio/ogg", "audio/vorbis": return "ogg"
    case "audio/opus": return "opus"
    case "audio/wav", "audio/x-wav", "audio/wave", "audio/vnd.wave": return "wav"
    case "audio/aiff", "audio/x-aiff": return "aiff"
    case "audio/ape", "audio/x-ape": return "ape"
    case "audio/wavpack", "audio/x-wavpack": return "wv"
    case "audio/x-ms-wma": return "wma"
    case "audio/webm": return "webm"
    default: return "audio"
    }
}

/// Characters no file system takes in a name.
private let downloadUnsafe = Set("\\/:*?\"<>|".unicodeScalars)

/// Leaves out what a file name cannot hold, and tidies the spaces: control characters and the
/// unsafe ones become spaces, each run of spaces becomes one, and spaces and dots go from the
/// ends.
private func downloadSafePart(_ text: String) -> String {
    var out = String.UnicodeScalarView()
    var inSpace = false
    for scalar in text.unicodeScalars {
        let control = scalar.value <= 0x1F || (0x7F...0x9F).contains(scalar.value)
        let next: Unicode.Scalar = control || downloadUnsafe.contains(scalar) ? " " : scalar
        if downloadAsciiSpace(next) {
            if !inSpace { out.append(" ") }
            inSpace = true
        } else {
            out.append(next)
            inSpace = false
        }
    }
    var scalars = Array(out)
    while let last = scalars.last, last == " " || last == "." { scalars.removeLast() }
    let start = scalars.firstIndex { $0 != " " && $0 != "." } ?? scalars.endIndex
    return String(String.UnicodeScalarView(scalars[start...]))
}

/// Space, tab, line feed, vertical tab, form feed and carriage return.
private func downloadAsciiSpace(_ scalar: Unicode.Scalar) -> Bool {
    scalar == " " || (0x09...0x0D).contains(scalar.value)
}

/// At most `utf16Units` UTF-16 units of the text, never cutting a character in two.
private func downloadPrefix(_ text: String, utf16Units: Int) -> String {
    var count = 0
    var out = String.UnicodeScalarView()
    for scalar in text.unicodeScalars {
        let width = scalar.value > 0xFFFF ? 2 : 1
        if count + width > utf16Units { break }
        count += width
        out.append(scalar)
    }
    return String(out)
}

/// The text less any spaces, dots and dashes at its end.
private func downloadTrimEnd(_ text: String) -> String {
    var scalars = Array(text.unicodeScalars)
    while let last = scalars.last, last == " " || last == "." || last == "-" { scalars.removeLast() }
    return String(String.UnicodeScalarView(scalars))
}

/// The first 4 bytes of the text's SHA-1, as 8 hex digits.
private func downloadShortHash(_ text: String) -> String {
    Hashes.hex(Hashes.sha1(Array(text.utf8)).prefix(4))
}
