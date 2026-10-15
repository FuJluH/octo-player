import Foundation
import OctoKit

/// Keeps a station going. Once fewer than `stationTopUpAt` songs come after the one playing and a
/// station's songs are among them, it asks the server for more of that station's songs, once for
/// each end of the queue, and adds them at the end under the same station, leaving out any the
/// station already has queued. When the queue played out while the server answered, the first new song
/// plays. The player calls `check` whenever the song or the queue changes. While it keeps a
/// station going, Autoplay leaves the station's songs alone; when the server has nothing more or
/// cannot answer, Autoplay carries on as it would after any list.
@MainActor
final class StationRefill {
    private let data: DataServices
    private unowned let player: Player
    /// Told when a top-up is over without songs, so Autoplay can look again.
    var settled: () -> Void = {}

    private var task: Task<Void, Never>?
    /// The last queue entry a top-up was asked after, so each end of the queue is asked once.
    private var askedAfter: String?
    /// The last queue entry after which the server had nothing more, or could not answer.
    private var gaveUpAfter: String?

    init(data: DataServices, player: Player) {
        self.data = data
        self.player = player
    }

    /// Whether the server in use sends more of a station's songs.
    private var offered: Bool { player.session.client != nil && offersStationSongs(player.session.extensions) }

    /// The station to top up now, with the last queue entry in play order it would go after.
    private func due() -> (station: QueueSource, tail: String)? {
        guard offered else { return nil }
        return stationTopUp(player.engine.queue)
    }

    /// Whether a station is being kept going from here, so Autoplay stands down.
    var keepsGoing: Bool {
        guard let found = due() else { return false }
        return found.tail != gaveUpAfter
    }

    func check() {
        guard let found = due(), found.tail != askedAfter, case .station(let id, _) = found.station else { return }
        let (station, tail) = found
        askedAfter = tail
        task?.cancel()
        task = Task { [weak self] in await self?.topUp(station, id: id, tail: tail) }
    }

    private func topUp(_ station: QueueSource, id: String, tail: String) async {
        let engine = player.engine
        let queued = stationSongsQueued(engine.queue.items, station: station)
        var items: [QueueItem] = []
        do {
            let tracks = try await data.discovery.moreStationSongs(id, after: queued)
            let have = Set(queued)
            let fresh = tracks.map(\.id).filter { !have.contains($0) }
            items = await player.playable.items(ids: fresh, source: station).compactMap { $0 }
        } catch {
            if isCancellation(error) { return }
            playbackLog.info("station: top-up failed")
        }
        if Task.isCancelled { return }
        task = nil
        // The queue may have moved on while the server answered: only a station still running
        // low in play order takes the songs, leaving out any it gained meanwhile.
        guard !items.isEmpty, let now = due(), now.station == station else {
            gaveUpAfter = tail
            playbackLog.info("station: nothing to add")
            settled()
            return
        }
        let have = Set(stationSongsQueued(engine.queue.items, station: station))
        var seen = Set<String>()
        let adding = items.filter { !have.contains($0.trackId) && seen.insert($0.trackId).inserted }
        guard !adding.isEmpty else {
            gaveUpAfter = tail
            settled()
            return
        }
        let first = engine.queue.count
        let ended = engine.ended
        player.addStationSongs(adding)
        // The queue played out while the server answered: carry on.
        if ended {
            engine.seek(to: first)
            engine.play()
        }
        playbackLog.info("station: added \(adding.count)")
    }
}
