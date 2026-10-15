package app.winters.octo.desktop.update

import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import app.winters.octo.desktop.settings.DesktopOs
import app.winters.octo.desktop.settings.SettingsStore
import app.winters.octo.desktop.settings.separateProfile
import app.winters.octo.desktop.system.installedProgram
import app.winters.octo.update.GITHUB_API
import app.winters.octo.update.InstallWhen
import app.winters.octo.update.ManifestAsset
import app.winters.octo.update.PlayerApp
import app.winters.octo.update.PlayerUpdater
import app.winters.octo.update.PlayerVersion
import app.winters.octo.update.ReleaseFeed
import app.winters.octo.update.UpdateCheck
import app.winters.octo.update.UpdateTiming
import app.winters.octo.update.trustedKeys
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.OkHttpClient
import java.io.File
import java.util.concurrent.TimeUnit

// Whether this Octo looks for updates, and if not, why not. Only an
// installed Octo does: a build run from source, a run with a folder of its
// own, and the portable zip never replace themselves. -Docto.updates.force=true
// turns it on anyway, for trying the updater from a build (with
// -Docto.updates.api=<address> pointing it at a pretend GitHub).
sealed interface UpdaterAvailability {
    data class On(val running: PlayerVersion) : UpdaterAvailability
    data class Off(val why: String) : UpdaterAvailability
}

// The file name the portable zip carries beside the app's jars.
const val PORTABLE_MARK = "octo-portable"

fun updaterAvailability(
    version: String? = System.getProperty("octo.version"),
    installed: Boolean = installedProgram() != null,
    portable: Boolean = runningFolder()?.let { File(it, PORTABLE_MARK).isFile } == true,
    forced: Boolean = System.getProperty(FORCE_PROPERTY) == "true",
    hasKeys: Boolean = trustedKeys().isNotEmpty(),
): UpdaterAvailability {
    val running = PlayerVersion.parse(version) ?: return UpdaterAvailability.Off("This is a development build, so it doesn't update itself.")
    if (!hasKeys) return UpdaterAvailability.Off("This build has no key to check updates with.")
    if (forced) return UpdaterAvailability.On(running)
    if (portable) return UpdaterAvailability.Off("This is the portable copy. New versions are on Octo's releases page.")
    if (!installed) return UpdaterAvailability.Off("Only an installed Octo updates itself.")
    return UpdaterAvailability.On(running)
}

const val FORCE_PROPERTY = "octo.updates.force"
const val API_PROPERTY = "octo.updates.api"

// The folder of the jar this runs from.
private fun runningFolder(): File? = runCatching {
    File(DesktopUpdates::class.java.protectionDomain.codeSource.location.toURI()).parentFile
}.getOrNull()

// The kind of package a Linux system installs, from /etc/os-release.
fun linuxPackageKind(osRelease: String?, hasDpkg: Boolean, hasRpm: Boolean): String? {
    val words = osRelease.orEmpty().lineSequence()
        .filter { it.startsWith("ID=") || it.startsWith("ID_LIKE=") }
        .flatMap { it.substringAfter('=').trim('"', '\'', ' ').split(' ') }
        .map { it.lowercase() }
        .toSet()
    return when {
        words.any { it in setOf("debian", "ubuntu") } -> "deb"
        words.any { it in setOf("fedora", "rhel", "centos", "suse", "opensuse") || it.startsWith("opensuse") } -> "rpm"
        hasDpkg -> "deb"
        hasRpm -> "rpm"
        else -> null
    }
}

// The chip, as the release names it.
fun archName(arch: String = System.getProperty("os.arch").orEmpty()): String = when (arch.lowercase()) {
    "amd64", "x86_64", "x64" -> "x64"
    "aarch64", "arm64" -> "arm64"
    else -> arch.lowercase()
}

// This system's installer among a release's files: the MSI on Windows,
// the DMG on macOS, the DEB or RPM on Linux, for this chip.
fun installerFor(assets: List<ManifestAsset>, os: DesktopOs, arch: String, linuxKind: String?): ManifestAsset? {
    val (system, kind) = when (os) {
        DesktopOs.Windows -> "windows" to "msi"
        DesktopOs.Mac -> "macos" to "dmg"
        DesktopOs.Linux -> "linux" to (linuxKind ?: return null)
    }
    return assets.firstOrNull { it.os == system && it.arch == arch && it.kind == kind }
}

