package app.winters.octo.offline

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import androidx.compose.runtime.Immutable
import app.winters.octo.catalog.TrackEntity
import app.winters.octo.playback.cacheKeyWithoutSize
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.stateIn
import javax.inject.Inject
import javax.inject.Singleton

// What song rows show about copies kept on the phone: which songs are
// downloaded, and, with no connection, which server songs cannot play.
@Immutable
data class OfflineMarks(
    val downloaded: Set<String> = emptySet(),
    val offline: Boolean = false,
    // Server songs saved whole, as "<server>|<song id there>".
    val saved: Set<String> = emptySet(),
) {
    fun isDownloaded(track: TrackEntity): Boolean = track.id in downloaded

    // A song that cannot play right now: no connection, and neither on the
    // phone, downloaded nor saved from an earlier play.
    fun isOutOfReach(track: TrackEntity): Boolean =
        offline && !track.onPhone && track.id !in downloaded && savedSong(track.sourceId, track.nativeId) !in saved
}

fun savedSong(sourceId: String, serverId: String) = "$sourceId|$serverId"

// The song a saved key is for: the key less its type, request and file size.
fun savedSongOf(key: String): String = cacheKeyWithoutSize(key).substringBeforeLast('|').substringBeforeLast('|')

@OptIn(ExperimentalCoroutinesApi::class)
@Singleton
class OfflineMarksSource @Inject constructor(
    @ApplicationContext context: Context,
    downloads: OfflineDownloads,
    cache: StreamCache,
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    // Whether the phone has a connection, as it changes.
    private val online: Flow<Boolean> = callbackFlow {
        val connectivity = context.getSystemService(ConnectivityManager::class.java)
        fun now() = connectivity.activeNetwork?.let(connectivity::getNetworkCapabilities)
            ?.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) == true
        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                trySend(true)
            }

            override fun onLost(network: Network) {
                trySend(now())
            }

            override fun onCapabilitiesChanged(network: Network, caps: NetworkCapabilities) {
                trySend(caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET))
            }
        }
        trySend(now())
        connectivity.registerDefaultNetworkCallback(callback)
        awaitClose { connectivity.unregisterNetworkCallback(callback) }
    }.distinctUntilChanged()

    // The saved songs are only looked through once the connection is gone.
    private val saved: Flow<Pair<Boolean, Set<String>>> = online.flatMapLatest { up ->
        if (up) {
            flowOf(false to emptySet())
        } else {
            flow { emit(true to cache.fullySavedKeys().mapTo(HashSet(), ::savedSongOf)) }.flowOn(Dispatchers.IO)
        }
    }

    val marks: StateFlow<OfflineMarks> = combine(downloads.done, saved) { done, (offline, keys) ->
        OfflineMarks(done, offline, keys)
    }.stateIn(scope, SharingStarted.WhileSubscribed(5_000), OfflineMarks())
}
