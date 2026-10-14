package app.winters.octo.ui.common

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.FilterQuality
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import app.winters.octo.catalog.ArtworkRef
import app.winters.octo.covers.backgroundColour
import app.winters.octo.covers.chooseBackground
import app.winters.octo.covers.coverArtKey
import app.winters.octo.covers.coverSide
import app.winters.octo.design.OctoColors
import app.winters.octo.design.OctoIcons
import app.winters.octo.design.artworkRim
import app.winters.octo.playback.StationArt
import app.winters.octo.playback.isWebPicture
import app.winters.octo.playlists.PlaylistArtEntry
import coil3.compose.AsyncImage
import coil3.compose.LocalPlatformContext
import coil3.request.ImageRequest
import coil3.request.crossfade
import dagger.hilt.android.EntryPointAccessors

private val RimFrom = 96.dp

// A live station's cover, in layers, so it never goes blank: the cover
// drawn from its name at the bottom, there at once; its logo over that once
// one loads (a logo that fails gives way to the next, and the last to the
// drawn cover); the artwork the station sends with the song over that; and
// on top the song's own cover as Octo has it. Each fades in over what is
// under it, and a new song's cover loads over what shows until it comes.
@Composable
fun StationCover(art: StationArt, size: Dp, modifier: Modifier = Modifier, shape: Shape) {
    val context = LocalPlatformContext.current
    val px = with(LocalDensity.current) { size.roundToPx() }
    Box(modifier.size(size).clip(shape)) {
        DrawnStationCover(art, px, size, Modifier.matchParentSize())
        var logoAt by remember(art.logos) { mutableIntStateOf(0) }
        var logoShown by remember(art.logos) { mutableStateOf(false) }
        val logos = remember(art.logos, px) { art.logos.mapNotNull { pictureRequest(context, it, px) } }
        val logo = logos.getOrNull(logoAt)
        if (logo != null) {
            // A logo is often not square, or see-through: it sits whole on a
            // plain tile, which fades in with it.
            val tile by animateFloatAsState(if (logoShown) 1f else 0f, tween(FADE_MS), label = "logo tile")
            if (tile > 0f) Box(Modifier.matchParentSize().graphicsLayer { alpha = tile }.background(OctoColors.BackgroundTertiary))
            AsyncImage(
                model = logo,
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
        // The station's artwork for the song, then Octo's cover for it on top.
        if (art.artwork.isNotBlank()) SongPicture(art.artwork, px, Modifier.matchParentSize())
        if (art.cover.isNotBlank()) SongPicture(art.cover, px, Modifier.matchParentSize())
        if (size >= RimFrom) Box(Modifier.matchParentSize().artworkRim(shape))
    }
}

// A song's picture that keeps the last one up, from memory, until the new
// one has loaded over it.
@Composable
private fun SongPicture(picture: String, px: Int, modifier: Modifier) {
    val context = LocalPlatformContext.current
    var settled by remember { mutableStateOf<String?>(null) }
    val previous = settled
    if (previous != null && previous != picture) {
        key(previous) {
            remember(previous, px) { pictureRequest(context, previous, px) }?.let {
                AsyncImage(model = it, contentDescription = null, contentScale = ContentScale.Crop, modifier = modifier)
            }
        }
    }
    key(picture) {
        remember(picture, px) { pictureRequest(context, picture, px) }?.let {
            AsyncImage(model = it, contentDescription = null, contentScale = ContentScale.Crop, modifier = modifier, onSuccess = { settled = picture })
        }
    }
}

private const val FADE_MS = 300

// The cover Octo draws for a station from its name, as playlists' are: its
// colour and a radio at once, worked out here with no wait, and the
// designed cover fading in over them once drawn (at once when it was drawn
// before).
@Composable
private fun DrawnStationCover(art: StationArt, px: Int, size: Dp, modifier: Modifier) {
    val context = LocalContext.current
    val covers = remember(context) { EntryPointAccessors.fromApplication(context.applicationContext, PlaylistArtEntry::class.java).playlistArt() }
    val spec = remember(art.key, art.name) { art.drawnSpec() }
    val ground = remember(spec) { Color(backgroundColour(chooseBackground(spec.id, spec.palette))) }
    val side = coverSide(px)
    val key = remember(spec, side) { coverArtKey(spec, side) }
    val ready = remember(key) { covers.known(key) }
    val picture by produceState(ready, key) {
        if (value == null) value = runCatching { covers.art(spec, side) }.getOrNull()
    }
    val shown by animateFloatAsState(if (picture != null) 1f else 0f, tween(if (ready != null) 0 else FADE_MS), label = "drawn cover")
    Box(modifier.background(ground), contentAlignment = Alignment.Center) {
        if (shown < 1f) {
            Icon(
                painterResource(OctoIcons.Radio),
                contentDescription = null,
                tint = Color.White.copy(alpha = 0.7f),
                modifier = Modifier.size(size * 0.4f).graphicsLayer { alpha = 1f - shown },
            )
        }
        picture?.let {
            Image(
                it,
                contentDescription = null,
                modifier = Modifier.matchParentSize().graphicsLayer { alpha = shown },
                contentScale = ContentScale.FillBounds,
                filterQuality = FilterQuality.High,
            )
        }
    }
}

// A picture of a station's to load, fading in: a web address asked for at
// the size drawn, or an artwork reference through the app's own loader.
private fun pictureRequest(context: coil3.PlatformContext, picture: String, px: Int): ImageRequest? = when {
    isWebPicture(picture) -> ImageRequest.Builder(context).data(picture).size(px, px).crossfade(FADE_MS).build()
    else -> ArtworkRef.decode(picture)?.let { ImageRequest.Builder(context).data(it).size(px, px).crossfade(FADE_MS).build() }
}
