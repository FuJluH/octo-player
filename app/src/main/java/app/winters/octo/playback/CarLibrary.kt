package app.winters.octo.playback

import android.content.ContentResolver
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import androidx.annotation.DrawableRes
import androidx.annotation.OptIn
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.util.UnstableApi
import androidx.media3.session.MediaConstants
import app.winters.octo.catalog.AlbumEntity
import app.winters.octo.catalog.ArtistEntity
import app.winters.octo.catalog.CatalogDao
import app.winters.octo.catalog.PlaylistSummary
import app.winters.octo.catalog.SongIdentity
import app.winters.octo.catalog.TrackEntity
import app.winters.octo.catalog.UserDao
import app.winters.octo.catalog.byLatestPlay
import app.winters.octo.catalog.byPlayCount
import app.winters.octo.catalog.matchKey
import app.winters.octo.design.OctoIcons
import app.winters.octo.listening.PlayHistory
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import javax.inject.Inject
import javax.inject.Singleton

// The music as a car sees it: four tabs to browse, lists that play from the
// chosen song, search, and requests like "play Drake on Octo".
@Singleton
class CarLibrary @Inject constructor(
    @ApplicationContext private val context: Context,
    private val catalog: CatalogDao,
    private val user: UserDao,
    private val history: PlayHistory,
    private val playlists: PlaylistStore,
) {
    fun root(): MediaItem = folder(CarNode.Root, "Octo")

    // What a car's tabs are built from: how many songs there are, the
    // playlists and their sizes, and how many songs are liked.
    val changes: Flow<Unit> = combine(
        catalog.libraryTrackCount(),
        playlists.playlists.map { lists -> lists.map { it.id to it.songCount } },
        user.likedCount(),
        ::Triple,
    ).distinctUntilChanged().map { }

    // What is inside one place in the tree, a page at a time.
    suspend fun children(parentId: String, page: Int, pageSize: Int): List<MediaItem> {
        val all = when (val node = parseCarId(parentId)) {
            CarNode.Root -> tabs()
            CarNode.Recent -> {
                val albums = byLatestPlay(history.albums.first(), 20)
                val songs = byPlayCount(history.tracks.first(), 20)
                albums.map { albumItem(it, group = "Recently played") } +
                    songs.map { songItem(it, CarNode.MostPlayed, group = "Most played") }
            }
            CarNode.Playlists -> {
                val summaries = playlists.playlists.first()
                val liked = user.likedCount().first()
                val likedItem = if (liked > 0) listOf(likedItem(liked)) else emptyList()
                likedItem + summaries.filterNot { isToolPlaylist(it.name) }.map(::playlistItem)
            }
            CarNode.Albums -> catalog.albums().first().map { albumItem(it) }
            CarNode.Artists -> catalog.artists().first().map(::artistItem)
            is CarNode.Artist -> catalog.artistAlbums(node.id).first().map { albumItem(it) }
            is CarNode.Album, is CarNode.Playlist, CarNode.Liked -> songsOf(node).map { songItem(it, node) }
            else -> emptyList()
        }
        return all.drop(page * pageSize).take(pageSize)
    }

    // One item by its id, for a car that asks about a single place or song.
    suspend fun lookup(id: String): MediaItem? = when (val node = parseCarId(id)) {
        CarNode.Root -> root()
        CarNode.Recent, CarNode.Playlists, CarNode.Albums, CarNode.Artists -> tabs().first { it.mediaId == id }
        CarNode.Liked -> likedItem(user.likedCount().first())
        is CarNode.Album -> catalog.album(node.id).first()?.let { albumItem(it) }
        is CarNode.Artist -> catalog.artist(node.id).first()?.let(::artistItem)
        is CarNode.Playlist -> playlists.playlists.first().firstOrNull { it.id == node.id }?.let(::playlistItem)
        is CarNode.Song -> catalog.track(node.trackId)?.let { songItem(it, node.list) }
        CarNode.MostPlayed, null -> null
    }

    // The songs to play for a choice made in the car, and where to start.
    suspend fun playFor(id: String): Pair<List<String>, Int>? = when (val node = parseCarId(id)) {
        is CarNode.Album, is CarNode.Playlist, CarNode.Liked -> songsOf(node).map { it.id } to 0
        is CarNode.Song -> {
            val list = node.list?.let { songsOf(it).map(TrackEntity::id) } ?: listOf(node.trackId)
            list to startIndex(list, node.trackId)
        }
        else -> null
    }

    // Songs, albums and artists matching what was typed or said.
    suspend fun search(query: String): List<MediaItem> {
        val q = query.trim()
        if (q.isEmpty()) return emptyList()
        return catalog.searchTracks(q, 30).map { songItem(it, null) } +
            catalog.searchAlbums(q, 15).map { albumItem(it) } +
            catalog.searchArtists(q, 10).map(::artistItem)
    }

    // A spoken request, like "play Nothing Was the Same". An album or artist
    // named exactly (case, accents and punctuation aside) wins, then songs
    // that match; saying nothing in particular shuffles everything.
    suspend fun forVoice(query: String): Pair<List<String>, Boolean> {
        val q = query.trim()
        if (q.isEmpty()) return catalog.allTrackIds() to true
        val name = matchKey(q)
        val album = catalog.searchAlbums(q, 5).firstOrNull { name.isNotEmpty() && matchKey(it.title) == name }
        if (album != null) return catalog.albumTrackIds(album.id) to false
        val artist = catalog.searchArtists(q, 5).firstOrNull { SongIdentity.sameArtistName(it.name, q) }
        if (artist != null) {
            val ids = catalog.artistAlbums(artist.id).first().flatMap { catalog.albumTrackIds(it.id) }
            return ids to true
        }
        return catalog.searchTracks(q, 50).map { it.id } to false
    }

    // Lets a car app read the covers of the items it was just sent. Icons
    // from the app's own drawables need no grant.
    fun grantArtwork(packageName: String, items: List<MediaItem>) {
        items.mapNotNull { it.mediaMetadata.artworkUri }.filter { it.scheme == ContentResolver.SCHEME_CONTENT }.forEach {
            context.grantUriPermission(packageName, it, Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
    }

    private suspend fun songsOf(node: CarNode): List<TrackEntity> = when (node) {
        is CarNode.Album -> catalog.albumTracks(node.id).first()
        is CarNode.Playlist -> user.playlistTracks(node.id).first().map { it.track }
        CarNode.Liked -> user.likedTracks().first()
        CarNode.MostPlayed -> byPlayCount(history.tracks.first(), 20)
        else -> emptyList()
    }

    private fun tabs() = listOf(
        folder(CarNode.Recent, "Recent", icon = OctoIcons.History),
        folder(CarNode.Playlists, "Playlists", icon = OctoIcons.Playlists),
        folder(CarNode.Albums, "Albums", grid = true, icon = OctoIcons.Album),
        folder(CarNode.Artists, "Artists", icon = OctoIcons.Artist),
    )

    private fun likedItem(count: Int) = listItem(CarNode.Liked, "Liked songs", "$count songs", null)

    private fun playlistItem(playlist: PlaylistSummary) =
        listItem(CarNode.Playlist(playlist.id), playlist.name, "${playlist.songCount} songs", playlist.covers.firstOrNull())

    private fun folder(node: CarNode, title: String, grid: Boolean = false, @DrawableRes icon: Int? = null) = item(
        node,
        MediaMetadata.Builder()
            .setTitle(title)
            .setArtworkUri(icon?.let(::drawableUri))
            .setIsBrowsable(true)
            .setIsPlayable(false)
            .setExtras(if (grid) gridStyle() else null),
    )

    private fun albumItem(album: AlbumEntity, group: String? = null) = item(
        CarNode.Album(album.id),
        MediaMetadata.Builder()
            .setTitle(album.title)
            .setArtist(album.artist)
            .setSubtitle(album.artist)
            .setArtworkUri(album.artwork?.let(ArtworkProvider::uriFor))
            .setIsBrowsable(true)
            .setIsPlayable(true)
            .setMediaType(MediaMetadata.MEDIA_TYPE_ALBUM)
            .setExtras(group?.let(::groupTitle)),
    )

    private fun artistItem(artist: ArtistEntity) = item(
        CarNode.Artist(artist.id),
        MediaMetadata.Builder()
            .setTitle(artist.name)
            .setIsBrowsable(true)
            .setIsPlayable(false)
            .setMediaType(MediaMetadata.MEDIA_TYPE_ARTIST)
            .setExtras(gridStyle()),
    )

    private fun listItem(node: CarNode, title: String, subtitle: String, cover: String?) = item(
        node,
        MediaMetadata.Builder()
            .setTitle(title)
            .setSubtitle(subtitle)
            .setArtworkUri(cover?.let(ArtworkProvider::uriFor))
            .setIsBrowsable(true)
            .setIsPlayable(true)
            .setMediaType(MediaMetadata.MEDIA_TYPE_PLAYLIST),
    )

    private fun songItem(track: TrackEntity, list: CarNode?, group: String? = null) = item(
        CarNode.Song(track.id, list),
        MediaMetadata.Builder()
            .setTitle(track.title)
            .setArtist(track.artist)
            .setSubtitle(track.artist)
            .setAlbumTitle(track.album)
            .setDurationMs(track.durationMs)
            .setArtworkUri(track.artwork?.let(ArtworkProvider::uriFor))
            .setIsBrowsable(false)
            .setIsPlayable(true)
            .setMediaType(MediaMetadata.MEDIA_TYPE_MUSIC)
            .setExtras(group?.let(::groupTitle)),
    )

    // One of the app's own drawables, at an address a car can read.
    private fun drawableUri(@DrawableRes id: Int): Uri = Uri.Builder()
        .scheme(ContentResolver.SCHEME_ANDROID_RESOURCE)
        .authority(context.packageName)
        .appendPath(context.resources.getResourceTypeName(id))
        .appendPath(context.resources.getResourceEntryName(id))
        .build()

    private fun item(node: CarNode, metadata: MediaMetadata.Builder) =
        MediaItem.Builder().setMediaId(carId(node)).setMediaMetadata(metadata.build()).build()

    // Shows a folder's contents as a grid of covers rather than a list.
    @OptIn(UnstableApi::class)
    private fun gridStyle() = Bundle().apply {
        putInt(MediaConstants.EXTRAS_KEY_CONTENT_STYLE_BROWSABLE, MediaConstants.EXTRAS_VALUE_CONTENT_STYLE_GRID_ITEM)
        putInt(MediaConstants.EXTRAS_KEY_CONTENT_STYLE_PLAYABLE, MediaConstants.EXTRAS_VALUE_CONTENT_STYLE_GRID_ITEM)
    }

    // Groups items under a heading, like "Recently played".
    @OptIn(UnstableApi::class)
    private fun groupTitle(title: String) = Bundle().apply {
        putString(MediaConstants.EXTRAS_KEY_CONTENT_STYLE_GROUP_TITLE, title)
    }
}
