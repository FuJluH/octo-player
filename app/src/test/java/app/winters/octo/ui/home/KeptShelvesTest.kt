package app.winters.octo.ui.home

import app.winters.octo.catalog.TrackEntity
import app.winters.octo.discovery.Station
import app.winters.octo.home.HomeShelfStore
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class KeptShelvesTest {
    @get:Rule val temp = TemporaryFolder()

    private fun track(id: String, title: String, explicit: Boolean? = null) = TrackEntity(
        id = id, sourceId = "server:a", nativeId = id.substringAfterLast(':'), title = title, searchKey = title.lowercase(), sortKey = title.lowercase(),
        artist = "Artist", artistId = "ar1", album = "Album", albumId = "al1", trackNo = 1, discNo = null, year = 2024,
        durationMs = 200_000, addedAt = 1L, mimeType = "audio/flac", sizeBytes = null, artwork = "server:a|al1", uri = null,
        onPhone = false, rating = 4, explicit = explicit,
    )

    // Every field of a station, a Made for you list and a chart song comes
    // back as it was kept, finds and library songs alike.
    @Test
    fun theShelvesComeBackAsTheyWereKept() {
        val shelves = KeptShelves(
            stations = listOf(Station("st1", "Morning", "server:a|st1")),
            madeForYou = listOf(Station("og-new", "New Releases", null, songCount = 40)),
            charts = listOf(track("server:a:s1", "First", explicit = true), track("find:s2", "Second")),
        )
        val store = HomeShelfStore(temp.root, KeptShelves.serializer())
        store.write("account-1", shelves)
        assertEquals(shelves, HomeShelfStore(temp.root, KeptShelves.serializer()).read("account-1"))
    }
}
