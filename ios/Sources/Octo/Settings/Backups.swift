import Foundation
import OctoKit

/// The library's part of a backup: phone playlists, likes, ratings, favorites, pins, sort orders
/// and each song's lyrics timing, and putting them back through the same stores as when the
/// listener makes them by hand. The part of the app that keeps the library supplies it.
@MainActor
protocol BackupLibrary: AnyObject {
    func tracks() async -> [BackupTrack]
    func albums() async -> [NamedItem]
    func artists() async -> [NamedItem]
    /// Every playlist on the phone, whichever server it is kept with, the one changed last first.
    func playlistRows() async -> [PlaylistRow]
    /// Playlists that exist only on the phone, oldest first, each song in play order.
    func phonePlaylists() async -> [PlaylistBackup]
    /// Every like, oldest first, songs the library no longer has included.
    func likes() async -> [SongKey]
    /// Every rating made on the phone, oldest first, songs the library no longer has included.
    func ratings() async -> [RatedSong]
    /// Every favorite album, oldest first; one the library no longer has keeps only its key.
    func favoriteAlbums() async -> [HeldKey]
    func favoriteArtists() async -> [HeldKey]
    /// Every pin in row order. A playlist pin is named by the playlist's name alone.
    func pins() async -> [PinBackup]
    func sortOrders() async -> [String: String]
    /// Each library song's own lyrics timing.
    func lyricsOffsets() async -> [LyricsOffsetBackup]

    func makePlaylist(_ name: String, trackIds: [String]) async -> String?
    func isLiked(_ trackId: String) async -> Bool
    func like(_ trackId: String) async
    func rate(_ trackId: String, stars: Int) async
    func favoriteAlbumIds() async -> Set<String>
    func favoriteArtistIds() async -> Set<String>
    func favorite(album id: String) async
    func favorite(artist id: String) async
    /// Pins by id: an album, an artist, or a playlist, which need not be in the library yet.
    func pin(_ kind: PinKind, id: String) async
    func restoreSortOrders(_ orders: [String: String]) async
}

/// Saves the app's settings, playlists, likes, ratings, favorites and pins to a file the
/// listener picks, and puts them back from one. Sign-in secrets are never written: only the
/// server's address and user name, for reference, and no ListenBrainz token at all.
@MainActor
final class Backups {
    static let shared = Backups()

    /// The library's part, once the part of the app that keeps the library is in.
    weak var library: BackupLibrary?

    /// The server's queue sync and new playlists choices, where the Server page and
    /// PlaylistSync keep them.
    private let syncChoices = ServerSyncChoices()

    private init() {}

