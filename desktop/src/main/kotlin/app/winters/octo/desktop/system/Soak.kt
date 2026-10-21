package app.winters.octo.desktop.system

import androidx.compose.runtime.snapshotFlow
import app.winters.octo.desktop.AppState
import app.winters.octo.desktop.SidePanel
import app.winters.octo.animated.KnownArt
import app.winters.octo.desktop.animated.LoopShape
import app.winters.octo.desktop.animated.clip
import app.winters.octo.desktop.player.RepeatMode
import app.winters.octo.desktop.playStations
import app.winters.octo.desktop.radioId
import app.winters.octo.liveradio.radioId
import app.winters.octo.subsonic.Song
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.delay
import app.winters.octo.desktop.library.LibraryState
import kotlinx.coroutines.flow.filterIsInstance
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import java.io.File
import java.util.Properties
import kotlin.random.Random

// Set to a plan file, the app plays by itself for as long as it runs once
// its window is up, for measuring its memory over hours
// (scripts/soak-desktop.ps1). It plays at no volume (the player's own, for
// this run only), keeps the full player open with the lyrics beside the
// cover or not, and moves to the next song every `advance` seconds (0 lets
// each one play out), round the queue again and again. The plan is a
// properties file:
//   source=library   songs from albums with a tall animated loop first
//                    (`songs` of them, asking about at most `ask` albums),
//                    or radio: the server's stations, else the kept ones
//   lyrics=on|off    the lyrics beside the cover
//   full=on|off      the full player open, or Home behind the player bar
//   pauseAfter=20    minutes before it pauses and stays paused (0, never)
//   cacheAfter=30:32 minutes before the window's graphics card cache limit
//                    is set to that many MB, to see what it gives back
//   advance=45       seconds a song plays before the next
//   queue=<file>     the songs picked, written by the first run and read by
//                    the next ones, so every run plays the same songs
// What it plays is written to <plan>.events, a line each.
const val SOAK_RUN = "octo.soak"

suspend fun soakRun(app: AppState, plan: File) {
    val wants = Properties().apply { plan.inputStream().use(::load) }
    val events = File(plan.path + ".events")
    fun note(line: String) {
        runCatching { events.appendText("${System.currentTimeMillis()} $line\n") }
    }
    val advance = wants.getProperty("advance", "45").toLong()
    val lyrics = wants.getProperty("lyrics", "on") == "on"
    val full = wants.getProperty("full", "on") == "on"
    val pauseAfter = wants.getProperty("pauseAfter", "0").toLong() * 60_000
    val cacheAfter = wants.getProperty("cacheAfter", "").split(":").mapNotNull(String::toLongOrNull).takeIf { it.size == 2 }
    var cacheSet = false
    val radio = wants.getProperty("source", "library") == "radio"
    note("start source=${if (radio) "radio" else "library"} lyrics=$lyrics full=$full advance=$advance")

    val index = withTimeoutOrNull(300_000) {
        val library = snapshotFlow { app.library }.filterNotNull().first()
        library.state.filterIsInstance<LibraryState.Ready>().first().index
    }
    if (index == null) return note("stop: the library was not read within 5 minutes")
    app.player.setVolume(0f)
    if (radio) {
        val ids = soakStations(app)
        if (ids.isEmpty()) return note("stop: no radio stations")
        note("stations ${ids.size}")
        app.playStations(ids, 0, "Soak")
    } else {
        val songs = soakSongs(app, index.songs, wants, ::note)
        if (songs.isEmpty()) return note("stop: no songs")
        note("songs ${songs.size}")
        app.play(songs, 0, source = "Soak")
    }
    app.player.setRepeat(RepeatMode.All)
    var played = 0
    val started = System.currentTimeMillis()
    while (true) {
        if (cacheAfter != null && !cacheSet && System.currentTimeMillis() - started >= cacheAfter[0] * 60_000) {
            cacheSet = true
            windowContext()?.resourceCacheLimit = cacheAfter[1] * 1024 * 1024
            note("cache limit set to ${cacheAfter[1]} MB, now ${gpuCacheLimit()}")
        }
        if (pauseAfter > 0 && System.currentTimeMillis() - started >= pauseAfter) {
            app.player.pause()
            note("paused gpuCache=${gpuCacheLimit()}")
            awaitCancellation()
        }
        app.player.setVolume(0f)
        app.fullPlayer = full
        if ((app.playerPanel == SidePanel.Lyrics) != lyrics) app.togglePlayerPanel(SidePanel.Lyrics)
        val now = app.player.state.value
        note("playing ${played++} ${now.current?.song?.id} album=${now.current?.song?.albumId} playing=${now.playing} gpuCache=${gpuCacheLimit()}")
        now.current?.song?.let { song ->
            val art = song.albumId?.let { (app.animated.book?.peek(it) as? KnownArt.Has)?.art }
            note("art title=${song.title} album=${song.album} tall=${art?.tall?.video} poster=${art?.tall?.poster}")
        }
        if (advance > 0) {
            delay(advance * 1000)
            app.player.next()
        } else {
            val key = now.current?.key
            withTimeoutOrNull(15 * 60_000) { app.player.state.first { it.current?.key != key } }
            // A queue that stopped at its end starts over.
            if (!app.player.state.value.playing) app.player.togglePlay()
        }
    }
}

