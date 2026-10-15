package app.winters.octo.desktop.system

import app.winters.octo.desktop.player.DesktopPlayer
import com.sun.jna.Callback
import com.sun.jna.Library
import com.sun.jna.Native
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

// Octo on the Windows taskbar: the thumbnail's buttons and the progress on
// its button, and the jump list. Everything goes through the system
// library (desktop/system-shim), version 3 on. A call that fails is logged
// and otherwise left alone: the taskbar is a nicety, never a reason to stop.

// The taskbar and jump list calls of the system library.
@Suppress("FunctionName")
internal interface ShellLibrary : Library {
    fun octo_system_version(): Int

    fun octo_taskbar_attach(window: Long, callback: ButtonCallback?): Int

    fun octo_taskbar_detach()

    fun octo_taskbar_icon_size(): Int

    fun octo_taskbar_set_icons(pixels: ByteArray, length: Long, size: Int): Int

    fun octo_taskbar_set_buttons(shown: Int, playing: Int, previous: Int, toggle: Int, next: Int, previousTip: String, toggleTip: String, nextTip: String): Int

    fun octo_taskbar_set_progress(kind: Int, done: Long, total: Long): Int

    fun octo_taskbar_sync_now(): Int

    fun octo_jump_list_set(appId: String?, program: String, items: String, removed: ByteArray?, capacity: Long): Long

    fun octo_jump_list_removed(appId: String?, removed: ByteArray?, capacity: Long): Long

    fun octo_jump_list_clear(appId: String?): Int
}

// A thumbnail button click: 1 previous, 2 play or pause, 3 next.
internal fun interface ButtonCallback : Callback {
    fun invoke(button: Int)
}

// The thumbnail's buttons by the library's numbers.
enum class TaskbarButton(val code: Int) { Previous(1), Toggle(2), Next(3) }

fun taskbarButtonOf(code: Int): TaskbarButton? = TaskbarButton.entries.firstOrNull { it.code == code }

// The first version of the system library with the taskbar and jump list.
private const val SHELL_VERSION = 3

// The library with the taskbar and jump list, or null where there is none
// (macOS, Linux, an older library, a build made without it).
internal fun loadShellLibrary(): ShellLibrary? = try {
    if (!System.getProperty("os.name").orEmpty().startsWith("Windows")) {
        null
    } else {
        Native.load("octo_system", ShellLibrary::class.java, mapOf(Library.OPTION_STRING_ENCODING to "UTF-8"))
            .takeIf { it.octo_system_version() >= SHELL_VERSION }
    }
} catch (e: UnsatisfiedLinkError) {
    null
} catch (e: RuntimeException) {
    null
}

// Through the platform logger, which needs nothing beyond the base runtime.
internal val shellLog: System.Logger = System.getLogger("octo.windows-shell")

// Logs a call that did not work, once per kind of failure.
internal class QuietFailures {
    private val seen = HashSet<String>()

    fun check(what: String, answer: Long) {
        if (answer >= 0) return
        val key = "$what:$answer"
        if (synchronized(seen) { seen.add(key) }) shellLog.log(System.Logger.Level.INFO, "$what did not work: 0x${java.lang.Long.toHexString(answer and 0xFFFFFFFFL)}")
    }
}

