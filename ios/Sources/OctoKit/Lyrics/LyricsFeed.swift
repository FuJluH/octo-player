import Foundation

/// What the lyrics view is asked to show: the song on now while lyrics are open, whether the
/// listener hid its lyrics, and anything that means they must be fetched again when it changes
/// (the listener's pick, a retry).
public struct LyricsWanted: Equatable, Sendable {
    public var id: String
    public var hidden: Bool
    public var version: String

    public init(_ id: String, hidden: Bool = false, version: String = "") {
        self.id = id
        self.hidden = hidden
        self.version = version
    }
}

/// What the lyrics view shows.
public enum LyricsState: Equatable, Sendable {
    case hidden
    /// The listener hid this song's lyrics.
    case hiddenForSong
    case loading
    case none
    /// The lookup could not finish (no network, the server did not answer): not "no lyrics", and
    /// worth another try.
    case failed(String)
    case found(String, Lyrics)

    public var lyrics: Lyrics? {
        if case .found(_, let lyrics) = self { return lyrics }
        return nil
    }
}

/// How many times, and how far apart, a failed lookup is asked again before it shows as failed.
public let QUIET_RETRIES = 2
public let QUIET_RETRY_MS = 4_000

/// What the lyrics view shows, following the song while lyrics are open. Lyrics are only looked
/// up while the view is on screen (`watched`). A song that changes while it is off screen shows
/// as loading, never as the last song's lyrics or as "none", and is looked up the moment the
/// view is back. The first lookup each time the view comes back is `resumed`, so a "none" found
/// while it was away is asked again. A lookup that fails shows as Failed and is tried once more
/// when the network comes back; coming back on screen tries again too. Every new song or watched
/// turn stops the lookup under way and starts over.
@MainActor
public final class LyricsFeed {
    private let lookUp: (String, Bool) async throws -> LyricsAnswer
    private let networkBack: () async throws -> Void
    private let sleep: (Int) async throws -> Void
    private let onState: (LyricsState) -> Void

    // What the view shows now, and what it was asked for then.
    private var shown = LyricsState.hidden
    private var shownFor: LyricsWanted?
    // Counts each time the view comes on screen, and the last one a lookup was made in.
    private var turn = 0
    private var lookedIn = -1

    private var wanted: LyricsWanted?
    private var watched: Bool?
    private var on: Int?
    private var started = false
    private var last: (wanted: LyricsWanted?, on: Int?)?
    private var running: Task<Void, Never>?

    public init(
        lookUp: @escaping (String, Bool) async throws -> LyricsAnswer,
        networkBack: @escaping () async throws -> Void,
        sleep: @escaping (Int) async throws -> Void = { try await Task.sleep(nanoseconds: UInt64(max($0, 0)) * 1_000_000) },
        onState: @escaping (LyricsState) -> Void
    ) {
        self.lookUp = lookUp
        self.networkBack = networkBack
        self.sleep = sleep
        self.onState = onState
    }

    /// Starts following, with what is wanted and whether the view is on screen now.
    public func start(wanted: LyricsWanted?, watched: Bool) {
        self.wanted = wanted
        started = true
        setWatched(watched)
        react()
    }

    public func setWanted(_ wanted: LyricsWanted?) {
        self.wanted = wanted
        if started { react() }
    }

    public func setWatched(_ watched: Bool) {
        guard watched != self.watched else { return }
        self.watched = watched
        if watched {
            turn += 1
            on = turn
        } else {
            on = nil
        }
        if started { react() }
    }

    /// Stops following.
    public func stop() {
        running?.cancel()
        running = nil
        started = false
        last = nil
    }

    private func react() {
        if let last, last.wanted == wanted, last.on == on { return }
        last = (wanted, on)
        running?.cancel()
        let song = wanted
        let on = self.on
        running = Task { [weak self] in await self?.follow(song, on) }
    }

    private func show(_ state: LyricsState, for song: LyricsWanted?) {
        if Task.isCancelled { return }
        shown = state
        shownFor = song
        onState(state)
    }

    // A lookup that throws is a failure, never "none"; a stop from outside stops.
    private func safeLookUp(_ id: String, _ resumed: Bool) async -> LyricsAnswer? {
        do {
            return try await lookUp(id, resumed)
        } catch {
            return Task.isCancelled ? nil : .failed
        }
    }

    private func follow(_ song: LyricsWanted?, _ on: Int?) async {
        guard let song else {
            show(.hidden, for: nil)
            return
        }
        if song.hidden {
            show(.hiddenForSong, for: song)
            return
        }
        // Off screen: nothing is looked up, and another song waits as loading.
        guard let on else {
            if shownFor != song { show(.loading, for: song) }
            return
        }
        let resumed = on != lookedIn
        lookedIn = on
        // Lyrics or "none" for this song stay while they are checked.
        let keeps: Bool
        switch shown {
        case .found, .none: keeps = true
        default: keeps = false
        }
        if shownFor != song || !keeps { show(.loading, for: song) }
        guard var answer = await safeLookUp(song.id, resumed) else { return }
        // The server may still be looking (it keeps going after telling us "not yet"), so ask
        // again quietly a couple of times before saying anything failed.
        var quietTries = 0
        while answer == .failed && quietTries < QUIET_RETRIES {
            quietTries += 1
            do { try await sleep(QUIET_RETRY_MS) } catch { return }
            guard let next = await safeLookUp(song.id, false) else { return }
            answer = next
        }
        if answer == .failed {
            show(.failed(song.id), for: song)
            do { try await networkBack() } catch { return }
            if Task.isCancelled { return }
            show(.loading, for: song)
            guard let next = await safeLookUp(song.id, false) else { return }
            answer = next
        }
        switch answer {
        case .found(let lyrics): show(.found(song.id, lyrics), for: song)
        case .none: show(.none, for: song)
        case .failed: show(.failed(song.id), for: song)
        }
    }
}
