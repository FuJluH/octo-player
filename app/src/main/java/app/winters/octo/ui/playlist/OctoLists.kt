package app.winters.octo.ui.playlist

import android.content.Context
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Text
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.navigation3.runtime.NavKey
import app.winters.octo.design.OctoColors
import app.winters.octo.design.OctoType
import app.winters.octo.discovery.Station
import app.winters.octo.discovery.isRadio
import app.winters.octo.home.HomeShelfStore
import app.winters.octo.lists.OctoListGroup
import app.winters.octo.ui.common.Artwork
import app.winters.octo.ui.common.ListRowSide
import app.winters.octo.ui.common.SectionTitle
import app.winters.octo.ui.common.songs
import app.winters.octo.ui.nav.ServerListRoute
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.serialization.Serializable
import java.io.File
import javax.inject.Inject
import javax.inject.Singleton

// Octo's lists for the listener as a server last gave them, by group
// (OctoListGroup's name), so the Playlists page shows them at once.
@Serializable
data class KeptOctoLists(val groups: Map<String, List<Station>> = emptyMap()) {
    fun read(): List<Pair<OctoListGroup, List<Station>>> =
        OctoListGroup.entries.mapNotNull { group -> groups[group.name]?.takeIf { it.isNotEmpty() }?.let { group to it } }

    companion object {
        fun of(lists: List<Pair<OctoListGroup, List<Station>>>) = KeptOctoLists(lists.associate { (group, items) -> group.name to items })
    }
}

// Where they are kept: one file per kept server, in the app's cache.
@Singleton
class KeptOctoListsFiles @Inject constructor(@ApplicationContext context: Context) {
    val store = HomeShelfStore(File(context.cacheDir, "octo-lists"), KeptOctoLists.serializer())
}

// "From Octo": the lists an Octo server made for the listener, under a
// heading for each kind. A list opens its songs; a station keeps going
// once played. None of them is copied to the phone, as nobody can edit them.
fun LazyListScope.octoListRows(lists: List<Pair<OctoListGroup, List<Station>>>, onOpen: (NavKey) -> Unit) {
    if (lists.isEmpty()) return
    item(key = "octo:title") { SectionTitle("From Octo", Modifier.padding(top = 24.dp)) }
    lists.forEach { (group, items) ->
        item(key = "octo:group:${group.name}") {
            Text(
                group.title,
                style = OctoType.label,
                color = OctoColors.TextSecondary,
                modifier = Modifier.padding(start = ListRowSide, end = ListRowSide, top = 16.dp, bottom = 4.dp),
            )
        }
        items(items, key = { "octo:${group.name}:${it.id}" }) { list ->
            PlaylistLine(
                list.name,
                list.songCount?.let(::songs),
                onClick = { onOpen(ServerListRoute(list.id, list.name, list.artwork, radio = group == OctoListGroup.Stations && list.isRadio)) },
            ) {
                Artwork(list.artwork, 56.dp)
            }
        }
    }
}