// Keeps the taskbar button in step with the player. All library calls run
// in order on one thread of their own.
class WindowsTaskbar internal constructor(
    private val library: ShellLibrary,
    private val player: DesktopPlayer,
    private val scope: CoroutineScope,
    private val lightTaskbar: () -> Boolean = ::taskbarIsLight,
    private val clock: () -> Long = System::currentTimeMillis,
) : AutoCloseable {
    private val worker: ExecutorService = Executors.newSingleThreadExecutor { task -> Thread(task, "octo-taskbar-calls").apply { isDaemon = true } }
    private val throttle = TaskbarThrottle()
    private val failures = TaskbarFailures()
    private val quiet = QuietFailures()
    private val jobs = ArrayList<Job>()

    // Held here so the JVM never frees it while the library can call it.
    private var callback: ButtonCallback? = null
    private var light: Boolean? = null
    private var stopIcon: Boolean? = null

    // Starts looking after the window's taskbar button. `window` is its
    // handle; clicks come back to `onButton` on the app's scope.
    fun attach(window: Long, onButton: (TaskbarButton) -> Unit) {
        if (window == 0L) return
        val listener = ButtonCallback { code -> taskbarButtonOf(code)?.let { button -> scope.launch { onButton(button) } } }
        callback = listener
        later("Taking on the taskbar button") { library.octo_taskbar_attach(window, listener).toLong() }
        icons()
        jobs += scope.launch { player.state.collect { update() } }
        // The place moves on by itself while a song plays, a failure's red
        // runs out, and the taskbar's theme can change. Paused, only the
        // theme is looked at, now and then.
        jobs += scope.launch {
            var themeAt = clock()
            player.state.collectLatest { state ->
                while (true) {
                    delay(if (state.playing || failures.showing(clock())) TICK_MS else THEME_EVERY_MS)
                    update()
                    if (clock() - themeAt >= THEME_EVERY_MS) {
                        themeAt = clock()
                        icons()
                    }
                }
            }
        }
    }

    // The icons at the size Windows wants, for the taskbar's theme, when
    // that theme changed.
    private fun icons(stop: Boolean = stopIcon == true) {
        val now = runCatching(lightTaskbar).getOrDefault(false)
        if (now == light && stop == stopIcon) return
        light = now
        stopIcon = stop
        later("Drawing the taskbar icons") {
            val size = library.octo_taskbar_icon_size().takeIf { it in 8..256 } ?: 16
            val pixels = taskbarIconPixels(size, taskbarIconColour(now), stop)
            library.octo_taskbar_set_icons(pixels, pixels.size.toLong(), size).toLong()
        }
    }

    private fun update() {
        val state = player.state.value
        val now = clock()
        val view = taskbarViewOf(state, player.positionMs(), failures.failing(state.problem, now))
        val (buttons, progress) = throttle.next(view, now)
        // A live station's middle button is Stop: its icon is drawn first.
        buttons?.let { b -> if (b.live != stopIcon) icons(stop = b.live) }
        buttons?.let { b ->
            later("Showing the taskbar buttons") {
                library.octo_taskbar_set_buttons(1, b.playing.bit(), b.previous.bit(), b.toggle.bit(), b.next.bit(), b.previousTip, b.toggleTip, b.nextTip).toLong()
            }
        }
        progress?.let { p -> later("Showing the song's progress") { library.octo_taskbar_set_progress(p.kind.code, p.doneMs, p.totalMs).toLong() } }
    }

    private fun Boolean.bit() = if (this) 1 else 0

    private fun later(what: String, call: () -> Long) {
        if (worker.isShutdown) return
        runCatching { worker.execute { quiet.check(what, runCatching(call).getOrDefault(-4L)) } }
    }

    override fun close() {
        jobs.forEach { it.cancel() }
        later("Letting go of the taskbar button") {
            library.octo_taskbar_detach()
            0
        }
        worker.shutdown()
        runCatching { worker.awaitTermination(QUIT_WAIT_MS, TimeUnit.MILLISECONDS) }
    }

    private companion object {
        const val TICK_MS = 250L

        // How often the taskbar's theme is looked at again.
        const val THEME_EVERY_MS = 10_000L
    }
}

// Whether the taskbar and Start are light, as Windows keeps it.
fun taskbarIsLight(): Boolean =
    WindowsRegistry.firstByte("Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize", "SystemUsesLightTheme") == 1

// Fills the jump list from the record, whenever it changes, and hands back
// the entries the listener took out of it.
class WindowsJumpList internal constructor(
    private val library: ShellLibrary,
    private val program: String,
    // Null for the app's own list; the tests use their own id.
    private val appId: String? = null,
) : AutoCloseable {
    private val worker: ExecutorService = Executors.newSingleThreadExecutor { task -> Thread(task, "octo-jump-list-calls").apply { isDaemon = true } }
    private val quiet = QuietFailures()

    // Sets the list to `items`, then tells `removed` the links the listener
    // had taken out, off the window's thread.
    fun publish(items: List<JumpItem>, removed: (List<String>) -> Unit = {}) {
        val text = jumpListText(items)
        later {
            val buffer = ByteArray(REMOVED_ROOM)
            val answer = library.octo_jump_list_set(appId, program, text, buffer, buffer.size.toLong())
            quiet.check("Setting the jump list", answer)
            if (answer > 0) removed(removedLinks(buffer, answer))
        }
    }

    // Empties the list, as when signing out.
    fun clear() = later { quiet.check("Emptying the jump list", library.octo_jump_list_clear(appId).toLong()) }

    private fun later(call: () -> Unit) {
        if (worker.isShutdown) return
        runCatching { worker.execute { runCatching(call) } }
    }

    // Waits for the calls sent so far, for the tests.
    internal fun settle() {
        runCatching { worker.submit {}.get(10, TimeUnit.SECONDS) }
    }

    override fun close() {
        worker.shutdown()
        runCatching { worker.awaitTermination(QUIT_WAIT_MS, TimeUnit.MILLISECONDS) }
    }

    private companion object {
        const val REMOVED_ROOM = 16 * 1024
    }
}

// The links in the library's answer, one a line, as much as came back.
fun removedLinks(buffer: ByteArray, length: Long): List<String> =
    buffer.copyOf(length.coerceIn(0, buffer.size.toLong()).toInt()).decodeToString().lines().map(String::trim).filter(String::isNotEmpty)
