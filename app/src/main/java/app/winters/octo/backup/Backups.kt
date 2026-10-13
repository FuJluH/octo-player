package app.winters.octo.backup

import android.content.Context
import android.net.Uri
import app.winters.octo.catalog.AlbumEntity
import app.winters.octo.catalog.ArtistEntity
import app.winters.octo.catalog.CatalogDao
import app.winters.octo.catalog.FavouritesDao
import app.winters.octo.catalog.PinKind
import app.winters.octo.catalog.SongKeyRow
import app.winters.octo.catalog.TrackEntity
import app.winters.octo.catalog.UserDao
import app.winters.octo.data.SessionStore
import app.winters.octo.device.FolderRules
import app.winters.octo.favourites.FavouriteStore
import app.winters.octo.favourites.PinKey
import app.winters.octo.favourites.PinStore
import app.winters.octo.listening.FavouriteKind
import app.winters.octo.listening.ListenBrainzStore
import app.winters.octo.liveradio.LiveRadioStore
import app.winters.octo.lyrics.LyricsLookSettings
import app.winters.octo.lyrics.LyricsTiming
import app.winters.octo.offline.OfflineSettings
import app.winters.octo.playback.LikeStore
import app.winters.octo.playback.PlaylistStore
import app.winters.octo.playback.RatingStore
import app.winters.octo.player.PlayerSettings
import app.winters.octo.playlists.PlaylistSyncStore
import app.winters.octo.server.QueueSync
import app.winters.octo.sort.SortSettings
import app.winters.octo.sound.EqPreset
import app.winters.octo.sound.SoundEngine
import app.winters.octo.sound.UserPresets
import app.winters.octo.home.encodeHomeSections
import app.winters.octo.home.homeSectionOrder
import app.winters.octo.ui.home.HomePrefs
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.withContext
import java.io.ByteArrayOutputStream
import javax.inject.Inject
import javax.inject.Singleton

// The largest backup read. Even a big library's backup is a few megabytes.
private const val MAX_BACKUP_BYTES = 32 * 1024 * 1024

