package app.winters.octo.desktop.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import org.jetbrains.skia.Font
import org.jetbrains.skia.FontMgr
import org.jetbrains.skia.FontStyle
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.foundation.layout.wrapContentHeight
import androidx.compose.ui.unit.dp
import app.winters.octo.design.ControlHeight
import app.winters.octo.design.Corner
import app.winters.octo.design.DesktopType
import app.winters.octo.design.GlazeCapsule
import app.winters.octo.design.Glyph
import app.winters.octo.design.IconAction
import app.winters.octo.design.IconSize
import app.winters.octo.design.LocalReduceMotion
import app.winters.octo.design.MenuRow
import app.winters.octo.design.MenuSeparator
import app.winters.octo.design.MenuTitle
import app.winters.octo.design.OctoColors
import app.winters.octo.design.OctoIcons
import app.winters.octo.design.PopupPadding
import app.winters.octo.design.RowHeight
import app.winters.octo.design.Space
import app.winters.octo.design.Spinner
import app.winters.octo.design.TextAction
import app.winters.octo.design.Txt
import app.winters.octo.design.hoverLift
import app.winters.octo.design.scrollbar
import app.winters.octo.desktop.AppState
import app.winters.octo.desktop.addLiveToServer
import app.winters.octo.desktop.copyWords
import app.winters.octo.desktop.dropLive
import app.winters.octo.desktop.isKept
import app.winters.octo.desktop.keepLive
import app.winters.octo.desktop.liveStationOf
import app.winters.octo.desktop.liveradio.HeartPhase
import app.winters.octo.desktop.search.FetchPhase
import app.winters.octo.desktop.search.phaseText
import app.winters.octo.liveradio.LiveSongButton
import app.winters.octo.liveradio.liveSongButtonLabel
import app.winters.octo.design.OctoTooltip
import app.winters.octo.design.ProgressRing
import androidx.compose.runtime.collectAsState
import kotlinx.coroutines.flow.MutableStateFlow
import app.winters.octo.desktop.liveradio.streamKey
import app.winters.octo.desktop.pages.countryName
import app.winters.octo.desktop.player.LiveNow
import app.winters.octo.desktop.player.PlayerState
import app.winters.octo.desktop.player.QueueEntry
import app.winters.octo.desktop.searchFor
import app.winters.octo.liveradio.LiveStation
import app.winters.octo.liveradio.OnAir
import app.winters.octo.liveradio.heartQuery
import app.winters.octo.liveradio.liveCodecLine
import app.winters.octo.liveradio.liveSubtitle
import app.winters.octo.liveradio.listenedFor
import app.winters.octo.playback.RadioDetails
import app.winters.octo.playback.radioDetailsOf
import app.winters.octo.playback.radioOf
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull

// The live player: what takes the place of the seek line, the transport,
// the heart and the queue while a live station plays.

// Stop: a rounded square, sized as the pause glyph is.
@Composable
fun StopGlyph(color: Color, modifier: Modifier = Modifier, size: Dp = 20.dp) {
    Canvas(modifier.size(size)) {
        val side = this.size.width * 0.62f
        val inset = (this.size.width - side) / 2
        drawRoundRect(color, Offset(inset, inset), Size(side, side), CornerRadius(side * 0.18f))
    }
}

// The LIVE pill: a red dot that breathes gently (held still when motion
// is reduced, or while it is not on screen) and LIVE, on a red tint. A
// screen reader hears "Live".
@Composable
fun LivePill(modifier: Modifier = Modifier) {
    val glow = rememberSteppedPulse(0.35f, 1_100, running = !LocalReduceMotion.current && LocalWindowShown.current)
    Row(
        modifier
            .clearAndSetSemantics { contentDescription = "Live" }
            .background(OctoColors.SignalRed.copy(alpha = 0.16f), CircleShape)
            .border(1.dp, OctoColors.SignalRed.copy(alpha = 0.55f), CircleShape)
            .padding(horizontal = Space.S, vertical = Space.Xxs),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Space.Xs),
    ) {
        Box(Modifier.size(7.dp).graphicsLayer { alpha = glow.value }.background(OctoColors.SignalRed, CircleShape))
        Txt("LIVE", DesktopType.label, LiveRedInk)
    }
}

