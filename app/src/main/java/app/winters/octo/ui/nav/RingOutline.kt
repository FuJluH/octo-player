package app.winters.octo.ui.nav

import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Path
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.min
import kotlin.math.sin

// The outline of a rounded rectangle `width` by `height` with corners of
// `radius`, walked clockwise from the middle of its top edge, for a
// progress ring round a rounded-square artwork. A radius of half the side
// walks a circle.
class RingOutline(val width: Float, val height: Float, radius: Float) {
    val radius: Float = radius.coerceIn(0f, min(width, height) / 2f)

    // A straight run or a quarter turn round a corner, in walking order.
    sealed interface Piece {
        val length: Float
    }

    data class Straight(val from: Offset, val to: Offset) : Piece {
        override val length: Float get() = (to - from).getDistance()
    }

    // A turn round `center`, from `startDegrees` (0 pointing right, growing
    // clockwise on screen) through `sweepDegrees`.
    data class Turn(val center: Offset, val radius: Float, val startDegrees: Float, val sweepDegrees: Float) : Piece {
        override val length: Float get() = (radius * sweepDegrees / 180f * PI).toFloat()
    }

    val pieces: List<Piece> = run {
        val r = this.radius
        val w = width
        val h = height
        val mid = w / 2f
        listOf(
            Straight(Offset(mid, 0f), Offset(w - r, 0f)),
            Turn(Offset(w - r, r), r, -90f, 90f),
            Straight(Offset(w, r), Offset(w, h - r)),
            Turn(Offset(w - r, h - r), r, 0f, 90f),
            Straight(Offset(w - r, h), Offset(r, h)),
            Turn(Offset(r, h - r), r, 90f, 90f),
            Straight(Offset(0f, h - r), Offset(0f, r)),
            Turn(Offset(r, r), r, 180f, 90f),
            Straight(Offset(r, 0f), Offset(mid, 0f)),
        ).filter { it.length > 0f }
    }

    val length: Float = pieces.sumOf { it.length.toDouble() }.toFloat()

    // Where the walk is after `fraction` of the way round, 0 to 1.
    fun pointAt(fraction: Float): Offset {
        var left = fraction.coerceIn(0f, 1f) * length
        for (piece in pieces) {
            if (left <= piece.length) return piece.at(left)
            left -= piece.length
        }
        return Offset(width / 2f, 0f)
    }

    // The walk's first `fraction`, as a path from the top's middle, offset
    // by `origin`.
    fun pathTo(fraction: Float, origin: Offset = Offset.Zero, into: Path = Path()): Path {
        into.reset()
        var left = fraction.coerceIn(0f, 1f) * length
        into.moveTo(origin.x + width / 2f, origin.y)
        for (piece in pieces) {
            if (left <= 0f) break
            val share = min(left, piece.length)
            when (piece) {
                is Straight -> {
                    val end = piece.at(share) + origin
                    into.lineTo(end.x, end.y)
                }
                is Turn -> {
                    val c = piece.center + origin
                    val sweep = piece.sweepDegrees * share / piece.length
                    into.arcTo(Rect(c.x - piece.radius, c.y - piece.radius, c.x + piece.radius, c.y + piece.radius), piece.startDegrees, sweep, false)
                }
            }
            left -= share
        }
        return into
    }
}

private fun RingOutline.Piece.at(distance: Float): Offset = when (this) {
    is RingOutline.Straight -> if (length <= 0f) from else from + (to - from) * (distance / length)
    is RingOutline.Turn -> {
        val angle = Math.toRadians((startDegrees + sweepDegrees * (distance / length)).toDouble())
        Offset(center.x + radius * cos(angle).toFloat(), center.y + radius * sin(angle).toFloat())
    }
}
