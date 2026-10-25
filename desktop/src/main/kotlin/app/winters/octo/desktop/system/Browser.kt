package app.winters.octo.desktop.system

import app.winters.octo.desktop.settings.DesktopOs
import app.winters.octo.desktop.settings.currentOs
import java.awt.Desktop
import java.net.URI
import java.util.concurrent.CompletableFuture
import java.util.concurrent.TimeUnit

// Opens a web address in the person's own browser: Java's way where the
// platform has one, else the platform's own command. Only http and https,
// so nothing else can be launched through it. False when nothing opened.
fun openInBrowser(url: String, os: DesktopOs = currentOs()): Boolean {
    val uri = runCatching { URI(url) }.getOrNull() ?: return false
    if (uri.scheme != "https" && uri.scheme != "http") return false
    val desktop = runCatching { Desktop.getDesktop().takeIf { Desktop.isDesktopSupported() && it.isSupported(Desktop.Action.BROWSE) } }.getOrNull()
    if (desktop != null && runCatching { desktop.browse(uri) }.isSuccess) return true
    val command = when (os) {
        DesktopOs.Windows -> listOf("rundll32", "url.dll,FileProtocolHandler", uri.toString())
        DesktopOs.Mac -> listOf("open", uri.toString())
        DesktopOs.Linux -> listOf("xdg-open", uri.toString())
    }
    // The command is only a launcher: it hands the address to the browser
    // and ends. Its handles stay open until the collector takes the
    // process, so every click on a link held a pair of pipes and a process
    // handle for a while — read over a long session that is what grew. The
    // output is drained so nothing blocks, and a launcher that hangs is
    // let go of rather than left running.
    return runCatching {
        val process = ProcessBuilder(command).redirectErrorStream(true).start()
        // Drained on its own: the reading is not what decides here, only
        // that the pipes never fill and wedge the launcher.
        CompletableFuture.runAsync(Runnable { runCatching { process.inputStream.readAllBytes() } })
        // Let go of the handles as soon as the launcher ends, and drop a
        // launcher that hangs; nothing here waits, so opening never stalls.
        process.onExit().thenAccept { process.destroy() }
        process.onExit().orTimeout(OpenHandoverSeconds, TimeUnit.SECONDS).exceptionally { runCatching { process.destroyForcibly() }; null }
        true
    }.getOrDefault(false)
}

private const val OpenHandoverSeconds = 30L
