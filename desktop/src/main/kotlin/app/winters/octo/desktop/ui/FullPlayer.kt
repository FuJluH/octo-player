package app.winters.octo.desktop.ui

import app.winters.octo.design.motionScale
import androidx.compose.ui.semantics.Role
import androidx.compose.foundation.layout.heightIn
import app.winters.octo.design.Focus
import app.winters.octo.desktop.nav.SEEK_STEP_MS
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.State
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameMillis
import androidx.compose.ui.Alignment
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.input.pointer.PointerEventType
import androidx.compose.ui.input.pointer.onPointerEvent
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import app.winters.octo.desktop.AppState
import app.winters.octo.desktop.SidePanel
import app.winters.octo.desktop.library.Cover
import app.winters.octo.desktop.library.lengthText
import app.winters.octo.desktop.lyrics.LyricsMenuButton
import app.winters.octo.desktop.lyrics.LyricsView
import app.winters.octo.desktop.nav.Page
import app.winters.octo.desktop.player.DesktopPlayer
import app.winters.octo.desktop.player.LiveNow
import androidx.compose.ui.layout.onGloballyPositioned
import app.winters.octo.desktop.player.PlayerState
import app.winters.octo.desktop.player.RepeatMode
import app.winters.octo.desktop.player.wash.ImmersiveWash
import app.winters.octo.desktop.player.wash.WashCover
import app.winters.octo.design.IconAction
import app.winters.octo.design.FrameSize
import app.winters.octo.design.LineSlider
import app.winters.octo.design.LocalReduceMotion
import app.winters.octo.design.OctoColors
import app.winters.octo.design.OctoIcons
import app.winters.octo.design.OctoType
import app.winters.octo.design.Txt
import app.winters.octo.player.immersive.CoverFadeMs
import app.winters.octo.player.immersive.DarkInkArgb
import app.winters.octo.player.immersive.FinalGain
import app.winters.octo.player.immersive.WashInk
import app.winters.octo.player.immersive.WashTuning
import app.winters.octo.player.immersive.inkOver
import app.winters.octo.player.immersive.paceBpm
import app.winters.octo.subsonic.Song

// The dark words used over a light background, as on the phone.
val DarkInk = Color(DarkInkArgb)

// What the full player's words need over this cover's wash, drawn over the
// page colour: dark or white, and how much of the wash shows so they read
// on every part of it.
fun WashCover.playerInk(): WashInk = inkOver(range.scaled(FinalGain), OctoColors.Background.toArgb())

// The words' colour for that.
fun WashInk?.color(): Color = if (this?.dark == true) DarkInk else Color.White

// The full player's background: the moving wash of the cover, dimmed as its
// words need (`playerInk`), easing between covers.
@Composable
internal fun PlayerBackdrop(cover: WashCover?, bpm: Float, fps: Int, speed: Float, moving: Boolean, dolly: () -> Float) {
    val ink = remember(cover) { cover?.playerInk() }
    val show by animateFloatAsState(ink?.show ?: 1f, tween(motionScale().ms(CoverFadeMs.toInt())), label = "player wash")
    ImmersiveWash(cover, bpm, fps, speed, moving, dolly = dolly, opacity = { show })
}

// The way in: the background dollies in over 0.8 s after 0.02 s, quick then
// settling, as on the phone.
private val DollyIn = CubicBezierEasing(0.22f, 1f, 0.36f, 1f)

// Where the song is, read every frame while it plays and the window is on
// screen, so the line glides, and once at each change of the player (a
// seek counts as one) otherwise.
@Composable
fun rememberFramePosition(player: DesktopPlayer): State<Long> {
    val position = remember { mutableLongStateOf(player.positionMs()) }
    val state by player.state.collectAsState()
    val shown = LocalWindowShown.current
    LaunchedEffect(player, state, shown) {
        position.longValue = player.positionMs()
        while (state.playing && shown) withFrameMillis { position.longValue = player.positionMs() }
    }
    return position
}

