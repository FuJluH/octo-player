package app.winters.octo.desktop.pages

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Modifier
import app.winters.octo.design.ChipRow
import app.winters.octo.design.GlazeCapsule
import app.winters.octo.design.OctoColors
import app.winters.octo.design.OctoIcons
import app.winters.octo.design.OctoType
import app.winters.octo.design.Space
import app.winters.octo.design.Txt
import app.winters.octo.design.scrollbar
import app.winters.octo.desktop.AppState
import app.winters.octo.desktop.home.HomeStore
import app.winters.octo.desktop.nav.Page
import app.winters.octo.desktop.nav.Visit
import app.winters.octo.desktop.search.Charts
import app.winters.octo.desktop.ui.LoadingLine
import app.winters.octo.desktop.ui.LocalBottomRoom
import app.winters.octo.desktop.ui.PageTitle
import app.winters.octo.desktop.ui.SectionTitle
import app.winters.octo.desktop.ui.pagePadding
import app.winters.octo.desktop.ui.rememberListState
import app.winters.octo.discovery.CHARTS_ROW
import app.winters.octo.discovery.rankedBy
import app.winters.octo.subsonic.CHART_OVERALL
import app.winters.octo.subsonic.TopSongs
import java.util.Locale

// The charts and new songs an Octo server reads from Apple Music: the
// chart country's most played songs, Best New Songs, Trending Songs and a
// chart per genre, one at a time, picked with the chips. Each song plays
// from the library when the library has it and is added with its "+"
// otherwise, as on the search page.
@Composable
fun ChartsPage(app: AppState, visit: Visit) {
    val charts = app.search?.charts ?: return
    LaunchedEffect(charts) { charts.loadChoices() }
    LaunchedEffect(charts, charts.selected) { charts.load(charts.selected) }
    val list = rememberListState(app.navigator, visit)
    val choices = charts.choices?.chart.orEmpty()
    val top = charts.lists[charts.selected]
    LazyColumn(Modifier.scrollbar(list, LocalBottomRoom.current), state = list, contentPadding = pagePadding(LocalBottomRoom.current)) {
        item(key = "title") { PageTitle("Charts", detail = top?.let(::caption)) }
        if (choices.isNotEmpty()) {
            item(key = "chips") {
                ChipRow(
                    choices.map { it.id },
                    charts.selected,
                    label = { id -> choices.firstOrNull { it.id == id }?.label ?: id },
                    onSelect = { charts.selected = it },
                    modifier = Modifier.padding(top = Space.M, bottom = Space.M),
                )
            }
        }
        when {
            charts.offered == false -> item(key = "none") { NothingHere("No charts here", "This server doesn't have charts.") }
            top == null -> item(key = "loading") { LoadingLine() }
            top.entry.none { it.song != null } -> item(key = "empty") {
                NothingHere("Nothing in this chart right now", "Apple Music has no songs for it at the moment. Try another.")
            }
            else -> chartSongs(app, top, shown = null)
        }
    }
}

// Who ranked the chart and for which country: "Most played on Apple Music
// in United States".
private fun caption(top: TopSongs): String? {
    val by = rankedBy(top.source, top.chart) ?: return null
    val country = top.country?.takeIf { it.length == 2 }?.let { Locale("", it.uppercase()).displayCountry }
    return if (country.isNullOrBlank()) by else "$by in $country"
}

// A chart's songs with Play all above them; `shown` keeps only the first
// few (Home's row).
private fun LazyListScope.chartSongs(app: AppState, top: TopSongs, shown: Int?) {
    val entries = top.entry.filter { it.song != null }.let { if (shown != null) it.take(shown) else it }
    val songs = entries.map { it.song!! }
    if (shown == null) {
        item(key = "play") {
            GlazeCapsule(OctoIcons.Play, "Play all", { app.play(songs, 0) }, Modifier.padding(bottom = Space.M))
        }
    }
    itemsIndexed(entries, key = { i, e -> "chart:${top.chart}:$i:${e.song!!.id}" }) { index, entry ->
        Box(Modifier.animateItem()) { RankedSong(app, songs, index, entry, withArtist = true) }
    }
}

// Home's Charts row: the most played songs right now, the first ten, with
// "See all" opening the Charts page. Only from a server that has charts.
// The row shows the chart as the server last gave it (HomeStore) until the
// server answers again; a server without charts empties it.
internal fun LazyListScope.chartsRow(app: AppState, charts: Charts, home: HomeStore) {
    moving(key = "charts-ask") {
        LaunchedEffect(charts, home) {
            charts.check()
            charts.load(CHART_OVERALL)
            snapshotFlow { charts.offered to charts.lists[CHART_OVERALL] }.collect { (offered, top) ->
                when {
                    offered == false -> home.chartAnswered(null)
                    top != null -> home.chartAnswered(top)
                }
            }
        }
    }
    val top = home.shelves.chart ?: return
    if (top.entry.none { it.song != null }) return
    moving(key = "charts-title") {
        Column(verticalArrangement = Arrangement.spacedBy(Space.Xs)) {
            SectionTitle(top.name ?: "Popular right now", action = "See all") {
                charts.selected = CHART_OVERALL
                app.navigator.go(Page.Charts)
            }
            caption(top)?.let { Txt(it, OctoType.caption, OctoColors.TextMuted, Modifier.padding(bottom = Space.S)) }
        }
    }
    chartSongs(app, top, shown = CHARTS_ROW)
}
