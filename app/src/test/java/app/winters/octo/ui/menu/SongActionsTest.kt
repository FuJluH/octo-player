package app.winters.octo.ui.menu

import app.winters.octo.discovery.DownloadState
import app.winters.octo.offline.DownloadStatus
import app.winters.octo.output.DeviceShape
import app.winters.octo.output.OutputChoice
import app.winters.octo.output.OutputDevice
import app.winters.octo.output.OutputFamily
import app.winters.octo.ui.menu.SongAction.AddToLastPlaylist
import app.winters.octo.ui.menu.SongAction.AddToPlaylist
import app.winters.octo.ui.menu.SongAction.AddToQueue
import app.winters.octo.ui.menu.SongAction.Cast
import app.winters.octo.ui.menu.SongAction.DeleteFromDisk
import app.winters.octo.ui.menu.SongAction.DeleteFromPhone
import app.winters.octo.ui.menu.SongAction.Download
import app.winters.octo.ui.menu.SongAction.FindFlac
import app.winters.octo.ui.menu.SongAction.FindSongs
import app.winters.octo.ui.menu.SongAction.GoToAlbum
import app.winters.octo.ui.menu.SongAction.GoToArtist
import app.winters.octo.ui.menu.SongAction.Info
import app.winters.octo.ui.menu.SongAction.KeepOffline
import app.winters.octo.ui.menu.SongAction.Like
import app.winters.octo.ui.menu.SongAction.PlayNext
import app.winters.octo.ui.menu.SongAction.Rate
import app.winters.octo.ui.menu.SongAction.SetAsSound
import app.winters.octo.ui.menu.SongAction.Share
import app.winters.octo.ui.menu.SongAction.ShareFile
import app.winters.octo.ui.menu.SongAction.Sound
import app.winters.octo.ui.menu.SongAction.StartRadio
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Test

class SongActionsTest {
    @Test
    fun aLibrarySongOffersFindInFlacWhenTheServerCan() {
        assertEquals(
            listOf(PlayNext, AddToQueue, StartRadio, AddToPlaylist, FindFlac, Like, Rate, GoToAlbum, GoToArtist, Info),
            songActions(find = false, radio = true, upgrade = true),
        )
        // Among the ways to keep it, after downloading it to the phone.
        assertEquals(listOf(AddToPlaylist, Like, Rate, KeepOffline, FindFlac), songMenuGroups(songActions(find = false, radio = true, offline = true, upgrade = true))[1])
    }

    @Test
    fun findSongsComesAfterTheInfo_ForFoundAndLibrarySongsAlike() {
        assertEquals(listOf(PlayNext, AddToQueue, Download, Info, FindSongs), songActions(find = true, radio = false, findSongs = true))
        assertEquals(listOf(Info, FindSongs), songMenuGroups(songActions(find = false, radio = false, findSongs = true))[3])
        assertEquals(false, FindSongs in songActions(find = false, radio = true))
    }

    @Test
    fun theMenuFromThePlayerEndsWithCastAndSound() {
        val player = MenuPlace(inPlayer = true)
        assertEquals(
            listOf(PlayNext, AddToQueue, StartRadio, AddToPlaylist, Like, Rate, GoToAlbum, GoToArtist, Info, Cast, Sound),
            songActions(find = false, radio = true, place = player),
        )
        // A song found online plays somewhere and through the equalizer too.
        assertEquals(
            listOf(PlayNext, AddToQueue, Download, Info, FindSongs, Cast, Sound),
            songActions(find = true, radio = false, findSongs = true, place = player),
        )
        // Anywhere else, neither: a row held on a page is about the song only.
        val elsewhere = songActions(find = false, radio = true, share = true, offline = true, phone = true, findSongs = true, disk = true)
        assertFalse(Cast in elsewhere)
        assertFalse(Sound in elsewhere)
    }

    @Test
    fun theCastRowNamesTheDeviceOnlyWhileTheMusicIsElsewhere() {
        val tv = OutputDevice("cast:tv", "Living room TV", OutputFamily.Cast, DeviceShape.Tv)
        assertEquals("Living room TV", castDetail(OutputChoice.Casting(tv)))
        assertEquals("Connecting to Living room TV", castDetail(OutputChoice.Connecting(tv)))
        assertNull(castDetail(OutputChoice.Phone))
    }

