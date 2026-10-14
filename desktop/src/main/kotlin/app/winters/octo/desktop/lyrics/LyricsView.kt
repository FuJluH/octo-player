package app.winters.octo.desktop.lyrics

import app.winters.octo.design.motionScale
import androidx.compose.foundation.lazy.rememberLazyListState
import app.winters.octo.design.scrollbar
import app.winters.octo.design.OctoDuration
import androidx.compose.ui.semantics.Role
import androidx.compose.animation.Crossfade
import androidx.compose.animation.core.tween
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.IntRect
import androidx.compose.ui.unit.dp
import app.winters.octo.desktop.AppState
import app.winters.octo.desktop.ui.windowRect
import app.winters.octo.design.GlassField
import app.winters.octo.design.GlazeCapsule
import app.winters.octo.design.LocalReduceMotion
import app.winters.octo.design.IconAction
import app.winters.octo.design.MenuRow
import app.winters.octo.design.MenuSeparator
import app.winters.octo.design.MenuTitle
import app.winters.octo.design.OctoColors
import app.winters.octo.design.OctoIcons
import app.winters.octo.design.OctoType
import app.winters.octo.design.PopupPadding
import app.winters.octo.design.Separator
import app.winters.octo.design.Spinner
import app.winters.octo.design.TextAction
import app.winters.octo.design.Txt
import app.winters.octo.design.hoverLift
import app.winters.octo.lyrics.LyricsLook
import app.winters.octo.subsonic.Song
import kotlinx.coroutines.launch
import java.io.IOException

// The lyrics of the song playing, wherever they show (the side panel and
// the full player): flowing word by word when timed, as text when not, or
// a quiet line saying why there are none. The clock is the engine's audio
// clock, with the song's and the output's timing on top of the screen's
// lead, as on the phone.
@Composable
fun LyricsView(app: AppState, modifier: Modifier = Modifier, textColor: Color = Color.White) {
    val model = app.lyrics
    val shown by model.state.collectAsState()
    val player by app.player.state.collectAsState()
    val settings by app.settings.state.collectAsState()
    val bluetooth by model.bluetooth.collectAsState()
    val song = shown.song
    Crossfade(shown.answer, animationSpec = tween(motionScale().ms(OctoDuration.Neutral)), modifier = modifier, label = "lyrics") { answer ->
        when {
            song == null -> Quiet("Play a song to see its lyrics here.", textColor)
            answer == null -> Box(Modifier.fillMaxSize())
            answer is LyricsAnswer.Found -> {
                val lyrics = answer.lyrics
                val screenLead = remember { screenLeadMs(screenRefreshHz()) }
                val device = player.playingOn?.id
                val outputOffset = outputTimingOf(device?.let { settings.lyrics.outputOffsets[it] }, bluetooth).ms + screenLead
                val offset = settings.lyrics.offsets[song.id] ?: 0L
                when {
                    lyrics.instrumental -> Quiet("Instrumental", textColor)
                    lyrics.synced -> FlowingLyrics(
                        lyrics,
                        playing = player.playing,
                        trackKey = player.current?.key,
                        positionMs = app.player::positionMs,
                        speed = { app.player.state.value.speed },
                        offsetMs = offset,
                        outputOffsetMs = outputOffset,
                        look = LyricsLook(bloomFast = settings.lyrics.bloomFast),
                        calm = LocalReduceMotion.current,
                        onSeek = app.player::seekTo,
                        textColor = textColor,
                    )
                    else -> PlainLyrics(lyrics.lines.map { it.text }, textColor)
                }
            }
            answer == LyricsAnswer.None -> Quiet("No lyrics for this song", textColor)
            answer == LyricsAnswer.Hidden -> Quiet("Lyrics are hidden for this song", textColor)
            else -> Quiet("Couldn't load lyrics. Click to try again.", textColor) { model.sources.refresh(song.id) }
        }
    }
}

@Composable
private fun Quiet(text: String, color: Color, onClick: (() -> Unit)? = null) {
    Box(Modifier.fillMaxSize().padding(24.dp), contentAlignment = Alignment.Center) {
        Txt(
            text,
            OctoType.bodySmall,
            color.copy(alpha = 0.9f),
            if (onClick != null) Modifier.clickable(role = Role.Button, onClick = onClick) else Modifier,
            align = TextAlign.Center,
            maxLines = 3,
        )
    }
}

