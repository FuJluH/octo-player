package app.winters.octo.ui.admin

import android.content.Intent
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.core.net.toUri
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import app.winters.octo.admin.AdminStation
import app.winters.octo.admin.AdminStatus
import app.winters.octo.admin.DownloadRecord
import app.winters.octo.admin.Health
import app.winters.octo.admin.LibraryStatus
import app.winters.octo.admin.RadioState
import app.winters.octo.design.AccentButton
import app.winters.octo.design.GlazeButton
import app.winters.octo.design.OctoColors
import app.winters.octo.design.OctoIcons
import app.winters.octo.design.OctoType
import app.winters.octo.ui.common.BackButton
import app.winters.octo.ui.common.DetailTopGap
import app.winters.octo.ui.common.LoadState
import app.winters.octo.ui.common.ScreenTitle
import app.winters.octo.ui.common.SectionTitle
import app.winters.octo.ui.common.screenPadding
import app.winters.octo.ui.common.songs
import coil3.compose.AsyncImage
import java.time.Instant

// How many downloads show before "Show all".
private const val RecentDownloads = 30

// Status dots: calm, never lit.
private val DotOk = Color(0xFF8FBFA0)
private val DotWarning = Color(0xFFE3B35B)
private val DotNotSetUp: Color get() = OctoColors.Accent.copy(alpha = 0.3f)

// What Octo is doing: its services, stations, recent downloads and where
// they land. Only reachable on the home network.
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun OctoAdminScreen(onBack: () -> Unit, vm: OctoAdminViewModel = hiltViewModel()) {
    val context = LocalContext.current
    var showAll by rememberSaveable { mutableStateOf(false) }

    Box(Modifier.fillMaxSize()) {
        PullToRefreshBox(
            isRefreshing = vm.refreshing,
            onRefresh = vm::refresh,
            modifier = Modifier.fillMaxSize(),
        ) {
            LazyColumn(Modifier.fillMaxSize(), contentPadding = screenPadding(extraTop = DetailTopGap)) {
                item(key = "title") { ScreenTitle("Octo admin") }
                when (vm.place) {
                    AdminPlace.Looking -> item(key = "looking") { Spinner(Modifier.padding(top = 24.dp)) }
                    AdminPlace.Away -> item(key = "away") { AwayMessage(vm::tryAgain) }
                    is AdminPlace.Found -> {
                        health(vm.status)
                        stations(vm.radio, vm.refreshingStations, vm.stationsProblem, vm::refreshStations)
                        downloads(vm.downloads, showAll) { showAll = !showAll }
                        library(vm.library)
                        item(key = "open") {
                            OpenRow("Open full admin", Modifier.padding(top = 18.dp)) {
                                val url = vm.pageUrl() ?: return@OpenRow
                                runCatching { context.startActivity(Intent(Intent.ACTION_VIEW, url.toUri())) }
                            }
                        }
                    }
                }
            }
        }
        BackButton(onBack)
    }
}

private fun LazyListScope.health(state: LoadState<AdminStatus>) {
    item(key = "title:health") { SectionTitle("Health", Modifier.padding(top = 8.dp)) }
    section(state, "health") { status ->
        item(key = "service:octo") { HealthRow("Octo", status.octo) }
        items(status.services.entries.toList(), key = { "service:${it.key}" }) { (key, health) ->
            HealthRow(serviceName(key), health)
        }
    }
}

