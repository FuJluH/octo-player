package app.winters.octo.desktop.ui

import app.winters.octo.desktop.FakeServer
import app.winters.octo.desktop.SidePanel
import app.winters.octo.desktop.pages.showTrash
import java.time.Duration
import java.time.Instant
import org.junit.Assume.assumeTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import javax.swing.SwingUtilities

// Replacing a library song's copy from Find songs, as it looks: the copies
// with how each stands against yours and the line about your take, the
// replace anyway question, the copy's row while it replaces, the notice
// with Undo once it has, the notice when your copy was kept, and a
// replaced song in Recently removed. Only when asked:
// OCTO_SHOTS=1 ./gradlew :desktop:test --tests '*ReplaceAnywayShotsTest*'.
// Saved under build/shots/polish/replace/.
class ReplaceAnywayShotsTest {
    @get:Rule val folder = TemporaryFolder()

    // How far the pretend server's replacement has got, and when it got
    // to each step, which stays put as a real server's would.
    @Volatile private var phase = 0
    private val times = java.util.concurrent.ConcurrentHashMap<Int, Instant>()

    private fun at(): Instant = times.getOrPut(phase) { Instant.now() }

    @Test
    fun drawReplacingACopy() {
        assumeTrue(System.getenv("OCTO_SHOTS") == "1")
        FakeServer().use { server ->
            PolishShotsTest.Rig(folder, PolishData.library(100), server).use { rig ->
                server.answer(
                    "getOpenSubsonicExtensions",
                    """"openSubsonicExtensions":[{"name":"songLyrics","versions":[1]},{"name":"octoAcquisitions","versions":[1,2,3]},{"name":"octoLibraryActions","versions":[1,2,3]}]""",
                    type = "octo",
                )
                server.answer(
                    "getLibraryActions",
                    """"libraryActions":{"enabled":true,"allowed":true,"dryRun":false,"admin":true,"actions":["remove","upgrade","restore"],"keepDays":30,"upgradeSource":"Soulseek"}""",
                    type = "octo",
                )
                server.answerBy("getAcquisitions") {
                    val rows = when (phase) {
                        1 -> """{"id":"nd-9","artist":"Bon Iver","title":"Holocene","state":"downloading","progress":0.42,"source":"Soulseek","startedAt":"${at()}","updatedAt":"${at()}","key":"soulseek:r1","kind":"pick","libraryId":"nd-9","quality":"FLAC 16-bit 44.1 kHz"}"""
                        else -> ""
                    }
                    server.ok(""""acquisitions":{"acquisition":[$rows]}""", type = "octo")
                }
                server.answerBy("getUpgrades") {
                    val now = at()
                    val job = when (phase) {
                        1 -> """{"id":"nd-9","title":"Holocene","artist":"Bon Iver","state":"working","acquisition":"soulseek:r1","picked":"FLAC from northwoods","updatedAt":"$now"}"""
                        2 -> """{"id":"nd-9","title":"Holocene","artist":"Bon Iver","state":"upgraded","detail":"Now the plain song, FLAC 16-bit 44.1 kHz.","acquisition":"soulseek:r1","updatedAt":"$now"}"""
                        3 -> """{"id":"nd-9","title":"Holocene","artist":"Bon Iver","state":"failed","detail":"The copy you picked was not the right recording, so it was thrown away. Your copy was kept.","updatedAt":"$now"}"""
                        else -> ""
                    }
                    server.ok(""""upgrades":[$job]""", type = "octo")
                }
                server.answer(
                    "findSongs",
                    """"foundSongs":{"id":"f1","state":"done","song":{"artist":"Bon Iver","title":"Holocene","album":"Bon Iver, Bon Iver","duration":420,"libraryId":"nd-9","format":"flac","quality":"FLAC 16-bit 44.1 kHz","size":52100000,
                    "take":"Yours looks like a live recording. Pick the plain song to replace it.","takeKind":"live"},
                    "source":[{"name":"Soulseek","state":"done","text":"96 files from 31 peers; 3 fit the song","query":["Bon Iver Holocene"]}],
                    "candidate":[
                     {"source":"Soulseek","peer":"northwoods","file":"03 Holocene.flac","folder":"Bon Iver/Bon Iver, Bon Iver","title":"Holocene","album":"Bon Iver, Bon Iver","format":"flac","quality":"FLAC 16-bit 44.1 kHz","size":38200000,"length":298,"freeSlot":true,"speed":1800000,"rank":1,"index":0,"id":"c-1","vsYours":"same","vsYoursText":"Same as yours"},
                     {"source":"Soulseek","peer":"mp3land","file":"Holocene.mp3","title":"Holocene","format":"mp3","quality":"MP3 320 kbps","size":11900000,"length":298,"rank":2,"index":1,"id":"c-2","vsYours":"lower","vsYoursText":"Lower than yours"},
                     {"source":"Soulseek","peer":"eau_claire","file":"Bon Iver - Holocene.flac","title":"Bon Iver - Holocene","format":"flac","quality":"FLAC 24-bit 96 kHz","size":121000000,"length":298,"queueLength":2,"speed":900000,"rank":3,"index":2,"id":"c-3"}]}""",
                    type = "octo",
                )
                server.answerBy("pickFoundSong") { request ->
                    if (request.url.queryParameter("anyway") == "false") {
                        server.ok(
                            """"pick":{"state":"confirm","detail":"Yours looks like a live recording and this copy is the plain song. Replace yours anyway?","key":null,
                            "compare":{"yours":{"quality":"FLAC","length":420,"take":"live recording"},"copy":{"quality":"FLAC","length":298,"take":"the plain song"}}}""",
                            type = "octo",
                        )
                    } else {
                        server.ok(""""pick":{"state":"queued","detail":"Getting it.","key":null}""", type = "octo")
                    }
                }
                server.answer(
                    "getLibraryTrash",
                    """"libraryTrash":{"keepDays":30,"songs":[{"id":"nd-9","title":"Holocene","artist":"Bon Iver","album":"Bon Iver, Bon Iver","kind":"replaced","was":"FLAC 16-bit 44.1 kHz","now":"MP3 320","goneAt":"${Instant.now().plus(Duration.ofDays(29))}"},""" +
                        """{"id":"t2","title":"Nightcall","artist":"Kavinsky","album":"OutRun","goneAt":"${Instant.now().plus(Duration.ofDays(3))}"}]}""",
                    type = "octo",
                )
                rig.signIn()
                val app = rig.app
                fun until(what: String, test: () -> Boolean) {
                    val end = System.currentTimeMillis() + 10_000
                    while (!test() && System.currentTimeMillis() < end) Thread.sleep(50)
                    check(test()) { "never: $what" }
                }
                until("the drawer knows the server asks first") { app.downloads?.asksFirst == true }
                val model = app.downloads!!
                rig.scene(PolishShotsTest.Size.Hd) { scene ->
                    rig.reset(scene)
                    SwingUtilities.invokeAndWait {
                        app.showSidePanel(SidePanel.Downloads)
                        model.find("nd-9", "Holocene")
                    }
                    until("the search ended") { model.found.value?.state == "done" }
                    rig.shot(scene, "replace/1-copies", 1_500)

                    SwingUtilities.invokeAndWait { model.pick("f1", model.found.value!!.candidate.first()) }
                    until("the question came") { model.question.value != null }
                    rig.shot(scene, "replace/2-confirm", 1_500)

                    phase = 1
                    rig.clickText(scene, "Replace anyway")
                    until("the copy is replacing") { "nd-9" in model.replacing.value }
                    model.wake()
                    until("its download shows") { model.rows.value.any { it.findId == "nd-9" && !it.finished } }
                    rig.shot(scene, "replace/3-replacing", 2_000)

                    phase = 2
                    model.wake()
                    until("the notice says it") { app.notice?.startsWith("Replaced") == true }
                    rig.shot(scene, "replace/4-replaced-undo", 1_500)

                    // Once more with another copy, which the server throws away.
                    SwingUtilities.invokeAndWait { model.pick("f1", model.found.value!!.candidate[1]) }
                    until("the question came again") { model.question.value != null }
                    SwingUtilities.invokeAndWait { model.replaceAnyway() }
                    until("the copy is replacing again") { "nd-9" in model.replacing.value }
                    phase = 3
                    model.wake()
                    until("the notice says it was kept") { app.notice?.contains("Your copy was kept") == true }
                    rig.shot(scene, "replace/5-kept", 1_500)

                    SwingUtilities.invokeAndWait {
                        app.showSidePanel(null)
                        app.popups.close()
                        showTrash(app)
                    }
                    rig.shot(scene, "replace/6-recently-removed", 2_000)
                }
            }
        }
    }
}
