import Foundation

// An internet radio station in the queue. Its id carries everything needed to play it, so
// nothing about it is stored anywhere else:
//
//   radio:<url-encoded stream address>:<url-encoded station name>
//
// Encoding turns every ':' into %3A, so the two parts split cleanly. The name may be empty. The
// player opens the address as it is; a live stream has no length, so it never crossfades and
// never counts as a play.
public let radioPrefix = "radio:"

public func isRadio(_ id: String) -> Bool { id.hasPrefix(radioPrefix) }

public func radioId(_ streamUrl: String, _ name: String = "") -> String {
    radioPrefix + javaEncode(streamUrl.trimmingCharacters(in: .whitespaces)) + ":" + javaEncode(name.trimmingCharacters(in: .whitespaces))
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
    openedFilePrefix + javaEncode(uri.trimmingCharacters(in: .whitespaces)) + ":"
        + javaEncode(title.trimmingCharacters(in: .whitespaces)) + ":" + javaEncode(artist.trimmingCharacters(in: .whitespaces))
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
