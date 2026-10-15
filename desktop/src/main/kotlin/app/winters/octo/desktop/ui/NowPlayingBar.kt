package app.winters.octo.desktop.ui

import app.winters.octo.design.OctoDuration
import app.winters.octo.design.octoTween
import app.winters.octo.design.motionScale
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.heightIn
import app.winters.octo.design.Focus
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import app.winters.octo.design.FocusRing
import app.winters.octo.design.adjustable
import app.winters.octo.desktop.nav.SEEK_STEP_MS
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.MutableFloatState
import androidx.compose.runtime.State
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.PointerEventType
import androidx.compose.ui.input.pointer.PointerIcon
import androidx.compose.ui.input.pointer.onPointerEvent
import androidx.compose.ui.input.pointer.pointerHoverIcon
import androidx.compose.ui.layout.boundsInWindow
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntRect
import androidx.compose.ui.unit.dp
import app.winters.octo.design.ControlHeight
import app.winters.octo.design.Corner
import app.winters.octo.design.CutTxt
import app.winters.octo.design.DesktopType
import app.winters.octo.design.FloatingGlaze
import app.winters.octo.design.FrameSize
import app.winters.octo.design.Glaze
import app.winters.octo.design.GlazeLight
import app.winters.octo.design.Glyph
import app.winters.octo.design.IconAction
import app.winters.octo.design.IconSize
import app.winters.octo.design.IslandFilm
import app.winters.octo.design.IslandFrost
import app.winters.octo.design.IslandSaturation
import app.winters.octo.design.LineSlider
import app.winters.octo.design.MenuFilm
import app.winters.octo.design.MenuFrost
import app.winters.octo.design.MenuRow
import app.winters.octo.design.MenuSeparator
import app.winters.octo.design.MenuShape
import app.winters.octo.design.MenuTitle
import app.winters.octo.design.OctoColors
import app.winters.octo.design.OctoIcons
import app.winters.octo.design.OctoType
import app.winters.octo.design.PauseGlyph
import app.winters.octo.design.Scrubber
import app.winters.octo.design.Space
import app.winters.octo.design.Spinner
import app.winters.octo.design.Txt
import app.winters.octo.design.hoverLift
import app.winters.octo.design.OctoTooltip
import app.winters.octo.design.TooltipPopup
import app.winters.octo.design.rememberTooltipState
import app.winters.octo.design.tooltipTarget
import app.winters.octo.desktop.AppState
import app.winters.octo.desktop.SidePanel
import app.winters.octo.desktop.library.Cover
import app.winters.octo.desktop.library.lengthText
import app.winters.octo.desktop.nav.Page
import app.winters.octo.desktop.player.DesktopPlayer
import app.winters.octo.desktop.player.LiveNow
import app.winters.octo.desktop.player.PlayerState
import app.winters.octo.desktop.player.RepeatMode
import app.winters.octo.desktop.player.formatLabel
import app.winters.octo.desktop.startRadio
import app.winters.octo.desktop.system.MiniPlayerButton
import app.winters.octo.desktop.system.isOpenedFile
import app.winters.octo.playback.SLEEP_EXTENSIONS
import app.winters.octo.playback.SLEEP_MINUTES
import app.winters.octo.playback.SLEEP_SONG_COUNTS
import app.winters.octo.playback.SleepState
import app.winters.octo.playback.sleepSummary
import app.winters.octo.subsonic.Song
import dev.chrisbanes.haze.HazeState
import kotlin.math.roundToInt
import kotlinx.coroutines.delay

