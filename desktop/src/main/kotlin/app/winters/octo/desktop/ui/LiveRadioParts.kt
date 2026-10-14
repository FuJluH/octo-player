package app.winters.octo.desktop.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.fillMaxSize
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
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.foundation.Image
import androidx.compose.runtime.produceState
import app.winters.octo.covers.CoverPalette
import app.winters.octo.covers.CoverSpec
import app.winters.octo.covers.coverArtKey
import app.winters.octo.covers.coverPaletteKey
import app.winters.octo.covers.coverSide
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
import app.winters.octo.desktop.library.LocalCovers
import app.winters.octo.covers.coverBucket
import app.winters.octo.desktop.library.coverFetchPx
import app.winters.octo.desktop.library.coverRequest
import app.winters.octo.desktop.liveradio.LiveAction
import app.winters.octo.desktop.liveradio.liveActionLabel
import app.winters.octo.desktop.liveradio.liveActions
import app.winters.octo.desktop.liveradio.liveCoverOrder
import app.winters.octo.desktop.liveradio.streamKey
import app.winters.octo.desktop.playLive
import app.winters.octo.liveradio.LiveStation
import coil3.PlatformContext
import coil3.compose.AsyncImage
import coil3.compose.AsyncImagePainter
import coil3.compose.LocalPlatformContext
import coil3.request.ImageRequest
import coil3.request.crossfade
import app.winters.octo.design.LocalReduceMotion
import kotlin.math.abs

// Whether a logo address is one the app fetches: a web address.
fun isLogoAddress(url: String): Boolean = url.startsWith("https://", ignoreCase = true) || url.startsWith("http://", ignoreCase = true)

// A station's own color for its drawn logo, from its name, so the same
// station always looks the same.
fun stationHue(name: String): Float = (abs(name.lowercase().hashCode()) % 360).toFloat()

// A station's logo, small, for a row: the catalog's picture when it has one
// that loads, else the server's picture, else a drawn one, a radio in the
// station's own color, which also shows while a picture loads.
@Composable
fun StationLogo(logo: String, name: String, modifier: Modifier, shape: Shape, coverArt: String? = null) {
    LiveArt(name, "", modifier, shape, logo = logo, coverArt = coverArt, small = true)
}

// A station's picture on a card: its logo on a dark tile, or, without one
// that loads, a designed cover with its name, as playlists have.
@Composable
fun StationArt(app: AppState, logo: String, name: String, streamUrl: String, modifier: Modifier, shape: Shape, coverArt: String? = null) {
    LiveArt(name, streamUrl, modifier, shape, logo = logo, coverArt = coverArt, app = app)
}

// A station's picture from the best there is: the song on air as Octo
// has it (its cover from the server), the artwork the station sends with
// it, the station's logo (on a dark tile), its picture on the server. Each
// shows only once it has loaded, over the station's drawn cover, which is
// drawn here at once (no wait on the network) and stays when none loads,
// so a station never shows an empty or black square: a radio in the
// station's own color, and on a large picture (given the app) the designed
// cover with its name over it once drawn.
@Composable
fun LiveArt(
    name: String,
    streamUrl: String,
    modifier: Modifier,
    shape: Shape,
    artwork: String = "",
    logo: String = "",
    coverArt: String? = null,
    small: Boolean = false,
    app: AppState? = null,
    // The cover of the song in Octo, and whether it is one found online.
    songCover: String? = null,
    songOnline: Boolean = false,
) {
    var songShown by remember(songCover) { mutableStateOf(false) }
    var artShown by remember(artwork) { mutableStateOf(false) }
    var logoShown by remember(logo) { mutableStateOf(false) }
    var serverShown by remember(coverArt) { mutableStateOf(false) }
    BoxWithConstraints(modifier.clip(shape), contentAlignment = Alignment.Center) {
        val px = with(LocalDensity.current) { maxOf(maxWidth, maxHeight).roundToPx() }
        val glyph = maxWidth * 0.5f
        val covered = songShown || artShown
        if (!covered && !logoShown && !serverShown) {
            val hue = remember(name) { stationHue(name) }
            Box(Modifier.matchParentSize().background(drawnGround(hue)), contentAlignment = Alignment.Center) {
                Glyph(OctoIcons.Radio, size = glyph, tint = Color.White.copy(alpha = 0.85f))
            }
            if (!small && app != null) DesignedStation(app, name, streamUrl, px)
        }
        val client = LocalCovers.current
        val context = LocalPlatformContext.current
        // Each picture fades in over the one under it, unless motion is reduced.
        val still = LocalReduceMotion.current
        if (coverArt != null && client != null && !covered && !logoShown) {
            val request = remember(coverArt, px, client, still) { coverRequest(context, client, coverArt, coverBucket(coverFetchPx(px))).crossfade(!still).build() }
            AsyncImage(
                model = request,
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.matchParentSize(),
                filterQuality = FilterQuality.Medium,
                onState = { serverShown = it is AsyncImagePainter.State.Success },
            )
        }
        if (isLogoAddress(logo) && !covered) {
            Box(Modifier.matchParentSize().then(if (logoShown) Modifier.background(OctoColors.BackgroundTertiary) else Modifier), contentAlignment = Alignment.Center) {
                AsyncImage(
                    model = webRequest(context, logo, px),
                    contentDescription = null,
                    contentScale = ContentScale.Fit,
                    modifier = if (small) Modifier.fillMaxSize() else Modifier.fillMaxSize(0.62f),
                    filterQuality = FilterQuality.High,
                    onState = { logoShown = it is AsyncImagePainter.State.Success },
                )
            }
        }
        if (isLogoAddress(artwork) && !songShown) {
            AsyncImage(
                model = webRequest(context, artwork, px),
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.matchParentSize(),
                filterQuality = FilterQuality.Medium,
                onState = { artShown = it is AsyncImagePainter.State.Success },
            )
        }
        if (songCover != null && client != null) {
            val request = remember(songCover, px, client, songOnline, still) { coverRequest(context, client, songCover, coverBucket(coverFetchPx(px)), songOnline).crossfade(!still).build() }
            AsyncImage(
                model = request,
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.matchParentSize(),
                filterQuality = FilterQuality.Medium,
                onState = { songShown = it is AsyncImagePainter.State.Success },
            )
        }
        Box(Modifier.matchParentSize().artworkRim(shape))
    }
}

