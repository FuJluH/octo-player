package app.winters.octo.liveradio

import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.IOException

class ServerAddsTest {
    private val kexp = LiveStation("u1", "KEXP", "https://kexp.example/live")

    private class Fake(var admin: Boolean, val streams: MutableList<String> = mutableListOf(), val signedIn: Boolean = true, val fails: Boolean = false) {
        val asked = mutableListOf<String>()
        val adds = ServerAdds(
            admin = { admin },
            streams = { streams },
            add = { station ->
                if (fails) throw IOException("refused")
                if (signedIn) asked += station.streamUrl
                signedIn
            },
        )
    }

    @Test
    fun anAdminAddsAStationTheServerLacks() = runBlocking {
        val fake = Fake(admin = true)
        assertTrue(fake.adds.offers(kexp))
        assertEquals(AddResult.Added, fake.adds.addToServer(kexp))
        assertEquals(listOf("https://kexp.example/live"), fake.asked)
        assertEquals("Added KEXP to your server", addResultLine(AddResult.Added, "KEXP"))
    }

    @Test
    fun someoneWhoIsNotAnAdminNeverAsksTheServer() = runBlocking {
        val fake = Fake(admin = false)
        assertFalse(fake.adds.offers(kexp))
        assertEquals(AddResult.NotAdmin, fake.adds.addToServer(kexp))
        assertTrue(fake.asked.isEmpty())
    }

    @Test
    fun aStationOnTheServerIsNotOfferedOrAddedAgain() = runBlocking {
        val fake = Fake(admin = true, streams = mutableListOf("http://KEXP.example/live/"))
        assertFalse(fake.adds.offers(kexp))
        assertEquals(AddResult.AlreadyThere, fake.adds.addToServer(kexp))
        assertTrue(fake.asked.isEmpty())
    }

    @Test
    fun withNoServerNothingIsSaidToBeAdded() = runBlocking {
        val result = Fake(admin = true, signedIn = false).adds.addToServer(kexp)
        assertEquals(AddResult.NoServer, result)
        assertFalse(addResultLine(result, "KEXP").startsWith("Added"))
    }

    @Test
    fun aRefusalSaysWhy() = runBlocking {
        val result = Fake(admin = true, fails = true).adds.addToServer(kexp)
        assertEquals(AddResult.Failed("refused"), result)
        assertEquals("Could not add KEXP: refused", addResultLine(result, "KEXP"))
    }
}
