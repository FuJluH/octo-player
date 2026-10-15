package app.winters.octo.player.immersive

import android.graphics.ColorMatrix
import android.graphics.ColorMatrixColorFilter
import android.graphics.Paint
import android.os.Build
import androidx.annotation.RequiresApi
import androidx.compose.runtime.IntState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.layout.LayoutCoordinates
import app.winters.octo.design.GlassBackdrop
import app.winters.octo.design.OctoColors

// The player's glasses' view of the moving background, while it is drawn
// from its pictures: each glass draws the part of the picture behind it,
// over the frost's own backing colour and deepened as the frost deepens,
// instead of blurring the background again on every frame. The wash is far
// softer than a glass's frost, so blurring it again changed nothing to see.
// The glass redraws when a new picture is shown.
class WashGlass : GlassBackdrop {
    private var shownRenderer: WashRenderer? = null
    private var washArea: LayoutCoordinates? = null
    private var pictures: IntState = mutableIntStateOf(0)
    private var zoom: () -> Float = { 1f }
    private var fade: () -> Float = { 1f }

    // How much of the background shows over the player's base, as its
    // layer draws it.
    var show: () -> Float = { 1f }

    private var hasPicture by mutableStateOf(false)
    override val ready: Boolean get() = hasPicture

    private val deepened = Paint()
    private var deepenedBy = Float.NaN

    // The wash's renderer, once it draws from pictures, and what the glass
    // draws it with: where the wash is laid out, its pictures' count (read
    // so a new one redraws the glass), its zoom and its fade-in.
    internal fun follow(renderer: WashRenderer?, pictures: IntState, zoom: () -> Float, fade: () -> Float) {
        shownRenderer = renderer
        this.pictures = pictures
        this.zoom = zoom
        this.fade = fade
    }

    internal fun placed(area: LayoutCoordinates) {
        washArea = area
    }

    internal fun pictureShown(shown: Boolean) {
        if (hasPicture != shown) hasPicture = shown
    }

    @RequiresApi(Build.VERSION_CODES.TIRAMISU)
    override fun DrawScope.drawBehind(glass: LayoutCoordinates, saturation: Float) {
        pictures.intValue
        val renderer = shownRenderer ?: return
        val area = washArea?.takeIf { it.isAttached } ?: return
        val at = area.localPositionOf(glass, Offset.Zero)
        if (deepenedBy != saturation) {
            deepened.colorFilter = ColorMatrixColorFilter(ColorMatrix().apply { setSaturation(saturation) })
            deepenedBy = saturation
        }
        drawIntoCanvas { canvas ->
            val c = canvas.nativeCanvas
            c.saveLayer(0f, 0f, size.width, size.height, deepened)
            c.drawColor(OctoColors.Background.toArgb())
            c.translate(-at.x, -at.y)
            renderer.drawPicture(c, area.size.width, area.size.height, zoom(), fade() * show())
            c.restore()
        }
    }
}
