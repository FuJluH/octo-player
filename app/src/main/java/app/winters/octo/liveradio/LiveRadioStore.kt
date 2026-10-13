package app.winters.octo.liveradio

import android.content.Context
import android.util.Log
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.MutablePreferences
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.serialization.json.Json
import java.io.IOException
import javax.inject.Inject
import javax.inject.Singleton

// The store's name. Its file (datastore/live_radio.preferences_pb) is left
// out of Android's own cloud backup and device transfer, by
// res/xml/data_extraction_rules.xml and res/xml/backup_rules.xml.
const val LIVE_RADIO_STORE = "live_radio"

private val Context.liveRadioPrefs by preferencesDataStore(LIVE_RADIO_STORE)

private val KEPT = stringPreferencesKey("kept")
private val PLACE = stringPreferencesKey("place")
private val RADIUS = intPreferencesKey("radius")
private val SORT = stringPreferencesKey("sort")

private val placeJson = Json { ignoreUnknownKeys = true }

// Where the page last looked, how far and in what order.
data class LiveSearch(
    val place: LivePlace? = null,
    val radiusIndex: Int = LIVE_RADIUS_DEFAULT_INDEX,
    val sort: LiveSort = LiveSort.Distance,
)

// What Live radio near you keeps on the phone: the stations kept, and the
// last place, radius and order. None of it goes to a server or to Android's
// cloud backup; Octo's own backups carry the kept stations only.
@Singleton
class LiveRadioStore internal constructor(private val store: DataStore<Preferences>) {
    @Inject constructor(@ApplicationContext context: Context) : this(context.liveRadioPrefs)

    val kept: Flow<KeptStations> = store.data.map { KeptStations.decoded(it[KEPT]) }.distinctUntilChanged()

    val search: Flow<LiveSearch> = store.data.map { prefs ->
        LiveSearch(
            place = prefs[PLACE]?.let { runCatching { placeJson.decodeFromString(LivePlace.serializer(), it) }.getOrNull() },
            radiusIndex = prefs[RADIUS] ?: LIVE_RADIUS_DEFAULT_INDEX,
            sort = prefs[SORT]?.let { name -> LiveSort.entries.firstOrNull { it.name == name } } ?: LiveSort.Distance,
        )
    }.distinctUntilChanged()

    suspend fun keep(station: LiveStation) = change { it[KEPT] = KeptStations.decoded(it[KEPT]).keep(station).encoded() }

    suspend fun drop(uuid: String) = change { it[KEPT] = KeptStations.decoded(it[KEPT]).drop(uuid).encoded() }

    // The backup's stations join the ones kept here.
    suspend fun restore(stations: List<LiveStation>) {
        if (stations.isEmpty()) return
        change { it[KEPT] = restoredKept(KeptStations.decoded(it[KEPT]), stations).encoded() }
    }

    suspend fun keptNow(): KeptStations = kept.first()

    suspend fun setPlace(place: LivePlace) = change { it[PLACE] = placeJson.encodeToString(LivePlace.serializer(), place) }

    suspend fun setRadius(index: Int) = change { it[RADIUS] = index }

    suspend fun setSort(sort: LiveSort) = change { it[SORT] = sort.name }

    // A choice that cannot be written is let be; the page still shows it.
    private suspend fun change(update: (MutablePreferences) -> Unit) {
        try {
            store.edit { update(it) }
        } catch (e: IOException) {
            Log.w("Octo", "live radio choice not saved", e)
        }
    }
}
