package app.winters.octo

import app.winters.octo.subsonic.parseFamilyLink
import app.winters.octo.family.FamilyOpen
import app.winters.octo.family.FamilyNotifier
import app.winters.octo.family.FamilyHub
import app.winters.octo.ui.settings.KeepAccent
import app.winters.octo.ui.imports.ImportInbox
import app.winters.octo.ui.imports.fromHistory
import app.winters.octo.ui.imports.sharedImport
import android.app.SearchManager
import android.content.Intent
import android.os.Bundle
import android.provider.MediaStore
import android.view.KeyEvent
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.setValue
import app.winters.octo.ui.common.Feedback
import app.winters.octo.update.AppUpdates
import app.winters.octo.design.OctoTheme
import app.winters.octo.device.DeviceLibrary
import app.winters.octo.playback.PlaybackConnection
import app.winters.octo.server.QueueSync
import app.winters.octo.system.SystemEntries
import app.winters.octo.system.publishShortcuts
import app.winters.octo.ui.common.ProvideAdoptedFinds
import app.winters.octo.ui.common.ProvideLearnedLengths
import app.winters.octo.ui.common.ProvideOfflineMarks
import app.winters.octo.ui.nav.MainShell
import app.winters.octo.widget.EXTRA_OPEN_PLAYER
import dagger.hilt.android.AndroidEntryPoint
import javax.inject.Inject

@AndroidEntryPoint
class MainActivity : ComponentActivity() {
    @Inject lateinit var library: DeviceLibrary
    @Inject lateinit var playback: PlaybackConnection
    @Inject lateinit var queueSync: QueueSync
    @Inject lateinit var feedback: Feedback
    // Launcher shortcuts and "Open with Octo".
    @Inject lateinit var systemEntries: SystemEntries
    @Inject lateinit var updates: AppUpdates
    // Family links and family notices.
    @Inject lateinit var family: FamilyHub
    // Lists shared to Octo, for Import.
    @Inject lateinit var imports: ImportInbox

    // Counts up each time a home screen widget asks for the full player.
    private var openPlayer by mutableIntStateOf(0)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        // The app opens on the library; servers are an optional add-on.
        setContent { OctoTheme { KeepAccent(); ProvideOfflineMarks { ProvideAdoptedFinds { ProvideLearnedLengths { MainShell(library, playback, feedback, openPlayer) } } } } }
        publishShortcuts(this)
        // Opened by a voice request or a widget; not again when the screen turns.
        if (savedInstanceState == null) {
            playIfAsked(intent)
            openPlayerIfAsked(intent)
            familyIfAsked(intent)
            importIfShared(intent)
            systemEntries.handle(this, intent) { openPlayer++ }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        playIfAsked(intent)
        openPlayerIfAsked(intent)
        familyIfAsked(intent)
        importIfShared(intent)
        systemEntries.handle(this, intent) { openPlayer++ }
    }

    // A list shared to Octo opens Import, which sends it.
    private fun importIfShared(intent: Intent) {
        if (intent.fromHistory()) return
        intent.sharedImport()?.let(imports::offer)
    }

    // Coming to the front: a family link on the clipboard is offered once.
    // Android lets only the app in front read the clipboard.
    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (!hasFocus) return
        val clip = runCatching { getSystemService(android.content.ClipboardManager::class.java)?.primaryClip?.getItemAt(0)?.text?.toString() }.getOrNull()
        family.offerClipboard(clip)
    }

    // A family link (an invite, or a sign-in from another device, from a QR
    // code the camera read or a link tapped) opens the sign-in form filled
    // in; a family notice opens Family.
    private fun familyIfAsked(intent: Intent) {
        if (intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY != 0) return
        when {
            intent.action == FamilyNotifier.OPEN_FAMILY -> family.open(FamilyOpen.Family)
            intent.action == Intent.ACTION_VIEW ->
                parseFamilyLink(intent.dataString.orEmpty())?.let { family.open(FamilyOpen.Join(it)) }
        }
    }

    // A widget's artwork or title opens the player. Coming back from recents
    // hands over the old intent again, which is not a new tap.
    private fun openPlayerIfAsked(intent: Intent) {
        if (!intent.getBooleanExtra(EXTRA_OPEN_PLAYER, false)) return
        if (intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY != 0) return
        openPlayer++
    }

    // "Play Drake on Octo": the assistant sends what was said.
    private fun playIfAsked(intent: Intent) {
        if (intent.action != MediaStore.INTENT_ACTION_MEDIA_PLAY_FROM_SEARCH) return
        playback.playFromSearch(intent.getStringExtra(SearchManager.QUERY).orEmpty())
    }

    // While casting, the volume buttons turn the TV or speaker up and down.
    override fun onKeyDown(keyCode: Int, event: KeyEvent): Boolean {
        if (isVolumeKey(keyCode) && playback.stepDeviceVolume(up = keyCode == KeyEvent.KEYCODE_VOLUME_UP)) return true
        return super.onKeyDown(keyCode, event)
    }

    override fun onKeyUp(keyCode: Int, event: KeyEvent): Boolean {
        if (isVolumeKey(keyCode) && playback.now.value.casting) return true
        return super.onKeyUp(keyCode, event)
    }

    private fun isVolumeKey(keyCode: Int) = keyCode == KeyEvent.KEYCODE_VOLUME_UP || keyCode == KeyEvent.KEYCODE_VOLUME_DOWN

    override fun onStart() {
        super.onStart()
        playback.connect()
        // A queue left on another device may be waiting on the server.
        queueSync.check()
    }

    // Letting go lets the service stop itself when nothing is playing.
    override fun onStop() {
        // Leaving Octo is when "When I leave Octo" puts a ready update in,
        // unless music is playing.
        if (!isChangingConfigurations) updates.leaving(playing = playback.now.value.isPlaying)
        playback.release()
        super.onStop()
    }
}