// The player filling the window: the moving wash of the cover's colours
// behind, the cover, the song, the seek line, the transport, volume and the
// heart on the left, and the lyrics or the queue on the right. The words
// turn dark over a wash light all over; otherwise they stay white and the
// wash dims as far as they need. Escape closes it, as the collapse button does.
// The wash fills the whole window; `top` is the room the title bar keeps.
@Composable
fun FullPlayer(app: AppState, modifier: Modifier = Modifier, top: androidx.compose.ui.unit.Dp = 0.dp) {
    val state by app.player.state.collectAsState()
    val settings by app.settings.state.collectAsState()
    val song = state.current?.song ?: return
    val look = settings.appearance
    val wash = look.wash
    val tuning = WashTuning(wash.contrast, wash.saturation / 100f, wash.brightnessCap / 100f)
    // The cover made ready, keeping the last one while the next is made.
    var cover by remember { mutableStateOf<WashCover?>(null) }
    LaunchedEffect(song.coverArt, tuning, app.connection) {
        app.washCovers.follow(app.connection?.client, song.coverArt, tuning).collect { cover = it }
    }
    val ink = remember(cover) { cover?.playerInk() }.color()
    val dolly = remember { Animatable(0f) }
    val calm = LocalReduceMotion.current
    // With motion reduced, the background is simply there.
    LaunchedEffect(Unit) { if (calm) dolly.snapTo(1f) else dolly.animateTo(1f, tween(800, delayMillis = 20, easing = DollyIn)) }

    // It takes every click and scroll on its background, so none reach the
    // page hidden under it.
    Box(modifier.swallowClicks().background(OctoColors.Background)) {
        PlayerBackdrop(
            cover,
            paceBpm(song.bpm, wash.useBpm),
            wash.fps,
            wash.speed / 100f,
            // Still while the window is minimised or in the tray.
            moving = wash.moving && !LocalReduceMotion.current && LocalWindowShown.current,
            dolly = { dolly.value },
        )
        val live = state.live
        BoxWithConstraints(Modifier.fillMaxSize().padding(start = 56.dp, end = 40.dp, top = top + 48.dp, bottom = 32.dp)) {
            // A station has no lyrics or song details; its queue is its stations.
            val panel = app.playerPanel.takeUnless { live != null && (it == SidePanel.Lyrics || it == SidePanel.Info) }
            val artSide = minOf(440.dp, maxHeight - 290.dp, if (panel != null) maxWidth * 0.36f else maxWidth * 0.6f).coerceAtLeast(120.dp)
            Row(Modifier.fillMaxSize(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(48.dp, Alignment.CenterHorizontally)) {
                PlayerColumn(app, song, state, ink, artSide)
                if (panel != null) {
                    Box(Modifier.weight(1f).fillMaxHeight()) {
                        when (panel) {
                            SidePanel.Lyrics -> LyricsView(app, Modifier.fillMaxSize(), textColor = ink)
                            SidePanel.Queue -> Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.28f), RoundedCornerShape(20.dp)).padding(top = 8.dp)) {
                                QueueList(app)
                            }
                            SidePanel.Info -> Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.28f), RoundedCornerShape(20.dp)).padding(top = 8.dp)) {
                                InfoPanel(app, Modifier.fillMaxSize())
                            }
                            SidePanel.Downloads -> Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.28f), RoundedCornerShape(20.dp)).padding(top = 8.dp)) {
                                DownloadsPanel(app, Modifier.fillMaxSize())
                            }
                        }
                    }
                }
            }
        }
        // The panel toggles and the way out.
        Row(Modifier.align(Alignment.TopEnd).padding(top = top + 4.dp, end = 12.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            if (live != null) {
                if (state.queue.size > 1) IconAction(OctoIcons.Queue, "Stations", { app.togglePlayerPanel(SidePanel.Queue) }, size = 36.dp, iconSize = 20.dp, active = app.playerPanel == SidePanel.Queue, tint = ink)
                LiveMoreButton(app, live, state.current?.song?.id.orEmpty(), ink)
            } else {
                if (app.playerPanel == SidePanel.Lyrics) LyricsMenuButton(app, tint = ink)
                IconAction(OctoIcons.Lyrics, "Lyrics", { app.togglePlayerPanel(SidePanel.Lyrics) }, size = 36.dp, iconSize = 20.dp, active = app.playerPanel == SidePanel.Lyrics, tint = ink)
                IconAction(OctoIcons.Queue, "Queue", { app.togglePlayerPanel(SidePanel.Queue) }, size = 36.dp, iconSize = 20.dp, active = app.playerPanel == SidePanel.Queue, tint = ink)
                IconAction(OctoIcons.Info, "Song details", { app.togglePlayerPanel(SidePanel.Info) }, size = 36.dp, iconSize = 20.dp, active = app.playerPanel == SidePanel.Info, tint = ink)
            }
            IconAction(OctoIcons.Collapse, "Close the player", { app.fullPlayer = false }, size = 36.dp, iconSize = 20.dp, tint = ink)
        }
    }
}

// The transport's width, with a little room either side.
private val ColumnLeast = 340.dp

