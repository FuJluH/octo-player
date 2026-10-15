import Foundation
import OctoIntents
import OctoKit
import OctoSystem

/// The songs behind each Quick play start, the launcher's quick actions and Siri's "Play my
/// Liked songs".
@MainActor
struct QuickPicks {
    let library: Library

    /// The songs a start plays, in order, and whether to shuffle them. Empty when there are
    /// none, and for Resume, which plays the queue.
    func songs(_ pick: QuickPick) async -> (ids: [String], shuffled: Bool) {
        switch pick {
        case .liked:
            return (await library.likedTracks().map(\.id), true)
        case .recentlyAdded:
            // Newest album first, each in its own order.
            var ids: [String] = []
            for album in await library.recentAlbums(limit: QuickPick.recentAlbums) { ids += await library.albumTracks(album.id).map(\.id) }
            return (ids, false)
        case .albumMix:
            var ids: [String] = []
            let albums = (try? await library.store.randomAlbums(limit: QuickPick.mixAlbums)) ?? []
            for album in albums { ids += await library.albumTracks(album.id).map(\.id) }
            return (ids, true)
        case .resume:
            return ([], false)
        }
    }

    /// Every library song, for a play button with no queue to go back to.
    func everything() async -> [String] { (try? await library.store.allTrackIds()) ?? [] }
}

/// What the widgets' buttons and links, Siri, Shortcuts and the launcher's quick actions ask the
/// player for, carried out in one place.
@MainActor
final class SystemActions: OctoIntentHandling {
    static weak var shared: SystemActions?

    let player: Player
    let router: Router

    init(player: Player, router: Router) {
        self.player = player
        self.router = router
    }

    private var library: Library? { player.data?.library }
    private var picks: QuickPicks? { library.map(QuickPicks.init) }

    /// The words when a start finds nothing.
    static let noSongs = "No songs in your library yet"
    static let noLiked = "No liked songs yet"
    static let nothingToPlay = "Nothing to play"
    static let noRadio = "No songs to start a radio from"

    // MARK: Commands

    /// Carries out a widget command once the queue kept from last time is back. Answers the
    /// words to show when there was nothing to play.
    func run(_ command: WidgetCommand) async -> String? {
        await restored()
        switch command {
        case .play, .quick(.resume):
            return await resumeOrShuffle()
        case .pause:
            player.pause()
        case .next:
            player.next()
        case .previous:
            player.previous()
        case .quick(let pick):
            guard let picks else { return Self.noSongs }
            let (ids, shuffled) = await picks.songs(pick)
            guard !ids.isEmpty else { return pick == .liked ? Self.noLiked : Self.noSongs }
            player.play(ids: ids, shuffled: shuffled)
        }
        return nil
    }

    /// Carries on with the queue, or with none, shuffles everything, as the play button does.
    private func resumeOrShuffle() async -> String? {
        guard player.engine.queue.isEmpty else {
            // A queue that played out starts the song it ended on again from its start.
            if player.engine.state == .ended { player.engine.seek(to: player.engine.queue.current) }
            player.resume()
            return nil
        }
        guard let picks else {
            await player.shuffleLibrary()
            return nil
        }
        let ids = await picks.everything()
        guard !ids.isEmpty else { return Self.noSongs }
        player.play(ids: ids, shuffled: true)
        return nil
    }

    /// Waits up to ten seconds for the saved queue to come back.
    private func restored() async {
        var waits = 0
        while player.restoring && waits < 100 {
            try? await Task.sleep(for: .milliseconds(100))
            waits += 1
        }
    }

    // MARK: Links

