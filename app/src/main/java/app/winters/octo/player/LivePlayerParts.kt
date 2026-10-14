package app.winters.octo.player

import android.content.Intent
import android.net.Uri
import android.os.SystemClock
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.winters.octo.R
import app.winters.octo.design.Glaze
import app.winters.octo.design.GlowIcon
import app.winters.octo.design.IconAccent
import app.winters.octo.design.OctoIcons
import app.winters.octo.design.OctoType
import app.winters.octo.design.rememberIconAccent
import app.winters.octo.discovery.DownloadPhase
import app.winters.octo.liveradio.LiveLineup
import app.winters.octo.liveradio.LiveSongButton
import app.winters.octo.liveradio.liveSongButtonLabel
import app.winters.octo.liveradio.liveCodecLine
import app.winters.octo.liveradio.liveShown
import app.winters.octo.liveradio.listenedFor
import app.winters.octo.player.immersive.mutedInk
import app.winters.octo.playback.LiveNow
import app.winters.octo.playback.stationArt
import app.winters.octo.ui.common.Artwork
import app.winters.octo.ui.common.DownloadRing
import app.winters.octo.ui.common.Choice
import app.winters.octo.ui.common.ChoiceRequest
import app.winters.octo.ui.common.LocalChoiceSheet
import app.winters.octo.ui.common.LocalHaze
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

// The stop sign for a live station, in place of pause.
val LiveStopIcon = R.drawable.sym_live_stop

// The red of the "LIVE" mark.
private val LiveRed = Color(0xFFFF3B30)

// In place of the scrub bar while a station plays: a calm thin line that
// cannot be dragged, how long the listener has been on the station where a
// song's played time would be, and the LIVE pill where a song's quality
// label would be. The station's codec is in Station info.
@Composable
internal fun LiveBar(live: LiveNow, calm: Boolean) {
    // In the room the scrub bar takes, with the times' line under it, so
    // a song and a station keep the same rhythm.
    Box(Modifier.fillMaxWidth().height(BarRoom), contentAlignment = Alignment.Center) {
        Box(
            Modifier
                .fillMaxWidth()
                .height(3.dp)
                .background(LocalContentColor.current.copy(alpha = 0.24f), CircleShape)
                .clearAndSetSemantics { },
        )
    }
    Box(Modifier.fillMaxWidth().heightIn(min = TimesRoom).offset(y = (-8).dp)) {
        ListenedTime(live.since, Modifier.align(Alignment.CenterStart))
        LivePill(calm, Modifier.align(Alignment.Center))
    }
}