// The station's designed cover, with its name, as the shelf's cards have
// it: drawn off the window's thread and shown once drawn (at once when
// drawn before), over the drawn tile under it, with no ground of its own.
@Composable
private fun DesignedStation(app: AppState, name: String, streamUrl: String, px: Int) {
    val client = LocalCovers.current
    val store = app.playlistArt
    val side = coverSide(px)
    val order = remember(name, streamUrl) { liveCoverOrder(name, streamUrl) }
    val paletteKey = coverPaletteKey(client?.primaryUrl?.host.orEmpty(), order.sources + listOfNotNull(order.stamp))
    fun specOf(palette: CoverPalette) = CoverSpec(order.id, order.name, order.line, order.footer, palette, order.coverTitle, order.glyph)
    val ready = remember(paletteKey, side) { store.knownPalette(paletteKey)?.let { store.known(coverArtKey(specOf(it), side)) } }
    val picture by produceState(ready, paletteKey, side) {
        if (value == null) value = store.art(specOf(store.palette(client, order, paletteKey)), side)
    }
    picture?.let { Image(it, contentDescription = null, modifier = Modifier.fillMaxSize(), contentScale = ContentScale.FillBounds, filterQuality = FilterQuality.High) }
}

// A picture from the web, decoded no bigger than it is drawn.
@Composable
private fun webRequest(context: PlatformContext, url: String, px: Int): ImageRequest {
    val still = LocalReduceMotion.current
    return remember(url, px, still) { ImageRequest.Builder(context).data(url).size(coverFetchPx(px).coerceAtLeast(1)).crossfade(!still).build() }
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

// A live station's menu: play it (with the list it is in, by `play`), keep
// it here or remove it, and for an admin, add it to the server when the
// server does not have it.
@Composable
fun ColumnScope.LiveStationMenu(app: AppState, station: LiveStation, kept: Boolean, close: () -> Unit, play: () -> Unit = { app.playLive(station) }) {
    MenuTitle(station.name)
    val actions = liveActions(kept = kept, admin = app.liveRadio.admin == true, onServer = onServer(app, station.streamUrl))
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
                LiveAction.Play -> play()
                LiveAction.Keep -> app.keepLive(station)
                LiveAction.Remove -> app.dropLive(station)
                LiveAction.AddToServer -> app.addLiveToServer(station)
            }
            close()
        }, icon, destructive = action == LiveAction.Remove)
    }
}

// Whether the server in use already has a stream, by its list of stations
// or Home's Live radio shelf.
fun onServer(app: AppState, streamUrl: String): Boolean =
    app.liveRadio.onServer(streamUrl) || app.home?.shelves?.live.orEmpty().any { streamKey(it.streamUrl) == streamKey(streamUrl) }

// Opens a live station's menu where the pointer is, for a right click.
@Composable
fun liveStationMenu(app: AppState, station: LiveStation, kept: Boolean, play: () -> Unit = { app.playLive(station) }): () -> Unit {
    val pointer = LocalPointer.current
    return { app.popups.showAt(pointer.point) { close -> LiveStationMenu(app, station, kept, close, play) } }
}
