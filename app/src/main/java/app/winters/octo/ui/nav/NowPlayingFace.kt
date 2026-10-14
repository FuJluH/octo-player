package app.winters.octo.ui.nav

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import app.winters.octo.design.OctoColors
import app.winters.octo.design.OctoIcons
import app.winters.octo.design.PauseGlyph
import app.winters.octo.playback.NowPlaying
import app.winters.octo.player.LiveStopIcon
import app.winters.octo.ui.common.Artwork
import app.winters.octo.ui.output.CastingMark

// The face of the round button at the end of the bar: the song's artwork
// behind a play or pause sign, with a thin ring showing how far through the
// song it is. The bar supplies the glaze around it.
@Composable
fun NowPlayingFace(now: NowPlaying, progress: () -> Float, size: Dp = BarHeight) {
    Box(Modifier.size(size), contentAlignment = Alignment.Center) {
        if (now.artwork != null) {
            Artwork(now.artwork, size - 12.dp, shape = CircleShape)
            // Darkens the picture so the sign on top stays readable.
            Box(Modifier.size(size - 12.dp).background(Color.Black.copy(alpha = 0.35f), CircleShape))
        }
        if (now.live != null) {
            // A station stops rather than pauses.
            Icon(
                painterResource(if (now.playWhenReady) LiveStopIcon else OctoIcons.Play),
                contentDescription = null,
                tint = OctoColors.TextPrimary,
                modifier = Modifier.size(22.dp),
            )
        } else if (now.isPlaying) {
            PauseGlyph(OctoColors.TextPrimary, size = 22.dp)
        } else {
            Icon(painterResource(OctoIcons.Play), contentDescription = null, tint = OctoColors.TextPrimary, modifier = Modifier.size(22.dp))
        }
        if (now.trackId != null) ProgressRing(progress, Modifier.matchParentSize().padding(3.dp))
        // Playing on a TV or speaker.
        if (now.casting) CastingMark(Modifier.align(Alignment.BottomEnd).padding(2.dp))
    }
}

// How far through the song it is, as an arc from the top. The value is read
// while drawing, so the arc can move every frame without recomposing.
@Composable
fun ProgressRing(progress: () -> Float, modifier: Modifier) {
    Canvas(modifier) {
        drawArc(
            color = OctoColors.Accent,
            startAngle = -90f,
            sweepAngle = 360f * progress(),
            useCenter = false,
            style = Stroke(width = 2.dp.toPx(), cap = StrokeCap.Round),
        )
    }
}