// The graphics card cache limit of the window's drawing, in bytes, as Skia
// has it: skiko keeps the context out of reach, so it is read by reflection
// (null when its insides differ, or it draws without the card).
private fun gpuCacheLimit(): Long? = windowContext()?.resourceCacheLimit

private fun windowContext(): org.jetbrains.skia.DirectContext? = runCatching {
    fun find(component: java.awt.Component): org.jetbrains.skiko.SkiaLayer? {
        if (component is org.jetbrains.skiko.SkiaLayer) return component
        if (component is java.awt.Container) component.components.forEach { child -> find(child)?.let { return it } }
        return null
    }
    val layer = java.awt.Window.getWindows().firstNotNullOfOrNull(::find) ?: return null
    val redrawer = layer.javaClass.getMethod("getRedrawer\$skiko").invoke(layer) ?: return null
    val handler = redrawer.javaClass.getDeclaredField("contextHandler").apply { isAccessible = true }.get(redrawer) ?: return null
    val context = Class.forName("org.jetbrains.skiko.context.ContextHandler").getDeclaredMethod("getContext").apply { isAccessible = true }.invoke(handler)
    context as? org.jetbrains.skia.DirectContext
}.getOrNull()

// The songs a library run plays: the ones picked by an earlier run, or one
// song from each album with a tall loop, the rest from any album.
private suspend fun soakSongs(app: AppState, library: List<Song>, wants: Properties, note: (String) -> Unit): List<Song> {
    val queue = wants.getProperty("queue")?.let(::File)
    val byId = library.associateBy { it.id }
    queue?.takeIf { it.exists() }?.let { file ->
        val ids = withContext(Dispatchers.IO) { file.readLines() }.filter(String::isNotBlank)
        return ids.mapNotNull(byId::get)
    }
    val count = wants.getProperty("songs", "60").toInt()
    val ask = wants.getProperty("ask", "200").toInt()
    val random = Random(7)
    val albums = library.groupBy { it.albumId }.filterKeys { it != null }.entries.shuffled(random)
    val book = withTimeoutOrNull(60_000) { snapshotFlow { app.animated.book }.filterNotNull().first() }
    val picked = mutableListOf<Song>()
    val plain = mutableListOf<Song>()
    for ((at, entry) in albums.withIndex()) {
        if (picked.size >= count) break
        val song = entry.value.random(random)
        val art = if (book != null && at < ask) runCatching { book.art(entry.key!!) }.getOrNull() else null
        if (art?.clip(LoopShape.Tall) != null) picked += song else plain += song
    }
    val songs = picked + plain.take(count - picked.size)
    runCatching { File(wants.getProperty("events", "")).takeIf { it.path.isNotBlank() }?.appendText("${System.currentTimeMillis()} picked ${picked.size} with a tall loop of ${songs.size}\n") }
    queue?.let { file -> withContext(Dispatchers.IO) { file.writeText(songs.joinToString("\n") { it.id }) } }
    return songs
}

// The stations a radio run plays: the server's, else the ones kept here,
// without their catalog ids, so the catalog never hears of these starts.
private suspend fun soakStations(app: AppState): List<String> {
    app.liveRadio.readServerStations()
    val server = app.liveRadio.serverStations.orEmpty().filter { it.streamUrl.isNotBlank() }
    if (server.isNotEmpty()) return server.map { it.radioId() }
    return app.liveRadio.kept().stations.map { it.copy(uuid = "").radioId() }
}
