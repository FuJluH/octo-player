import Foundation

// Who decides a song's lyrics, when the server keeps a choice for every app (it lists the
// octoLyrics extension) and this phone keeps its own (LyricsChoices):
//
// - A pick or a hide made on this phone wins on this phone, over whatever the server chose,
//   automatic or pinned. It is how this phone keeps the song file's or a .lrc file's lyrics,
//   which the server cannot see.
// - Choosing one of the server's copies, or "Automatic", sends it to the server and clears this
//   phone's own pick and hide for the song, so the two can never disagree.
// - Hiding sends "none" to the server and hides the song here too. Showing again sends "auto"
//   and shows the song here, keeping a pick this phone made before the hide.
// - The server's answer is final: plain lyrics from it are used as they are, and the online
//   library is asked directly only when the server cannot be reached, since the server asks it
//   itself and may have been told to show none.
// - After any choice sent to the server, the song's saved lyrics are dropped and fetched again
//   at once.
// - A server without the extension changes nothing: every choice stays on this phone.

/// The OpenSubsonic extension an Octo server lists while it looks lyrics up itself.
public let OCTO_LYRICS = "octoLyrics"

/// The server's choice for a song when nothing is pinned: it finds the lyrics itself.
public let LYRICS_AUTO = "auto"

/// The server's choice for a song whose lyrics are hidden.
public let LYRICS_NONE = "none"

/// Whether the server keeps lyrics choices for every app, going by the extensions it listed.
public func offersLyricsChoices(_ extensions: [String]) -> Bool { extensions.contains("\(OCTO_LYRICS):1") }

/// How the server is asked for a song's lyrics.
public enum ServerLyricsCall: Sendable {
    /// By artist and title, the older call, for a server without songLyrics.
    case byName
    /// By song id (songLyrics version 1): timed lines.
    case bySongId
    /// By song id with enhanced=true (songLyrics version 2): word timings too.
    case withWords
}

public func serverLyricsCall(_ extensions: [String]) -> ServerLyricsCall {
    let versions = extensions.filter { $0.hasPrefix("songLyrics:") }.compactMap { Int($0.dropFirst("songLyrics:".count)) }
    guard let highest = versions.max() else { return .byName }
    return highest >= 2 ? .withWords : .bySongId
}

/// A value shared by the steps of one lookup.
private final class Flag: @unchecked Sendable {
    var on = false
}

/// The sources a song's lyrics are looked for in, in order. When the song is on a server that
/// keeps lyrics choices (`serverDecides`), its answer is final and the online library is only
/// asked when the server could not be reached. Such a server looks lyrics up itself and answers
/// "none" when its few seconds run out, so its "none" is unsure. A source that is nil is not
/// there for this song.
public func lyricsSteps(
    server: @escaping @Sendable () async throws -> Lyrics?,
    serverDecides: Bool,
    songFile: (@Sendable () async throws -> Lyrics?)?,
    lyricsFile: (@Sendable () async throws -> Lyrics?)?,
    online: (@Sendable () async throws -> Lyrics?)?
) -> [LyricsStep] {
    let serverAnswered = Flag()
    var steps = [LyricsStep(.server, final: serverDecides, unsure: serverDecides) {
        let found = try await server()
        serverAnswered.on = true
        return found
    }]
    if let songFile { steps.append(LyricsStep(.songFile, fetch: songFile)) }
    if let lyricsFile { steps.append(LyricsStep(.lyricsFile, fetch: lyricsFile)) }
    if let online {
        steps.append(LyricsStep(.online) { serverDecides && serverAnswered.on ? nil : try await online() })
    }
    return steps
}

/// A source's name as the listener knows it, from the server's name for it.
public func lyricsSourceName(_ key: String) -> String {
    let trimmed = key.trimWhitespace()
    switch trimmed.lowercased() {
    case "kugou": return "KuGou"
    case "lrclib": return "LRCLIB"
    case "netease": return "NetEase"
    case "lyricsovh": return "Lyrics.ovh"
    case "", "pinned": return "your server"
    default: return trimmed.prefix(1).uppercased() + trimmed.dropFirst()
    }
}

extension Lyrics {
    /// Where a song's lyrics came from, in plain words, for the lyrics menu: "From KuGou, word by
    /// word", "From LRCLIB", "From your server".
    public func sourceLine() -> String {
        let pinned = source == .server ? serverPick.map { String($0.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).first ?? "") } : nil
        let from = pinned.map { "From \(lyricsSourceName($0))" } ?? source.label
        return kindOf(self) == .words ? "\(from), word by word" : from
    }
}

/// A candidate's first line in the chooser: where it is from, in plain words, or "Automatic"
/// for letting the server find them.
public func candidateLabel(_ candidate: LyricsCandidate) -> String {
    if case .onServer(let choice) = candidate.pick {
        if choice == LYRICS_AUTO { return "Automatic" }
        return "From \(lyricsSourceName(candidate.source.isBlankText ? prefixBeforeColon(choice) : candidate.source))"
    }
    switch candidate.origin {
    case .server, .serverCopy: return LyricsSource.server.label
    case .songFile: return LyricsSource.songFile.label
    case .lyricsFile: return LyricsSource.lyricsFile.label
    case .onlineMatch, .onlineSearch: return LyricsSource.online.label
    }
}