// Where the song is, for the time and a progress line `lengthPx` long (0
// for a time alone): read on each whole second for the time and, for the
// line, each time it has moved half a pixel but at most five times a
// second, while it plays and the window is on screen; and once at each
// change of the player (a seek counts as one), so a paused or hidden
// window never wakes to ask.
@Composable
fun rememberPosition(player: DesktopPlayer, lengthPx: Float = 0f): State<Long> {
    val position = remember { mutableLongStateOf(player.positionMs()) }
    val state by player.state.collectAsState()
    val shown = LocalWindowShown.current
    val length by rememberUpdatedState(lengthPx)
    LaunchedEffect(player, state, shown) {
        position.longValue = player.positionMs()
        while (state.playing && shown) {
            val line = if (length > 0f) progressStepMs(state.durationMs, length).coerceAtLeast(LINE_STEP_MS) else Long.MAX_VALUE
            delay(minOf(line, msToNextSecond(position.longValue)))
            position.longValue = player.positionMs()
        }
    }
    return position
}

// The shortest wait between two steps of a small progress line.
private const val LINE_STEP_MS = 200L

// The player, floating in glass at the foot of the page. The cover fills
// its height on the left (a click opens the full player). Beside it, the
// top line has the song, the transport in the middle and the panels,
// volume and More on the right, with the progress line underneath. The two
// sides share the width evenly, so the transport stays centred whatever
// the song's title. When `compact` (a narrow page), the panel buttons move
// into More and the song takes all the room the transport leaves.
@Composable
fun PlayerBar(app: AppState, backdrop: HazeState, modifier: Modifier = Modifier, compact: Boolean = false) {
    val state by app.player.state.collectAsState()
    val song = state.current?.song
    // Songs dragged here go to the end of the queue; the player lights
    // while they are held over it.
    val over = isDropOver(PlayerDrop)
    FloatingGlaze(backdrop, modifier.dropTarget(PlayerDrop, "Add to the queue", layer = 1) { app.addToQueue(it) }, shape = MenuShape, film = IslandFilm, frost = IslandFrost, saturation = IslandSaturation, halo = true, seesAll = true) {
        if (over) Box(Modifier.matchParentSize().background(DropLit, MenuShape))
        Row(Modifier.fillMaxSize().padding(horizontal = Space.L), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Space.L)) {
            val live = state.live
            OctoTooltip(if (song != null) "Open the player" else "") {
                val thumb = Modifier
                    .size(FrameSize.PlayerThumb)
                    .clickable(enabled = song != null, role = Role.Button) { app.fullPlayer = true }
                    .semantics { contentDescription = "Open the player" }
                if (live != null) {
                    LiveCover(app, live, thumb, Corner.ArtMShape, small = true)
                } else {
                    Cover(song?.coverArt, thumb, shape = Corner.ArtMShape, placeholder = OctoIcons.Songs, retry = true)
                }
            }
            Column(Modifier.weight(1f)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Box(Modifier.weight(1f), contentAlignment = Alignment.CenterStart) { if (live != null && song != null) LiveSongZone(app, song, live) else SongZone(app, song) }
                    if (live != null) {
                        Box(Modifier.padding(horizontal = Space.M)) {
                            LiveTransport(app, state, live, playSize = PlayTarget, stepSize = ControlHeight.L, stepIcon = IconSize.Transport, tint = OctoColors.TextPrimary)
                        }
                    } else {
                        Transport(app, state)
                    }
                    if (compact) UtilityZone(app, state, compact = true)
                    else Box(Modifier.weight(1f), contentAlignment = Alignment.CenterEnd) { UtilityZone(app, state) }
                }
                if (live != null) {
                    LiveLine(app, OctoColors.TextPrimary, OctoColors.TextMuted, Modifier.fillMaxWidth().heightIn(min = Focus.MinTarget))
                } else {
                    ProgressLine(app, state)
                }
            }
        }
    }
}

private const val PlayerDrop = "player"