private fun LazyListScope.stations(
    state: LoadState<RadioState>,
    refreshing: Boolean,
    problem: String?,
    onRefresh: () -> Unit,
) {
    item(key = "title:stations") { SectionTitle("Stations", Modifier.padding(top = 18.dp)) }
    section(state, "stations") { radio ->
        if (!radio.enabled) {
            item(key = "stations:off") { Note("Stations are switched off in Octo") }
            return@section
        }
        radio.learning?.let { learning ->
            item(key = "stations:learning") {
                Column(Modifier.padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(learningLine(learning), style = OctoType.bodySmall, color = OctoColors.TextPrimary)
                    val last = ago(learning.lastRefreshSuccessUtc, Instant.now())
                    Text(
                        last?.let { "Last refreshed $it" } ?: "Not refreshed yet",
                        style = OctoType.caption,
                        color = OctoColors.TextMuted,
                    )
                    refreshProblem(learning.lastRefreshError)?.let {
                        Text(it, style = OctoType.caption, color = OctoColors.Error, maxLines = 2, overflow = TextOverflow.Ellipsis)
                    }
                }
            }
        }
        if (radio.stations.isEmpty()) item(key = "stations:none") { Note("No stations yet") }
        itemsIndexed(radio.stations, key = { index, _ -> "station:$index" }) { _, station -> StationRow(station) }
        item(key = "stations:refresh") {
            val busy = refreshing || radio.learning?.refreshing == true
            Column(Modifier.padding(start = 20.dp, end = 20.dp, top = 8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                GlazeButton(if (busy) "Refreshing" else "Refresh stations", onClick = onRefresh, enabled = !busy)
                problem?.let { Text(it, style = OctoType.caption, color = OctoColors.Error) }
            }
        }
    }
}

private fun LazyListScope.downloads(state: LoadState<List<DownloadRecord>>, showAll: Boolean, onToggle: () -> Unit) {
    item(key = "title:downloads") { SectionTitle("Downloads", Modifier.padding(top = 18.dp)) }
    section(state, "downloads") { list ->
        if (list.isEmpty()) {
            item(key = "downloads:none") { Note("Nothing downloaded yet") }
            return@section
        }
        val now = Instant.now()
        val shown = if (showAll) list else list.take(RecentDownloads)
        // Octo can list the same song twice, so rows are keyed by place.
        itemsIndexed(shown, key = { index, _ -> "download:$index" }) { _, record -> DownloadRow(record, now) }
        if (list.size > RecentDownloads) {
            item(key = "downloads:toggle") {
                GlazeButton(
                    if (showAll) "Show fewer" else "Show all",
                    onClick = onToggle,
                    modifier = Modifier.padding(start = 20.dp, top = 8.dp),
                )
            }
        }
    }
}

private fun LazyListScope.library(state: LoadState<LibraryStatus>) {
    item(key = "title:library") { SectionTitle("Library", Modifier.padding(top = 18.dp)) }
    section(state, "library") { status ->
        item(key = "library:status") {
            Column(Modifier.padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                if (status.effectiveDownloadPath.isNotBlank()) {
                    Text(
                        status.effectiveDownloadPath,
                        style = OctoType.caption.copy(fontFamily = FontFamily.Monospace),
                        color = OctoColors.TextMuted,
                    )
                }
                val problems = libraryProblems(status)
                if (problems.isEmpty()) {
                    Text("Downloads go straight into your library", style = OctoType.bodySmall, color = OctoColors.TextSecondary)
                }
                problems.forEach { Text(it, style = OctoType.bodySmall, color = OctoColors.Error) }
            }
        }
    }
}

// A section's rows once they arrive, a small spinner before, or a quiet
// line if they could not be read.
private fun <T> LazyListScope.section(state: LoadState<T>, name: String, content: LazyListScope.(T) -> Unit) {
    when (state) {
        LoadState.Loading -> item(key = "$name:loading") { Spinner(Modifier.padding(vertical = 8.dp)) }
        is LoadState.Failed -> item(key = "$name:failed") { Note(state.message) }
        is LoadState.Ready -> content(state.data)
    }
}

@Composable
private fun Spinner(modifier: Modifier = Modifier) {
    Box(modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
        CircularProgressIndicator(color = OctoColors.Accent, strokeWidth = 2.dp, modifier = Modifier.size(22.dp))
    }
}

@Composable
private fun Note(text: String) {
    Text(text, style = OctoType.bodySmall, color = OctoColors.TextMuted, modifier = Modifier.padding(horizontal = 20.dp))
}

// Shown away from home, where Octo's admin does not answer.
@Composable
private fun AwayMessage(onRetry: () -> Unit) {
    Column(
        Modifier.fillMaxWidth().padding(horizontal = 32.dp, vertical = 48.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Text(
            "Octo's admin is only available on your home network",
            style = OctoType.bodySmall,
            color = OctoColors.TextSecondary,
            textAlign = TextAlign.Center,
        )
        AccentButton("Try again", onClick = onRetry)
    }
}

// A service line: a small dot for how it is, the name, and what Octo says.
@Composable
private fun HealthRow(name: String, health: Health) {
    val dot = healthDot(health)
    val (color, said) = when (dot) {
        HealthDot.Ok -> DotOk to "Working"
        HealthDot.Warning -> DotWarning to "Needs a look"
        HealthDot.Down -> OctoColors.Error to "Not working"
        HealthDot.NotSetUp -> DotNotSetUp to "Not set up"
    }
    Row(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = 20.dp, vertical = 8.dp)
            .semantics(mergeDescendants = true) {},
        horizontalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Box(
            Modifier
                .padding(top = 6.dp)
                .size(8.dp)
                .background(color, CircleShape)
                .semantics { contentDescription = said },
        )
        Column(Modifier.weight(1f)) {
            Text(
                name,
                style = OctoType.bodySmall,
                color = if (dot == HealthDot.NotSetUp) OctoColors.TextMuted else OctoColors.TextPrimary,
            )
            val detail = if (dot == HealthDot.NotSetUp) "Not set up" else health.detail
            if (detail.isNotBlank()) {
                Text(detail, style = OctoType.caption, color = OctoColors.TextMuted, maxLines = 3, overflow = TextOverflow.Ellipsis)
            }
        }
    }
}

@Composable
private fun StationRow(station: AdminStation) {
    Column(
        Modifier
            .fillMaxWidth()
            .height(52.dp)
            .padding(horizontal = 20.dp),
        verticalArrangement = Arrangement.Center,
    ) {
        Text(station.name, style = OctoType.bodySmall, color = OctoColors.TextPrimary, maxLines = 1, overflow = TextOverflow.Ellipsis)
        Text(songs(station.trackCount), style = OctoType.caption, color = OctoColors.TextMuted)
    }
}

// A finished download: its cover, title, who it is by, and when it landed.
@Composable
private fun DownloadRow(record: DownloadRecord, now: Instant) {
    Row(
        Modifier
            .fillMaxWidth()
            .height(56.dp)
            .padding(horizontal = 20.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        val shape = RoundedCornerShape(6.dp)
        Box(Modifier.size(44.dp).clip(shape).background(OctoColors.BackgroundTertiary)) {
            if (record.coverArtUrl != null) {
                AsyncImage(
                    model = record.coverArtUrl,
                    contentDescription = null,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier.matchParentSize(),
                )
            }
        }
        Column(Modifier.weight(1f)) {
            Text(record.title, style = OctoType.bodySmall, color = OctoColors.TextPrimary, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(downloadLine(record), style = OctoType.caption, color = OctoColors.TextMuted, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        ago(record.downloadedAt, now)?.let { Text(it, style = OctoType.caption, color = OctoColors.TextMuted) }
    }
}

// A line that leads somewhere else.
@Composable
private fun OpenRow(label: String, modifier: Modifier = Modifier, onClick: () -> Unit) {
    Row(
        modifier
            .fillMaxWidth()
            .clickable(role = Role.Button, onClick = onClick)
            .height(52.dp)
            .padding(horizontal = 20.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(label, style = OctoType.body, color = OctoColors.TextPrimary, modifier = Modifier.weight(1f))
        Icon(painterResource(OctoIcons.Chevron), contentDescription = null, tint = OctoColors.TextMuted, modifier = Modifier.size(22.dp))
    }
}
