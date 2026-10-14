package app.winters.octo.playback

import android.content.Context
import android.graphics.Bitmap
import android.util.Size
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.core.net.toUri
import app.winters.octo.catalog.ArtworkRef
import app.winters.octo.covers.coverSide
import app.winters.octo.playlists.PlaylistArtEntry
import coil3.SingletonImageLoader
import coil3.executeBlocking
import coil3.request.ImageRequest
import coil3.request.SuccessResult
import coil3.request.allowHardware
import coil3.toBitmap
import dagger.hilt.android.EntryPointAccessors
import kotlinx.coroutines.runBlocking

// A catalog picture as a plain bitmap about `px` wide, for what draws
// outside the app's screens: the notification, a car's screen and the
// player's colours. Null when there is none. Blocks, so never call it on
// the main thread. A live station always has one: its song's artwork, its
// logo, or the cover drawn from its name.
fun artworkBitmap(context: Context, ref: String?, px: Int): Bitmap? {
    stationArtOf(ref)?.let { return stationBitmap(context, it, px) }
    return when (val art = ArtworkRef.decode(ref)) {
        is ArtworkRef.Device -> runCatching {
            context.contentResolver.loadThumbnail(art.uri.toUri(), Size(px, px), null)
        }.getOrNull()
        // Server covers go through the app's image loader, which signs the
        // address and keeps the download.
        is ArtworkRef.Server -> loaded(context, art, px)
        null -> null
    }
}

// The first of a station's pictures that can be had (see StationArt), at
// most `px` across, else its drawn cover.
private fun stationBitmap(context: Context, art: StationArt, px: Int): Bitmap? {
    for (picture in art.pictures) {
        val bitmap = if (isWebPicture(picture)) loaded(context, picture, px) else artworkBitmap(context, picture, px)
        if (bitmap != null) return bitmap
    }
    return runCatching {
        val covers = EntryPointAccessors.fromApplication(context.applicationContext, PlaylistArtEntry::class.java).playlistArt()
        runBlocking { covers.art(art.drawnSpec(), coverSide(px)) }.asAndroidBitmap()
    }.getOrNull()
}

private fun loaded(context: Context, data: Any, px: Int): Bitmap? {
    val request = ImageRequest.Builder(context).data(data).size(px).allowHardware(false).build()
    return (SingletonImageLoader.get(context).executeBlocking(request) as? SuccessResult)?.image?.toBitmap()
}