// The song's title (which opens its album), the artist as a link, and the
// heart, or the "+" for a song found online.
@Composable
private fun SongZone(app: AppState, song: Song?) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Space.Xs)) {
        // Far enough apart that the title and the artist are two targets.
        Column(Modifier.weight(1f, fill = false), verticalArrangement = Arrangement.spacedBy(Space.Xs)) {
            if (song == null) {
                Txt("Nothing playing", DesktopType.emphasis, OctoColors.TextMuted)
            } else {
                val album = song.albumId?.takeIf(String::isNotBlank)
                MarkedTitle(song, DesktopType.emphasis) { title ->
                    CutTxt(
                        song.title,
                        DesktopType.emphasis,
                        OctoColors.TextPrimary,
                        if (album != null) {
                            title
                                .pointerHoverIcon(PointerIcon.Hand)
                                .clickable(role = Role.Button) { app.navigator.go(Page.Album(album)) }
                                .semantics { contentDescription = "${song.title}, open its album" }
                        } else {
                            title
                        },
                    )
                }
                LinkText(song.displayArtist ?: song.artist.orEmpty(), song.artistId) { app.navigator.go(Page.Artist(it, song.artist.orEmpty())) }
            }
        }
        // A song found online can't be a favorite; its "+" adds it to the
        // library instead.
        if (song != null && isOutside(app, song)) {
            FetchButton(app, song, ControlHeight.M, IconSize.Toolbar, tint = OctoColors.TextPrimary)
        } else if (song != null) {
            val starred = app.isStarred(song)
            IconAction(if (starred) OctoIcons.Liked else OctoIcons.Like, if (starred) "Remove from favorites" else "Add to favorites", { app.setStarred(listOf(song), !starred) }, size = ControlHeight.M, iconSize = IconSize.Toolbar)
        }
    }
}

// A station's title (the song on air, or the station), "Artist ·
// Station" under it, and the heart for the song on air.
@Composable
private fun LiveSongZone(app: AppState, song: Song, live: LiveNow) {
    // The button sits on the title's line.
    Row(verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(Space.Xs)) {
        Column(Modifier.weight(1f, fill = false), verticalArrangement = Arrangement.spacedBy(Space.Xs)) {
            CutTxt(song.title, DesktopType.emphasis, OctoColors.TextPrimary, Modifier)
            Txt(live.shown.subtitle, DesktopType.meta, OctoColors.TextSecondary)
        }
        OnTitleLine(DesktopType.emphasis) { OnAirButton(app, live, ControlHeight.M, IconSize.Toolbar, OctoColors.TextPrimary) }
    }
}

// Shuffle, back, play, next and repeat.
@Composable
private fun Transport(app: AppState, state: PlayerState) {
    val song = state.current?.song
    Row(Modifier.padding(horizontal = Space.M), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Space.Xs)) {
        IconAction(OctoIcons.Shuffle, "Shuffle", { app.player.setShuffle(!state.shuffle) }, size = ControlHeight.M, iconSize = IconSize.Toolbar, active = state.shuffle, toggled = state.shuffle)
        IconAction(OctoIcons.Previous, "Previous", app.player::previous, size = ControlHeight.L, iconSize = IconSize.Transport, enabled = song != null)
        PlayButton(state.playing, enabled = song != null, size = PlayTarget, glyph = IconSize.Transport * PlayScale, waiting = state.buffering) { app.player.togglePlay() }
        IconAction(OctoIcons.Next, "Next", app.player::next, size = ControlHeight.L, iconSize = IconSize.Transport, enabled = song != null)
        val repeat = state.repeat
        IconAction(
            if (repeat == RepeatMode.One) OctoIcons.RepeatOne else OctoIcons.Repeat,
            when (repeat) {
                RepeatMode.Off -> "Repeat"
                RepeatMode.All -> "Repeat all"
                RepeatMode.One -> "Repeat one"
            },
            { app.player.setRepeat(RepeatMode.entries[(repeat.ordinal + 1) % RepeatMode.entries.size]) },
            size = ControlHeight.M,
            iconSize = IconSize.Toolbar,
            active = repeat != RepeatMode.Off,
            toggled = repeat != RepeatMode.Off,
        )
    }
}

