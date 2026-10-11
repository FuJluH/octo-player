package app.winters.octo.ui.downloads

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.animateContentSize
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import app.winters.octo.data.ServerDownloads
import app.winters.octo.design.FloatingGlaze
import app.winters.octo.design.OctoDuration
import app.winters.octo.design.OctoColors
import app.winters.octo.design.OctoType
import app.winters.octo.design.motionScale
import app.winters.octo.design.octoTween
import app.winters.octo.discovery.DownloadPhase
import app.winters.octo.discovery.Downloads
import app.winters.octo.player.PlayerSettings
import app.winters.octo.ui.common.DownloadRing
import app.winters.octo.ui.common.rememberSystemReduceMotion
import dagger.hilt.android.lifecycle.HiltViewModel
import dev.chrisbanes.haze.HazeState
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.transformLatest
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import javax.inject.Inject

@HiltViewModel
class DownloadsPillViewModel @Inject constructor(
    downloads: Downloads,
    private val serverDownloads: ServerDownloads,
    player: PlayerSettings,
) : ViewModel() {
    // How many songs are on their way into the library: the server's
    // running rows, and songs just asked for that no list could show yet.
    // Looked at again when the oldest of those runs out.
    @OptIn(ExperimentalCoroutinesApi::class)
    val coming: StateFlow<Int> = combine(serverDownloads.rows, downloads.asked, serverDownloads.listedSince, ::Triple)
        .transformLatest { (rows, asked, since) ->
            while (true) {
                val now = System.currentTimeMillis()
                emit(pillCount(rows, asked, since, now))
                delay(pillRecheckMs(rows, asked, since, now) ?: break)
            }
        }
        .distinctUntilChanged()
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), 0)

    // The server's own rows, which say the step each song is on.
    val rows: StateFlow<List<DownloadRow>> = serverDownloads.rows

    // Only a server that keeps a downloads list has a sheet to open.
    val canOpen: StateFlow<Boolean> = serverDownloads.supported

    // Octo's own Reduce motion, beside the phone's.
    val reduceMotion: StateFlow<Boolean> = player.prefs
        .map { it.reduceMotion }
        .distinctUntilChanged()
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), false)

    fun open() {
        if (!serverDownloads.supported.value) return
        serverDownloads.showList()
        serverDownloads.open()
    }
}

// The pill's words: how many songs are on their way, until the server's
// list says which step they are on.
internal fun comingText(count: Int): String = if (count == 1) "1 downloading" else "$count downloading"

// The ring for the server's step: turning while it looks, filling as it
// downloads, full while it is checked and added.
internal fun ringPhase(row: DownloadRow): DownloadPhase = when (row.phase) {
    RowPhase.Downloading -> DownloadPhase.Downloading(row.fraction)
    RowPhase.Checking, RowPhase.Adding -> DownloadPhase.Adding
    RowPhase.Done -> DownloadPhase.Done
    else -> DownloadPhase.Queued
}

// While songs are on their way into the library, a small glazed pill with
// the download ring of the song furthest along, the step it is on
// ("Downloading 42%", "Checking"), its name, and how many more. A tap opens
// the server downloads sheet from anywhere; nothing opens by itself, and
// with nothing on its way the pill is gone.
@Composable
fun DownloadsPill(haze: HazeState, modifier: Modifier = Modifier, vm: DownloadsPillViewModel = hiltViewModel()) {
    val coming by vm.coming.collectAsStateWithLifecycle()
    val canOpen by vm.canOpen.collectAsStateWithLifecycle()
    val rows by vm.rows.collectAsStateWithLifecycle()
    val appCalm by vm.reduceMotion.collectAsStateWithLifecycle()
    val calm = appCalm || rememberSystemReduceMotion()
    if (coming <= 0 || !canOpen) return
    val lead = pillLead(rows)
    val more = if (lead != null) coming - 1 else 0
    val spoken = if (lead != null) pillSpoken(rows) else comingText(coming)
    val motion = motionScale()
    FloatingGlaze(
        haze,
        modifier
            .height(36.dp)
            .widthIn(max = 280.dp)
            .clip(CircleShape)
            .clickable(role = Role.Button, onClickLabel = "Show server downloads", onClick = vm::open)
            .semantics(mergeDescendants = true) { contentDescription = "$spoken. Show server downloads" }
            .animateContentSize(octoTween(motion, OctoDuration.Card)),
    ) {
        Row(
            Modifier.padding(start = 8.dp, end = if (more > 0) 6.dp else 14.dp).align(Alignment.Center),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            DownloadRing(lead?.let(::ringPhase) ?: DownloadPhase.Queued, calm, Modifier.size(20.dp))
            AnimatedContent(
                lead?.let(::stepWords) ?: comingText(coming),
                transitionSpec = { fadeIn(octoTween(motion, OctoDuration.Swap)) togetherWith fadeOut(octoTween(motion, OctoDuration.Swap)) },
                label = "step",
            ) { words -> Text(words, style = OctoType.caption, color = OctoColors.TextPrimary, maxLines = 1) }
            lead?.let {
                Text(it.title, style = OctoType.caption, color = OctoColors.TextSecondary, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
            }
            if (more > 0) {
                Text(
                    "+$more",
                    style = OctoType.caption,
                    color = OctoColors.TextPrimary,
                    maxLines = 1,
                    modifier = Modifier.clip(CircleShape).background(Color.White.copy(alpha = 0.12f)).padding(horizontal = 7.dp, vertical = 2.dp),
                )
            }
        }
    }
}