// The red-tinted LIVE pill: a red dot, gently pulsing unless motion is
// reduced, and "LIVE".
@Composable
private fun LivePill(calm: Boolean, modifier: Modifier) {
    val glow = if (calm) {
        1f
    } else {
        val pulse = rememberInfiniteTransition(label = "live pulse")
        val value by pulse.animateFloat(1f, 0.35f, infiniteRepeatable(tween(1_100), RepeatMode.Reverse), label = "live dot")
        value
    }
    Glaze(
        modifier.height(24.dp).clearAndSetSemantics { contentDescription = "Live" },
        backdrop = LocalHaze.current,
        film = LiveRed.copy(alpha = 0.22f),
    ) {
        Row(
            Modifier.padding(horizontal = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Box(Modifier.size(7.dp).graphicsLayer { alpha = glow }.background(LiveRed, CircleShape))
            Text("LIVE", style = LiveLabel, color = LocalContentColor.current, maxLines = 1)
        }
    }
}

// How long the listener has been on the station, counted each second.
@Composable
private fun ListenedTime(since: Long?, modifier: Modifier) {
    var now by remember { mutableLongStateOf(SystemClock.elapsedRealtime()) }
    LaunchedEffect(since) {
        while (since != null) {
            now = SystemClock.elapsedRealtime()
            delay(1_000 - (now - since) % 1_000)
        }
    }
    val shown = listenedFor(since?.let { now - it } ?: 0)
    Text(
        shown,
        style = OctoType.caption.copy(fontFeatureSettings = "tnum"),
        color = mutedInk,
        modifier = modifier.semantics { contentDescription = "Listening for $shown" },
    )
}

private val LiveLabel = OctoType.caption.copy(fontSize = 10.5.sp, fontWeight = FontWeight.SemiBold, letterSpacing = 1.sp)

// Beside the song on air: the heart, which hearts that song (hidden while
// the station names none), and the station's menu.
@Composable
internal fun LiveSongButtons(live: LiveNow, vm: LivePlayerViewModel, calm: Boolean) {
    val button by vm.songButton.collectAsStateWithLifecycle()
    val phase by vm.songPhase.collectAsStateWithLifecycle()
    val air = live.shown.onAir
    if (air.named && button != LiveSongButton.None) {
        val pulse = rememberIconAccent(IconAccent.Pulse)
        val label = liveSongButtonLabel(button, air)
        Box(
            Modifier
                .size(44.dp)
                .clickable(interactionSource = null, indication = null, role = Role.Button) {
                    if (button == LiveSongButton.Heart(starred = false)) pulse.play()
                    vm.tapSong()
                }
                .semantics { contentDescription = label },
            contentAlignment = Alignment.Center,
        ) {
            when (val shown = button) {
                is LiveSongButton.Heart -> GlowIcon(
                    painterResource(if (shown.starred) OctoIcons.Liked else OctoIcons.Like),
                    tint = if (shown.starred) LocalContentColor.current else LocalContentColor.current.copy(alpha = 0.6f),
                    lit = shown.starred,
                    modifier = Modifier.size(24.dp),
                    accent = pulse,
                )
                // On its way into the library: the ring the app's other add
                // buttons show.
                is LiveSongButton.Add -> if (shown.adding) {
                    DownloadRing(if (phase == DownloadPhase.None) DownloadPhase.Queued else phase, calm, Modifier.size(24.dp))
                } else {
                    PlusIcon()
                }
                LiveSongButton.Search -> PlusIcon()
                LiveSongButton.None -> Unit
            }
        }
    } else {
        Spacer(Modifier.size(44.dp))
    }
    LiveMoreButton(live, vm)
}

// The plus the app's outside songs show where a heart would be.
@Composable
private fun PlusIcon() {
    GlowIcon(
        painterResource(OctoIcons.AddToLibrary),
        tint = LocalContentColor.current.copy(alpha = 0.6f),
        lit = false,
        modifier = Modifier.size(24.dp),
    )
}

// What the station's menu offers, in order.
internal enum class LiveAction(val label: String) {
    Info("Station info"),
    Keep("Keep station"),
    Remove("Remove station"),
    AddToServer("Add to your server"),
    FindSong("Find this song in Octo"),
    CopySong("Copy song name"),
}

// The station's menu: what can be done with it, and with the song on air.
// A station without a Radio Browser id is not kept on the phone.
internal fun liveActions(named: Boolean, keepable: Boolean, kept: Boolean, addable: Boolean): List<LiveAction> = buildList {
    add(LiveAction.Info)
    if (keepable) add(if (kept) LiveAction.Remove else LiveAction.Keep)
    if (addable) add(LiveAction.AddToServer)
    if (named) {
        add(LiveAction.FindSong)
        add(LiveAction.CopySong)
    }
}

@Composable
private fun LiveMoreButton(live: LiveNow, vm: LivePlayerViewModel) {
    val sheet = LocalChoiceSheet.current
    val kept by vm.kept.collectAsStateWithLifecycle()
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val id = live.lineup.ids[live.lineup.index]
    Box(
        Modifier
            .size(44.dp)
            .clickable(interactionSource = null, indication = null, role = Role.Button) {
                vm.menuOpened()
                val details = live.shown.details
                val actions = liveActions(
                    named = live.shown.onAir.named,
                    keepable = details.uuid.isNotBlank(),
                    kept = kept.has(details.uuid),
                    addable = vm.addable(id),
                )
                sheet.show(ChoiceRequest(live.shown.station, actions.map { Choice(it.label) }, selected = -1) { index ->
                    when (actions[index]) {
                        // The menu closes first, then the info opens in its place.
                        LiveAction.Info -> scope.launch {
                            delay(SHEET_SWAP_MS)
                            sheet.show(stationInfo(live) { url -> runCatching { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) } })
                        }
                        LiveAction.Keep -> vm.keep(id)
                        LiveAction.Remove -> vm.remove(id)
                        LiveAction.AddToServer -> vm.addToServer(id)
                        LiveAction.FindSong -> vm.findSong(live.shown.onAir)
                        LiveAction.CopySong -> vm.copySong(live.shown.onAir)
                    }
                })
            }
            .semantics { contentDescription = "More" },
        contentAlignment = Alignment.Center,
    ) {
        Icon(painterResource(OctoIcons.More), contentDescription = null, tint = LocalContentColor.current.copy(alpha = 0.6f), modifier = Modifier.size(24.dp))
    }
}

private const val SHEET_SWAP_MS = 180L

// What is known about the station, one line each, on one screen: its
// stream, where it is, what it plays and its website, which a tap opens.
internal data class InfoLine(val label: String, val value: String, val link: String? = null)

internal fun stationInfoLines(live: LiveNow): List<InfoLine> {
    val details = live.shown.details
    val place = listOf(details.state, details.country.ifBlank { details.countryCode }).filter(String::isNotBlank).distinct().joinToString(", ")
    return listOfNotNull(
        liveCodecLine(details).takeIf(String::isNotEmpty)?.let { InfoLine("Stream", it) },
        place.takeIf(String::isNotEmpty)?.let { InfoLine("Where", it) },
        details.tags.take(4).joinToString(", ") { it.replaceFirstChar(Char::uppercase) }.takeIf(String::isNotEmpty)?.let { InfoLine("Plays", it) },
        details.homepage.takeIf { it.startsWith("http://") || it.startsWith("https://") }?.let {
            InfoLine("Website", it.removePrefix("https://").removePrefix("http://").removePrefix("www.").trimEnd('/'), it)
        },
    ).ifEmpty { listOf(InfoLine("Stream", "Live radio")) }
}

private fun stationInfo(live: LiveNow, open: (String) -> Unit): ChoiceRequest {
    val lines = stationInfoLines(live)
    return ChoiceRequest(live.shown.station, lines.map { Choice(it.value, it.label) }, selected = -1) { index ->
        lines[index].link?.let(open)
    }
}

// The stations being surfed, as the queue button lists them: each with its
// logo and what it is, the one on now marked. A tap switches to it.
internal fun stationList(lineup: LiveLineup, onPick: (Int) -> Unit): ChoiceRequest = ChoiceRequest(
    "Stations",
    lineup.ids.map { id ->
        val shown = liveShown(id, null)
        Choice(
            label = shown?.station.orEmpty(),
            detail = shown?.subtitle?.takeIf(String::isNotBlank),
            leading = { Artwork(stationArt(id)?.encode(), 36.dp, shape = RoundedCornerShape(6.dp)) },
        )
    },
    selected = lineup.index,
    onPick = onPick,
)

// The room the scrub bar takes, and the line of times under it: the live
// bar takes the same.
internal val BarRoom = 48.dp
internal val TimesRoom = 24.dp