// The progress line, with the time played on the left and, on the right,
// the time left (or the song's length; a click swaps).
@Composable
private fun ProgressLine(app: AppState, state: PlayerState) {
    var lineLength by remember { mutableFloatStateOf(0f) }
    val position by rememberPosition(app.player, lineLength)
    val settings by app.settings.state.collectAsState()
    val left = settings.frame.showTimeLeft
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Space.M)) {
        val duration = state.durationMs
        // Where a drag would land, shown in place of the time while dragging.
        var scrubbing by remember { mutableStateOf<Float?>(null) }
        val shownMs = scrubbing?.let { (it * duration).toLong() } ?: position
        Txt(lengthText((shownMs / 1000).toInt()).ifEmpty { "0:00" }, TimeStyle, OctoColors.TextMuted, Modifier.width(TimeWidth))
        Scrubber(
            fraction = { if (duration > 0) position.toFloat() / duration else 0f },
            onSeek = { app.player.seekTo((it * duration).toLong()) },
            // The arrow keys move it five seconds; a screen reader hears where it is.
            modifier = Modifier.weight(1f).onSizeChanged { lineLength = it.width.toFloat() }.adjustable(
                "Song position",
                { if (duration > 0) position.toFloat() / duration else 0f },
                { app.player.seekTo((it * duration).toLong()) },
                step = if (duration > 0) (SEEK_STEP_MS.toFloat() / duration).coerceAtMost(1f) else 0.05f,
                reading = { "${lengthText((it * duration / 1000).toInt()).ifEmpty { "0:00" }} of ${lengthText((duration / 1000).toInt()).ifEmpty { "0:00" }}" },
                shape = CircleShape,
            ),
            onScrub = { scrubbing = it },
        )
        val end = if (left && duration > 0) "-" + lengthText(((duration - shownMs).coerceAtLeast(0) / 1000).toInt()).ifEmpty { "0:00" } else lengthText((duration / 1000).toInt()).ifEmpty { "0:00" }
        val tip = rememberTooltipState()
        Box(
            Modifier
                .width(TimeWidth)
                .heightIn(min = Focus.MinTarget)
                .tooltipTarget(tip)
                .clickable(role = Role.Button) { app.updateFrame { it.copy(showTimeLeft = !left) } }
                .semantics { contentDescription = if (left) "Time left, $end. Show the length instead" else "Length, $end. Show the time left instead" },
            contentAlignment = Alignment.CenterEnd,
        ) {
            Txt(end, TimeStyle, OctoColors.TextMuted, align = TextAlign.End)
            TooltipPopup(tip, if (left) "Show the length" else "Show the time left")
        }
    }
}

// Times in figures of one width, so the line never shifts as they change.
private val TimeStyle = DesktopType.meta.copy(fontFeatureSettings = "tnum")
private val TimeWidth = Space.Wide + Space.S

// The panels, the volume and More; when `compact`, the panels are in More.
@Composable
private fun UtilityZone(app: AppState, state: PlayerState, compact: Boolean = false) {
    Row(horizontalArrangement = Arrangement.spacedBy(Space.Xxs), verticalAlignment = Alignment.CenterVertically) {
        if (!compact) {
            // A station has no lyrics.
            if (state.live == null) IconAction(OctoIcons.Lyrics, "Lyrics", { app.toggleSidePanel(SidePanel.Lyrics) }, size = ControlHeight.M, iconSize = IconSize.Toolbar, active = app.sidePanel == SidePanel.Lyrics, toggled = app.sidePanel == SidePanel.Lyrics)
            // A station alone has no stations to list.
            if (state.live == null || state.queue.size > 1) IconAction(OctoIcons.Queue, if (state.live != null) "Stations" else "Queue", { app.toggleSidePanel(SidePanel.Queue) }, size = ControlHeight.M, iconSize = IconSize.Toolbar, active = app.sidePanel == SidePanel.Queue, toggled = app.sidePanel == SidePanel.Queue)
        }
        VolumeButton(app, state.volume)
        MoreButton(app, state, compact)
    }
}