// Lyrics with no timing, as text to read.
@Composable
private fun PlainLyrics(lines: List<String>, color: Color) {
    val list = rememberLazyListState()
    LazyColumn(Modifier.fillMaxSize().scrollbar(list), list, contentPadding = PaddingValues(horizontal = 24.dp, vertical = 32.dp)) {
        items(lines) { line ->
            Txt(line.ifBlank { " " }, OctoType.body, color.copy(alpha = 0.9f), Modifier.padding(vertical = 4.dp), maxLines = 6)
        }
    }
}

// The lyrics menu's button: where the lyrics came from, other lyrics to
// choose, the timing, and hiding them for this song or showing them again,
// in glass pop-ups.
@Composable
fun LyricsMenuButton(app: AppState, tint: Color = Color.White) {
    var anchor by remember { mutableStateOf(IntRect.Zero) }
    val shown by app.lyrics.state.collectAsState()
    val song = shown.song ?: return
    Box(Modifier.onGloballyPositioned { anchor = it.windowRect() }) {
        IconAction(OctoIcons.More, "Lyrics options", { openLyricsMenu(app, song, anchor) }, size = 32.dp, iconSize = 18.dp, tint = tint)
    }
}

fun openLyricsMenu(app: AppState, song: Song, anchor: IntRect) {
    val model = app.lyrics
    app.popups.showUnder(anchor, width = 300.dp) { close ->
        val scope = rememberCoroutineScope()
        val answer = model.state.value.answer
        MenuTitle("Lyrics")
        Txt(
            when (answer) {
                is LyricsAnswer.Found -> sourceLine(answer.lyrics)
                LyricsAnswer.Hidden -> "Lyrics are hidden for this song"
                LyricsAnswer.None -> "No lyrics found for this song"
                LyricsAnswer.Failed -> "Couldn't load lyrics"
                null -> "Looking for lyrics"
            },
            OctoType.caption,
            OctoColors.TextMuted,
            Modifier.padding(start = 16.dp, end = 16.dp, bottom = 6.dp),
        )
        MenuSeparator()
        if (answer == LyricsAnswer.Hidden) {
            MenuRow("Show lyrics again", {
                scope.launch { model.sources.show(song) }
                close()
            }, OctoIcons.Lyrics)
        } else {
            MenuRow(if (answer is LyricsAnswer.Found) "Choose other lyrics" else "Find lyrics", {
                close()
                app.popups.showCentred(width = 480.dp) { done -> LyricsChooser(app, song, done) }
            }, OctoIcons.Search, more = true)
            if (answer is LyricsAnswer.Found && answer.lyrics.synced) {
                MenuRow("Adjust timing", {
                    close()
                    app.popups.showUnder(anchor, width = 320.dp) { TimingControl(app, song) }
                }, OctoIcons.History, more = true)
            }
            MenuRow("Hide lyrics for this song", {
                scope.launch { model.sources.hide(song) }
                close()
            }, OctoIcons.Close)
        }
    }
}

// Moves the lyrics earlier or later a twentieth of a second a click, while
// they keep playing behind the menu: for this song, and for every song on
// the output playing now.
@Composable
private fun TimingControl(app: AppState, song: Song) {
    val settings by app.settings.state.collectAsState()
    val player by app.player.state.collectAsState()
    val model = app.lyrics
    MenuTitle("Lyrics timing")
    PopupPadding {
        Txt("If the words light up late, click Earlier. If early, click Later.", OctoType.caption, OctoColors.TextMuted, maxLines = 3)
        TimingRow("This song", "For this song only, on every output.", settings.lyrics.offsets[song.id] ?: 0L, { model.stepSong(song.id, it) }) {
            model.stepSong(song.id, -((settings.lyrics.offsets[song.id] ?: 0L) / TIMING_STEP_MS).toInt())
        }
        val device = player.playingOn
        if (device != null) {
            Separator()
            val bluetooth by model.bluetooth.collectAsState()
            val timing = outputTimingOf(settings.lyrics.outputOffsets[device.id], bluetooth)
            TimingRow(
                device.name,
                outputTimingAbout(bluetooth, timing.automatic),
                timing.ms,
                { model.stepOutput(device.id, it) },
                canReset = !timing.automatic,
                resetLabel = "Use automatic",
            ) { model.resetOutput(device.id) }
        }
    }
}

