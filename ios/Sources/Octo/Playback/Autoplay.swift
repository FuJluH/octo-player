import Foundation
import OctoKit

/// Keeps music playing when the queue runs out. Near the end of the last song, with repeat off,
/// it adds songs like it, marked as Autoplay's so the queue can tell them from the listener's
/// own. The player calls `check` whenever the song, the queue, repeat or playing changes.
/// Turning the setting off stops it adding. A station the server keeps going is left to it.
@MainActor
final class Autoplay {
    private let data: DataServices
    private unowned let player: Player
    private var enabled: Bool { AppSettings.shared.player.autoplay }

    /// Watches the last song until it is time, then adds; for one entry at a time.
    private var watch: Task<Void, Never>?
    private var watching: String?
    /// The last song Autoplay added after, so it tries once per song.
    private var doneFor: String?

    init(data: DataServices, player: Player) {
        self.data = data
        self.player = player
    }

    func check() {
        let engine = player.engine
        let item = engine.currentItem
        let key = item?.entryId
        let last = enabled && key != nil && key != doneFor && !(item?.isRadioStation ?? true)
            && engine.repeatMode == .off && engine.queue.nextOnEnd == nil
            && (engine.isPlaying || engine.ended) && !player.stationKeepsGoing
        guard last, let key, let item else {
            // Paused, repeat on, songs added, a station kept going, or switched off: stand down.
            stop()
            return
        }
        if watch != nil && watching == key { return }
        stop()
        watching = key
        watch = Task { [weak self] in await self?.watchAndAdd(key, seedId: item.trackId) }
    }

    func stop() {
        watch?.cancel()
        watch = nil
        watching = nil
    }

    private func watchAndAdd(_ key: String, seedId: String) async {
        let engine = player.engine
        let lead = autoplayLead(crossfadeMs: engine.automix.maxOverlapMs)
        while !autoplayDue(enabled, repeatMode: engine.repeatMode, hasNext: engine.queue.nextOnEnd != nil,
                           remainingMs: remainingMs(), leadMs: lead) {
            try? await Task.sleep(for: .milliseconds(autoplayWatchEveryMs))
            if Task.isCancelled { return }
        }
        let entries = engine.queue.items
        let queued = entries.map(\.trackId)
        // The listener's own songs keep Autoplay near their taste.
        let anchors = Array(entries.suffix(30).filter { $0.source != .autoplay }.map(\.trackId).filter { $0 != seedId }.suffix(10).reversed())
        let ids = await picksAfter(seedId, queued: queued, anchors: anchors)
        let items = await player.playable.items(ids: ids, source: .autoplay).compactMap { $0 }
        // Stood down meanwhile (paused, repeat on, songs added, switched off): nothing is marked
        // or added.
        if Task.isCancelled { return }
        // Tried once for this song, whatever came of it.
        doneFor = key
        if watching == key {
            watch = nil
            watching = nil
        }
        if items.isEmpty {
            playbackLog.info("autoplay: nothing to add")
            return
        }
        // Only if the song is still the last one, the setting still on, and no station is kept
        // going meanwhile.
        guard enabled, engine.currentItem?.entryId == key, engine.queue.nextOnEnd == nil, !player.stationKeepsGoing else { return }
        let first = engine.queue.count
        let ended = engine.ended
        player.addAutoplay(items)
        // The song already ended while the server answered: carry on.
        if ended {
            engine.seek(to: first)
            engine.play()
        }
        playbackLog.info("autoplay: added \(items.count)")
    }

    /// Octo's radio for the seed and the listener's own recent songs (`anchors`), from the
    /// library and the server's suggestions; else the library's songs by the same artist, then in
    /// the same genre.
    private func picksAfter(_ seedId: String, queued: [String], anchors: [String]) async -> [String] {
        guard let seed = await seedTrack(seedId) else { return [] }
        let recent = await data.library.playedTracks().sorted { $0.lastPlayedAt > $1.lastPlayedAt }
            .prefix(autoplayRecentPlays).map(\.track.id)
        let exclude = Set(queued + recent + [seed.id])
        let own = await data.library.tracks(ids: anchors)
        var byId: [String: LibraryTrack] = [:]
        for track in own { byId[track.id] = track }
        let seeds = [seed] + anchors.compactMap { byId[$0] }
        let mixed = await LibraryRadio(data: data).songsLike(seeds, count: autoplayBatch, exclude: exclude, before: Array(queued.suffix(30)))
        if !mixed.isEmpty { return mixed }
        return autoplayPicks(similar: [], sameArtist: await sameArtist(seed).shuffled(), sameGenre: await sameGenre(seed).shuffled(),
                             exclude: exclude)
    }

    /// The song as the library has it, or as found online.
    private func seedTrack(_ id: String) async -> LibraryTrack? {
        await data.library.songs(ids: [id]).first
    }

    /// The library's songs by the seed's artist. A song found online is matched to a library
    /// artist by name.
    private func sameArtist(_ seed: LibraryTrack) async -> [String] {
        let artistIds = isFind(seed.id) ? await data.library.artistsWithKeys([searchKey(seed.artist)]).map(\.id) : [seed.artistId]
        var ids: [String] = []
        for artist in artistIds {
            for album in await data.library.artistAlbums(artist) {
                ids += await data.library.albumTracks(album.id).map(\.id)
            }
        }
        return ids
    }

    private func sameGenre(_ seed: LibraryTrack) async -> [String] {
        seed.genre.trimmingCharacters(in: .whitespaces).isEmpty ? [] : await data.library.genreTrackIds(seed.genre)
    }

    /// How long until the song ends, in real time at the current speed.
    private func remainingMs() -> Int {
        let engine = player.engine
        guard let item = engine.currentItem else { return 0 }
        let length = engine.measuredMs.flatMap { $0 > 0 ? $0 : nil } ?? item.durationMs
        guard length > 0 else { return 0 }
        return Int(Double(max(0, length - engine.positionMs)) / Double(engine.pace.speed))
    }
}