// The pill's words: the red, lifted enough to read on the dark.
private val LiveRedInk = Color(0xFFFF8A80)

// In place of the seek line: a calm thin line that cannot be dragged, how
// long the station has been listened to since it started where a song's
// time played is, and the LIVE pill. Stacked, the time and the pill sit
// under the line, as the full player has its times; otherwise they sit
// either side of it.
@Composable
fun LiveLine(app: AppState, color: Color, muted: Color, modifier: Modifier = Modifier, times: Boolean = true, stacked: Boolean = false) {
    val position by rememberPosition(app.player)
    val listened = listenedFor(position)
    val line = @Composable { m: Modifier -> Box(m.height(2.dp).background(color.copy(alpha = 0.3f), CircleShape)) }
    val time = @Composable { if (times) Txt(listened, LiveTimeStyle, muted, Modifier.semantics { contentDescription = "Listening for $listened" }) }
    if (stacked) {
        Column(modifier, verticalArrangement = Arrangement.spacedBy(Space.S)) {
            // Level with a seek line's track.
            line(Modifier.fillMaxWidth().padding(top = 11.dp))
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                time()
                Spacer(Modifier.weight(1f))
                LivePill()
            }
        }
    } else {
        Row(modifier, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Space.M)) {
            time()
            line(Modifier.weight(1f))
            LivePill()
        }
    }
}

// Holds a button centered on the first line of a title in this style: as
// tall as that line, with the button free to reach past it, so it sits
// level with the title rather than with the title and the line under it.
@Composable
fun OnTitleLine(style: TextStyle, content: @Composable () -> Unit) {
    val line = with(LocalDensity.current) { (if (style.lineHeight.isSp) style.lineHeight else style.fontSize * 1.3f).toDp() }
    Box(Modifier.height(line).wrapContentHeight(unbounded = true), contentAlignment = Alignment.Center) { content() }
}

// Holds a button with its middle on the middle of the capitals of a title's
// first line in this style (its baseline less half its capital height,
// from the font), with the button free to reach past it: the title's big
// capitals are what the eye lines it up with, not its line's box.
@Composable
fun OnTitleCapitals(style: TextStyle, content: @Composable () -> Unit) {
    val measurer = rememberTextMeasurer()
    val density = LocalDensity.current
    val middle = remember(measurer, style, density) {
        val baseline = measurer.measure("H", style, maxLines = 1).firstBaseline
        val size = with(density) { style.fontSize.toPx() }
        val bold = (style.fontWeight ?: FontWeight.Normal) >= FontWeight.SemiBold
        val typeface = FontMgr.default.matchFamilyStyle(null, if (bold) FontStyle.BOLD else FontStyle.NORMAL)
        val cap = typeface?.let { Font(it, size).metrics.capHeight } ?: (size * 0.7f)
        baseline - cap / 2
    }
    Box(Modifier.height(with(density) { (middle * 2).toDp() }).wrapContentHeight(unbounded = true), contentAlignment = Alignment.Center) { content() }
}

// How strongly the icons beside a song's name show: a step quieter than
// the name, as actions beside it rather than part of it. A filled heart
// keeps the name's full ink.
const val TitleIconAlpha = 0.7f

private val LiveTimeStyle = DesktopType.meta.copy(fontFeatureSettings = "tnum")

