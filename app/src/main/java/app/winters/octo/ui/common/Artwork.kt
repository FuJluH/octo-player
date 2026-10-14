package app.winters.octo.ui.common

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import app.winters.octo.catalog.ArtworkRef
import app.winters.octo.design.ArtworkShape
import app.winters.octo.design.OctoColors
import app.winters.octo.design.OctoShapes
import app.winters.octo.design.artworkRim
import app.winters.octo.playback.stationArtOf
import app.winters.octo.server.serverCoverKey
import coil3.PlatformContext
import coil3.compose.AsyncImage
import coil3.compose.LocalPlatformContext
import coil3.request.CachePolicy
import coil3.request.ImageRequest
import coil3.request.crossfade

// Covers smaller than this are drawn without the rim.
private val RimMinSize = 96.dp

// A picture from the catalog, whatever its source, on a quiet tile until
// it arrives. Music with no artwork, or whose cover cannot be had (the
// server has none, or no connection), keeps the tile: a failed picture
// draws nothing and is not asked for again until it is shown again.
// `outside` is for a song, album or artist not in the library: it gets a
// small mark in the corner, and says so to TalkBack. Large covers at the
// top of a page leave it off and say it in words instead.
//
// A smaller copy of the cover already in memory shows at once while the
// sharp one loads. With `keptFirst` (the player's card), a smaller copy
// kept on the disk shows too.
@Composable
fun Artwork(
    ref: String?,
    size: Dp,
    modifier: Modifier = Modifier,
    shape: Shape = ArtworkShape,
    outside: Boolean = false,
    keptFirst: Boolean = false,
) {
    // A live station draws its own layered cover.
    stationArtOf(ref)?.let {
        StationCover(it, size, modifier, shape)
        return
    }
    val description = artworkDescription(null, outside)
    Box(
        modifier
            .size(size)
            .clip(shape)
            .background(OctoColors.BackgroundTertiary)
            .then(if (description != null) Modifier.semantics { contentDescription = description } else Modifier),
    ) {
        val model = remember(ref) { ArtworkRef.decode(ref) }
        if (model != null) {
            val context = LocalPlatformContext.current
            val request = remember(model) { artworkRequest(context, model) }
            var sharp by remember(model) { mutableStateOf(false) }
            if (keptFirst && !sharp && model is ArtworkRef.Server) {
                val kept = remember(model) { keptArtworkRequest(context, model) }
                AsyncImage(
                    model = kept,
                    contentDescription = null,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier.matchParentSize(),
                )
            }
            AsyncImage(
                model = request,
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.matchParentSize(),
                onSuccess = { sharp = true },
            )
        }
        // The rim sits on top of the picture, so it is drawn last. Small
        // covers go without: on a thumbnail it reads as a frame cutting in.
        if (size >= RimMinSize) Box(Modifier.matchParentSize().artworkRim(shape))
        if (outside) NotInLibraryMark(size, round = shape == CircleShape)
    }
}

// Artwork that fills the width it is given, square, with the rounder
// corners a card's picture takes.
@Composable
fun ArtworkFill(ref: String?, modifier: Modifier = Modifier, outside: Boolean = false) {
    BoxWithConstraints(modifier.fillMaxWidth().aspectRatio(1f)) {
        Artwork(ref, maxWidth, shape = OctoShapes.ArtM, outside = outside)
    }
}

// A catalog picture to draw, showing whatever copy of a server cover is in
// memory (a smaller one, say) until the one at its size comes.
fun artworkRequest(context: PlatformContext, art: ArtworkRef): ImageRequest =
    ImageRequest.Builder(context)
        .data(art)
        .apply { if (art is ArtworkRef.Server) placeholderMemoryCacheKey(serverCoverKey(art)) }
        .build()

// A server cover from what is kept on the phone only, at any size, for the
// moment before the sharp one comes. It never goes to the server, and
// keeps nothing new.
private fun keptArtworkRequest(context: PlatformContext, art: ArtworkRef.Server): ImageRequest =
    ImageRequest.Builder(context)
        .data(art)
        .networkCachePolicy(CachePolicy.DISABLED)
        .memoryCachePolicy(CachePolicy.READ_ONLY)
        .diskCachePolicy(CachePolicy.READ_ONLY)
        .crossfade(false)
        .build()
