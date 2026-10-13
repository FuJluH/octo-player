package app.winters.octo.ui.nav

import androidx.navigation3.runtime.NavKey
import app.winters.octo.ui.settings.SettingsPage
import app.winters.octo.query.LibraryQuery
import kotlinx.serialization.Serializable

@Serializable data object HomeRoute : NavKey
@Serializable data object SearchRoute : NavKey
@Serializable data object LibraryRoute : NavKey
@Serializable data object SettingsRoute : NavKey

// One page of Settings, and the row a search result points at, if any.
@Serializable data class SettingsPageRoute(val page: SettingsPage, val highlight: String? = null) : NavKey

@Serializable data class AlbumRoute(val id: String) : NavKey
@Serializable data class ArtistRoute(val id: String) : NavKey

// An album or artist on the server, not in the library, by the server's id.
@Serializable data class OnlineAlbumRoute(val id: String) : NavKey
@Serializable data class OnlineArtistRoute(val id: String) : NavKey

@Serializable data object AlbumsRoute : NavKey
@Serializable data object ArtistsRoute : NavKey
@Serializable data object SongsRoute : NavKey
@Serializable data object GenresRoute : NavKey
@Serializable data class GenreRoute(val name: String) : NavKey
@Serializable data object FoldersRoute : NavKey
@Serializable data object PlaylistsRoute : NavKey

// What is worth fixing in the library's files, and one check's songs.
@Serializable data object LibraryHealthRoute : NavKey
@Serializable data class HealthCheckRoute(val check: String) : NavKey

// Songs deleted from the server's disk, still in its trash.
@Serializable data object HealthTrashRoute : NavKey

// Liked songs: the Favourites page, opened on its songs. The way in for
// anything that means hearted songs, and what a back stack saved when this
// was a page of its own still lands on.
@Serializable data object LikedRoute : NavKey

// Liked songs, favourite albums and favourite artists. From the Favourite
// albums shelf it opens on the albums.
@Serializable data class FavouritesRoute(val albums: Boolean = false) : NavKey
@Serializable data object DownloadsRoute : NavKey
@Serializable data class PlaylistRoute(val id: String) : NavKey

// A live list: songs picked by rules, kept on the phone.
@Serializable data class LiveListRoute(val id: String) : NavKey

// A live list's editor: an existing one by `id`, or a new one, begun from
// `start` (a page's filters) when given.
@Serializable data class LiveListEditRoute(val id: String? = null, val start: LibraryQuery? = null) : NavKey
@Serializable data object SignInRoute : NavKey

// The sign-in form, starting from the saved connection to change it.
@Serializable data object EditConnectionRoute : NavKey

// What the sign-in form is for, opened from the list of servers.
@Serializable
enum class ServerForm {
    // Keep another server without leaving the one in use.
    Add,

    // Change a kept server's details.
    Edit,

    // Sign in again to a kept server, which then is the one in use.
    SignIn,
}

// The sign-in form for one of the kept servers (`id`), or a new one, with a
// note to show first (why its password is asked for).
@Serializable data class ServerFormRoute(val form: ServerForm, val id: String? = null, val note: String? = null) : NavKey
@Serializable data object OctoAdminRoute : NavKey
@Serializable data object ImportRoute : NavKey

// Family on the server in use: what the account may do, requests, devices and, for a
// manager, the members and the requests waiting.
@Serializable data object FamilyRoute : NavKey

// Signing up or signing in, filled in from a family link.
@Serializable data class FamilyJoinRoute(val link: String) : NavKey

// The charts and new songs, on an Octo server that has them.
@Serializable data object ChartsRoute : NavKey

// The server's shared links, and its internet radio stations.
@Serializable data object SharesRoute : NavKey
@Serializable data object RadioStationsRoute : NavKey

// The equalizer and everything else that shapes the sound.
@Serializable data object SoundRoute : NavKey

// The order of Home's shelves, and which ones show.
@Serializable data object HomeSectionsRoute : NavKey

// What was played: the latest plays by day, or the most played songs.
@Serializable data class HistoryRoute(val mostPlayed: Boolean = false) : NavKey