// Back, Play or Stop, and Next for a station: Back and Next change station
// in the list it was started from, hidden with one station and dimmed at
// the ends.
@Composable
fun LiveTransport(app: AppState, state: PlayerState, live: LiveNow, playSize: Dp, stepSize: Dp, stepIcon: Dp, tint: Color, gap: Dp = Space.Xs) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(gap)) {
        val lineup = live.lineup
        if (lineup.shows) IconAction(OctoIcons.Previous, "Previous station", app.player::previous, size = stepSize, iconSize = stepIcon, enabled = lineup.hasPrevious, tint = tint)
        PlayButton(state.playing, enabled = true, size = playSize, glyph = stepIcon * PlayScale, waiting = state.buffering, stop = true, tint = tint) { app.player.togglePlay() }
        if (lineup.shows) IconAction(OctoIcons.Next, "Next station", app.player::next, size = stepSize, iconSize = stepIcon, enabled = lineup.hasNext, tint = tint)
    }
}

// The button beside the song on air, while the station names one: the
// heart for a song in the library (filled once a favorite), the add button
// for one Octo found online (with how its download goes, then the heart
// once it is in), and a plus that opens Search when Octo has no song it is
// sure of. A press while Octo is still looking waits for its answer.
// `quiet` is how strongly an icon shows that is not a filled heart.
@Composable
fun OnAirButton(app: AppState, live: LiveNow, size: Dp, iconSize: Dp, tint: Color, quiet: Float = 1f) {
    val soft = tint.copy(alpha = tint.alpha * quiet)
    val heart = app.liveHeart
    val onAir = live.shown.onAir
    LaunchedEffect(onAir) { heart.follow(onAir) }
    if (!heart.shows || heart.onAir != onAir) return
    val found = heart.match
    val fetches = app.fetches
    val phases by remember(fetches) { fetches?.phases ?: MutableStateFlow(emptyMap()) }.collectAsState()
    val fetch = found?.song?.id?.let { phases[it] } ?: FetchPhase.None
    val starred = found != null && app.isStarred(found.song)
    val button = heart.button(fetch, starred)
    val label = liveSongButtonLabel(button, onAir)
    if (heart.phase == HeartPhase.Looking) {
        Box(Modifier.size(size).semantics { contentDescription = label; stateDescription = "Looking for it in Octo" }, contentAlignment = Alignment.Center) { Spinner(size = iconSize) }
        return
    }
    when (button) {
        LiveSongButton.None -> Unit
        is LiveSongButton.Heart -> IconAction(
            if (button.starred) OctoIcons.Liked else OctoIcons.Like,
            label,
            { heart.press(starredNow = starred) },
            size = size,
            iconSize = iconSize,
            tint = if (button.starred) tint else soft,
            toggled = button.starred,
        )
        is LiveSongButton.Add -> if (button.adding) {
            OctoTooltip(if (fetch == FetchPhase.None) "Adding it to your library" else phaseText(fetch)) {
                Box(
                    Modifier.size(size).semantics {
                        contentDescription = label
                        stateDescription = if (fetch == FetchPhase.None) "Adding" else phaseText(fetch)
                    },
                    contentAlignment = Alignment.Center,
                ) {
                    when (fetch) {
                        is FetchPhase.Downloading -> ProgressRing(fetch.progress, size = iconSize)
                        FetchPhase.Adding -> ProgressRing(1f, size = iconSize)
                        is FetchPhase.Failed -> Glyph(OctoIcons.Info, size = iconSize, tint = OctoColors.Error)
                        else -> ProgressRing(null, size = iconSize)
                    }
                }
            }
        } else {
            IconAction(OctoIcons.AddToLibrary, label, { heart.press() }, size = size, iconSize = iconSize, tint = soft, tooltip = "Not in your library. Press to add it")
        }
        LiveSongButton.Search -> IconAction(OctoIcons.Add, label, { heart.press() }, size = size, iconSize = iconSize, tint = soft, tooltip = "Octo isn't sure which song this is. Press to search for it")
    }
}

