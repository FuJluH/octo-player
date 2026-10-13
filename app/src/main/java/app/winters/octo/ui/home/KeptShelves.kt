package app.winters.octo.ui.home

import android.content.Context
import app.winters.octo.catalog.TrackEntity
import app.winters.octo.discovery.Station
import app.winters.octo.home.HomeShelfStore
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.serialization.Serializable
import java.io.File
import javax.inject.Inject
import javax.inject.Singleton

// Home's server shelves as a server last gave them: its stations, the
// lists it made for the listener and the first songs of its chart.
@Serializable
data class KeptShelves(
    val stations: List<Station> = emptyList(),
    val madeForYou: List<Station> = emptyList(),
    val charts: List<TrackEntity> = emptyList(),
)

// Where they are kept: one file per kept server, in the app's cache.
@Singleton
class KeptShelvesFiles @Inject constructor(@ApplicationContext context: Context) {
    val store = HomeShelfStore(File(context.cacheDir, "home"), KeptShelves.serializer())
}
