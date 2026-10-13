package app.winters.octo.ui.liveradio

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import app.winters.octo.design.OctoColors
import app.winters.octo.design.OctoIcons
import app.winters.octo.design.OctoShapes
import app.winters.octo.design.OctoType
import app.winters.octo.design.glassPanel
import app.winters.octo.liveradio.LiveStation
import app.winters.octo.liveradio.detailLine
import app.winters.octo.liveradio.streamLine
import coil3.compose.AsyncImage
import coil3.compose.LocalPlatformContext
import coil3.request.ImageRequest

// The words for the way into Live radio near you.
const val LIVE_NEAR_TITLE = "Live radio near you"
const val FIND_NEAR_TITLE = "Find stations near you"

// A station's logo from its favicon, asked for at the size it is drawn,
// over a drawn radio until it comes. One that never comes keeps the radio.
@Composable
fun StationLogo(favicon: String, size: Dp, modifier: Modifier = Modifier, shape: RoundedCornerShape = OctoShapes.ArtM) {
    var shown by remember(favicon) { mutableStateOf(false) }
    Box(
        modifier.size(size).clip(shape).background(OctoColors.BackgroundTertiary),
        contentAlignment = Alignment.Center,
    ) {
        if (!shown) {
            Icon(painterResource(OctoIcons.Radio), contentDescription = null, tint = OctoColors.TextSecondary, modifier = Modifier.size(size * 0.45f))
        }
        if (favicon.isNotBlank()) {
            val context = LocalPlatformContext.current
            val px = with(LocalDensity.current) { size.roundToPx() }
            val request = remember(favicon, px) { ImageRequest.Builder(context).data(favicon).size(px, px).build() }
            AsyncImage(
                model = request,
                contentDescription = null,
                contentScale = ContentScale.Fit,
                modifier = Modifier.fillMaxSize(),
                onSuccess = { shown = true },
                onError = { shown = false },
            )
        }
    }
}

// One station in a list: its logo, name, where it is with its tags, and
// its stream's kind and size. A tap plays it; the dots open its menu.
@Composable
fun LiveStationRow(station: LiveStation, miles: Boolean, onPlay: () -> Unit, onMenu: () -> Unit, modifier: Modifier = Modifier) {
    Row(
        modifier
            .fillMaxWidth()
            .clickable(role = Role.Button, onClickLabel = "Play", onClick = onPlay)
            .heightIn(min = 68.dp)
            .padding(start = 20.dp, end = 8.dp, top = 6.dp, bottom = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        StationLogo(station.favicon, 48.dp)
        Column(Modifier.weight(1f)) {
            Text(station.name, style = OctoType.bodySmall, color = OctoColors.TextPrimary, maxLines = 1, overflow = TextOverflow.Ellipsis)
            detailLine(station, miles).takeIf { it.isNotEmpty() }?.let {
                Text(it, style = OctoType.caption, color = OctoColors.TextSecondary, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
            streamLine(station).takeIf { it.isNotEmpty() }?.let {
                Text(it, style = OctoType.caption, color = OctoColors.TextMuted, maxLines = 1)
            }
        }
        IconButton(onClick = onMenu) {
            Icon(painterResource(OctoIcons.More), contentDescription = "More for ${station.name}", tint = OctoColors.TextMuted, modifier = Modifier.size(20.dp))
        }
    }
}

// The way into Live radio near you as a row, for Search and the server's
// radio stations.
@Composable
fun FindNearRow(onClick: () -> Unit, modifier: Modifier = Modifier) {
    Row(
        modifier
            .fillMaxWidth()
            .clickable(role = Role.Button, onClick = onClick)
            .heightIn(min = 64.dp)
            .padding(horizontal = 20.dp, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Box(Modifier.size(48.dp).glassPanel(OctoShapes.ArtM), contentAlignment = Alignment.Center) {
            Icon(painterResource(OctoIcons.Radio), contentDescription = null, tint = OctoColors.TextPrimary, modifier = Modifier.size(24.dp))
        }
        Column(Modifier.weight(1f)) {
            Text(LIVE_NEAR_TITLE, style = OctoType.bodySmall, color = OctoColors.TextPrimary)
            Text("Stations on the air around you", style = OctoType.caption, color = OctoColors.TextMuted)
        }
        Icon(painterResource(OctoIcons.Chevron), contentDescription = null, tint = OctoColors.TextMuted, modifier = Modifier.size(20.dp))
    }
}

private val CardWidth = 150.dp

// The first card on the Live radio shelf, sized like a station's: it opens
// Live radio near you.
@Composable
fun FindNearCard(onClick: () -> Unit) {
    Column(Modifier.width(CardWidth).clickable(role = Role.Button, onClick = onClick)) {
        Box(
            Modifier.fillMaxWidth().aspectRatio(1f).glassPanel(OctoShapes.ArtM),
            contentAlignment = Alignment.Center,
        ) {
            Icon(painterResource(OctoIcons.Radio), contentDescription = null, tint = OctoColors.TextPrimary, modifier = Modifier.size(44.dp))
        }
        Spacer(Modifier.height(8.dp))
        Text(
            FIND_NEAR_TITLE,
            style = OctoType.bodySmall.copy(fontWeight = FontWeight.SemiBold),
            color = OctoColors.TextPrimary,
            maxLines = 2,
        )
    }
}

// A station kept on this phone, on the Live radio shelf: its logo on a
// card, its name and where it is under it. A tap plays it; a long press
// asks to remove it.
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun KeptStationCard(station: LiveStation, onPlay: () -> Unit, onLongPress: () -> Unit, modifier: Modifier = Modifier) {
    val haptics = LocalHapticFeedback.current
    Column(
        modifier
            .width(CardWidth)
            .combinedClickable(
                role = Role.Button,
                onClick = onPlay,
                onLongClickLabel = "More options",
                onLongClick = {
                    haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                    onLongPress()
                },
            ),
    ) {
        BoxWithConstraints(Modifier.fillMaxWidth().aspectRatio(1f).clip(OctoShapes.ArtM).background(OctoColors.BackgroundTertiary), contentAlignment = Alignment.Center) {
            StationLogo(station.favicon, maxWidth * 0.6f, shape = RoundedCornerShape(12.dp))
        }
        Spacer(Modifier.height(8.dp))
        Text(
            station.name,
            style = OctoType.bodySmall.copy(fontWeight = FontWeight.SemiBold),
            color = OctoColors.TextPrimary,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
        val area = station.state.ifBlank { station.country }
        if (area.isNotBlank()) {
            Text(area, style = OctoType.bodySmall, color = OctoColors.TextSecondary, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
    }
}

// One radius as a chip: the darker accent pill with a check while chosen, a
// faint fill with quieter words while not.
@Composable
fun RadiusChip(text: String, chosen: Boolean, onClick: () -> Unit) {
    Row(
        Modifier
            .heightIn(min = 36.dp)
            .clip(CircleShape)
            .background(if (chosen) OctoColors.AccentSelected else OctoColors.TextPrimary.copy(alpha = 0.07f))
            .clickable(role = Role.RadioButton, onClick = onClick)
            .semantics { selected = chosen }
            .padding(horizontal = 14.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        if (chosen) Icon(painterResource(OctoIcons.Check), contentDescription = null, tint = Color.White, modifier = Modifier.size(16.dp))
        Text(text, style = OctoType.label, color = if (chosen) OctoColors.TextPrimary else OctoColors.TextSecondary, maxLines = 1)
    }
}