// What is used now and then: the full player, where the sound goes, the
// sleep timer, stopping after this song, a radio from it, the song's
// details (with its format) and the mini player. Lit while a timer is set.
@Composable
private fun MoreButton(app: AppState, state: PlayerState, compact: Boolean) {
    var anchor by remember { mutableStateOf(IntRect.Zero) }
    val sleep by app.sleep.state.collectAsState()
    val timing = sleep != SleepState.Off
    Box(Modifier.onGloballyPositioned { anchor = it.windowRect() }) {
        IconAction(OctoIcons.More, if (timing) "More (sleep timer: ${sleepSummary(sleep)})" else "More", {
            app.popups.showUnder(anchor, width = FrameSize.Menu) { close -> MoreMenu(app, close, compact) }
        }, size = ControlHeight.M, iconSize = IconSize.Toolbar, active = timing || state.stopAfterCurrent)
    }
}

private enum class MorePage { Main, Output, Sleep }

@Composable
private fun ColumnScope.MoreMenu(app: AppState, close: () -> Unit, compact: Boolean) {
    var page by remember { mutableStateOf(MorePage.Main) }
    val now by app.player.state.collectAsState()
    val sleep by app.sleep.state.collectAsState()
    when (page) {
        MorePage.Main -> {
            val live = now.live
            MenuRow("Open the player", { app.fullPlayer = true; close() }, OctoIcons.Expand, enabled = now.current != null)
            // The panel buttons, when the player is too narrow to show them.
            if (compact) {
                if (live == null) MenuRow("Lyrics", { app.toggleSidePanel(SidePanel.Lyrics); close() }, if (app.sidePanel == SidePanel.Lyrics) OctoIcons.Check else OctoIcons.Lyrics)
                if (live == null || now.queue.size > 1) MenuRow(if (live != null) "Stations" else "Queue", { app.toggleSidePanel(SidePanel.Queue); close() }, if (app.sidePanel == SidePanel.Queue) OctoIcons.Check else OctoIcons.Queue)
            }
            MenuRow("Play on", { page = MorePage.Output }, outputIcon(now.playingOn?.name), more = true, detail = now.playingOn?.name ?: "System default")
            MenuSeparator()
            MenuRow("Sleep timer", { page = MorePage.Sleep }, OctoIcons.SleepTimer, more = true, detail = if (sleep != SleepState.Off) sleepSummary(sleep) else null)
            // A station: its own rows, in place of the song's.
            if (live != null) {
                MenuSeparator()
                LiveMenuRows(app, live, now.current?.song?.id.orEmpty(), close)
                app.toggleMiniPlayer?.let { toggle -> MenuRow("Mini player", { toggle(); close() }, OctoIcons.Expand) }
                return
            }
            MenuRow(
                "Stop after this song",
                { app.player.setStopAfterCurrent(!now.stopAfterCurrent); close() },
                if (now.stopAfterCurrent) OctoIcons.Check else OctoIcons.Pause,
                enabled = now.current != null,
            )
            MenuSeparator()
            // Songs like this one after it, as the song menu's Start radio.
            // A file opened from this computer has none on the server.
            val song = now.current?.song
            MenuRow("Start radio", { song?.let(app::startRadio); close() }, OctoIcons.Radio, enabled = song != null && app.connection != null && !isOpenedFile(song.id))
            MenuRow("Song details", { app.showInfo(null); close() }, OctoIcons.Info, enabled = now.current != null, detail = formatLabel(now.format))
            app.toggleMiniPlayer?.let { toggle -> MenuRow("Mini player", { toggle(); close() }, OctoIcons.Expand) }
        }
        MorePage.Output -> OutputMenu(app, back = { page = MorePage.Main }, close = close)
        MorePage.Sleep -> SleepMenu(app, sleep, back = { page = MorePage.Main }, close = close)
    }
}