// The cover large, then the song and its heart, the seek line, the
// transport and the volume.
@OptIn(ExperimentalComposeUiApi::class)
@Composable
private fun PlayerColumn(app: AppState, song: Song, state: PlayerState, ink: Color, side: androidx.compose.ui.unit.Dp) {
    // The quieter words: most of the ink, so they keep 4.5:1 over the wash.
    val muted = ink.copy(alpha = 0.9f)
    // Never narrower than the transport, however small the cover gets on a short window.
    Column(Modifier.width(maxOf(side, ColumnLeast)), horizontalAlignment = Alignment.CenterHorizontally) {
        // A touch smaller while paused, as on the phone.
        val scale = remember { Animatable(1f) }
        val still = LocalReduceMotion.current
        // With motion reduced the cover keeps its size.
        LaunchedEffect(state.playing, still) {
            val target = if (state.playing || still) 1f else 0.94f
            if (still) scale.snapTo(target) else scale.animateTo(target, tween(420))
        }
        val coverModifier = Modifier.size(side).graphicsLayer {
            scaleX = scale.value
            scaleY = scale.value
        }
        val live = state.live
        if (live != null) {
            LiveCover(app, live, coverModifier, RoundedCornerShape(14.dp))
        } else {
            Cover(song.coverArt, coverModifier, shape = RoundedCornerShape(14.dp), placeholder = OctoIcons.Songs, retry = true)
        }
        Spacer(Modifier.height(28.dp))
        if (live != null) return@Column LivePlayerLines(app, song, state, live, ink, muted)
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                MarkedTitle(song, OctoType.headline, markColor = muted) { Txt(song.title, OctoType.headline, ink, it, maxLines = 2) }
                val artist = song.displayArtist ?: song.artist.orEmpty()
                Txt(
                    artist,
                    OctoType.body,
                    muted,
                    Modifier.heightIn(min = Focus.MinTarget).clickable(enabled = song.artistId != null, role = Role.Button) {
                        song.artistId?.let { app.navigator.go(Page.Artist(it, song.artist.orEmpty())) }
                        app.fullPlayer = false
                    },
                )
            }
            if (isOutside(app, song)) {
                FetchButton(app, song, 40.dp, 22.dp, tint = ink)
            } else {
                val starred = app.isStarred(song)
                IconAction(
                    if (starred) OctoIcons.Liked else OctoIcons.Like,
                    if (starred) "Remove from favorites" else "Add to favorites",
                    { app.setStarred(listOf(song), !starred) },
                    size = 40.dp,
                    iconSize = 22.dp,
                    tint = ink,
                )
            }
        }
        Spacer(Modifier.height(14.dp))
        val position = rememberFramePosition(app.player)
        val duration = state.durationMs
        LineSlider(
            fraction = { if (duration > 0) position.value.toFloat() / duration else 0f },
            onSeek = { app.player.seekTo((it * duration).toLong()) },
            modifier = Modifier.fillMaxWidth(),
            color = ink,
            trackColor = ink.copy(alpha = 0.22f),
            hoverLabel = { lengthText(((it * duration) / 1000).toInt()).ifEmpty { "0:00" } },
            label = "Song position",
            keyStep = if (duration > 0) (SEEK_STEP_MS.toFloat() / duration).coerceAtMost(1f) else 0.05f,
            reading = { "${lengthText((it * duration / 1000).toInt()).ifEmpty { "0:00" }} of ${lengthText((duration / 1000).toInt()).ifEmpty { "0:00" }}" },
        )
        PlayTimes(position, duration, muted)
        Spacer(Modifier.height(10.dp))
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
            IconAction(OctoIcons.Shuffle, "Shuffle", { app.player.setShuffle(!state.shuffle) }, size = 40.dp, iconSize = 22.dp, active = state.shuffle, tint = ink, toggled = state.shuffle)
            IconAction(OctoIcons.Previous, "Previous", app.player::previous, size = 48.dp, iconSize = 30.dp, tint = ink)
            PlayButton(state.playing, enabled = true, size = 68.dp) { app.player.togglePlay() }
            IconAction(OctoIcons.Next, "Next", app.player::next, size = 48.dp, iconSize = 30.dp, tint = ink)
            val repeat = state.repeat
            IconAction(
                if (repeat == RepeatMode.One) OctoIcons.RepeatOne else OctoIcons.Repeat,
                when (repeat) {
                    RepeatMode.Off -> "Repeat"
                    RepeatMode.All -> "Repeat all"
                    RepeatMode.One -> "Repeat one"
                },
                { app.player.setRepeat(RepeatMode.entries[(repeat.ordinal + 1) % RepeatMode.entries.size]) },
                size = 40.dp,
                iconSize = 22.dp,
                active = repeat != RepeatMode.Off,
                tint = ink,
                toggled = repeat != RepeatMode.Off,
            )
        }
        Spacer(Modifier.height(10.dp))
        // The volume: quiet on the left, loud on the right; the wheel moves it.
        val volume = state.volume
        Row(
            Modifier.fillMaxWidth().onPointerEvent(PointerEventType.Scroll) { event ->
                val dy = event.changes.firstOrNull()?.scrollDelta?.y ?: 0f
                if (dy != 0f) app.setVolume(volume - dy * 0.05f)
            },
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            IconAction(OctoIcons.VolumeDown, "Quieter", { app.setVolume(volume - 0.1f) }, size = 30.dp, iconSize = 18.dp, tint = muted)
            LineSlider(fraction = { volume }, onSeek = app::setVolume, modifier = Modifier.weight(1f), live = true, color = ink, trackColor = ink.copy(alpha = 0.22f), label = "Volume")
            IconAction(OctoIcons.VolumeUp, "Louder", { app.setVolume(volume + 0.1f) }, size = 30.dp, iconSize = 18.dp, tint = muted)
        }
    }
}

