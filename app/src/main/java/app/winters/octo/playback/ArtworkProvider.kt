package app.winters.octo.playback

import android.content.ContentProvider
import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.graphics.Bitmap
import android.net.Uri
import android.os.ParcelFileDescriptor
import app.winters.octo.BuildConfig
import java.io.File
import java.io.FileNotFoundException
import java.security.MessageDigest

// Serves cover pictures to other apps that are allowed to see them, like a
// car's screen, which cannot read the app's own artwork references. Each
// cover is made once as a small JPEG and kept in the cache. Nothing is
// readable without a grant for its address (see `grantArtwork`).
class ArtworkProvider : ContentProvider() {
    override fun onCreate() = true

    override fun getType(uri: Uri) = "image/jpeg"

    override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor {
        val ctx = context ?: throw FileNotFoundException("Not ready")
        val ref = uri.lastPathSegment ?: throw FileNotFoundException("No artwork")
        val file = cached(ctx, ref) ?: throw FileNotFoundException("No artwork")
        return ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
    }

    private fun cached(ctx: Context, ref: String): File? {
        val dir = File(ctx.cacheDir, "car-art-$ART_SIZE").apply { mkdirs() }
        val file = File(dir, sha1(ref) + ".jpg")
        if (file.exists()) return file
        val loaded = artworkBitmap(ctx, ref, ART_SIZE) ?: return null
        // The size asked for is only a hint, so bring it down to size here.
        val bitmap = shrink(loaded)
        // Written aside first, so a half-written file is never served.
        val part = File(dir, file.name + ".part")
        part.outputStream().use { bitmap.compress(Bitmap.CompressFormat.JPEG, 88, it) }
        part.renameTo(file)
        return file
    }

    private fun shrink(bitmap: Bitmap): Bitmap {
        val longest = maxOf(bitmap.width, bitmap.height)
        if (longest <= ART_SIZE) return bitmap
        val scale = ART_SIZE.toFloat() / longest
        return Bitmap.createScaledBitmap(bitmap, (bitmap.width * scale).toInt(), (bitmap.height * scale).toInt(), true)
    }

    override fun query(uri: Uri, projection: Array<out String>?, selection: String?, selectionArgs: Array<out String>?, sortOrder: String?): Cursor? = null
    override fun insert(uri: Uri, values: ContentValues?): Uri? = null
    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?) = 0
    override fun update(uri: Uri, values: ContentValues?, selection: String?, selectionArgs: Array<out String>?) = 0

    companion object {
        const val AUTHORITY = BuildConfig.APPLICATION_ID + ".art"
        private const val ART_SIZE = 512

        // The address of a cover for other apps. The size is part of it, so a
        // car that keeps pictures by address asks again when the size changes.
        fun uriFor(ref: String): Uri =
            Uri.Builder().scheme("content").authority(AUTHORITY).appendPath(ART_SIZE.toString()).appendPath(ref).build()

        private fun sha1(text: String): String =
            MessageDigest.getInstance("SHA-1").digest(text.toByteArray()).joinToString("") { "%02x".format(it) }
    }
}