@Composable
private fun TimingRow(
    title: String,
    about: String,
    offset: Long,
    step: (Int) -> Unit,
    canReset: Boolean = offset != 0L,
    resetLabel: String = "Reset",
    reset: () -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Txt(title, OctoType.label)
        Txt(about, OctoType.caption, OctoColors.TextMuted, maxLines = 3)
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            GlazeCapsule(null, "Earlier", { step(-1) }, height = 32.dp)
            Txt(signedTiming(offset), OctoType.label.copy(fontFeatureSettings = "tnum"), modifier = Modifier.weight(1f), align = TextAlign.Center)
            GlazeCapsule(null, "Later", { step(1) }, height = 32.dp)
        }
        if (canReset) Row { TextAction(resetLabel, reset) }
    }
}

// Every copy of the song's lyrics that can be found, to pick one: a search
// by hand at the top, for a song whose title or artist is filed wrong, then
// what was found for the song. Picking one uses it from now on.
@Composable
private fun LyricsChooser(app: AppState, song: Song, close: () -> Unit) {
    val sources = app.lyrics.sources
    val scope = rememberCoroutineScope()
    val onServer = remember { sources.serverDecides() }
    val showing = (app.lyrics.state.value.answer as? LyricsAnswer.Found)?.lyrics
    var query by remember { mutableStateOf("") }
    var searched by remember { mutableStateOf<Result<List<LyricsOption>>?>(null) }
    var searching by remember { mutableStateOf(false) }
    var problem by remember { mutableStateOf<String?>(null) }
    val found by produceState<List<LyricsOption>?>(null, song.id) { value = sources.optionsFor(song) }

    MenuTitle("Choose lyrics")
    PopupPadding {
        if (onServer) Txt("Lyrics picked from your server show on all your devices and apps.", OctoType.caption, OctoColors.TextMuted, maxLines = 2)
        // No search box when there is nowhere to search: online lookups
        // off, on a server that does not keep lyrics choices.
        if (sources.canSearch()) {
            GlassField(
                query,
                { query = it },
                placeholder = if (onServer) "Search by title, or artist - title" else "Search LRCLIB by title or artist",
                icon = OctoIcons.Search,
                onSubmit = {
                    if (query.isNotBlank()) {
                        searching = true
                        scope.launch {
                            searched = try {
                                Result.success(sources.searchFor(song, query))
                            } catch (e: IOException) {
                                Result.failure(e)
                            }
                            searching = false
                        }
                    }
                },
            )
        }
        problem?.let { Txt(it, OctoType.caption, OctoColors.TextMuted) }
    }
    fun pick(option: LyricsOption) {
        scope.launch {
            try {
                sources.choose(song, option)
                close()
            } catch (e: IOException) {
                problem = "Your server couldn't take that choice. Try again, or pick others."
            }
        }
    }
    val results = searched
    if (searching) Row(Modifier.padding(16.dp)) { Spinner() }
    if (results != null && !searching) {
        MenuTitle("Search results")
        results.fold(
            onSuccess = { list ->
                if (list.isEmpty()) Quietly("Nothing found for that")
                list.forEach { OptionRow(it, showing = false) { pick(it) } }
            },
            onFailure = { Quietly(if (onServer) "Couldn't reach your server" else "Couldn't reach LRCLIB") },
        )
        MenuSeparator()
    }
    MenuTitle("For this song")
    val list = found
    when {
        list == null -> Row(Modifier.padding(16.dp)) { Spinner() }
        list.isEmpty() -> Quietly("No lyrics found for this song")
        else -> list.forEach { option -> OptionRow(option, showing = option.lyrics != null && option.lyrics == showing) { pick(option) } }
    }
}

@Composable
private fun Quietly(text: String) {
    Txt(text, OctoType.caption, OctoColors.TextMuted, Modifier.padding(horizontal = 16.dp, vertical = 6.dp))
}

// One set of lyrics to choose: where it is from, what it is, and its first
// two lines. The one showing now is marked.
@Composable
private fun OptionRow(option: LyricsOption, showing: Boolean, onClick: () -> Unit) {
    Column(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = 6.dp)
            .hoverLift(RoundedCornerShape(10.dp), lifted = showing)
            .clickable(role = Role.Button, onClick = onClick)
            .padding(horizontal = 10.dp, vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(2.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Txt(option.from, OctoType.label, modifier = Modifier.weight(1f))
            if (showing) Txt("Showing", OctoType.caption, OctoColors.Accent)
        }
        val about = listOf(option.detail, option.kind.label).filter(String::isNotBlank).joinToString(" · ")
        if (about.isNotEmpty()) Txt(about, OctoType.caption, OctoColors.TextMuted, maxLines = 2)
        val preview = if (option.kind == LyricsKind.Instrumental) listOf("Instrumental") else option.preview
        preview.forEach { Txt(it, OctoType.caption, OctoColors.TextSecondary) }
    }
}