// A station's picture in the player: the song on air as Octo has it, else
// the artwork the station sends, else its logo or server picture, else its
// drawn cover.
@Composable
fun LiveCover(app: AppState, live: LiveNow, modifier: Modifier, shape: Shape, small: Boolean = false) {
    val shown = live.shown
    val heart = app.liveHeart
    val found = heart.match?.song?.takeIf { heart.onAir == shown.onAir }
    LiveArt(
        shown.station,
        shown.streamUrl,
        modifier,
        shape,
        artwork = shown.onAir.artwork,
        logo = shown.details.logo,
        coverArt = shown.details.coverArt.ifBlank { null },
        small = small,
        app = app,
        songCover = found?.coverArt,
        songOnline = found?.isExternal == true,
    )
}

// The stations being surfed, in their order, in place of the queue: a
// click switches to one, and the one playing is marked.
@Composable
fun LiveLineupList(app: AppState, state: PlayerState, modifier: Modifier = Modifier.fillMaxSize(), textColor: Color = OctoColors.TextPrimary) {
    val stations = remember(state.played, state.current, state.upcoming) { state.played + listOfNotNull(state.current) + state.upcoming }
    val list = rememberLazyListState(initialFirstVisibleItemIndex = (stations.indexOfFirst { it.key == state.current?.key }).coerceAtLeast(0))
    LazyColumn(modifier.scrollbar(list), list) {
        item(key = "title") {
            Txt("STATIONS", DesktopType.label, textColor.copy(alpha = 0.8f), Modifier.padding(top = Space.M, bottom = Space.Xs, start = Space.L))
        }
        items(stations, key = { it.key }) { entry -> LineupRow(app, entry, entry.key == state.current?.key, textColor) }
    }
}

@Composable
private fun LineupRow(app: AppState, entry: QueueEntry, current: Boolean, textColor: Color) {
    val (stream, name) = radioOf(entry.song.id) ?: (entry.song.id to entry.song.title)
    val details = remember(entry.song.id) { radioDetailsOf(entry.song.id) }
    val station = name.ifBlank { stream }
    val line = liveSubtitle(OnAir.Nothing, station, details)
    Row(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = Space.S)
            .heightIn(min = RowHeight.Roomy)
            .then(if (current) Modifier.background(OctoColors.AccentSelected, Corner.RowShape) else Modifier)
            .hoverLift(Corner.RowShape)
            .clickable(role = Role.Button) { if (!current) app.player.skipTo(entry.key) }
            .semantics {
                contentDescription = if (current) "$station, playing" else "Play $station"
                selected = current
            }
            .padding(horizontal = Space.S, vertical = Space.Xs),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Space.M),
    ) {
        StationLogo(details.logo, station, Modifier.size(ControlHeight.L), Corner.ArtSShape, coverArt = details.coverArt.ifBlank { null })
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(Space.Xxs)) {
            Txt(station, DesktopType.tableTitle, textColor, maxLines = 2)
            Txt(line, DesktopType.meta, textColor.copy(alpha = 0.8f))
        }
        if (current) Glyph(OctoIcons.Check, size = IconSize.Toolbar, tint = OctoColors.TextPrimary)
    }
}

// The More menu's rows for a station: its details, keeping it here, adding
// it to the server (for an admin), and the song on air: found in Octo, or
// its name copied. `info` shows Station info, `find` searches Octo for the
// song; the mini player shows them its own way.
@Composable
fun ColumnScope.LiveMenuRows(
    app: AppState,
    live: LiveNow,
    stationId: String,
    close: () -> Unit,
    info: () -> Unit = {
        close()
        showStationInfo(app, live)
    },
    find: (String) -> Unit = { query ->
        close()
        app.searchFor(query)
    },
) {
    val shown = live.shown
    MenuRow("Station info", info, OctoIcons.Info)
    val catalog = remember(stationId) { liveStationOf(stationId) }
    if (catalog != null) {
        val kept = app.isKept(catalog)
        MenuRow(if (kept) "Remove station" else "Keep station", {
            if (kept) app.dropLive(catalog) else app.keepLive(catalog)
            close()
        }, if (kept) OctoIcons.Close else OctoIcons.Pin)
    }
    if (app.liveRadio.admin == true && !onServer(app, shown.streamUrl)) {
        MenuRow("Add to your server", {
            app.addLiveToServer(catalog ?: LiveStation("", shown.station, shown.streamUrl))
            close()
        }, OctoIcons.Servers)
    }
    MenuSeparator()
    MenuRow("Find this song in Octo", { find(heartQuery(shown.onAir)) }, OctoIcons.Search, enabled = live.named)
    MenuRow("Copy song name", {
        app.copyWords(live.songName, "Copied ${live.songName}.")
        close()
    }, OctoIcons.Copy, enabled = live.named)
}