// Saves the app's settings, playlists, likes, ratings, favourites, pins and
// kept live radio stations to a file the listener picks, and puts them back
// from one. Sign-in secrets are never written: only the server's address
// and user name, for reference, and no ListenBrainz token at all.
@Singleton
class Backups @Inject constructor(
    @ApplicationContext private val context: Context,
    private val player: PlayerSettings,
    private val sound: SoundEngine,
    private val presets: UserPresets,
    private val folders: FolderRules,
    private val queueSync: QueueSync,
    private val playlistSync: PlaylistSyncStore,
    private val sessions: SessionStore,
    private val userDao: UserDao,
    private val catalog: CatalogDao,
    private val playlists: PlaylistStore,
    private val likes: LikeStore,
    private val ratings: RatingStore,
    private val favouritesDao: FavouritesDao,
    private val favourites: FavouriteStore,
    private val pins: PinStore,
    private val lyrics: LyricsTiming,
    private val lyricsLook: LyricsLookSettings,
    private val offline: OfflineSettings,
    private val listenBrainz: ListenBrainzStore,
    private val sorts: SortSettings,
    private val home: HomePrefs,
    liveRadioStore: LiveRadioStore,
) {
    private val liveRadio = LiveRadioBackup(liveRadioStore)

    // Everything as it is now.
    suspend fun make(now: Long = System.currentTimeMillis()): Backup = withContext(Dispatchers.IO) {
        val (playerPrefs, streamPrefs) = player.snapshot()
        val (perOutput, profiles) = sound.saved()
        val songsByPlaylist = userDao.phonePlaylistSongKeys().groupBy { it.playlistId }
        val albums = catalog.albums().first().associateBy { it.id }
        val artists = catalog.artists().first().associateBy { it.id }
        val playlistNames = userDao.playlists().first().associate { it.id to it.name }
        val tracks = catalog.tracks().first().associateBy { it.id }
        Backup(
            createdAt = now,
            player = playerPrefs,
            streaming = streamPrefs,
            sound = SoundBackup(perOutput, profiles),
            presets = presets.saved().map { PresetBackup(it.name, it.gains) },
            library = LibraryBackup(
                excludedFolders = folders.excluded.first().sorted(),
                syncQueue = queueSync.enabled.first(),
                newPlaylistsOnServer = playlistSync.newOnServer.first(),
            ),
            server = sessions.read().inUse?.let { ServerBackup(plainAddress(it.serverUrl), it.username) },
            playlists = userDao.phonePlaylists().sortedBy { it.createdAt }.map { playlist ->
                PlaylistBackup(playlist.name, songsByPlaylist[playlist.id].orEmpty().map { it.toKey() })
            },
            likes = userDao.likedSongKeys().map { it.toKey() },
            ratings = userDao.ratedSongKeys().mapNotNull { row -> row.rating?.let { RatedSong(row.toKey(), it) } },
            favouriteAlbums = favouritesDao.likedAlbumRows().sortedBy { it.likedAt }.map { albumKey(it.relinkKey, albums[it.albumId]) },
            favouriteArtists = favouritesDao.likedArtistRows().sortedBy { it.likedAt }.map { artistKey(it.relinkKey, artists[it.artistId]) },
            pins = favouritesDao.pins().mapNotNull { pin ->
                when (PinKind.of(pin.kind)) {
                    PinKind.Album -> albumKey(pin.relinkKey, albums[pin.itemId])
                    PinKind.Artist -> artistKey(pin.relinkKey, artists[pin.itemId])
                    PinKind.Playlist -> playlistNames[pin.itemId]?.let { HeldKey(name = it) }
                    null -> null
                }?.let { PinBackup(pin.kind, it) }
            },
            lyrics = LyricsBackup(
                keepScreenOn = lyrics.keepScreenOn.first(),
                offsets = lyrics.offsets().mapNotNull { (id, ms) -> tracks[id]?.let { LyricsOffsetBackup(it.toKey(), ms) } }
                    .sortedBy { it.song.relinkKey },
                look = lyricsLook.current(),
                outputOffsets = lyrics.outputOffsets().toSortedMap(),
            ),
            offline = offline.prefs.first().toBackup(playlistNames),
            listenBrainz = listenBrainz.current().let { ListenBrainzBackup(it.enabled, it.sendPlays, it.nowPlaying) },
            homeSections = encodeHomeSections(home.homeSections.first()),
            sortOrders = sorts.saved(),
            keptStations = liveRadio.saved(),
        )
    }

    // Writes a backup to a picked file. False when it could not be written.
    suspend fun save(uri: Uri): Boolean = withContext(Dispatchers.IO) {
        val text = encodeBackup(make())
        runCatching {
            context.contentResolver.openOutputStream(uri, "wt")?.use { it.write(text.toByteArray(Charsets.UTF_8)) } != null
        }.getOrDefault(false)
    }

    // Reads a picked file.
    suspend fun read(uri: Uri): BackupRead = withContext(Dispatchers.IO) {
        val bytes = runCatching {
            context.contentResolver.openInputStream(uri)?.use { input ->
                val out = ByteArrayOutputStream()
                val buffer = ByteArray(64 * 1024)
                while (out.size() < MAX_BACKUP_BYTES) {
                    val read = input.read(buffer)
                    if (read < 0) break
                    out.write(buffer, 0, read)
                }
                out.toByteArray()
            }
        }.getOrNull() ?: return@withContext BackupRead.NotABackup
        decodeBackup(String(bytes, Charsets.UTF_8))
    }

    // What restoring would do with the library as it is now.
    suspend fun plan(backup: Backup): RestorePlan = withContext(Dispatchers.IO) {
        planRestore(
            backup,
            catalog.tracks().first(),
            userDao.playlists().first().map { it.name },
            albums = catalog.albums().first().map { Named(it.id, it.searchKey, it.title, it.artist) },
            artists = catalog.artists().first().map { Named(it.id, it.searchKey, it.name) },
        )
    }

    // Puts a backup's settings back, and makes its playlists, likes and
    // ratings as planned. Songs go through the same stores as when the
    // listener does it, so a connected server follows as usual.
    suspend fun restore(backup: Backup, plan: RestorePlan) = withContext(Dispatchers.IO) {
        val playerPrefs = backup.player
        val streamPrefs = backup.streaming
        if (playerPrefs != null || streamPrefs != null) {
            val (currentPlayer, currentStream) = player.snapshot()
            player.restore(playerPrefs ?: currentPlayer, streamPrefs ?: currentStream)
        }
        backup.sound?.let { sound.restore(it.perOutput, it.profiles) }
        presets.restore(backup.presets.map { EqPreset(it.name, it.gains) })
        backup.library?.let { library ->
            folders.setExcluded(library.excludedFolders.toSet())
            queueSync.setEnabled(library.syncQueue)
            playlistSync.setNewOnServer(library.newPlaylistsOnServer)
        }
        backup.listenBrainz?.let { listenBrainz.restoreChoices(it.enabled, it.sendPlays, it.nowPlaying) }
        backup.homeSections?.let { home.setHomeSections(homeSectionOrder(it)) }
        sorts.restore(backup.sortOrders)
        liveRadio.restore(backup)
        backup.lyrics?.let { lyrics.setKeepScreenOn(it.keepScreenOn) }
        backup.lyrics?.look?.let { lyricsLook.restore(it) }
        plan.lyricsOffsets.forEach { (id, ms) -> lyrics.setOffset(id, ms) }
        backup.lyrics?.outputOffsets?.forEach { (output, ms) -> lyrics.setOutputOffset(output, ms) }
        // Playlists by name, with the ones made here, so pins can find them.
        val playlistIds = userDao.playlists().first().associate { it.name.trim().lowercase() to it.id }.toMutableMap()
        plan.playlists.filter { it.trackIds.isNotEmpty() || it.total == 0 }.forEach {
            playlistIds[it.name.trim().lowercase()] = playlists.create(it.name, it.trackIds)
        }
        plan.likes.forEach { id -> if (!userDao.isLiked(id)) likes.toggle(id) }
        plan.ratings.forEach { (id, stars) -> ratings.rate(id, stars) }
        val likedAlbums = favouritesDao.likedAlbumRows().mapTo(HashSet()) { it.albumId }
        plan.favouriteAlbums.filterNot { it in likedAlbums }.forEach { favourites.set(FavouriteKind.Album, it, true) }
        val likedArtists = favouritesDao.likedArtistRows().mapTo(HashSet()) { it.artistId }
        plan.favouriteArtists.filterNot { it in likedArtists }.forEach { favourites.set(FavouriteKind.Artist, it, true) }
        // After the playlists, so the ones kept downloaded can be found by name.
        backup.offline?.let { saved ->
            val kept = plan.keptPlaylists.mapNotNullTo(HashSet()) { playlistIds[it.lowercase()] }
            offline.restore(saved.toPrefs(kept))
        }
        // Added after the pins already here, in the backup's order, while Home has room.
        plan.pins.forEach { pin ->
            val id = if (pin.kind == PinKind.Playlist) playlistIds[pin.target.lowercase()] else pin.target
            if (id != null) pins.pin(PinKey(pin.kind, id))
        }
    }
}

private fun albumKey(relinkKey: String, album: AlbumEntity?) =
    HeldKey(relinkKey = relinkKey, name = album?.title.orEmpty(), artist = album?.artist.orEmpty())

private fun artistKey(relinkKey: String, artist: ArtistEntity?) = HeldKey(relinkKey = relinkKey, name = artist?.name.orEmpty())

private fun TrackEntity.toKey() = SongKey(relinkKey, title, artist, album, durationMs)

private fun SongKeyRow.toKey() = SongKey(
    relinkKey = relinkKey,
    title = title.orEmpty(),
    artist = artist.orEmpty(),
    album = album.orEmpty(),
    durationMs = durationMs ?: 0,
)
