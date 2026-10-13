package app.winters.octo.ambient

import androidx.navigation3.runtime.NavKey
import app.winters.octo.ui.nav.AlbumRoute
import app.winters.octo.ui.nav.AlbumsRoute
import app.winters.octo.ui.nav.ArtistRoute
import app.winters.octo.ui.nav.ArtistsRoute
import app.winters.octo.ui.nav.ChartsRoute
import app.winters.octo.ui.nav.DownloadsRoute
import app.winters.octo.ui.nav.FamilyJoinRoute
import app.winters.octo.ui.nav.FamilyRoute
import app.winters.octo.ui.nav.EditConnectionRoute
import app.winters.octo.ui.nav.FavouritesRoute
import app.winters.octo.ui.nav.FoldersRoute
import app.winters.octo.ui.nav.GenreRoute
import app.winters.octo.ui.nav.GenresRoute
import app.winters.octo.ui.nav.HomeRoute
import app.winters.octo.ui.nav.HomeSectionsRoute
import app.winters.octo.ui.nav.LibraryRoute
import app.winters.octo.ui.nav.LikedRoute
import app.winters.octo.ui.nav.OctoAdminRoute
import app.winters.octo.ui.nav.ImportRoute
import app.winters.octo.ui.nav.OnlineAlbumRoute
import app.winters.octo.ui.nav.ServerListRoute
import app.winters.octo.ui.nav.OnlineArtistRoute
import app.winters.octo.ui.nav.PlaylistRoute
import app.winters.octo.ui.nav.PlaylistsRoute
import app.winters.octo.ui.nav.RadioStationsRoute
import app.winters.octo.ui.nav.SearchRoute
import app.winters.octo.ui.nav.SettingsPageRoute
import app.winters.octo.ui.nav.SettingsRoute
import app.winters.octo.ui.nav.SharesRoute
import app.winters.octo.ui.nav.ServerFormRoute
import app.winters.octo.ui.nav.SignInRoute
import app.winters.octo.ui.nav.SongsRoute
import app.winters.octo.ui.nav.SoundRoute

// Which colours a page glows with.
sealed interface AmbientSource {
    // None: the plain background.
    data object None : AmbientSource

    // The artwork of the song on now.
    data class Playing(val artwork: String?) : AmbientSource

    // The artwork of the album or artist the page shows.
    data class Page(val artwork: String) : AmbientSource
}

// The part of the app a page belongs to. Album, artist, playlist and genre
// pages are library pages wherever they were opened from. A page not listed
// here gets no glow, so a new page is plain until it is given an area.
fun areaOf(route: NavKey?): AmbientArea? = when (route) {
    HomeRoute, ChartsRoute, is ServerListRoute -> AmbientArea.Home
    SearchRoute -> AmbientArea.Search
    LibraryRoute, AlbumsRoute, ArtistsRoute, SongsRoute, GenresRoute, FoldersRoute,
    PlaylistsRoute, LikedRoute, DownloadsRoute, is FavouritesRoute,
    is AlbumRoute, is ArtistRoute, is OnlineAlbumRoute, is OnlineArtistRoute,
    is GenreRoute, is PlaylistRoute,
    -> AmbientArea.Library
    SettingsRoute, SoundRoute, SignInRoute, EditConnectionRoute, is ServerFormRoute, OctoAdminRoute, ImportRoute, FamilyRoute, is FamilyJoinRoute,
    SharesRoute, RadioStationsRoute, is SettingsPageRoute, HomeSectionsRoute,
    -> AmbientArea.Settings
    else -> null
}

// Pages that show one album or artist, and so have artwork of their own.
fun hasOwnArtwork(route: NavKey?): Boolean =
    route is AlbumRoute || route is ArtistRoute || route is OnlineAlbumRoute || route is OnlineArtistRoute

// What the page on top glows with. Settings not read yet count as off, so a
// glow the user turned off never flashes up at launch.
fun ambientSource(
    prefs: AmbientPrefs?,
    route: NavKey?,
    pageArtwork: String?,
    hasTrack: Boolean,
    playingArtwork: String?,
): AmbientSource {
    if (prefs == null) return AmbientSource.None
    val area = areaOf(route) ?: return AmbientSource.None
    if (!prefs.shows(area)) return AmbientSource.None
    if (prefs.pageArtwork && hasOwnArtwork(route) && pageArtwork != null) return AmbientSource.Page(pageArtwork)
    return if (hasTrack) AmbientSource.Playing(playingArtwork) else AmbientSource.None
}