// The station's details in a small dialog that fits without scrolling:
// its name, how it streams, where it is, what it plays and its website.
fun showStationInfo(app: AppState, live: LiveNow) {
    app.popups.showCentred(width = 400.dp, scrim = true) { close -> StationInfoCard(app, live, close) }
}

@Composable
fun ColumnScope.StationInfoCard(app: AppState, live: LiveNow, close: () -> Unit) {
    val shown = live.shown
    val details = shown.details
    // A server station's website comes from the server's list.
    val website = details.homepage.ifBlank {
        app.liveRadio.serverStations.orEmpty().firstOrNull { streamKey(it.streamUrl) == streamKey(shown.streamUrl) }?.homePageUrl.orEmpty()
    }
    val place = listOf(details.state, details.country.ifBlank { details.countryCode.takeIf(String::isNotBlank)?.let(::countryName).orEmpty() })
        .filter(String::isNotBlank).distinct().joinToString(", ")
    MenuTitle(shown.station)
    PopupPadding {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Space.L)) {
            LiveArt(shown.station, shown.streamUrl, Modifier.size(72.dp), Corner.ArtMShape, logo = details.logo, coverArt = details.coverArt.ifBlank { null }, small = true)
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(Space.Xxs)) {
                Txt(shown.station, DesktopType.emphasis, OctoColors.TextPrimary, maxLines = 2)
                Txt(liveSubtitle(OnAir.Nothing, shown.station, details), DesktopType.meta, OctoColors.TextMuted, maxLines = 2)
            }
        }
        Spacer(Modifier.height(Space.Xs))
        InfoFact("Sound", liveCodecLine(details).ifEmpty { "Not given" })
        InfoFact("Bitrate", if (details.bitrate > 0) "${details.bitrate} kbps" else "Not given")
        InfoFact("Where", place.ifEmpty { "Not given" })
        if (details.tags.isNotEmpty()) InfoFact("Plays", details.tags.take(4).joinToString(", "))
        InfoFact("Stream", shown.streamUrl.toHttpUrlOrNull()?.host ?: shown.streamUrl)
        if (website.isNotBlank()) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Txt("Website", DesktopType.meta, OctoColors.TextMuted, Modifier.width(InfoLabelWidth))
                TextAction(website.removePrefix("https://").removePrefix("http://").trimEnd('/'), { app.openUrl(website) })
            }
        }
        Row(Modifier.fillMaxWidth().padding(top = Space.S), horizontalArrangement = Arrangement.End) {
            GlazeCapsule(null, "Close", close, lit = true, height = ControlHeight.L)
        }
    }
}

@Composable
private fun InfoFact(label: String, value: String) {
    Row(Modifier.fillMaxWidth().heightIn(min = 24.dp), verticalAlignment = Alignment.CenterVertically) {
        Txt(label, DesktopType.meta, OctoColors.TextMuted, Modifier.width(InfoLabelWidth))
        Txt(value, DesktopType.table, OctoColors.TextPrimary, Modifier.weight(1f), maxLines = 2)
    }
}

private val InfoLabelWidth = 72.dp