    /// A link a widget opened the app with: the full player, or a button's command. A start that
    /// played opens the full player, as the launcher's quick actions do; one with nothing to
    /// play says so.
    func open(_ link: OctoLink) {
        switch link {
        case .open:
            break
        case .player:
            // Asked for with nothing loaded, the player opens as soon as a song loads.
            Task {
                await restored()
                router.drive = .openPlayer
            }
        case .command(let command):
            Task {
                let words = await run(command)
                // Resume with nothing to play plays nothing and says nothing.
                if let words, !Self.resumes(command) {
                    router.show(words)
                } else if case .quick = command {
                    router.drive = .openPlayer
                }
            }
        }
    }

    /// Whether a command is the play button's resume.
    private static func resumes(_ command: WidgetCommand) -> Bool {
        switch command {
        case .play, .quick(.resume): true
        default: false
        }
    }

    // MARK: The launcher's quick actions

    /// Plays what a quick action asks for with the widgets' lists, then opens the player; with
    /// nothing to play it says so.
    func run(_ shortcut: LauncherShortcut) async {
        let words: String?
        switch shortcut {
        case .shuffleAll:
            await restored()
            let ids = await picks?.everything() ?? []
            if ids.isEmpty {
                words = Self.noSongs
            } else {
                player.play(ids: ids, shuffled: true)
                words = nil
            }
        case .liked: words = await run(.quick(.liked))
        case .recentlyAdded: words = await run(.quick(.recentlyAdded))
        case .resume:
            // Resume always counts as started: the player opens, or opens once a song loads.
            _ = await run(.play)
            words = nil
        }
        if let words {
            router.show(words)
        } else {
            router.drive = .openPlayer
        }
    }

    // MARK: Voice

    /// Plays what the words name by the voice rules; no words shuffle everything.
    func playMusic(_ text: String?) async -> String? {
        await restored()
        let words = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        await player.playFromSearch(words)
        guard player.engine.queue.isEmpty else { return nil }
        return words.isEmpty ? Self.noSongs : Self.nothingToPlay
    }

    /// Plays what a spoken request asks for.
    func voice(_ ask: VoiceAsk) async -> String? {
        switch ask {
        case .search(let text): return await playMusic(text)
        case .liked: return await run(.quick(.liked))
        case .resume: return await run(.play)
        case .playlist(let name):
            let key = matchKey(name)
            if let list = await library?.playlists().first(where: { matchKey($0.name) == key }) {
                return await play(MusicItemRef(kind: .playlist, libraryId: list.id, title: list.name))
            }
            return await playMusic(name)
        case .radio(let text):
            guard let item = await find(text).first(where: { $0.kind != .playlist && $0.kind != .liked }) else { return Self.noRadio }
            return await startRadio(item)
        }
    }

    // MARK: Library items

    /// Plays one library item: an album in its order, an artist's songs shuffled, a playlist in
    /// its order, a song on its own, the liked songs shuffled.
    func play(_ item: MusicItemRef) async -> String? {
        await restored()
        guard let library else { return Self.nothingToPlay }
        switch item.kind {
        case .liked:
            return await run(.quick(.liked))
        case .album:
            let ids = await library.albumTracks(item.libraryId).map(\.id)
            guard !ids.isEmpty else { return Self.nothingToPlay }
            player.play(ids: ids, name: item.title)
        case .artist:
            var ids: [String] = []
            for album in await library.artistAlbums(item.libraryId) { ids += await library.albumTracks(album.id).map(\.id) }
            if ids.isEmpty { ids = await library.artistTracks(item.libraryId).map(\.id) }
            guard !ids.isEmpty else { return Self.nothingToPlay }
            player.play(ids: ids, name: item.title, shuffled: true)
        case .playlist:
            let ids = await library.playlistTracks(item.libraryId).map(\.track.id)
            guard !ids.isEmpty else { return Self.nothingToPlay }
            player.play(ids: ids, name: item.title)
        case .song:
            guard await library.track(item.libraryId) != nil else { return Self.nothingToPlay }
            player.play(ids: [item.libraryId])
        }
        return nil
    }

