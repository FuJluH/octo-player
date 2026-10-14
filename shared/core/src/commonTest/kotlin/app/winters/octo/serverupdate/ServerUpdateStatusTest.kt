package app.winters.octo.serverupdate

import app.winters.octo.markdown.Block
import app.winters.octo.markdown.Span
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ServerUpdateStatusTest {
    @Test
    fun readsAFullAnswer() {
        val status = parseServerUpdate(
            """
            {"enabled":true,"repo":"winters27/octo","running":"2026.10.11",
             "latest":{"tag":"2026.10.13","name":"2026.10.13","notes":"## Fixes\n- One","url":"https://github.com/winters27/octo/releases/tag/2026.10.13","publishedUtc":"2026-10-13T02:00:00Z"},
             "newer":[{"tag":"2026.10.13","name":"2026.10.13","notes":"n","url":"u","publishedUtc":null},{"tag":"2026.10.12","name":null,"notes":null,"url":null,"publishedUtc":null}],
             "updateAvailable":true,"standing":"behind","checkedUtc":"2026-10-13T03:00:00Z","error":null,
             "helper":{"installed":true,"version":"2","mode":"image","dir":"/opt/octo","installedUtc":"2026-10-01T00:00:00Z","outdated":false},
             "reinstallCommand":"scripts/updater/install-updater.sh","pending":false,"pendingId":null,"unanswered":null,
             "run":{"id":"r1","tag":"2026.10.11","from":"2026.10.10","state":"done","step":null,"error":null,"startedUtc":"x","finishedUtc":"y","log":[]},
             "command":"git fetch --tags","imageCommand":"docker compose pull","somethingNew":42}
            """.trimIndent(),
        )!!
        assertEquals("2026.10.11", status.running)
        assertEquals("2026.10.13", status.latest?.tag)
        assertEquals(listOf("2026.10.13", "2026.10.12"), status.newer.map { it.tag })
        assertTrue(status.updateAvailable)
        assertEquals("image", status.helper.mode)
        assertEquals(RunState.DONE, status.run?.state)
        assertFalse(status.busy)
        assertTrue(status.canUpdate)
    }

    @Test
    fun readsTheShortestAnswer() {
        val status = parseServerUpdate(
            """{"enabled":false,"repo":"winters27/octo","running":"2026.10.11","latest":null,"newer":[],"updateAvailable":false,"standing":"unknown","checkedUtc":null,"error":null,"helper":{"installed":false},"reinstallCommand":"r","pending":false,"pendingId":null,"unanswered":null,"run":null,"command":"c","imageCommand":"i"}""",
        )!!
        assertNull(status.latest)
        assertFalse(status.helper.installed)
        assertFalse(status.canUpdate)
    }

    @Test
    fun somethingElseIsNotAnAnswer() {
        assertNull(parseServerUpdate("<html>Bad gateway</html>"))
        assertNull(parseServerUpdate(""))
    }

    @Test
    fun ordersDatedTags() {
        assertTrue(compareReleaseTags("2026.10.13", "2026.10.11") > 0)
        assertTrue(compareReleaseTags("2026.10.03.1", "2026.10.03") > 0)
        assertTrue(compareReleaseTags("2026.10.03", "2026.10.03.1") < 0)
        assertTrue(compareReleaseTags("2026.9.30", "2026.10.01") < 0)
        assertEquals(0, compareReleaseTags("2026.10.13", "2026.10.13"))
    }

    @Test
    fun notesKeepOnlyGitHubLinks() {
        val notes = releaseNotes(
            listOf(ServerRelease(tag = "2026.10.13", notes = "See [the issue](https://github.com/winters27/octo/issues/9) and [elsewhere](https://example.com/x).\n\n- [plain http](http://github.com/a)")),
        ).single().second
        val paragraph = notes[0] as Block.Paragraph
        assertEquals("https://github.com/winters27/octo/issues/9", paragraph.text.first { it.text == "the issue" }.link)
        assertNull(paragraph.text.first { it.text == "elsewhere" }.link)
        val bullets = notes[1] as Block.Bullets
        assertEquals(Span("plain http"), bullets.items.single().text.single())
    }

    @Test
    fun aReleaseIsTitledByItsNameOrTag() {
        assertEquals("Octo 2026.10.13", releaseTitle(ServerRelease(tag = "2026.10.13", name = "2026.10.13")))
        assertEquals("Octo 2026.10.13", releaseTitle(ServerRelease(tag = "2026.10.13")))
        assertEquals("Faster radio", releaseTitle(ServerRelease(tag = "2026.10.13", name = "Faster radio")))
    }

    @Test
    fun onlyGitHubCounts() {
        assertTrue(isGitHub("https://github.com/winters27/octo"))
        assertFalse(isGitHub("https://github.com.evil.example/x"))
        assertFalse(isGitHub("https://gist.github.com/x"))
        assertFalse(isGitHub("javascript:alert(1)"))
    }
}
