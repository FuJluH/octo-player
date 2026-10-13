package app.winters.octo.desktop.queue

import app.winters.octo.desktop.nav.Page
import app.winters.octo.subsonic.Song

// The name the queue gives a list played from a page when the caller does
// not name it: the page's own list (the playlist, the artist, the genre,
// Songs, Favourites), or, on a page of cards or search, the album when
// every song is from one. Null when there is no name worth showing, and
// the queue says "Up next".
fun queueNameFor(page: Page, songs: List<Song>, playlistName: (String) -> String?): String? {
    val album = songs.takeIf { it.isNotEmpty() }?.map { it.albumId }?.distinct()?.singleOrNull()?.let { songs.first().album }?.takeIf { it.isNotBlank() }
    return when (page) {
        is Page.Playlist -> playlistName(page.id)
        // A live list's name, looked up the same way.
        is Page.LiveList -> playlistName(page.id)
        is Page.Artist -> page.name.ifBlank { null } ?: album
        is Page.Genre -> page.name
        is Page.Folder -> page.name
        Page.Songs -> "Songs"
        Page.Favourites -> "Favorites"
        Page.History -> "Recently played"
        Page.RecentlyAdded -> "Recently added"
        Page.Charts -> "Charts"
        Page.Search -> album ?: "Search"
        is Page.Album, is Page.Shelf, is Page.NewLiveList, Page.Home, Page.Albums, Page.Artists, Page.Genres, Page.Folders, Page.LibraryHealth, Page.Imports, Page.Family, Page.LiveRadio, Page.Settings, Page.Sound -> album
    }
}

// What a radio's songs are called in the queue: "Karma Police radio".
fun radioName(title: String): String = "$title radio"