    @Test
    fun theSoundRowSaysWhetherTheEqualizerIsOn() {
        assertEquals("Equalizer on", soundDetail(equalizerOn = true))
        assertEquals("Equalizer off", soundDetail(equalizerOn = false))
    }

    @Test
    fun aSongFoundOnlineNeverOffersFindInFlac() {
        assertEquals(listOf(PlayNext, AddToQueue, Download, Info), songActions(find = true, radio = false, upgrade = true))
    }

    @Test
    fun aLibrarySongOffersEverything() {
        assertEquals(
            listOf(PlayNext, AddToQueue, StartRadio, AddToPlaylist, Like, Rate, GoToAlbum, GoToArtist, Info),
            songActions(find = false, radio = true),
        )
    }

    @Test
    fun theLastPlaylistComesFirstAmongTheWaysToKeepASong() {
        val actions = songActions(find = false, radio = true, lastPlaylist = true)
        assertEquals(listOf(PlayNext, AddToQueue, StartRadio, AddToLastPlaylist, AddToPlaylist, Like, Rate, GoToAlbum, GoToArtist, Info), actions)
        assertEquals(listOf(AddToLastPlaylist, AddToPlaylist, Like, Rate), songMenuGroups(actions)[1])
        // A song found online cannot go in a playlist yet.
        assertEquals(listOf(PlayNext, AddToQueue, Download, Info), songActions(find = true, radio = false, lastPlaylist = true))
    }

    @Test
    fun radioNeedsAServer() {
        assertEquals(
            listOf(PlayNext, AddToQueue, AddToPlaylist, Like, Rate, GoToAlbum, GoToArtist, Info),
            songActions(find = false, radio = false),
        )
    }

    @Test
    fun shareFollowsAPlaylistWhenTheSongIsOnAServerThatShares() {
        assertEquals(
            listOf(PlayNext, AddToQueue, StartRadio, AddToPlaylist, Share, Like, Rate, GoToAlbum, GoToArtist, Info),
            songActions(find = false, radio = true, share = true),
        )
        // A find is never shared: it is not in the server's library.
        assertEquals(listOf(PlayNext, AddToQueue, StartRadio, Download, Info), songActions(find = true, radio = true, share = true))
    }

    @Test
    fun aSongWithAPhoneFileCanShareRingOrDeleteIt() {
        assertEquals(
            listOf(PlayNext, AddToQueue, StartRadio, AddToPlaylist, ShareFile, Like, Rate, GoToAlbum, GoToArtist, SetAsSound, DeleteFromPhone, Info),
            songActions(find = false, radio = true, phone = true),
        )
        // With a server copy that shares too, both shares are offered: the file and the link.
        assertEquals(
            listOf(PlayNext, AddToQueue, AddToPlaylist, ShareFile, Share, Like, Rate, GoToAlbum, GoToArtist, SetAsSound, DeleteFromPhone, Info),
            songActions(find = false, radio = false, share = true, phone = true),
        )
    }

    @Test
    fun aSongOnlyOnAServerHasNoFileToShareRingOrDelete() {
        assertEquals(
            listOf(PlayNext, AddToQueue, AddToPlaylist, KeepOffline, Share, Like, Rate, GoToAlbum, GoToArtist, Info),
            songActions(find = false, radio = false, share = true, offline = true, phone = false),
        )
    }

    @Test
    fun aFindHasNoPhoneFile() {
        assertEquals(listOf(PlayNext, AddToQueue, Download, Info), songActions(find = true, radio = false, phone = true))
    }

    @Test
    fun aFindOffersADownloadInsteadOfLibraryChoices() {
        assertEquals(listOf(PlayNext, AddToQueue, StartRadio, Download, Info), songActions(find = true, radio = true))
        assertEquals(listOf(PlayNext, AddToQueue, Download, Info), songActions(find = true, radio = false))
    }