// A station's lines under its cover: the song on air (or the station),
// "Artist · Station" (or its tagline or place) and the heart, the live
// line, Back, Play or Stop and Next, and the volume.
@OptIn(ExperimentalComposeUiApi::class)
@Composable
private fun LivePlayerLines(app: AppState, song: Song, state: PlayerState, live: LiveNow, ink: Color, muted: Color) {
    // The button sits on the title's line.
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.Top) {
        Column(Modifier.weight(1f)) {
            Txt(song.title, OctoType.headline, ink, maxLines = 2)
            Txt(live.shown.subtitle, OctoType.body, muted, Modifier.heightIn(min = Focus.MinTarget), maxLines = 2)
        }
        OnTitleLine(OctoType.headline) { OnAirButton(app, live, 40.dp, 22.dp, ink) }
    }
    Spacer(Modifier.height(14.dp))
    LiveLine(app, ink, muted, Modifier.fillMaxWidth(), stacked = true)
    Spacer(Modifier.height(16.dp))
    LiveTransport(app, state, live, playSize = 68.dp, stepSize = 48.dp, stepIcon = 30.dp, tint = ink, gap = 14.dp)
    Spacer(Modifier.height(10.dp))
    val volume = state.volume
    Row(
        Modifier.fillMaxWidth().onPointerEvent(PointerEventType.Scroll) { event ->
            val dy = event.changes.firstOrNull()?.scrollDelta?.y ?: 0f
            if (dy != 0f) app.setVolume(volume - dy * 0.05f)
        },
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        IconAction(OctoIcons.VolumeDown, "Quieter", { app.setVolume(volume - 0.1f) }, size = 30.dp, iconSize = 18.dp, tint = muted)
        LineSlider(fraction = { volume }, onSeek = app::setVolume, modifier = Modifier.weight(1f), live = true, color = ink, trackColor = ink.copy(alpha = 0.22f), label = "Volume")
        IconAction(OctoIcons.VolumeUp, "Louder", { app.setVolume(volume + 0.1f) }, size = 30.dp, iconSize = 18.dp, tint = muted)
    }
}

// The More button over the full player while a station plays: its menu of
// station rows, and the sleep timer.
@Composable
private fun LiveMoreButton(app: AppState, live: LiveNow, stationId: String, ink: Color) {
    var anchor by remember { mutableStateOf(androidx.compose.ui.unit.IntRect.Zero) }
    Box(Modifier.onGloballyPositioned { anchor = it.windowRect() }) {
        IconAction(OctoIcons.More, "More", {
            app.popups.showUnder(anchor, width = FrameSize.Menu) { close -> LiveMenuRows(app, live, stationId, close) }
        }, size = 36.dp, iconSize = 20.dp, tint = ink)
    }
}

// The time played and the time left under the seek line. The place moves
// every frame, but the two times only change about once a second, so only
// they compose again, and only then.
@Composable
private fun PlayTimes(position: State<Long>, duration: Long, color: Color) {
    val times by remember(position, duration) {
        derivedStateOf {
            val at = position.value
            (at / 1000).toInt() to ((duration - at).coerceAtLeast(0) / 1000).toInt()
        }
    }
    Row(Modifier.fillMaxWidth()) {
        Txt(lengthText(times.first).ifEmpty { "0:00" }, OctoType.caption, color, Modifier.weight(1f))
        Txt("-" + lengthText(times.second).ifEmpty { "0:00" }, OctoType.caption, color, align = TextAlign.End)
    }
}
