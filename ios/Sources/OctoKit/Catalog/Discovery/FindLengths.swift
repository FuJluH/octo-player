import Foundation

/// A song's length as a row shows it: the real one once playing it found its listing wrong, else
/// the listed one. Zero when neither is known.
public func shownLengthMs(_ listedMs: Int64, learnedMs: Int64?) -> Int64 { learnedMs ?? max(listedMs, 0) }

/// Lengths learned by playing songs. Half the finds come with no length, and a find's listed
/// length can be another copy's; the player knows the length of the sound once the song opens.
/// `correct` takes the player's length of a song and answers the length to use when the listing
/// was wrong (more than a second off, or missing), nil otherwise; it keeps the correction in
/// memory for every song, so rows and the queue already on screen show it. A find's corrected
/// length is also stored with the find through `store`, so it shows next time too.
public actor FindLengths {
    private let store: @Sendable (String, Int64) async throws -> Int
    private let correct: @Sendable (String, Int64, Int64) async -> Int64?

    /// Finds already stored with their length, so the same song opening again writes nothing.
    private var stored: [String: Int64] = [:]

    public init(store: @escaping @Sendable (String, Int64) async throws -> Int,
                correct: @escaping @Sendable (String, Int64, Int64) async -> Int64?) {
        self.store = store
        self.correct = correct
    }

    /// Takes the player's length of a song listed at `listedMs`.
    public func learn(_ trackId: String, listedMs: Int64, playerMs: Int64) async throws {
        guard let ms = await correct(trackId, listedMs, playerMs) else { return }
        guard isFind(trackId) else { return }
        if stored[trackId] == ms { return }
        stored[trackId] = ms
        do {
            _ = try await store(trackId, ms)
        } catch {
            stored[trackId] = nil
            throw error
        }
    }
}