// The phone's sleep choices: a length, the end of this song, or after a
// few songs; and while one runs, more time or off.
@Composable
private fun ColumnScope.SleepMenu(app: AppState, sleep: SleepState, back: () -> Unit, close: () -> Unit) {
    MenuRow("Back", back, OctoIcons.Back)
    MenuSeparator()
    if (sleep != SleepState.Off) {
        MenuTitle("Stopping: ${sleepSummary(sleep)}")
        if (sleep is SleepState.Counting) {
            SLEEP_EXTENSIONS.forEach { minutes -> MenuRow("Add $minutes minutes", { app.sleep.extend(minutes); close() }, OctoIcons.SleepTimer) }
        }
        MenuRow("Turn off", { app.sleep.cancel(); close() }, OctoIcons.Close)
        MenuSeparator()
    }
    SLEEP_MINUTES.forEach { minutes ->
        MenuRow(if (minutes == 60) "1 hour" else "$minutes minutes", { app.sleep.start(minutes); close() })
    }
    // A station never ends a song, so it stops only after a while.
    if (app.player.state.value.live == null) {
        MenuRow("At the end of this song", { app.sleep.endOfSong(); close() }, enabled = app.player.state.value.current != null)
        SLEEP_SONG_COUNTS.filter { it > 1 }.forEach { count ->
            MenuRow("After $count songs", { app.sleep.afterSongs(count); close() }, enabled = app.player.state.value.current != null)
        }
    }
}

// Play and pause in a transport: the sign alone, white like the controls
// beside it and the size of the main action, `glyph` square (about one and
// a half times theirs), in a round target `size` across that lifts under
// the pointer and shrinks a touch when pressed, as theirs do. While waiting
// for sound a spinner turns in its place. For a live station (`stop`) it is
// Play and Stop.
@Composable
fun PlayButton(
    playing: Boolean,
    enabled: Boolean,
    size: Dp = FrameSize.PlayButtonLarge,
    glyph: Dp = size * 0.68f,
    waiting: Boolean = false,
    label: String? = null,
    stop: Boolean = false,
    tint: Color = OctoColors.TextPrimary,
    onClick: () -> Unit,
) {
    val tip = rememberTooltipState()
    val words = if (!playing) "Play" else if (stop) "Stop" else "Pause"
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val motion = motionScale()
    val press by animateFloatAsState(if (pressed) motion.scale(0.9f) else 1f, octoTween(motion, OctoDuration.Press), label = "press")
    Box(
        Modifier
            .size(size.coerceAtLeast(Focus.MinTarget))
            .graphicsLayer {
                scaleX = press
                scaleY = press
            }
            .alpha(if (enabled) 1f else 0.35f)
            .hoverLift(CircleShape, clickable = enabled)
            .tooltipTarget(tip)
            .clickable(interactionSource = interaction, indication = FocusRing(CircleShape), enabled = enabled, role = Role.Button, onClick = onClick)
            .semantics { contentDescription = label ?: words },
        contentAlignment = Alignment.Center,
    ) {
        when {
            waiting && playing -> Spinner(size = glyph * 0.8f, color = tint)
            playing && stop -> StopGlyph(tint, size = glyph)
            playing -> PauseGlyph(tint, size = glyph)
            else -> Glyph(OctoIcons.Play, size = glyph, tint = tint)
        }
        TooltipPopup(tip, words)
    }
}

// Play over a picture (a station's card): the sign in a lit glass circle,
// so it reads on any picture.
@Composable
fun PlayBadge(size: Dp, label: String, onClick: () -> Unit) {
    val tip = rememberTooltipState()
    Glaze(
        Modifier
            .size(size)
            .hoverLift(CircleShape)
            .tooltipTarget(tip)
            .clickable(role = Role.Button, interactionSource = null, indication = FocusRing(CircleShape), onClick = onClick)
            .semantics { contentDescription = label },
        light = GlazeLight.Lifted,
    ) {
        Glyph(OctoIcons.Play, size = size * 0.48f)
        TooltipPopup(tip, "Play")
    }
}

