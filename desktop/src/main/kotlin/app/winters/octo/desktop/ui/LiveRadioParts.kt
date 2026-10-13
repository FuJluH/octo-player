package app.winters.octo.desktop.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.FilterQuality
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.layout.ContentScale
import app.winters.octo.design.Glyph
import app.winters.octo.design.MenuRow
import app.winters.octo.design.MenuSeparator
import app.winters.octo.design.MenuTitle
import app.winters.octo.design.OctoColors
import app.winters.octo.design.OctoIcons
import app.winters.octo.design.artworkRim
import app.winters.octo.desktop.AppState
import app.winters.octo.desktop.addLiveToServer
import app.winters.octo.desktop.dropLive
import app.winters.octo.desktop.keepLive
import app.winters.octo.desktop.library.Cover
import app.winters.octo.desktop.library.CoverOrder
import app.winters.octo.desktop.liveradio.LIVE_RADIO
import app.winters.octo.desktop.liveradio.LiveAction
import app.winters.octo.desktop.liveradio.liveActionLabel
import app.winters.octo.desktop.liveradio.liveActions
import app.winters.octo.desktop.liveradio.streamKey
import app.winters.octo.desktop.playLive
import app.winters.octo.liveradio.LiveStation
import coil3.compose.AsyncImage
import coil3.compose.AsyncImagePainter
import kotlin.math.abs

// Whether a logo address is one the app fetches: a web address.
fun isLogoAddress(url: String): Boolean = url.startsWith("https://", ignoreCase = true) || url.startsWith("http://", ignoreCase = true)

// A station's own color for its drawn logo, from its name, so the same
// station always looks the same.
fun stationHue(name: String): Float = (abs(name.lowercase().hashCode()) % 360).toFloat()

// A station's logo, small, for a row: the catalog's picture when it has one
// that loads, else the server's picture, else a drawn one, a radio in the
// station's own color.
@Composable
fun StationLogo(logo: String, name: String, modifier: Modifier, shape: Shape, coverArt: String? = null) {
    var failed by remember(logo) { mutableStateOf(false) }
    val hue = remember(name) { stationHue(name) }
    BoxWithConstraints(modifier.clip(shape).background(drawnGround(hue)), contentAlignment = Alignment.Center) {
        Glyph(OctoIcons.Radio, size = maxWidth * 0.5f, tint = Color.White.copy(alpha = 0.85f))
        when {
            isLogoAddress(logo) && !failed -> AsyncImage(
                model = logo,
                contentDescription = null,
                contentScale = ContentScale.Fit,
                modifier = Modifier.fillMaxSize().background(OctoColors.BackgroundTertiary),
                filterQuality = FilterQuality.Medium,
                onState = { if (it is AsyncImagePainter.State.Error) failed = true },
            )
            coverArt != null -> Cover(coverArt, Modifier.fillMaxSize(), shape = shape, placeholder = OctoIcons.Radio)
        }
        Box(Modifier.matchParentSize().artworkRim(shape))
    }
}

// A station's picture on a card: its logo on a dark tile, or, without one
// that loads, a designed cover with its name, as playlists have.
@Composable
fun StationArt(app: AppState, logo: String, name: String, streamUrl: String, modifier: Modifier, shape: Shape, coverArt: String? = null) {
    var failed by remember(logo) { mutableStateOf(false) }
    if (!isLogoAddress(logo) || failed) {
        if (coverArt != null) {
            Cover(coverArt, modifier, shape = shape, placeholder = OctoIcons.Radio)
        } else {
            DesignedCover(app, CoverOrder("live:${streamKey(streamUrl)}", name, LIVE_RADIO, null, emptyList()), modifier, shape)
        }
        return
    }
    Box(modifier.clip(shape).background(OctoColors.BackgroundTertiary), contentAlignment = Alignment.Center) {
        AsyncImage(
            model = logo,
            contentDescription = null,
            contentScale = ContentScale.Fit,
            modifier = Modifier.fillMaxSize(0.62f),
            filterQuality = FilterQuality.High,
            onState = { if (it is AsyncImagePainter.State.Error) failed = true },
        )
        Box(Modifier.matchParentSize().artworkRim(shape))
    }
}

// The tile a drawn logo sits on: the station's color, darker toward the foot.
private fun drawnGround(hue: Float): Brush = Brush.verticalGradient(
    listOf(Color.hsv(hue, 0.42f, 0.46f), Color.hsv(hue, 0.5f, 0.28f)),
)

// The picture of the Find stations near you card: a radio on the accent.
@Composable
fun FindStationsArt(modifier: Modifier, shape: Shape) {
    BoxWithConstraints(
        modifier.clip(shape).background(Brush.linearGradient(listOf(OctoColors.AccentSelected, OctoColors.BackgroundTertiary))),
        contentAlignment = Alignment.Center,
    ) {
        Glyph(OctoIcons.Radio, size = maxWidth * 0.36f, tint = OctoColors.TextPrimary)
        Box(Modifier.matchParentSize().artworkRim(shape))
    }
}

// A live station's menu: play it, keep it here or remove it, and for an
// admin, add it to the server when the server does not have it.
@Composable
fun ColumnScope.LiveStationMenu(app: AppState, station: LiveStation, kept: Boolean, close: () -> Unit) {
    MenuTitle(station.name)
    val onServer = app.liveRadio.onServer(station.streamUrl) || app.home?.shelves?.live.orEmpty().any { streamKey(it.streamUrl) == streamKey(station.streamUrl) }
    val actions = liveActions(kept = kept, admin = app.liveRadio.admin == true, onServer = onServer)
    actions.forEach { action ->
        if (action == LiveAction.AddToServer) MenuSeparator()
        val icon = when (action) {
            LiveAction.Play -> OctoIcons.Play
            LiveAction.Keep -> OctoIcons.Pin
            LiveAction.Remove -> OctoIcons.Close
            LiveAction.AddToServer -> OctoIcons.Servers
        }
        MenuRow(liveActionLabel(action), {
            when (action) {
                LiveAction.Play -> app.playLive(station)
                LiveAction.Keep -> app.keepLive(station)
                LiveAction.Remove -> app.dropLive(station)
                LiveAction.AddToServer -> app.addLiveToServer(station)
            }
            close()
        }, icon, destructive = action == LiveAction.Remove)
    }
}

// Opens a live station's menu where the pointer is, for a right click.
@Composable
fun liveStationMenu(app: AppState, station: LiveStation, kept: Boolean): () -> Unit {
    val pointer = LocalPointer.current
    return { app.popups.showAt(pointer.point) { close -> LiveStationMenu(app, station, kept, close) } }
}
