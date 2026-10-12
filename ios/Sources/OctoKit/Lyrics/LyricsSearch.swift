import Foundation

/// What is known about the song on now, for the lookups that go by name.
public struct LyricsSong: Equatable, Sendable {
    public var id: String
    public var title: String
    public var artist: String
    public var album: String
    public var durationMs: Int

    public init(_ id: String, _ title: String, _ artist: String, _ album: String, _ durationMs: Int) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.durationMs = durationMs
    }
}

/// One place lyrics can come from, tried in order. What a `final` source finds is used even when
/// it is plain: it has already chosen. An `unsure` source may answer "none" when it only ran out
/// of time.
public struct LyricsStep: Sendable {
    public var source: LyricsSource
    public var final: Bool
    public var unsure: Bool
    public var fetch: @Sendable () async throws -> Lyrics?

    public init(_ source: LyricsSource, final: Bool = false, unsure: Bool = false, fetch: @escaping @Sendable () async throws -> Lyrics?) {
        self.source = source
        self.final = final
        self.unsure = unsure
        self.fetch = fetch
    }
}

/// What a search found, and whether every source answered. An answer with a source that could
/// not be reached is not saved, so it is asked again. `unsure` is set when a source that may
/// have run out of time said "none"; `pick` names the listener's pick the lyrics came from.
public struct LyricsSearch: Equatable, Sendable {
    public var lyrics: Lyrics?
    public var complete: Bool
    public var askedOnline: Bool
    public var unsure: Bool
    public var pick: String?

    public init(_ lyrics: Lyrics?, complete: Bool, askedOnline: Bool, unsure: Bool = false, pick: String? = nil) {
        self.lyrics = lyrics
        self.complete = complete
        self.askedOnline = askedOnline
        self.unsure = unsure
        self.pick = pick
    }
}

/// Asks each source in order. The first synced lyrics, or any a final source finds, win at once;
/// plain lyrics are kept while the rest are asked for synced ones, and win if none have them. A
/// source that fails, or is cut off by a time limit of its own, is skipped, and the search is
/// then not complete. A search stopped from outside stops.
public func searchInOrder(_ steps: [LyricsStep]) async throws -> LyricsSearch {
    var plain: Lyrics?
    var complete = true
    var askedOnline = false
    var unsure = false
    for step in steps {
        if step.source == .online { askedOnline = true }
        var found: Lyrics?
        do {
            found = try await step.fetch()
        } catch {
            // The whole search was stopped: that goes on. Otherwise the source failed or ran out
            // of its own time.
            try Task.checkCancellation()
            complete = false
            found = nil
        }
        guard let lyrics = found, !lyrics.isEmpty else {
            if step.unsure { unsure = true }
            continue
        }
        if lyrics.synced || step.final { return LyricsSearch(lyrics, complete: complete, askedOnline: askedOnline) }
        if plain == nil { plain = lyrics }
    }
    return LyricsSearch(plain, complete: complete, askedOnline: askedOnline, unsure: unsure)
}

/// Every set of lyrics found for a song to choose from, the sources that could not be reached,
/// and whether the online library may be asked. `serverChoice` is what the server has the song
/// set to ("auto", "none" or a copy's id) when the server keeps lyrics choices for every app,
/// and nil when every choice stays on this phone.
public struct CandidateSearch: Equatable, Sendable {
    public var found: [LyricsCandidate]
    public var missed: Set<LyricsSource>
    public var onlineAllowed: Bool
    public var serverChoice: String?

    public init(_ found: [LyricsCandidate], missed: Set<LyricsSource>, onlineAllowed: Bool, serverChoice: String? = nil) {
        self.found = found
        self.missed = missed
        self.onlineAllowed = onlineAllowed
        self.serverChoice = serverChoice
    }
}

/// What looking up a song's lyrics came to.
public enum LyricsAnswer: Equatable, Sendable {
    case found(Lyrics)
    /// Every source answered, and none had lyrics (or the listener hid them).
    case none
    /// The lookup could not finish: it was cut off, a source could not be reached, or something
    /// went wrong. Nothing is known, so nothing is saved, and it is worth trying again.
    case failed
}

/// Each song's saved lyrics answer, in memory in front of the cache folder, and the rule for what
/// a new search may save: lyrics are kept, and "none" only when every source answered. A search
/// that could not finish keeps nothing, so an older answer stays as it was and the next look asks
/// again.
@MainActor
public final class LyricsAnswers {
    private let cache: LyricsCache
    private let clock: @Sendable () -> Int
    private var recent: [String: CachedLyrics] = [:]
    private var order: [String] = []

    /// The 32 answers used most lately stay in memory.
    public static let kept = 32

    public nonisolated init(_ cache: LyricsCache, clock: @escaping @Sendable () -> Int = { Int(Date().timeIntervalSince1970 * 1000) }) {
        self.cache = cache
        self.clock = clock
    }

    /// The song's answer: the saved one while it stands, or else what `search` finds. `resumed` is
    /// set when the lyrics have just come back on screen, so a "none" found while they were away
    /// is asked again. `away` says whether the lyrics are off screen right now, and is noted with
    /// what is saved.
    public func answer(
        _ songId: String,
        picked: String?,
        onlineAllowed: Bool,
        resumed: Bool,
        away: () -> Bool,
        search: () async throws -> LyricsSearch
    ) async throws -> LyricsAnswer {
        if let known = saved(songId), known.standsFor(picked, now: clock(), onlineAllowed: onlineAllowed),
           !(resumed && known.recheckOnReturn()) {
            remember(songId, known)
            return known.lyrics.map(LyricsAnswer.found) ?? .none
        }
        let found: LyricsSearch
        do {
            found = try await search()
        } catch {
            // Stopped from outside: nothing is saved, and the stop goes on. Cut off by a time
            // limit of its own: it failed.
            try Task.checkCancellation()
            return .failed
        }
        let lyrics = found.lyrics
        if lyrics == nil && !found.complete { return .failed }
        let entry = CachedLyrics(
            savedAt: clock(),
            lyrics: lyrics,
            askedOnline: found.askedOnline,
            lookupVersion: ONLINE_LOOKUP_VERSION,
            pick: found.pick,
            unsure: lyrics == nil && found.unsure,
            away: away()
        )
        remember(songId, entry)
        // Lyrics found while another source could not be reached are shown, but only kept in
        // memory, so that source is asked next time.
        if found.complete { cache.write(songId, entry) }
        return lyrics.map(LyricsAnswer.found) ?? .none
    }

    /// The song's saved answer, from memory or the cache folder.
    public func saved(_ songId: String) -> CachedLyrics? {
        if let entry = recent[songId] { return entry }
        return cache.read(songId)
    }

    /// Keeps an answer in memory and in the cache folder.
    public func keep(_ songId: String, _ entry: CachedLyrics) {
        remember(songId, entry)
        cache.write(songId, entry)
    }

    /// Forgets a song's answer, in memory and in the cache folder.
    public func forget(_ songId: String) {
        recent[songId] = nil
        order.removeAll { $0 == songId }
        cache.drop(songId)
    }

    private func remember(_ songId: String, _ entry: CachedLyrics) {
        recent[songId] = entry
        order.removeAll { $0 == songId }
        order.append(songId)
        while order.count > Self.kept { recent[order.removeFirst()] = nil }
    }
}
