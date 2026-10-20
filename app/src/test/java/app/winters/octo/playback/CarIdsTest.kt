package app.winters.octo.playback

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class CarIdsTest {
    private fun roundTrip(node: CarNode) = assertEquals(node, parseCarId(carId(node)))

    @Test
    fun everyNodeReadsBackAsItself() {
        listOf(
            CarNode.Root, CarNode.Recent, CarNode.Playlists, CarNode.Albums, CarNode.Artists,
            CarNode.Liked, CarNode.MostPlayed,
            CarNode.Album("device:album:12"), CarNode.Artist("device:artist:4"), CarNode.Playlist("3f2a-uuid"),
        ).forEach(::roundTrip)
    }

    @Test
    fun aSongKeepsTheListItWasFoundIn() {
        roundTrip(CarNode.Song("device:4054", CarNode.Album("device:album:12")))
        roundTrip(CarNode.Song("device:4054", CarNode.Playlist("3f2a-uuid")))
        roundTrip(CarNode.Song("device:4054", CarNode.Liked))
        roundTrip(CarNode.Song("device:4054", CarNode.MostPlayed))
        roundTrip(CarNode.Song("device:4054", null))
    }

    @Test
    fun theAppsOwnSongIdsAreNotCarIds() {
        assertNull(parseCarId("device:4054"))
    }

    @Test
    fun playingStartsAtTheChosenSongOrTheTop() {
        val list = listOf("a", "b", "c")
        assertEquals(1, startIndex(list, "b"))
        assertEquals(0, startIndex(list, "gone"))
        assertEquals(0, startIndex(list, null))
    }

    @Test
    fun theServersToolPlaylistsAreKnownByTheirMark() {
        assertTrue(isToolPlaylist("🛠 Delete"))
        assertTrue(isToolPlaylist("🛠️ Better quality"))
        assertFalse(isToolPlaylist("Road trip"))
        assertFalse(isToolPlaylist("Fixing up 🛠"))
    }
}