// Where downloads wait, with the installer's log: never inside the
// program's own folder, since a new version empties that folder as it
// goes in, the running installer and its log included. The user's temp
// folder on Windows and macOS; the cache on Linux, whose /tmp every user
// shares, and for a run with a folder of its own. When the first is
// inside the program's folder, the next; when all are, the home folder.
fun updatesFolder(
    cache: File,
    program: File?,
    os: DesktopOs,
    temp: File = File(System.getProperty("java.io.tmpdir")),
    separate: Boolean = separateProfile(),
    home: File = File(System.getProperty("user.home")),
): File {
    val own = File(cache, "updates")
    val choices = listOfNotNull(
        own.takeIf { separate || os == DesktopOs.Linux },
        File(File(temp, "Octo"), "updates").takeIf { os != DesktopOs.Linux },
        own,
    )
    val root = program?.let { programFolder(it, os) } ?: return choices.first()
    return choices.firstOrNull { !isInside(it, root, os) } ?: File(home, ".octo-updates")
}

// The folder a new version replaces as a whole: the program's own on
// Windows, the app bundle on macOS, the package's folder on Linux
// (/opt/octo for /opt/octo/bin/Octo).
fun programFolder(program: File, os: DesktopOs): File {
    val parent = program.absoluteFile.parentFile ?: return program.absoluteFile
    return when (os) {
        DesktopOs.Windows -> parent
        DesktopOs.Mac -> generateSequence(parent) { it.parentFile }.firstOrNull { it.name.endsWith(".app") } ?: parent
        DesktopOs.Linux -> if (parent.name == "bin") parent.parentFile ?: parent else parent
    }
}

// Whether `file` is `folder` or anywhere inside it. Windows ignores case.
fun isInside(file: File, folder: File, os: DesktopOs): Boolean {
    fun key(of: File) = of.absoluteFile.normalize().path.replace('\\', '/').trimEnd('/').let { if (os == DesktopOs.Windows) it.lowercase() else it }
    val inner = key(file)
    val outer = key(folder)
    return inner == outer || inner.startsWith("$outer/")
}

