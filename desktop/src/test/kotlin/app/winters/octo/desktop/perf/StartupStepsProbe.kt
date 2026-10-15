package app.winters.octo.desktop.perf

import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.ImageComposeScene
import androidx.compose.ui.unit.Density
import app.winters.octo.design.LocalTyping
import app.winters.octo.design.TypingState
import app.winters.octo.desktop.AppState
import app.winters.octo.desktop.audio.NativeAudioEngine
import app.winters.octo.desktop.secrets.SecretStore
import app.winters.octo.desktop.secrets.SessionOnlySecrets
import app.winters.octo.desktop.server.Accounts
import app.winters.octo.desktop.server.ServerSecurity
import app.winters.octo.desktop.settings.AppPlaces
import app.winters.octo.desktop.settings.DesktopOs
import app.winters.octo.desktop.settings.SettingsStore
import app.winters.octo.desktop.settings.systemReducesMotion
import app.winters.octo.desktop.settings.systemTextScale
import app.winters.octo.desktop.system.SingleInstance
import app.winters.octo.desktop.system.useAppNatives
import app.winters.octo.desktop.ui.Shell
import app.winters.octo.desktop.update.DesktopUpdates
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import okhttp3.OkHttpClient
import java.io.File
import java.nio.file.Files
import java.util.concurrent.TimeUnit
import javax.swing.SwingUtilities
import kotlin.system.exitProcess

private fun since(): Long = System.currentTimeMillis() - ProcessHandle.current().info().startInstant().get().toEpochMilli()

// Times each step the app takes before and around its window, one after
// another, on whatever runtime runs it (scripts/startup-probe.py --steps):
// main's own (the settings, the one-Octo lock), what Startup does on its
// threads (the HTTP client, the password store, the engine and the rest),
// then the app state and the signed-out first frame on the window's
// thread. `octo.probe.settings` names a settings file to start from,
// copied into a folder of its own; nothing is signed in.
fun main() {
    useAppNatives()
    val folder = Files.createTempDirectory("octo-steps").toFile()
    val steps = mutableListOf<Pair<String, Long>>()
    var last = System.nanoTime()
    fun step(name: String) {
        val now = System.nanoTime()
        steps += name to (now - last) / 1_000_000
        last = now
    }
    try {
        val start = since()
        val places = AppPlaces(File(folder, "config"), File(folder, "cache"))
        System.getProperty("octo.probe.settings")?.let { File(it).copyTo(File(places.config, SettingsStore.FILE_NAME)) }
        step("places")
        val claim = SingleInstance.claim(places.config, emptyList())
        step("single instance")
        val settings = SettingsStore(File(places.config, SettingsStore.FILE_NAME), SettingsStore.APP_WRITE_DELAY_MS)
        settings.current
        step("settings")
        val security = ServerSecurity(settings)
        val http = security.install(OkHttpClient.Builder()).connectTimeout(15, TimeUnit.SECONDS).build()
        step("tls and http client")
        val store = SecretStore.forSystem()
        runCatching { store.read("octo-probe@nowhere.invalid") }
        step("password store")
        val accounts = Accounts(settings, SessionOnlySecrets(), http, security)
        accounts.restore()
        step("accounts")
        systemReducesMotion(DesktopOs.Windows)
        systemTextScale(DesktopOs.Windows)
        step("system motion and text")
        app.winters.octo.desktop.system.OctopusArt.icon(32)
        step("icon (loads skia)")
        DesktopUpdates.forThisApp(settings, places.cache, DesktopOs.Windows)
        step("updates")
        val engine = NativeAudioEngine.open(silent = true)
        step("audio engine (silent)")
        runCatching { com.sun.jna.NativeLibrary.getInstance("octo_system") }
        step("system library")
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
        lateinit var app: AppState
        SwingUtilities.invokeAndWait { app = AppState(settings, accounts, http, scope, DesktopOs.Windows, restored = null) }
        step("app state (EDT)")
        SwingUtilities.invokeAndWait {
            val scene = ImageComposeScene(1440, 900, Density(1f), coroutineContext = Dispatchers.Main) {
                CompositionLocalProvider(LocalTyping provides TypingState()) { Shell(app, null) {} }
            }
            scene.render(0).close()
        }
        step("first frame, signed out (EDT)")
        engine.close()
        (claim as? SingleInstance.Claim.First)?.instance?.close()
        println("steps: main began ${start} ms after the process started")
        steps.forEach { (name, ms) -> println("step %-32s %6d ms".format(name, ms)) }
        println("steps: done ${since()} ms after the process started")
    } catch (e: Throwable) {
        e.printStackTrace()
        exitProcess(1)
    } finally {
        folder.deleteRecursively()
    }
    exitProcess(0)
}
