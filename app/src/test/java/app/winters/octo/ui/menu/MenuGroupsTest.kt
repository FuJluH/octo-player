package app.winters.octo.ui.menu

import app.winters.octo.ui.menu.SongAction.AddToPlaylist
import app.winters.octo.ui.menu.SongAction.AddToQueue
import app.winters.octo.ui.menu.SongAction.Cast
import app.winters.octo.ui.menu.SongAction.DeleteFromDisk
import app.winters.octo.ui.menu.SongAction.DeleteFromPhone
import app.winters.octo.ui.menu.SongAction.Download
import app.winters.octo.ui.menu.SongAction.FindFlac
import app.winters.octo.ui.menu.SongAction.GoToAlbum
import app.winters.octo.ui.menu.SongAction.GoToArtist
import app.winters.octo.ui.menu.SongAction.Info
import app.winters.octo.ui.menu.SongAction.KeepOffline
import app.winters.octo.ui.menu.SongAction.Like
import app.winters.octo.ui.menu.SongAction.PlayNext
import app.winters.octo.ui.menu.SongAction.Rate
import app.winters.octo.ui.menu.SongAction.RemoveFromPlaylist
import app.winters.octo.ui.menu.SongAction.Select
import app.winters.octo.ui.menu.SongAction.SetAsSound
import app.winters.octo.ui.menu.SongAction.Share
import app.winters.octo.ui.menu.SongAction.ShareFile
import app.winters.octo.ui.menu.SongAction.Sound
import app.winters.octo.ui.menu.SongAction.StartRadio
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class MenuGroupsTest {
    @Test
    fun aLibrarySongGroupsPlayingKeepingGoingAndLooking() {
        assertEquals(
            listOf(
                listOf(PlayNext, AddToQueue, StartRadio),
                listOf(AddToPlaylist, Like, Rate),
                listOf(GoToAlbum, GoToArtist),
                listOf(Info),
            ),
            songMenuGroups(songActions(find = false, radio = true)),
        )
    }

    @Test
    fun whatTakesASongAwayComesLast() {
        val actions = songActions(
            find = false,
            radio = false,
            share = true,
            offline = true,
            place = MenuPlace(inPlaylist = true, selectable = true),
            phone = true,
        )
        assertEquals(
            listOf(
                listOf(PlayNext, AddToQueue),
                listOf(AddToPlaylist, Like, Rate, KeepOffline),
                listOf(GoToAlbum, GoToArtist),
                listOf(Share, ShareFile, SetAsSound, Info, Select),
                listOf(RemoveFromPlaylist, DeleteFromPhone),
            ),
            songMenuGroups(actions),
        )
    }

    @Test
    fun castAndSoundAreTheirOwnGroupAfterEverythingElse() {
        val groups = songMenuGroups(songActions(find = false, radio = false, phone = true, disk = true, place = MenuPlace(inPlayer = true)))
        assertEquals(listOf(Cast, Sound), groups.last())
        assertEquals(listOf(DeleteFromPhone, DeleteFromDisk), groups[groups.size - 2])
        // A found song's menu in the player ends the same way.
        assertEquals(
            listOf(listOf(PlayNext, AddToQueue), listOf(Download), listOf(Info), listOf(Cast, Sound)),
            songMenuGroups(songActions(find = true, radio = false, place = MenuPlace(inPlayer = true))),
        )
    }

    @Test
    fun aFoundSongHasNoEmptyGroups() {
        assertEquals(
            listOf(listOf(PlayNext, AddToQueue, StartRadio), listOf(Download), listOf(Info)),
            songMenuGroups(songActions(find = true, radio = true)),
        )
    }

    @Test
    fun everySongActionHasAGroupAndOnlyOne() {
        val all = SongAction.entries.toList()
        val grouped = songMenuGroups(all).flatten()
        assertEquals(all.size, grouped.size)
        assertEquals(all.toSet(), grouped.toSet())
    }

    @Test
    fun groupingKeepsOnlyWhatIsOffered() {
        assertEquals(listOf(listOf(Info)), songMenuGroups(listOf(Info)))
        assertTrue(songMenuGroups(emptyList()).isEmpty())
    }

    @Test
    fun aCollectionGroupsPlayingKeepingHomeAndGoing() {
        assertEquals(
            listOf(
                listOf(CollectionAction.Play, CollectionAction.Shuffle, CollectionAction.PlayNext, CollectionAction.AddToQueue),
                listOf(CollectionAction.AddToPlaylist, CollectionAction.AddToFavourites, CollectionAction.Download),
                listOf(CollectionAction.PinToHome),
                listOf(CollectionAction.GoToArtist),
            ),
            collectionMenuGroups(albumActions(canDownload = true)),
        )
    }

    @Test
    fun findInFlacIsAWayToKeepASong() {
        assertEquals(
            listOf(
                listOf(PlayNext, AddToQueue),
                listOf(AddToPlaylist, Like, Rate, KeepOffline, FindFlac),
                listOf(GoToAlbum, GoToArtist),
                listOf(Info),
            ),
            songMenuGroups(songActions(find = false, radio = false, offline = true, upgrade = true)),
        )
        // And an album's, after its download.
        assertEquals(
            listOf(CollectionAction.AddToPlaylist, CollectionAction.AddToFavourites, CollectionAction.Download, CollectionAction.FindFlac),
            collectionMenuGroups(albumActions(canDownload = true, lossy = 4))[1],
        )
    }

    @Test
    fun aPlaylistPutsRenameAndDeleteLast() {
        assertEquals(
            listOf(
                listOf(CollectionAction.Unpin),
                listOf(CollectionAction.Rename, CollectionAction.Duplicate, CollectionAction.Delete),
            ),
            collectionMenuGroups(playlistActions(empty = true, pin = PinSpot.First)),
        )
    }

    @Test
    fun everyCollectionActionHasAGroupAndOnlyOne() {
        val all = CollectionAction.entries.toList()
        val grouped = collectionMenuGroups(all).flatten()
        assertEquals(all.size, grouped.size)
        assertEquals(all.toSet(), grouped.toSet())
    }
}