// The desktop's updater: checks a while after start and every six hours
// while "Check for updates automatically" is on, downloads the installer
// in the background, and holds it ready. Nothing is ever said loudly: the
// news is one row in Settings > About and a small dot beside Settings.
@Stable
class DesktopUpdates(
    private val settings: SettingsStore,
    val availability: UpdaterAvailability,
    private val os: DesktopOs,
    private val folder: File,
    private val updater: PlayerUpdater?,
    // Starts a process; tests hand in their own.
    private val start: (List<String>) -> Process = { ProcessBuilder(it).redirectErrorStream(true).start() },
    private val now: () -> Long = System::currentTimeMillis,
    // The installed program, which Windows opens again after the update.
    private val program: File? = installedProgram()?.let(::File),
) {
    val enabled: Boolean get() = availability is UpdaterAvailability.On && updater != null

    // The update downloaded and checked, waiting to go in.
    var ready by mutableStateOf<UpdateCheck.Ready?>(null)
        private set

    var checking by mutableStateOf(false)
        private set

    // The last check's outcome in a line, and when it ran.
    var lastLine by mutableStateOf<String?>(null)
        private set

    private var loop: Job? = null
    private var launched = false

    // Checks a while after start, then every six hours; a rate limit from
    // GitHub pushes the next check back to when it said.
    fun start(scope: CoroutineScope) {
        if (!enabled || loop != null) return
        loop = scope.launch {
            delay(UpdateTiming.FIRST_CHECK_DELAY_MS)
            while (isActive) {
                val retryAt = if (settings.current.updates.checkAutomatically) check() else null
                delay(UpdateTiming.nextWait(now(), retryAt))
            }
        }
    }

    // Checks now, downloading what it finds. Returns when GitHub asked to
    // be left alone until, if it did.
    suspend fun check(): Long? {
        val updater = updater ?: return null
        if (checking) return null
        checking = true
        val early = settings.current.updates.earlyVersions
        val result = try {
            withContext(Dispatchers.IO) { updater.check(early) }
        } finally {
            checking = false
        }
        val at = now()
        when (result) {
            is UpdateCheck.Ready -> {
                ready = result
                lastLine = null
            }
            is UpdateCheck.UpToDate -> {
                ready = null
                withContext(Dispatchers.IO) { forgetDownloads() }
                lastLine = "Octo is up to date."
            }
            is UpdateCheck.Available -> lastLine = "Octo ${result.version} is out."
            is UpdateCheck.NoInstaller -> lastLine = "Octo ${result.version} is out, but not yet for this computer."
            is UpdateCheck.Refused -> {
                ready = null
                lastLine = "An update didn't pass its safety check, so it was deleted. Octo will look again later."
            }
            is UpdateCheck.Unavailable -> lastLine = "Couldn't check for updates just now. Octo will try again later."
        }
        checkedAt = at
        return (result as? UpdateCheck.Unavailable)?.retryAt
    }

    var checkedAt by mutableStateOf<Long?>(null)
        private set

    // Downloads from releases that are no longer the one to install.
    private fun forgetDownloads() {
        folder.listFiles()?.filter(File::isDirectory)?.forEach { it.deleteRecursively() }
    }

    // What the ready update's button does here: restart into it on
    // Windows, open the disk image on macOS, show the package on Linux.
    val installAction: String get() = when (os) {
        DesktopOs.Windows -> "Restart to update"
        DesktopOs.Mac -> "Open installer"
        DesktopOs.Linux -> "Show package"
    }

    // A line on how the ready update goes in, for its row.
    fun installHelp(update: UpdateCheck.Ready): String = when (os) {
        DesktopOs.Windows -> "Octo closes, installs it, and opens again. Your queue and settings stay."
        DesktopOs.Mac -> "Opens the disk image; drag Octo into Applications to replace this one."
        DesktopOs.Linux -> if (update.asset.kind == "deb") {
            "Install it with your software center, or: sudo apt install ./${update.file.name}"
        } else {
            "Install it with your software center, or: sudo dnf install ./${update.file.name}"
        }
    }

    // "Restart to update": starts the installer's script, and when Windows
    // has it running, quits Octo the usual way (saving the queue, plays and
    // settings) so it can go in. On macOS and Linux, opens the installer or
    // its folder and leaves Octo running. False when nothing could start.
    fun install(quit: () -> Unit): Boolean {
        val update = ready ?: return false
        return when (os) {
            DesktopOs.Windows -> {
                if (!launchWindowsInstall(update, relaunch = true)) return false
                quit()
                true
            }
            DesktopOs.Mac -> runCatching { start(listOf("open", update.file.absolutePath)) }.isSuccess
            DesktopOs.Linux -> runCatching { start(listOf("xdg-open", update.file.parentFile.absolutePath)) }.isSuccess
        }
    }

    // As Octo quits: with "Automatically when I quit", a ready update goes
    // in on Windows, and Octo stays closed afterwards.
    fun onQuit() {
        val update = ready ?: return
        if (os != DesktopOs.Windows || settings.current.updates.install != InstallWhen.OnQuit) return
        launchWindowsInstall(update, relaunch = false)
    }

    private fun launchWindowsInstall(update: UpdateCheck.Ready, relaunch: Boolean): Boolean {
        if (launched) return true
        // The temp folder can be emptied while an update waits; the next
        // check fetches it again.
        if (!update.file.isFile) {
            ready = null
            lastLine = "The downloaded update was cleared away. Octo will fetch it again."
            return false
        }
        val command = WindowsInstall.command(update.file, octoProcesses(), File(update.file.parentFile, "install.log"), program, relaunch)
        val started = runCatching {
            val process = start(command)
            process.waitFor(LAUNCH_WAIT_S, TimeUnit.SECONDS) && process.exitValue() == 0
        }.getOrDefault(false)
        if (started) {
            launched = true
        } else {
            lastLine = "The update couldn't start. It stays ready for the next try."
        }
        return started
    }

    companion object {
        private const val LAUNCH_WAIT_S = 30L

        // The updater for this Octo, or one that stays off, with why.
        fun forThisApp(settings: SettingsStore, cache: File, os: DesktopOs): DesktopUpdates {
            val program = installedProgram()?.let(::File)
            val availability = updaterAvailability(installed = program != null)
            val folder = updatesFolder(cache, program, os)
            val on = availability as? UpdaterAvailability.On ?: return DesktopUpdates(settings, availability, os, folder, null, program = program)
            // A client of its own: the system's certificates only, never a
            // server's trusted ones or its headers.
            val client = OkHttpClient.Builder()
                .connectTimeout(20, TimeUnit.SECONDS)
                .readTimeout(60, TimeUnit.SECONDS)
                .build()
            val api = System.getProperty(API_PROPERTY)?.toHttpUrlOrNull() ?: GITHUB_API
            val linuxKind = if (os == DesktopOs.Linux) {
                linuxPackageKind(runCatching { File("/etc/os-release").readText() }.getOrNull(), File("/usr/bin/dpkg").exists(), File("/usr/bin/rpm").exists())
            } else {
                null
            }
            val arch = archName()
            val updater = PlayerUpdater(
                PlayerApp.Desktop,
                on.running,
                ReleaseFeed(client, File(folder, "releases.json"), "Octo/${on.running} (desktop)", apiBase = api),
                client,
                folder,
                trustedKeys(),
                pick = { assets -> installerFor(assets, os, arch, linuxKind) },
            )
            return DesktopUpdates(settings, availability, os, folder, updater, program = program)
        }
    }
}
