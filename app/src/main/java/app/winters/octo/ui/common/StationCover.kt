package app.winters.octo.ui.common

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.FilterQuality
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import app.winters.octo.catalog.ArtworkRef
import app.winters.octo.covers.coverArtKey
import app.winters.octo.covers.coverSide
import app.winters.octo.design.OctoColors
import app.winters.octo.design.artworkRim
import app.winters.octo.playback.StationArt
import app.winters.octo.playback.isWebPicture
import app.winters.octo.playlists.PlaylistArtEntry
import coil3.compose.AsyncImage
import coil3.compose.LocalPlatformContext
import coil3.request.ImageRequest
import dagger.hilt.android.EntryPointAccessors

private val RimFrom = 96.dp

// A live station's cover, in layers: the cover drawn from its name at the
// bottom, its logo over that once one loads (a logo that fails gives way
// to the next, and the last to the drawn cover), and the song's artwork on
// top while the station names a song with one. A new song's artwork loads
// over the logo, so the cover never goes blank between songs.
@Composable
fun StationCover(art: StationArt, size: Dp, modifier: Modifier = Modifier, shape: Shape) {
    val context = LocalPlatformContext.current
    val px = with(LocalDensity.current) { size.roundToPx() }
    Box(modifier.size(size).clip(shape).background(OctoColors.BackgroundTertiary)) {
        DrawnStationCover(art, px, Modifier.matchParentSize())
        var logoAt by remember(art.logos) { mutableIntStateOf(0) }
        var logoShown by remember(art.logos) { mutableStateOf(false) }
        val logos = remember(art.logos, px) { art.logos.mapNotNull { pictureRequest(context, it, px) } }
        val request = logos.getOrNull(logoAt)
        if (request != null) {
            // A logo is often not square, or see-through: it sits whole on a
            // plain tile.
            if (logoShown) Box(Modifier.matchParentSize().background(OctoColors.BackgroundTertiary))
            AsyncImage(
                model = request,
                contentDescription = null,
                contentScale = ContentScale.Fit,
                modifier = Modifier.matchParentSize().padding(size * 0.08f),
                onSuccess = { logoShown = true },
                onError = {
                    logoShown = false
                    logoAt++
                },
            )
        }
        if (art.artwork.isNotBlank()) {
            val request = remember(art.artwork, px) { pictureRequest(context, art.artwork, px) }
            if (request != null) {
                AsyncImage(model = request, contentDescription = null, contentScale = ContentScale.Crop, modifier = Modifier.matchParentSize())
            }
        }
        if (size >= RimFrom) Box(Modifier.matchParentSize().artworkRim(shape))
    }
}

// The cover Octo draws for a station from its name, as playlists' are.
@Composable
private fun DrawnStationCover(art: StationArt, px: Int, modifier: Modifier) {
    val context = LocalContext.current
    val covers = remember(context) { EntryPointAccessors.fromApplication(context.applicationContext, PlaylistArtEntry::class.java).playlistArt() }
    val spec = remember(art.key, art.name) { art.drawnSpec() }
    val side = coverSide(px)
    val key = remember(spec, side) { coverArtKey(spec, side) }
    val picture by produceState<ImageBitmap?>(covers.known(key), key) {
        if (value == null) value = runCatching { covers.art(spec, side) }.getOrNull()
    }
    picture?.let {
        Image(it, contentDescription = null, modifier = modifier, contentScale = ContentScale.FillBounds, filterQuality = FilterQuality.High)
    }
}

// A picture of a station's to load: a web address asked for at the size
// drawn, or an artwork reference through the app's own loader.
private fun pictureRequest(context: coil3.PlatformContext, picture: String, px: Int): ImageRequest? = when {
    isWebPicture(picture) -> ImageRequest.Builder(context).data(picture).size(px, px).build()
    else -> ArtworkRef.decode(picture)?.let { artworkRequest(context, it) }
}