// The part of an id before its colon, or nothing when it has none.
private func prefixBeforeColon(_ text: String) -> String {
    guard let colon = text.firstIndex(of: ":") else { return "" }
    return String(text[..<colon])
}

/// How the server says a copy is timed.
public func serverKindOf(_ kind: String) -> LyricsKind {
    switch kind.trimWhitespace().lowercased() {
    case "word": .words
    case "line": .lines
    case "instrumental": .instrumental
    default: .plain
    }
}

extension ServerLyricsCandidate {
    /// A copy the server holds, as an entry to choose from.
    public func asCandidate() -> LyricsCandidate {
        LyricsCandidate(
            .onServer(id),
            .serverCopy,
            nil,
            title: title,
            artist: artist,
            album: album ?? "",
            durationMs: max(duration ?? 0, 0) * 1000,
            source: source.isBlankText ? prefixBeforeColon(id) : source,
            serverKind: serverKindOf(kind),
            serverPreview: preview
        )
    }
}

/// The chooser's "Automatic" entry, which lets the server find the lyrics itself. While that is
/// what the server does, it carries the lyrics the server answers with; while a copy is pinned or
/// the lyrics are hidden, the server's answer is not its own find, so it carries none.
public func automaticCandidate(_ serverChoice: String, _ answer: Lyrics?) -> LyricsCandidate {
    LyricsCandidate(.onServer(LYRICS_AUTO), .server, answer.flatMap { serverChoice == LYRICS_AUTO && !$0.isEmpty ? $0 : nil })
}

/// Everything to choose from when the server keeps the choice: its automatic answer, the copies
/// its sources hold, then the lyrics only this phone has. `copies` is nil when the server could
/// not be reached.
public func serverCandidates(_ copies: LyricsCandidates?, _ answer: Lyrics?, _ local: [LyricsCandidate]) -> [LyricsCandidate] {
    var list: [LyricsCandidate] = []
    if copies != nil || answer != nil { list.append(automaticCandidate(copies?.choice ?? LYRICS_AUTO, answer)) }
    for copy in copies?.candidate ?? [] where !copy.id.isBlankText { list.append(copy.asCandidate()) }
    return list + local
}

/// Which entry in the chooser is showing now. When the server keeps the choice (`serverChoice`
/// is not nil), lyrics that came from the server are its choice: the copy it pinned, or its
/// automatic answer. Anything else is told by where the lyrics came from.
public func showingPick(_ serverChoice: String?, _ showing: Lyrics?) -> LyricsPick? {
    guard let showing else { return nil }
    if let serverChoice, showing.source == .server {
        return serverChoice == LYRICS_NONE ? nil : .onServer(serverChoice)
    }
    return pickOf(showing)
}

/// Whether a song's saved answer no longer matches what the server has chosen for it (changed
/// from another app or device), so it is fetched again. Only an answer the usual order found
/// counts: lyrics this phone picked stand, whatever the server chose.
public func servedStale(_ cached: CachedLyrics?, _ serverChoice: String) -> Bool {
    guard let cached, cached.pick == nil else { return false }
    let lyrics = cached.lyrics
    let fromServer = lyrics?.source == .server
    switch serverChoice {
    case LYRICS_AUTO: return fromServer && lyrics?.serverPick != nil
    case LYRICS_NONE: return fromServer
    default: return !fromServer || lyrics?.serverPick != serverChoice
    }
}

/// What a search typed in the chooser asks the server for, as a title and an artist: "artist -
/// title" gives both; anything else is a title, by the song's own artist.
public func splitLyricsSearch(_ query: String) -> (title: String, artist: String?) {
    let words = query.trimWhitespace()
    if let range = words.range(of: " - ") {
        let artist = String(words[..<range.lowerBound]).trimWhitespace()
        let title = String(words[range.upperBound...]).trimWhitespace()
        if !artist.isEmpty && !title.isEmpty { return (title, artist) }
    }
    return (words, nil)
}

/// Sends a choice to the server, then brings this phone in line with it and forgets the song's
/// saved lyrics, so they are fetched again. When the server cannot take it, this throws and
/// nothing on the phone changes.
public nonisolated(nonsending) func sendServerChoice(
    _ songId: String,
    _ choice: String,
    _ choices: LyricsChoices,
    send: (String) async throws -> Void,
    forget: () async -> Void,
    showAgain: Bool = false
) async throws {
    try await send(choice)
    await forget()
    if choice == LYRICS_NONE {
        choices.hide(songId)
    } else if showAgain {
        choices.show(songId)
    } else {
        choices.clear(songId)
    }
}