// Where the sound goes: the system's default (followed as it changes, so
// plugging in headphones moves the sound there) and every device the engine
// can play to. The chosen one is ticked.
@Composable
private fun ColumnScope.OutputMenu(app: AppState, back: () -> Unit, close: () -> Unit) {
    val now by app.player.state.collectAsState()
    MenuRow("Back", back, OctoIcons.Back)
    MenuSeparator()
    MenuTitle("Play on")
    now.outputs.forEachIndexed { index, device ->
        if (index == 1) MenuSeparator()
        MenuRow(
            device.name,
            {
                app.selectOutput(device.id)
                close()
            },
            if (device.id == now.output?.id) OctoIcons.Check else outputIcon(device.name),
            detail = if (index == 0) "Follows the system" else null,
        )
    }
}

// Headphones for a device named like a pair, a speaker otherwise.
private fun outputIcon(name: String?): ImageVector {
    val lower = name.orEmpty().lowercase()
    val pair = listOf("headphone", "headset", "earbud", "airpods", "buds", "earphone").any { it in lower }
    return if (pair) OctoIcons.Headphones else OctoIcons.Speaker
}

// The volume: the wheel over the speaker turns it up or down, and a click
// opens a line to drag and Mute.
@OptIn(ExperimentalComposeUiApi::class)
@Composable
private fun VolumeButton(app: AppState, volume: Float) {
    var anchor by remember { mutableStateOf(IntRect.Zero) }
    // The volume before muting, to go back to.
    val before = remember { mutableFloatStateOf(0.8f) }
    Box(
        Modifier
            .onGloballyPositioned { anchor = it.windowRect() }
            .onPointerEvent(PointerEventType.Scroll) { event ->
                val dy = event.changes.firstOrNull()?.scrollDelta?.y ?: 0f
                if (dy != 0f) app.setVolume(app.player.state.value.volume - dy * 0.05f)
            },
    ) {
        IconAction(
            if (volume <= 0.001f) OctoIcons.VolumeDown else OctoIcons.VolumeUp,
            "Volume ${(volume * 100).roundToInt()}%",
            { app.popups.showUnder(anchor, width = FrameSize.Menu) { _ -> VolumeMenu(app, before) } },
            size = ControlHeight.M,
            iconSize = IconSize.Toolbar,
        )
    }
}

@Composable
private fun ColumnScope.VolumeMenu(app: AppState, before: MutableFloatState) {
    val now by app.player.state.collectAsState()
    val volume = now.volume
    val muted = volume <= 0.001f
    MenuTitle("Volume ${(volume * 100).roundToInt()}%")
    LineSlider(
        fraction = { app.player.state.value.volume },
        onSeek = app::setVolume,
        modifier = Modifier.fillMaxWidth().padding(horizontal = Space.L, vertical = Space.M),
        live = true,
        label = "Volume",
    )
    MenuRow(
        if (muted) "Unmute" else "Mute",
        {
            if (muted) {
                app.setVolume(before.floatValue.takeIf { it > 0.01f } ?: 0.8f)
            } else {
                before.floatValue = volume
                app.setVolume(0f)
            }
        },
        if (muted) OctoIcons.VolumeUp else OctoIcons.VolumeDown,
    )
}

// A laid-out thing's bounds in the window, for opening a pop-up under it.
fun androidx.compose.ui.layout.LayoutCoordinates.windowRect(): IntRect {
    val r = boundsInWindow()
    return IntRect(r.left.roundToInt(), r.top.roundToInt(), r.right.roundToInt(), r.bottom.roundToInt())
}

// How much bigger Play's sign is than the controls' beside it.
val PlayTarget: Dp get() = FrameSize.PlayTarget
const val PlayScale = 1.5f
