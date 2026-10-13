package app.winters.octo.ui.home

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.winters.octo.design.OctoColors
import app.winters.octo.design.OctoIcons
import app.winters.octo.design.OctoType
import app.winters.octo.discovery.Station
import app.winters.octo.ui.common.ArtworkFill
import app.winters.octo.ui.common.GlassIconButton

// Stations change once a day, so a list older than this is asked for again
// when Home comes back.
internal const val STATIONS_STALE_MS = 10 * 60 * 1000L

// The words for a station the server no longer has: Octo makes its
// stations anew now and then, and an old one is taken off Home.
internal fun stationGoneLine(name: String): String = "$name isn't on the server any more"

// The line under a Made for you list's name.
internal fun songCountLine(count: Int): String = if (count == 1) "1 song" else "$count songs"

// Whether Home should ask for the stations again: never while a load is
// running, always after one failed, otherwise once the list is stale.
internal fun stationsDue(now: Long, loadedAt: Long?, failed: Boolean, loading: Boolean): Boolean = when {
    loading -> false
    failed || loadedAt == null -> true
    else -> now - loadedAt >= STATIONS_STALE_MS
}

// What a tap on a station card does: a station with a stream plays it, as it
// has no songs to show; any other opens its songs.
internal fun opensOnTap(station: Station): Boolean = station.streamUrl == null

// A station as its cover with its name under it, sized like an album card,
// and a Made for you list's song count under that. A tap opens its songs; the
// play button on the cover plays them at once. A station with a stream has
// no list, so a tap plays it and it has no button. It dims while its songs
// are on the way.
@Composable
fun StationCard(station: Station, starting: Boolean, onOpen: () -> Unit, onPlay: () -> Unit) {
    val fade by animateFloatAsState(if (starting) 0.5f else 1f, label = "station")
    val opens = opensOnTap(station)
    Column(
        Modifier
            .width(150.dp)
            .alpha(fade)
            .clickable(onClick = if (opens) onOpen else onPlay),
    ) {
        Box {
            ArtworkFill(station.artwork)
            if (opens) {
                GlassIconButton(
                    OctoIcons.Play,
                    "Play ${station.name}",
                    onClick = onPlay,
                    modifier = Modifier.align(Alignment.BottomEnd),
                )
            }
        }
        Spacer(Modifier.height(8.dp))
        Text(
            station.name,
            style = OctoType.bodySmall.copy(fontWeight = FontWeight.SemiBold),
            color = OctoColors.TextPrimary,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
        station.songCount?.let {
            Text(
                songCountLine(it),
                style = OctoType.bodySmall,
                color = OctoColors.TextSecondary,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
    }
}