    /// Radio from one library item: a song, or the most played song of an album, artist or
    /// list here, else its first.
    func startRadio(_ item: MusicItemRef) async -> String? {
        await restored()
        guard let library else { return Self.noRadio }
        let tracks: [LibraryTrack]
        switch item.kind {
        case .song: tracks = await library.track(item.libraryId).map { [$0] } ?? []
        case .album: tracks = await library.albumTracks(item.libraryId)
        case .artist: tracks = await library.artistTracks(item.libraryId)
        case .playlist: tracks = await library.playlistTracks(item.libraryId).map(\.track)
        case .liked: tracks = await library.likedTracks()
        }
        guard let first = tracks.first else { return Self.noRadio }
        let ids = Set(tracks.map(\.id))
        let played = await library.playedTracks().filter { ids.contains($0.track.id) }
        let seed = byPlayCount(played, limit: 1).first ?? first
        var song = seed.asSong
        song.id = seed.id
        await player.startRadio(from: song)
        return nil
    }

    /// Library items whose names hold the words: the liked songs when named, then playlists,
    /// artists, albums and songs.
    func find(_ text: String) async -> [MusicItemRef] {
        guard let library else { return [] }
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var items: [MusicItemRef] = []
        if namesLikedSongs(words) { items.append(.liked) }
        let key = searchKey(words)
        if !key.isEmpty {
            items += await library.playlists().filter { searchKey($0.name).contains(key) }.prefix(10)
                .map { MusicItemRef(kind: .playlist, libraryId: $0.id, title: $0.name) }
        }
        let found = await library.search(words, artists: 5, albums: 10, songs: 15)
        items += found.artists.map { MusicItemRef(kind: .artist, libraryId: $0.id, title: $0.name) }
        items += found.albums.map { MusicItemRef(kind: .album, libraryId: $0.id, title: $0.title, subtitle: $0.artist) }
        items += found.tracks.map { MusicItemRef(kind: .song, libraryId: $0.id, title: $0.title, subtitle: $0.artist) }
        return items
    }

    /// What Siri should know by name: the liked songs, the playlists, the artists with the most
    /// songs, and the albums played lately and added lately.
    func suggestions() async -> [MusicItemRef] {
        guard let library else { return [] }
        var items: [MusicItemRef] = []
        if await library.likedCount() > 0 { items.append(.liked) }
        items += await library.playlists().prefix(50).map { MusicItemRef(kind: .playlist, libraryId: $0.id, title: $0.name) }
        let artists = await library.artists().sorted { $0.songCount > $1.songCount }.prefix(100)
        items += artists.map { MusicItemRef(kind: .artist, libraryId: $0.id, title: $0.name) }
        let albums = await library.recentlyPlayedAlbums(limit: 50) + library.recentAlbums(limit: 50)
        items += albums.map { MusicItemRef(kind: .album, libraryId: $0.id, title: $0.title, subtitle: $0.artist) }
        var seen = Set<String>()
        return items.filter { seen.insert($0.id).inserted }
    }

    /// The items with these ids that the library still holds.
    func items(_ ids: [String]) async -> [MusicItemRef] {
        guard let library else { return [] }
        var items: [MusicItemRef] = []
        for id in ids {
            guard let (kind, libraryId) = MusicItemRef.parse(id) else { continue }
            switch kind {
            case .liked: items.append(.liked)
            case .song:
                if let track = await library.track(libraryId) { items.append(MusicItemRef(kind: .song, libraryId: track.id, title: track.title, subtitle: track.artist)) }
            case .album:
                if let album = await library.album(libraryId) { items.append(MusicItemRef(kind: .album, libraryId: album.id, title: album.title, subtitle: album.artist)) }
            case .artist:
                if let artist = await library.artist(libraryId) { items.append(MusicItemRef(kind: .artist, libraryId: artist.id, title: artist.name)) }
            case .playlist:
                if let list = await library.playlist(libraryId) { items.append(MusicItemRef(kind: .playlist, libraryId: list.id, title: list.name)) }
            }
        }
        return items
    }
}
