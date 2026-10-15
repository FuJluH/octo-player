package app.winters.octo.player

import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Icon
import androidx.compose.material3.LocalContentColor
import androidx.compose.runtime.Composable
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.rememberVectorPainter
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.dp
import app.winters.octo.design.GlowIcon
import app.winters.octo.design.IconAccentState
import app.winters.octo.design.OctoIcons

// How strongly they show: the player's colours' `quiet`.
val LocalTitleIconAlpha = compositionLocalOf { TitleIconAlpha }

// The icons beside the song's name, as the player's title row sized them.
@Composable
internal fun titleIcons(): TitleIcons = LocalTitleIcons.current ?: TitleIcons(17.dp)

// The heart: outlined in the quiet ink, or filled and lit once the song is
// in Liked songs.
@Composable
internal fun TitleHeart(filled: Boolean, accent: IconAccentState? = null) {
    val icons = titleIcons()
    val ink = LocalContentColor.current
    GlowIcon(
        if (filled) painterResource(OctoIcons.Liked) else rememberVectorPainter(icons.heart),
        tint = if (filled) ink else ink.copy(alpha = LocalTitleIconAlpha.current),
        lit = filled,
        modifier = Modifier.offset(y = -icons.heartLift).size(icons.size),
        accent = accent,
    )
}

// The plus a song not in the library shows where the heart would be.
@Composable
internal fun TitlePlus() {
    val icons = titleIcons()
    GlowIcon(
        rememberVectorPainter(icons.plus),
        tint = LocalContentColor.current.copy(alpha = LocalTitleIconAlpha.current),
        lit = false,
        modifier = Modifier.size(icons.size),
    )
}

// More's three dots.
@Composable
internal fun TitleMoreIcon() {
    val icons = titleIcons()
    Icon(
        rememberVectorPainter(icons.dots),
        contentDescription = null,
        tint = LocalContentColor.current.copy(alpha = LocalTitleIconAlpha.current),
        modifier = Modifier.size(icons.size),
    )
}
