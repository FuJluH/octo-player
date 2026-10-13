package app.winters.octo.home

import kotlinx.serialization.Serializable
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotSame
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File

class HomeShelvesTest {
    @get:Rule val temp = TemporaryFolder()

    @Serializable
    data class Shelf(val id: String, val name: String, val count: Int? = null)

    @Serializable
    data class Shelves(val stations: List<Shelf> = emptyList(), val madeForYou: List<Shelf> = emptyList(), val chart: List<Shelf> = emptyList())

    private val shelves = Shelves(
        stations = listOf(Shelf("st1", "Morning"), Shelf("st2", "Chill")),
        madeForYou = listOf(Shelf("og-new", "New Releases", 40), Shelf("og-deep", "Deep Cuts", 25)),
        chart = listOf(Shelf("s1", "First"), Shelf("find:s2", "Second")),
    )

    private fun store(folder: File = temp.root) = HomeShelfStore(File(folder, "home"), Shelves.serializer())

    @Test
    fun whatIsWrittenIsReadBackAsItWas() {
        store().write("server-a", shelves)
        assertEquals(shelves, store().read("server-a"))
    }

    @Test
    fun eachServerKeepsItsOwnShelves() {
        val other = Shelves(stations = listOf(Shelf("x", "Other")))
        val store = store()
        store.write("server-a", shelves)
        store.write("server-b", other)
        assertEquals(shelves, store.read("server-a"))
        assertEquals(other, store.read("server-b"))
        assertNull("a server never read from keeps nothing", store.read("server-c"))
    }

    @Test
    fun aLaterWriteReplacesTheLastOne() {
        val store = store()
        store.write("server-a", shelves)
        val fewer = shelves.copy(stations = listOf(Shelf("st2", "Chill")))
        store.write("server-a", fewer)
        assertEquals(fewer, store.read("server-a"))
    }

    @Test
    fun aBlankServerKeepsNothing() {
        val store = store()
        store.write("", shelves)
        assertNull(store.read(""))
        assertEquals(emptyList<File>(), File(temp.root, "home").listFiles()?.toList().orEmpty())
    }

    @Test
    fun aBrokenFileCountsAsNone() {
        val store = store()
        store.write("server-a", shelves)
        File(temp.root, "home").listFiles()!!.single().writeText("{\"stations\":[{")
        assertNull(store.read("server-a"))
    }

    @Test
    fun theFileNameShowsNothingOfTheServer() {
        store().write("https://music.example.com|brandon", shelves)
        val name = File(temp.root, "home").listFiles()!!.single().name
        assertEquals(64 + ".json".length, name.length)
    }

    @Test
    fun aChangedAnswerReplacesTheShelf() {
        val shown = shelves.stations
        val moved = listOf(Shelf("st2", "Chill"), Shelf("st1", "Morning"))
        assertSame(moved, answered(shown, moved))
        val renamed = listOf(Shelf("st1", "Morning"), Shelf("st2", "Chill out"))
        assertSame(renamed, answered(shown, renamed))
        assertSame("a server that now has none empties the shelf", emptyList<Shelf>(), answered(shown, emptyList()))
    }

    @Test
    fun anEqualAnswerLeavesTheShownShelfAlone() {
        val shown = store().let {
            it.write("server-a", shelves)
            it.read("server-a")!!.stations
        }
        val answer = listOf(Shelf("st1", "Morning"), Shelf("st2", "Chill"))
        assertNotSame(shown, answer)
        assertSame(shown, answered(shown, answer))
    }
}