    /// Everything as it is now.
    func make(session: Session, now: Date = Date()) async -> Backup {
        let settings = AppSettings.shared
        var b = Backup()
        b.createdAt = Int64(now.timeIntervalSince1970 * 1000)
        b.player = settings.player
        b.streaming = settings.stream
        if let sound = SoundStore.live {
            b.sound = SoundBackup(perOutput: sound.backup.perOutput, profiles: sound.backup.profiles)
            b.presets = sound.presets.map { PresetBackup($0.name, $0.gains) }
        }
        b.library = LibraryBackup(
            excludedFolders: settings.excludedFolders.sorted(),
            syncQueue: syncChoices.syncQueue,
            newPlaylistsOnServer: syncChoices.newPlaylistsOnServer
        )
        if let active = session.active, session.client != nil {
            b.server = ServerBackup(address: BackupFile.plainAddress(active.address.absoluteString), username: active.username)
        }
        let names = Dictionary((await library?.playlistRows() ?? []).map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        if let library {
            b.playlists = await library.phonePlaylists()
            b.likes = await library.likes()
            b.ratings = await library.ratings()
            b.favoriteAlbums = await library.favoriteAlbums()
            b.favoriteArtists = await library.favoriteArtists()
            b.pins = await library.pins()
            b.sortOrders = await library.sortOrders()
        }
        b.lyrics = LyricsBackup(
            keepScreenOn: settings.keepScreenOn,
            offsets: (await library?.lyricsOffsets() ?? []).sorted { $0.song.relinkKey < $1.song.relinkKey },
            look: settings.lyricsLook,
            outputOffsets: settings.outputTimings.mapValues(Int64.init)
        )
        var offline = settings.offline
        offline.keptPlaylists = offline.keptPlaylists.compactMap { names[$0] }.sorted()
        b.offline = offline
        let lb = settings.listenBrainz
        b.listenBrainz = ListenBrainzBackup(enabled: lb.enabled, sendPlays: lb.sendPlays, nowPlaying: lb.nowPlaying)
        b.homeSections = encodeHomeSections(settings.homeSections)
        b.keptStations = LiveRadioStore.shared.kept.stations
        return b
    }

    /// The backup as the bytes of its file: UTF-8 JSON, no byte order mark.
    func data(session: Session) async -> Data {
        Data(BackupFile.encode(await make(session: session)).utf8)
    }

    /// Reads a picked file, at most 32 MiB of it.
    nonisolated func read(_ url: URL) async -> BackupRead {
        await Task.detached {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let handle = try? FileHandle(forReadingFrom: url) else { return BackupRead.notABackup }
            defer { try? handle.close() }
            var bytes = Data()
            while bytes.count < BackupFile.maxBytes {
                guard let chunk = try? handle.read(upToCount: 64 * 1024), !chunk.isEmpty else { break }
                bytes.append(chunk)
            }
            return BackupFile.decode(bytes)
        }.value
    }

    /// What restoring would do with the library as it is now.
    func plan(_ backup: Backup) async -> RestorePlan {
        guard let library else { return BackupPlanner.plan(backup, library: [], existingPlaylists: []) }
        let tracks = await library.tracks()
        let playlists = await library.playlistRows().map(\.name)
        let albums = await library.albums()
        let artists = await library.artists()
        // Matching runs over the whole library, so it runs away from the main thread.
        return await Task.detached(priority: .userInitiated) {
            BackupPlanner.plan(backup, library: tracks, existingPlaylists: playlists, albums: albums, artists: artists)
        }.value
    }

    /// Puts a backup's settings back, and makes its playlists, likes and ratings as planned.
    func restore(_ backup: Backup, plan: RestorePlan, lyricsStore: LyricsStore?) async {
        let settings = AppSettings.shared
        if backup.player != nil || backup.streaming != nil {
            settings.restore(player: backup.player ?? settings.player, stream: backup.streaming ?? settings.stream)
            lyricsStore?.online = settings.player.lyricsOnline
        }
        if let sound = backup.sound { SoundStore.live?.restore(perOutput: sound.perOutput, profiles: sound.profiles) }
        SoundStore.live?.restorePresets(backup.presets.map { EqPreset(name: $0.name, gains: $0.gains) })
        if let library = backup.library {
            settings.setExcludedFolders(Set(library.excludedFolders))
            syncChoices.setSyncQueue(library.syncQueue)
            syncChoices.setNewPlaylistsOnServer(library.newPlaylistsOnServer)
        }
        if let lb = backup.listenBrainz {
            ListenBrainzSync.shared.restoreChoices(enabled: lb.enabled, sendPlays: lb.sendPlays, nowPlaying: lb.nowPlaying)
        }
        if let sections = backup.homeSections { settings.setHomeSections(homeSectionOrder(stored: sections)) }
        LiveRadioStore.shared.restore(backup.keptStations)
        await library?.restoreSortOrders(backup.sortOrders)
        if let lyrics = backup.lyrics {
            settings.setKeepScreenOn(lyrics.keepScreenOn)
            if let look = lyrics.look {
                settings.restoreLook(look)
                lyricsStore?.look = look.style == .classic ? .classic : .flowing
            }
            for (output, ms) in lyrics.outputOffsets { settings.setOutputTiming(output, Int(ms)) }
        }
        // Held to the song limit, and dropped at 0, as when set by hand.
        for (id, ms) in plan.lyricsOffsets { LyricsSongTiming.shared.set(id, Int(ms)) }
        // Playlists by name, with the ones made here, so pins and kept playlists can find them.
        var playlistIds: [String: String] = [:]
        for row in await library?.playlistRows() ?? [] { playlistIds[row.name.trimmingCharacters(in: .whitespaces).lowercased()] = row.id }
        for playlist in plan.playlists where !playlist.trackIds.isEmpty || playlist.total == 0 {
            if let id = await library?.makePlaylist(playlist.name, trackIds: playlist.trackIds) {
                playlistIds[playlist.name.trimmingCharacters(in: .whitespaces).lowercased()] = id
            }
        }
        if let library {
            for id in plan.likes where !(await library.isLiked(id)) { await library.like(id) }
            for (id, stars) in plan.ratings { await library.rate(id, stars: stars) }
            let albums = await library.favoriteAlbumIds()
            for id in plan.favoriteAlbums where !albums.contains(id) { await library.favorite(album: id) }
            let artists = await library.favoriteArtistIds()
            for id in plan.favoriteArtists where !artists.contains(id) { await library.favorite(artist: id) }
        }
        // After the playlists, so the ones kept downloaded can be found by name.
        if let offline = backup.offline {
            settings.restoreOffline(offline, keptPlaylistIds: plan.keptPlaylists.compactMap { playlistIds[$0.lowercased()] })
        }
        // Added after the pins already here, in the backup's order.
        for pin in plan.pins {
            let id = pin.kind == .playlist ? playlistIds[pin.target.lowercased()] : pin.target
            if let id { await library?.pin(pin.kind, id: id) }
        }
    }
}
