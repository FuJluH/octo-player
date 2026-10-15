import Observation
import OctoKit
import SwiftUI

/// The song a live station has on air, as Octo has it: searched for once each time the song on
/// air changes (search3, weighed by `heartMatch`), and kept by artist and title, so a song heard
/// again costs nothing. Its cover shows on the player and the lock screen, and the heart stars
/// it. Nothing waits for the answer: the title shows at once, the cover when it comes.
@MainActor
@Observable
final class LiveLookup {
    static let shared = LiveLookup()

    /// The song Octo has for a song on air, and whether it is in the library.
    struct Found: Equatable, Sendable {
        let song: Song
        let inLibrary: Bool
    }

    /// Counts answers, so views showing one draw again when it comes.
    private(set) var answers = 0
    /// Told when an answer comes, for the lock screen.
    @ObservationIgnored var onAnswer: (() -> Void)?
    @ObservationIgnored private var cache = LiveLookupCache<Found>()
    @ObservationIgnored private var running: [String: Task<Found?, Never>] = [:]
    /// The server the answers came from; another one starts them over.
    @ObservationIgnored private var server: String?

    private init() {}

    /// What Octo had for `onAir`, when it has been asked already.
    func found(_ onAir: OnAir) -> Found? {
        _ = answers
        guard case .found(let found) = cache[liveLookupKey(onAir)] else { return nil }
        return found
    }

    /// Whether Octo has answered for `onAir`, with a song or with none.
    func answered(_ onAir: OnAir) -> Bool {
        _ = answers
        return cache[liveLookupKey(onAir)] != nil
    }

    /// The cover of the song on air in Octo, when there is one.
    func cover(_ onAir: OnAir) -> (coverArt: String, online: Bool)? {
        guard let found = found(onAir), let coverArt = found.song.coverArt, !coverArt.isEmpty else { return nil }
        return (coverArt, found.song.isExternal)
    }

    /// Asks Octo for `onAir` unless it was asked already, without waiting for the answer.
    func start(_ onAir: OnAir, session: Session) {
        Task { _ = await find(onAir, session: session) }
    }

    /// Octo's song for `onAir`: the answer kept from before, the search already under way, or a
    /// new one. Nil for no song, no server, or no result that is surely it.
    func find(_ onAir: OnAir, session: Session) async -> Found? {
        let key = liveLookupKey(onAir)
        guard !key.isEmpty, let client = session.client else { return nil }
        if server != session.activeId {
            server = session.activeId
            cache = LiveLookupCache<Found>()
            running = [:]
        }
        switch cache[key] {
        case .found(let found): return found
        case .notFound: return nil
        case nil: break
        }
        if let running = running[key] { return await running.value }
        let task = Task<Found?, Never> { [weak self] in
            guard let result = try? await client.search(heartQuery(onAir), artists: 0, albums: 0, songs: 20) else {
                // Not reached: asked again the next time.
                return nil
            }
            let candidates = result.song.map {
                HeartCandidate(id: $0.id, title: $0.title, artist: $0.artist ?? $0.displayArtist ?? "", inLibrary: !$0.isExternal)
            }
            let answer = heartMatch(onAir, candidates).flatMap { match in
                result.song.first { $0.id == match.id }.map { Found(song: $0, inLibrary: match.inLibrary) }
            }
            self?.cache.keep(answer.map { .found($0) } ?? .notFound, for: key)
            return answer
        }
        running[key] = task
        let answer = await task.value
        running[key] = nil
        answers += 1
        onAnswer?()
        return answer
    }
}
