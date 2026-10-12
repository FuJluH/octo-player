package app.winters.octo.ui.menu

import app.winters.octo.ui.common.SongSelection
import app.winters.octo.ui.menu.SongAction.AddToPlaylist
import app.winters.octo.ui.menu.SongAction.AddToQueue
import app.winters.octo.ui.menu.SongAction.Download
import app.winters.octo.ui.menu.SongAction.GoToAlbum
import app.winters.octo.ui.menu.SongAction.GoToArtist
import app.winters.octo.ui.menu.SongAction.Info
import app.winters.octo.ui.menu.SongAction.Like
import app.winters.octo.ui.menu.SongAction.PlayNext
import app.winters.octo.ui.menu.SongAction.Rate
import app.winters.octo.ui.menu.SongAction.RemoveFromPlaylist
import app.winters.octo.ui.menu.SongAction.Select
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class MenuPlaceTest {
    private fun place(context: SongMenuContext) = menuPlace(context, albumId = "album:1", artistId = "artist:1")

    @Test
    fun anywhereElseLeadsToTheAlbumAndTheArtist() {
        assertEquals(MenuPlace(), place(SongMenuContext()))
        assertEquals(
            listOf(PlayNext, AddToQueue, AddToPlaylist, Like, Rate, GoToAlbum, GoToArtist, Info),
            songActions(find = false, radio = false, place = place(SongMenuContext())),
        )
    }

    @Test
    fun onlyThePlayersMoreButtonOpensTheMenuInThePlayer() {
        assertTrue(place(SongMenuContext(fromPlayer = true)).inPlayer)
        assertFalse(place(SongMenuContext()).inPlayer)
        assertFalse(place(SongMenuContext(albumId = "album:1", playlistId = "p", playlistItemId = 7)).inPlayer)
    }

    @Test
    fun theMenuRemembersWhereItWasOpenedFrom() {
        val menu = SongMenuState()
        menu.open("t", SongMenuContext(fromPlayer = true))
        assertTrue(menu.lastContext.fromPlayer)
        menu.open("t")
        assertFalse(menu.lastContext.fromPlayer)
    }

    @Test
    fun onItsOwnAlbumPageThereIsNoGoingToTheAlbum() {
        val here = place(SongMenuContext(albumId = "album:1"))
        assertTrue(here.onAlbumPage)
        assertEquals(listOf(PlayNext, AddToQueue, AddToPlaylist, Like, Rate, GoToArtist, Info), songActions(find = false, radio = false, place = here))
    }

    @Test
    fun onItsOwnArtistPageThereIsNoGoingToTheArtist() {
        val here = place(SongMenuContext(artistId = "artist:1"))
        assertEquals(listOf(PlayNext, AddToQueue, AddToPlaylist, Like, Rate, GoToAlbum, Info), songActions(find = false, radio = false, place = here))
    }

    @Test
    fun anotherAlbumsOrArtistsPageStillLeadsThere() {
        // A song featured on another artist's page, or an album page listing a
        // song from elsewhere, still goes to its own album and artist.
        val elsewhere = place(SongMenuContext(albumId = "album:2", artistId = "artist:2"))
        assertFalse(elsewhere.onAlbumPage)
        assertFalse(elsewhere.onArtistPage)
    }

    @Test
    fun onAPlaylistPageTheRowCanBeTakenOut() {
        val here = place(SongMenuContext(playlistId = "p", playlistItemId = 7))
        assertEquals(
            listOf(PlayNext, AddToQueue, AddToPlaylist, RemoveFromPlaylist, Like, Rate, GoToAlbum, GoToArtist, Info),
            songActions(find = false, radio = false, place = here),
        )
        // A find on a playlist page can be taken out too.
        assertEquals(listOf(PlayNext, AddToQueue, Download, RemoveFromPlaylist, Info), songActions(find = true, radio = false, place = here))
        // Without the row there is nothing to take out.
        assertFalse(place(SongMenuContext(playlistId = "p")).inPlaylist)
    }

    @Test
    fun selectIsOfferedInAListThatCanPickAndIsNotPickingYet() {
        val selection = SongSelection()
        val picking = place(SongMenuContext(selection = selection, selectKey = "t"))
        assertTrue(picking.selectable)
        assertEquals(
            listOf(PlayNext, AddToQueue, AddToPlaylist, Select, Like, Rate, GoToAlbum, GoToArtist, Info),
            songActions(find = false, radio = false, place = picking),
        )
        selection.start("t")
        assertFalse(place(SongMenuContext(selection = selection, selectKey = "t")).selectable)
        // A list that cannot pick offers no Select.
        assertFalse(place(SongMenuContext(selectKey = "t")).selectable)
    }
}
