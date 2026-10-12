import Foundation
import OctoKit

/// Octo's radio on the phone: songs like the seeds from the library and, when a server is signed
/// in, from its suggestions, songs it found online among them (see `radioMix`), tuned by the
/// listener's radio settings. Works from the library alone. Start radio and Autoplay both use it.
/// With "Library songs only" on, the server's songs found online are left out.
@MainActor
struct LibraryRadio {
    let data: DataServices

    /// Ids of up to `count` songs like `seeds`, never the first seed or one in `exclude`, spaced
    /// on from the songs in `before` (ids, oldest first). Server trouble only loses its
    /// suggestions.
    func songsLike(_ seeds: [LibraryTrack], count: Int, exclude: Set<String> = [], before: [String] = []) async -> [String] {
        guard let seed = seeds.first else { return [] }
        let prefs = AppSettings.shared.player
        let tuning = prefs.radioTuning
        var suggested: [LibraryTrack] = []
        do {
            suggested = try await data.discovery.radio(seed, count: tuning.suggestions).filter { $0.id != seed.id }
        } catch {
            playbackLog.info("radio: server suggestions failed: \(String(describing: type(of: error)), privacy: .public)")
        }
        let library = await data.library.tracks()
        let liked = await data.library.likedIds()
        var played: [String: PlayedTrack] = [:]
        for track in await data.library.playedTracks() { played[track.track.id] = track }
        let input = RadioInputs(seeds: seeds, library: library, suggested: librarySongsOnly(suggested, hide: prefs.libraryOnly) { isFind($0.id) },
                                before: before, exclude: exclude, liked: liked, played: played, tuning: tuning)
        return await Task.detached(priority: .userInitiated) { input.mix(count) }.value
    }
}

/// What a radio is mixed from, taken on the main actor and mixed off it.
private struct RadioInputs: Sendable {
    let seeds: [LibraryTrack]
    let library: [LibraryTrack]
    let suggested: [LibraryTrack]
    let before: [String]
    let exclude: Set<String>
    let liked: Set<String>
    let played: [String: PlayedTrack]
    let tuning: RadioTuning

    func mix(_ count: Int) -> [String] {
        var byId: [String: LibraryTrack] = [:]
        for track in library { byId[track.id] = track }
        let input = RadioInput(
            seeds: seeds.map(radio), library: library.map(radio), suggested: suggested.map(radio),
            before: before.compactMap { byId[$0] }.map(radio), exclude: exclude, now: Int(Date().timeIntervalSince1970 * 1000),
            tuning: tuning,
            // A song found online is not in `before` above, but its kind still carries the run on.
            beforeOutside: before.map(isFind))
        var random = OctoRandom()
        return radioMix(input, count: count, random: &random).map(\.id)
    }

    /// A phone song as the radio sees it.
    private func radio(_ track: LibraryTrack) -> RadioSong {
        radioSong(track, liked: liked, played: played[track.id])
    }
}
