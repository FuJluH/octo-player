import Foundation

// Things in the queue that are not songs of the library, whose ids carry everything needed to
// play them, so nothing about them is stored anywhere else:
//
//   radio:<encoded stream address>:<encoded station name>
//   file:<encoded address>:<encoded title>:<encoded artist>
//
// Encoding turns every ':' into %3A, so the parts split cleanly.

public let radioPrefix = "radio:"
public let openedFilePrefix = "file:"

public func isRadio(_ id: String) -> Bool { id.hasPrefix(radioPrefix) }

public func radioId(streamUrl: String, name: String = "") -> String {
    radioPrefix + formEncoded(streamUrl.trimmingCharacters(in: .whitespacesAndNewlines)) + ":"
        + formEncoded(name.trimmingCharacters(in: .whitespacesAndNewlines))
}

/// The station's stream address and name, or nil when the id is not one.
public func radioOf(_ id: String) -> (stream: String, name: String)? {
    guard isRadio(id) else { return nil }
    let parts = id.dropFirst(radioPrefix.count).split(separator: ":", omittingEmptySubsequences: false).map(String.init)
    guard let stream = parts.first.map(formDecoded), !stream.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
    return (stream, parts.count > 1 ? formDecoded(parts[1]) : "")
}

/// A station as a song for the queue: titled by its name (its address when it has none), by "Radio".
public func radioSong(_ id: String) -> Song? {
    guard let (stream, name) = radioOf(id) else { return nil }
    return Song(id: id, title: name.isEmpty ? stream : name, artist: "Radio")
}

public func isOpenedFile(_ id: String) -> Bool { id.hasPrefix(openedFilePrefix) }

/// What an opened file's id holds.
public struct OpenedFile: Sendable, Equatable {
    public var uri: String
    public var title: String
    public var artist: String
}

public func openedFileId(uri: String, title: String = "", artist: String = "") -> String {
    openedFilePrefix + formEncoded(uri.trimmingCharacters(in: .whitespacesAndNewlines)) + ":"
        + formEncoded(title.trimmingCharacters(in: .whitespacesAndNewlines)) + ":"
        + formEncoded(artist.trimmingCharacters(in: .whitespacesAndNewlines))
}

/// The file's address, title and artist, or nil when the id is not one.
public func openedFileOf(_ id: String) -> OpenedFile? {
    guard isOpenedFile(id) else { return nil }
    let parts = id.dropFirst(openedFilePrefix.count).split(separator: ":", omittingEmptySubsequences: false).map(String.init)
    guard let uri = parts.first.map(formDecoded), !uri.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
    return OpenedFile(uri: uri, title: parts.count > 1 ? formDecoded(parts[1]) : "", artist: parts.count > 2 ? formDecoded(parts[2]) : "")
}

/// An opened file as a song for the queue: its title, else the address's last part, else "Audio file".
public func openedFileSong(_ id: String) -> Song? {
    guard let file = openedFileOf(id) else { return nil }
    let last = URL(string: file.uri)?.lastPathComponent.removingPercentEncoding ?? ""
    let title = file.title.isEmpty ? (last.isEmpty || last == "/" ? "Audio file" : last) : file.title
    return Song(id: id, title: title, artist: file.artist.isEmpty ? nil : file.artist)
}

/// The name a file goes by, without its type: "Song.mp3" is "Song".
public func titleFromName(_ name: String?) -> String? {
    guard let name else { return nil }
    let base = name.range(of: ".", options: .backwards).map { String(name[..<$0.lowerBound]) } ?? name
    let trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

/// Form encoding as Java's URLEncoder writes it: letters, digits and . - * _ stay, a space is a
/// plus, and every other byte is %XX.
public func formEncoded(_ text: String) -> String {
    var out = ""
    for byte in text.utf8 {
        switch byte {
        case UInt8(ascii: "a")...UInt8(ascii: "z"), UInt8(ascii: "A")...UInt8(ascii: "Z"), UInt8(ascii: "0")...UInt8(ascii: "9"),
             UInt8(ascii: "."), UInt8(ascii: "-"), UInt8(ascii: "*"), UInt8(ascii: "_"):
            out.append(Character(UnicodeScalar(byte)))
        case UInt8(ascii: " "):
            out.append("+")
        default:
            out.append(String(format: "%%%02X", byte))
        }
    }
    return out
}

/// Reads form-encoded text: a plus is a space. Text that cannot be read is empty.
public func formDecoded(_ text: String) -> String {
    percentDecoded(text.replacingOccurrences(of: "+", with: " ")) ?? ""
}

/// Reads %XX escapes as UTF-8, or nil when an escape is broken or the bytes are not text.
func percentDecoded(_ text: String) -> String? {
    var bytes: [UInt8] = []
    var iterator = Array(text.utf8)[...]
    while let byte = iterator.popFirst() {
        if byte == UInt8(ascii: "%") {
            guard iterator.count >= 2, let high = hexValue(iterator.popFirst()!), let low = hexValue(iterator.popFirst()!) else { return nil }
            bytes.append(high << 4 | low)
        } else {
            bytes.append(byte)
        }
    }
    return String(bytes: bytes, encoding: .utf8)
}

private func hexValue(_ byte: UInt8) -> UInt8? {
    switch byte {
    case UInt8(ascii: "0")...UInt8(ascii: "9"): byte - UInt8(ascii: "0")
    case UInt8(ascii: "a")...UInt8(ascii: "f"): byte - UInt8(ascii: "a") + 10
    case UInt8(ascii: "A")...UInt8(ascii: "F"): byte - UInt8(ascii: "A") + 10
    default: nil
    }
}
