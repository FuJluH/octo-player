package app.winters.octo.desktop.ui

import app.winters.octo.desktop.FakeServer
import app.winters.octo.desktop.nav.Page
import app.winters.octo.desktop.pages.askToPaste
import app.winters.octo.desktop.pages.showSection
import app.winters.octo.subsonic.ImportServiceLink
import app.winters.octo.ui.imports.IMPORT
import org.junit.Assume.assumeTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import javax.swing.SwingUtilities

// Import as it looks: Get my music's tiles, the wait for a file and what the
// server said, the public link, the lists with their switches, one list's
// songs, and the trickle. Made-up lists, from a pretend Octo server.
// Only when asked: OCTO_SHOTS=1 ./gradlew :desktop:test --tests '*ImportShotsTest*'.
// Saved under build/shots/polish/imports/.
class ImportShotsTest {
    @get:Rule val folder = TemporaryFolder()

    private fun track(key: String, title: String, artist: String, album: String, state: String, detail: String? = null, progress: Double? = null) =
        """{"key":"$key","title":"$title","artist":"$artist","album":"$album","seconds":240,"state":"$state",
        "detail":${detail?.let { "\"$it\"" } ?: "null"},"progress":${progress ?: "null"}}"""

    @Test
    fun drawImport() {
        assumeTrue(System.getenv("OCTO_SHOTS") == "1")
        FakeServer().use { server ->
            PolishShotsTest.Rig(folder, PolishData.library(100), server).use { rig ->
                server.answer(
                    "getOpenSubsonicExtensions",
                    """"openSubsonicExtensions":[{"name":"songLyrics","versions":[1]},{"name":"octoImports","versions":[1,2]}]""",
                    type = "octo",
                )
                server.answer("getImportServices", """"importServices":{"services":[${SERVICES.joinToString(",") { (id, name) ->
                    """{"id":"$id","name":"$name","exportUrl":"https://www.tunemymusic.com/transfer/$id-to-file","tile":"$name"}"""
                }}]}""", type = "octo")
                server.answer("importFile", """"importAction":{"ok":true,"message":"Read 2 lists, 340 songs."}""", type = "octo")
                val angel = track("s:2", "Angel", "Massive Attack", "Mezzanine", "downloading", "Downloading from Soulseek", 0.42)
                server.answer(
                    "getImports",
                    """"imports":{"approval":{"needed":true,"by":"Sam"},
                    "lists":[
                      {"id":"spotify-liked","name":"Liked Songs","source":"spotifyLiked","total":412,"have":371,"missing":28,"queued":9,"downloading":1,"notFound":3,"getMissing":true,"canRefresh":true},
                      {"id":"spotify-road","name":"Road trip","source":"spotifyPlaylist","total":48,"have":44,"missing":4,"keepPlaylist":true,"playlistId":"pl1","canRefresh":true},
                      {"id":"spotify-hits","name":"Today's Top Hits","source":"spotifyPlaylist","by":"Spotify","total":50,"have":12,"missing":38,"canRefresh":true,
                       "partial":"Spotify shows Octo only the songs of playlists you made, so Octo read this one from its public page, which lists the first 100."},
                      {"id":"file-gym","name":"Gym","source":"file","total":31,"have":31}],
                    "trickle":{"state":"running","perHour":20,"queued":9,"downloading":1,"done":14,"notFound":3,"nextUtc":"2026-10-04T22:15:00Z",
                      "current":$angel,
                      "next":[${track("s:3", "Ivy", "Frank Ocean", "Blonde", "queued")},${track("s:4", "Pink + White", "Frank Ocean", "Blonde", "queued")}],
                      "recent":[${track("s:5", "Time to Pretend", "MGMT", "Oracular Spectacular", "notFound", "No download source could get this song.")},
                                ${track("s:6", "Dreams", "Fleetwood Mac", "Rumours", "done", "Fetched from Soulseek")}]}}""",
                    type = "octo",
                )
                server.answer(
                    "getImport",
                    """"import":{"list":{"id":"spotify-road","name":"Road trip","source":"spotifyPlaylist","total":48,"have":44,"missing":4},"tracks":[
                      ${track("s:1", "Teardrop", "Massive Attack", "Mezzanine", "have")},$angel,
                      ${track("s:7", "Go Your Own Way", "Fleetwood Mac", "Rumours", "missing")},
                      ${track("s:5", "Time to Pretend", "MGMT", "Oracular Spectacular", "notFound", "No download source could get this song.")}]}""",
                    type = "octo",
                )
                rig.signIn()
                val app = rig.app
                val apple = ImportServiceLink("apple-music", "Apple Music", "https://www.tunemymusic.com/transfer/apple-music-to-file", "Apple Music")
                for (size in listOf(PolishShotsTest.Size.Hd, PolishShotsTest.Size.Min)) {
                    rig.scene(size) { scene ->
                        val at = "imports/${size.label}"
                        for (section in listOf("get", "link", "lists", "trickle")) {
                            rig.reset(scene)
                            SwingUtilities.invokeAndWait {
                                app.imports.backToServices()
                                showSection(IMPORT, section)
                                app.navigator.go(Page.Imports)
                            }
                            rig.shot(scene, "$at/$section", 2_000)
                        }
                        rig.reset(scene)
                        SwingUtilities.invokeAndWait {
                            showSection(IMPORT, "get")
                            app.imports.openExport(apple)
                            app.navigator.go(Page.Imports)
                        }
                        rig.shot(scene, "$at/get-waiting", 2_000)
                        rig.reset(scene)
                        SwingUtilities.invokeAndWait {
                            showSection(IMPORT, "get")
                            app.imports.sendFile("Apple Music.csv", "Track name,Artist name\nAngel,Massive Attack\n".toByteArray())
                            app.navigator.go(Page.Imports)
                        }
                        rig.shot(scene, "$at/get-sent", 3_000)
                        rig.reset(scene)
                        SwingUtilities.invokeAndWait {
                            app.imports.backToServices()
                            showSection(IMPORT, "lists")
                            app.imports.open("spotify-road")
                            app.navigator.go(Page.Imports)
                        }
                        rig.shot(scene, "$at/list-open", 2_000)
                        SwingUtilities.invokeAndWait { app.imports.close() }
                        rig.reset(scene)
                        SwingUtilities.invokeAndWait {
                            showSection(IMPORT, "get")
                            app.navigator.go(Page.Imports)
                            askToPaste(app.popups, app.imports)
                        }
                        rig.shot(scene, "$at/paste", 2_000)
                        SwingUtilities.invokeAndWait { app.popups.close() }
                    }
                }
            }
        }
    }

    private companion object {
        val SERVICES = listOf(
            "spotify" to "Spotify",
            "apple-music" to "Apple Music",
            "youtube-music" to "YouTube Music",
            "amazon-music" to "Amazon Music",
            "tidal" to "TIDAL",
            "deezer" to "Deezer",
            "qobuz" to "Qobuz",
            "soundcloud" to "SoundCloud",
            "pandora" to "Pandora",
            "youtube" to "YouTube",
        )
    }
}
