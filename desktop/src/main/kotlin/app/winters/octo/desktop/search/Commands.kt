package app.winters.octo.desktop.search

import app.winters.octo.desktop.AppState
import app.winters.octo.desktop.SidePanel
import app.winters.octo.desktop.liveradio.LIVE_RADIO_NEAR
import app.winters.octo.desktop.nav.Page
import app.winters.octo.desktop.pages.RADIO_SECTION
import app.winters.octo.desktop.pages.STATIONS_ON_SERVER
import app.winters.octo.animated.AnimatedArtSetting
import app.winters.octo.desktop.pages.addServer
import app.winters.octo.desktop.pages.showSection
import app.winters.octo.desktop.pages.switchServer
import app.winters.octo.desktop.settings.name
import app.winters.octo.desktop.player.RepeatMode
import app.winters.octo.desktop.ui.newLiveList
import app.winters.octo.desktop.ui.newPlaylist
import app.winters.octo.playback.SleepState
import app.winters.octo.subsonic.SubsonicException
import app.winters.octo.ui.family.FAMILY
import app.winters.octo.ui.imports.IMPORT_SERVICE_WORDS
import kotlinx.coroutines.launch
import java.text.Normalizer

// Something the search box can do rather than find: open a page, run the
// player, change a panel. `words` are other names it answers to.
class Command(
    val title: String,
    val group: String,
    val words: String = "",
    val run: () -> Unit,
)