    @Test
    fun tappingAStarSetsTheRatingAndTappingItAgainClearsIt() {
        assertEquals(4, nextRating(current = 0, tapped = 4))
        assertEquals(2, nextRating(current = 4, tapped = 2))
        assertEquals(0, nextRating(current = 4, tapped = 4))
    }

    @Test
    fun aSongOnlyOnTheServerCanBeDownloadedToThePhone() {
        assertEquals(
            listOf(PlayNext, AddToQueue, StartRadio, AddToPlaylist, KeepOffline, Like, Rate, GoToAlbum, GoToArtist, Info),
            songActions(find = false, radio = true, offline = true),
        )
        // A find downloads to the server first, never straight to the phone.
        assertEquals(listOf(PlayNext, AddToQueue, Download, Info), songActions(find = true, radio = false, offline = true))
    }

    @Test
    fun theKeepRowSaysWhereTheSongIs() {
        assertEquals("Download", keepOfflineLabel(null, byHand = false))
        assertEquals("Waiting to download", keepOfflineLabel(DownloadStatus.Queued, byHand = true))
        assertEquals("Downloading", keepOfflineLabel(DownloadStatus.Downloading, byHand = true))
        assertEquals("Remove download", keepOfflineLabel(DownloadStatus.Done, byHand = true))
        assertEquals("Kept downloaded", keepOfflineLabel(DownloadStatus.Done, byHand = false))
        assertEquals("Download failed, try again", keepOfflineLabel(DownloadStatus.Failed, byHand = false))
        // Only what a tap can do is offered: a rule's download goes with its rule.
        assertEquals(true, keepOfflineEnabled(null, byHand = false))
        assertEquals(false, keepOfflineEnabled(DownloadStatus.Done, byHand = false))
        assertEquals(true, keepOfflineEnabled(DownloadStatus.Done, byHand = true))
        assertEquals(false, keepOfflineEnabled(DownloadStatus.Downloading, byHand = true))
        assertEquals(true, keepOfflineEnabled(DownloadStatus.Failed, byHand = false))
    }

    @Test
    fun theAddRowSaysWhereTheSongIs() {
        assertEquals("Add to your library", downloadLabel(DownloadState.None))
        assertEquals("Adding to your library", downloadLabel(DownloadState.Requested))
        assertEquals("In your library", downloadLabel(DownloadState.Done))
    }

    @Test
    fun deleteFromDiskIsLastAndOnlyForALibrarySongTheServerLetsGo() {
        val actions = songActions(find = false, radio = false, phone = true, disk = true)
        assertEquals(listOf(SetAsSound, DeleteFromPhone, DeleteFromDisk, Info), actions.takeLast(4))
        assertEquals(listOf(DeleteFromPhone, DeleteFromDisk), songMenuGroups(actions).last())
        // A find has no file on any disk yet.
        assertEquals(false, DeleteFromDisk in songActions(find = true, radio = false, disk = true))
        assertEquals(false, DeleteFromDisk in songActions(find = false, radio = false))
    }

    @Test
    fun aFamilyMemberWhoAsksGetsRequestACopyBesideTheAdd() {
        assertEquals(
            listOf(PlayNext, AddToQueue, SongAction.Download, SongAction.RequestCopy, Info),
            songActions(find = true, radio = false, requestCopy = true),
        )
        assertEquals(listOf(SongAction.Download, SongAction.RequestCopy), songMenuGroups(songActions(find = true, radio = false, requestCopy = true))[1])
        // Never on a library song.
        assertEquals(false, SongAction.RequestCopy in songActions(find = false, radio = false, requestCopy = true))
    }

    @Test
    fun aManagedMemberCanTakeALibrarySongOutOfTheirOwnLibrary() {
        val groups = songMenuGroups(songActions(find = false, radio = false, removeFromMine = true, disk = true))
        assertEquals(listOf(SongAction.RemoveFromMyLibrary, DeleteFromDisk), groups.last())
        assertEquals(false, SongAction.RemoveFromMyLibrary in songActions(find = true, radio = false, removeFromMine = true))
    }
}
