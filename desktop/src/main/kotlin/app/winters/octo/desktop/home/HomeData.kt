package app.winters.octo.desktop.home

import app.winters.octo.desktop.liveradio.isOctoStation
import app.winters.octo.desktop.liveradio.liveStationsOf
import app.winters.octo.desktop.server.Connection
import app.winters.octo.discovery.CHARTS_ROW
import app.winters.octo.home.HomeSection
import app.winters.octo.server.serverTime
import app.winters.octo.subsonic.Album
import app.winters.octo.subsonic.OCTO_LIST_KINDS
import app.winters.octo.subsonic.AlbumListType
import app.winters.octo.subsonic.Playlist
import app.winters.octo.subsonic.RadioStation
import app.winters.octo.subsonic.SubsonicException
import app.winters.octo.subsonic.TopSongs
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.serialization.Serializable
import app.winters.octo.lists.OctoListGroup
import app.winters.octo.lists.octoListGroups

// How many albums each shelf on Home holds at most. A shelf shows as many
// as fit across the window.
const val SHELF_SIZE = 20

// Home's shelves from the server's own lists, plus the stations an Octo
// server runs: null when it was asked for them and did not answer. The
// rediscovery shelves come from the library the app already holds
// (HomeStore).
data class HomeData(
    val recentlyAdded: List<Album> = emptyList(),
    val recentlyPlayed: List<Album> = emptyList(),
    val mostPlayed: List<Album> = emptyList(),
    val favourites: List<Album> = emptyList(),
    val stations: List<RadioStation>? = emptyList(),
    // The live streams added to the server, for the Live radio shelf; null
    // the same way.
    val live: List<RadioStation>? = emptyList(),
) {
    // No album shelf has anything; the stations are counted apart (HomeStore).
    val isEmpty get() = recentlyAdded.isEmpty() && recentlyPlayed.isEmpty() && mostPlayed.isEmpty() && favourites.isEmpty()
}

// Home's server shelves as a server last gave them: its stations, the
// lists it made for the listener and the first songs of its chart, kept on
// this computer so they show at once.
@Serializable
data class KeptShelves(
    val stations: List<RadioStation> = emptyList(),
    val live: List<RadioStation> = emptyList(),
    val madeForYou: List<Playlist> = emptyList(),
    val chart: TopSongs? = null,
)

// The shelves this app draws on Home, of all Home's sections. The others
// keep their places in the order the listener saved.
val DesktopHomeSections: Set<HomeSection> = setOf(
    HomeSection.RecentlyPlayed,
    HomeSection.MadeForYou,
    HomeSection.Stations,
    HomeSection.InternetRadio,
    HomeSection.YearMixes,
    HomeSection.GenreMixes,
    HomeSection.ArtistMixes,
    HomeSection.CountryMixes,
    HomeSection.RecentlyAdded,
    HomeSection.MostPlayed,
    HomeSection.FavoriteAlbums,
    HomeSection.Charts,
    HomeSection.NotPlayedLately,
    HomeSection.NeverFinished,
    HomeSection.NeverPlayed,
)

// The part of a chart Home's row shows: its first songs.
fun homeChart(top: TopSongs): TopSongs = top.copy(entry = top.entry.filter { it.song != null }.take(CHARTS_ROW))

// Reads Home's shelves at once. A shelf the server cannot give is empty
// rather than failing the page; only when every one fails does it throw.
// The server's stations are read once for two shelves: Octo's own, each a
// list of songs to play (it carries its id as its cover), for Radio, and
// the live streams added to any server, for Live radio. With `stations`
// off (the Radio shelf is hidden) Octo's are not looked for, and with
// `live` off the streams are not; either left out comes back null, and with
// both off the server is not asked at all.
suspend fun loadHome(connection: Connection, stations: Boolean = true, live: Boolean = true): HomeData = coroutineScope {
    val client = connection.client
    suspend fun <T> shelf(read: suspend () -> T): Result<T> =
        runCatching { read() }.onFailure { if (it !is SubsonicException) throw it }
    val added = async { shelf { client.albumList(AlbumListType.NEWEST, SHELF_SIZE) } }
    val played = async { shelf { client.albumList(AlbumListType.RECENT, SHELF_SIZE) } }
    val most = async { shelf { client.albumList(AlbumListType.FREQUENT, SHELF_SIZE) } }
    val starred = async { shelf { newestFavourites(client.starred().album) } }
    val isOcto = connection.isOcto
    val serverStations = async {
        if (live || (stations && isOcto)) runCatching { client.radioStations() } else null
    }
    val shelves = listOf(added.await(), played.await(), most.await(), starred.await())
    shelves.firstOrNull { it.isFailure }?.takeIf { shelves.all { s -> s.isFailure } }?.exceptionOrNull()?.let { throw it }
    HomeData(
        recentlyAdded = shelves[0].getOrDefault(emptyList()),
        recentlyPlayed = shelves[1].getOrDefault(emptyList()),
        mostPlayed = shelves[2].getOrDefault(emptyList()),
        favourites = shelves[3].getOrDefault(emptyList()),
        stations = when {
            !stations -> null
            !isOcto -> emptyList()
            else -> serverStations.await()?.getOrNull()?.filter { isOctoStation(it, isOcto = true) }
        },
        live = if (live) serverStations.await()?.getOrNull()?.let { liveStationsOf(it, isOcto) } else null,
    )
}

// The latest favourite albums, the newest favourite first, as the phone
// shows them.
fun newestFavourites(albums: List<Album>): List<Album> =
    albums.sortedWith(compareByDescending<Album> { serverTime(it.starred) ?: Long.MIN_VALUE }.thenBy { it.id }).take(SHELF_SIZE)

// The lists Octo made for the listener (New Releases, Rediscover, Deep
// Cuts), in that order, from the playlists the sidebar already holds. Only
// an Octo server that makes them marks a playlist so; any other has none.
fun madeForYou(playlists: List<Playlist>): List<Playlist> =
    playlists.filter { it.octoList != null }
        .sortedBy { OCTO_LIST_KINDS.indexOf(it.octoList).takeIf { i -> i >= 0 } ?: OCTO_LIST_KINDS.size }

// The playlists the listener keeps, without the Made for you lists, which
// have a shelf of their own on Home, and, on Octo (`isOcto`), without any
// other list Octo made for `listener`.
fun yourPlaylists(playlists: List<Playlist>, listener: String = "", isOcto: Boolean = false): List<Playlist> {
    val octo = octoLists(playlists, listener, isOcto).flatMap { it.second }.mapTo(HashSet()) { it.id }
    return playlists.filter { it.octoList == null && it.id !in octo }
}

// The lists Octo made for `listener`, by group, from the playlists the
// sidebar holds; none from any other server.
fun octoLists(playlists: List<Playlist>, listener: String, isOcto: Boolean): List<Pair<OctoListGroup, List<Playlist>>> =
    if (isOcto) octoListGroups(playlists, listener) else emptyList()

// The playlists with the pinned ones first, in the order they were pinned,
// as the sidebar lists them.
fun pinnedFirst(playlists: List<Playlist>, pinned: List<String>): List<Playlist> =
    playlists.sortedBy { pinned.indexOf(it.id).takeIf { i -> i >= 0 } ?: Int.MAX_VALUE }