// Every command that makes sense right now, in the order they are offered
// with nothing typed.
fun commandsFor(app: AppState): List<Command> = buildList {
    val go = "Go to"
    fun page(title: String, page: Page, words: String = "") = add(Command(title, go, "open show page $words") { app.fullPlayer = false; app.navigator.go(page) })
    page("Home", Page.Home)
    page("Songs", Page.Songs, "library tracks")
    page("Albums", Page.Albums, "library")
    page("Artists", Page.Artists, "library")
    page("Genres", Page.Genres, "library")
    page("Folders", Page.Folders, "files")
    page("Favorites", Page.Favourites, "liked starred hearts")
    page("Recently played", Page.History, "history")
    page("Recently added", Page.RecentlyAdded, "new")
    page("Library health", Page.LibraryHealth, "duplicates missing tags problems")
    if (app.connection?.isOcto == true) {
        val services = app.imports.services?.services.orEmpty().joinToString(" ") { it.name }
        page("Import", Page.Imports, "get my music move transfer $IMPORT_SERVICE_WORDS $services tunemymusic playlists liked songs file csv txt paste list missing download")
    }
    page(LIVE_RADIO_NEAR, Page.LiveRadio, "live radio stations fm am local near me nearby internet stream broadcast")
    if (app.connection?.family == true) page(FAMILY, Page.Family, "family members requests devices plan approve")
    if (app.search?.charts?.offered == true) page("Charts", Page.Charts, "top songs popular right now best new trending genre chart hip hop pop country")
    page("Sound", Page.Sound, "equalizer eq loudness crossfade blend transitions automix tempo")
    page("Settings", Page.Settings, "preferences options")
    // Settings' Radio section, by what each of its parts holds.
    fun radio(title: String, words: String) = add(Command(title, go, "open settings radio $words") {
        app.fullPlayer = false
        showSection("Settings", RADIO_SECTION)
        app.navigator.go(Page.Settings)
    })
    radio("Song radio settings", "start radio autoplay discovery adventure artist variety favorites more often tuning similar songs")
    radio(STATIONS_ON_SERVER, "live radio internet radio stations streams add a station edit fm")
    add(Command("Accent color", "Settings", "theme colour tint highlight palette appearance album art cover") {
        app.fullPlayer = false
        showSection("Settings", "look")
        app.navigator.go(Page.Settings)
    })
    add(Command(AnimatedArtSetting.TITLE, go, "settings animated covers album art loops apple music full screen square still") {
        app.fullPlayer = false
        showSection("Settings", "look")
        app.navigator.go(Page.Settings)
    })
    app.liveLists.lists.value.forEach { list -> page(list.name, Page.LiveList(list.id), "live list smart playlist") }

    val state = app.player.state.value
    val song = state.current?.song
    val player = "Player"
    if (song != null) {
        add(Command(if (state.playing) "Pause" else "Play", player, "resume toggle") { app.player.togglePlay() })
        add(Command("Next song", player, "skip") { app.player.next() })
        add(Command("Previous song", player, "back") { app.player.previous() })
        add(Command(if (state.stopAfterCurrent) "Keep playing after this song" else "Stop after this song", player, "end") { app.player.setStopAfterCurrent(!state.stopAfterCurrent) })
        song.albumId?.takeIf(String::isNotBlank)?.let { id -> add(Command("Go to the album playing", go, "current song") { app.navigator.go(Page.Album(id)) }) }
        song.artistId?.takeIf(String::isNotBlank)?.let { id -> add(Command("Go to the artist playing", go, "current song") { app.navigator.go(Page.Artist(id, song.artist.orEmpty())) }) }
        add(Command("Open the player", player, "full now playing") { app.fullPlayer = true })
    }
    add(Command(if (state.shuffle) "Turn shuffle off" else "Turn shuffle on", player, "random") { app.player.setShuffle(!state.shuffle) })
    val nextRepeat = RepeatMode.entries[(state.repeat.ordinal + 1) % RepeatMode.entries.size]
    add(Command(when (nextRepeat) { RepeatMode.Off -> "Turn repeat off"; RepeatMode.All -> "Repeat all"; RepeatMode.One -> "Repeat one" }, player, "loop") { app.player.setRepeat(nextRepeat) })
    listOf(15, 30, 60).forEach { minutes ->
        add(Command("Sleep in ${if (minutes == 60) "1 hour" else "$minutes minutes"}", player, "sleep timer stop") { app.sleep.start(minutes) })
    }
    if (app.sleep.state.value != SleepState.Off) add(Command("Turn off the sleep timer", player, "sleep cancel") { app.sleep.cancel() })

    val view = "View"
    add(Command("Show the queue", view, "up next panel") { app.showSidePanel(SidePanel.Queue) })
    add(Command("Show lyrics", view, "words panel") { app.showSidePanel(SidePanel.Lyrics) })
    add(Command("Show song details", view, "info panel") { app.showInfo(null) })
    if (app.downloads?.supported == true) add(Command("Show downloads", view, "downloads log progress drawer") { app.showSidePanel(SidePanel.Downloads) })
    if (app.sidePanel != null) add(Command("Close the side panel", view, "hide panel") { app.showSidePanel(null) })
    add(Command(if (app.settings.current.frame.sidebarRail) "Unfold the sidebar" else "Fold the sidebar to icons", view, "sidebar rail compact") { app.updateFrame { it.copy(sidebarRail = !it.sidebarRail) } })
    app.toggleMiniPlayer?.let { toggle -> add(Command("Mini player", view, "small window compact") { toggle() }) }

    val output = "Output"
    state.outputs.forEach { device ->
        if (device.id != state.output?.id) add(Command("Play on ${device.name}", output, "output device speakers headphones sound") { app.selectOutput(device.id) })
    }

    // Every other kept server, to switch to in one go.
    val servers = "Servers"
    app.accounts.servers.filter { it.id != app.connection?.server?.id }.forEach { server ->
        add(Command("Switch to ${server.name}", servers, "server change account ${server.username}") { switchServer(app, server.id) })
    }
    add(Command("Add a server", servers, "new server account connect") { addServer(app) })

    val library = "Library"
    add(Command("New playlist", library, "create make") { newPlaylist(app) })
    add(Command("New live list", library, "create make smart playlist rules auto") { newLiveList(app) })
    add(Command("Shuffle all songs", library, "random play everything") { app.library?.index?.songs?.let { app.play(it, shuffle = true) } })
    add(Command("Play favorites", library, "liked starred hearts") { playFavourites(app) })
    add(Command("Read the library again", library, "refresh reload rescan scan") { app.library?.load(); app.refreshPlaylists() })
}

// Plays the songs starred on the server, shuffled, or says there are none.
private fun playFavourites(app: AppState) {
    val client = app.connection?.client ?: return
    app.scope.launch {
        try {
            val songs = client.starred().song.filter(app::isStarred)
            if (songs.isEmpty()) app.notice = "No favorite songs yet." else app.play(songs, shuffle = true)
        } catch (e: SubsonicException) {
            app.notice = "Couldn't read your favorites."
        }
    }
}

// The commands that answer what was typed: every word typed must start a
// word of the command's title or other names. Titles that start with what
// was typed come first, then the rest in their usual order.
fun matchCommands(commands: List<Command>, typed: String): List<Command> {
    val wanted = fold(typed).split(' ').filter(String::isNotBlank)
    if (wanted.isEmpty()) return commands
    val matched = commands.filter { command ->
        val words = fold("${command.title} ${command.words} ${command.group}").split(' ')
        wanted.all { want -> words.any { it.startsWith(want) } }
    }
    val start = fold(typed).trim()
    return matched.sortedBy { if (fold(it.title).startsWith(start)) 0 else 1 }
}

private val Marks = Regex("\\p{M}")

private fun fold(text: String): String = Normalizer.normalize(text.lowercase(), Normalizer.Form.NFD).replace(Marks, "")
