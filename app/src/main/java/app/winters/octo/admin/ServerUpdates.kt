package app.winters.octo.admin

import android.content.Context
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import app.winters.octo.data.SessionRepository
import app.winters.octo.data.SessionState
import app.winters.octo.data.runsOcto
import app.winters.octo.serverupdate.LaterStore
import app.winters.octo.serverupdate.ServerUpdateHttp
import app.winters.octo.serverupdate.ServerUpdateWatcher
import app.winters.octo.serverupdate.UpdateTrack
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import okhttp3.OkHttpClient
import javax.inject.Inject
import javax.inject.Singleton

private val Context.serverUpdateData by preferencesDataStore("octo_server_update")

// Whether the Octo server in use has a newer release, and updating it from
// the app. Only a Navidrome admin is told; for anyone else, and on any
// other server, nothing shows.
@Singleton
class ServerUpdates @Inject constructor(
    @ApplicationContext private val context: Context,
    private val sessions: SessionRepository,
    private val admin: OctoAdmin,
    http: OkHttpClient,
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    private val later = object : LaterStore {
        override suspend fun dismissed(server: String): String? = context.serverUpdateData.data.first()[laterKey(server)]

        override suspend fun dismiss(server: String, tag: String) {
            context.serverUpdateData.edit { it[laterKey(server)] = tag }
        }
    }

    private val watcher = ServerUpdateWatcher(scope, later, onFinished = { sessions.refreshServerFacts() })

    // While an update is under way the address found last is asked again,
    // as the server restarting answers nowhere.
    private val calls = ServerUpdateHttp(http) { admin.updatePlace(reuse = watcher.track.value.watch != null) }

    val track: StateFlow<UpdateTrack> = watcher.track

    // Follows whichever Octo server is in use.
    fun start() {
        scope.launch {
            sessions.state.collect { state ->
                val session = (state as? SessionState.SignedIn)?.session?.takeIf { it.runsOcto }
                watcher.bind(session?.id, calls)
            }
        }
    }

    fun refresh() = watcher.refresh()

    fun updateNow() = watcher.updateNow()

    fun later() = watcher.later()

    fun closeOutcome() = watcher.closeOutcome()

    // Octo's dashboard, for updating there: where the admin pages answered,
    // else the server's own address.
    suspend fun dashboard(): String? {
        val base = admin.updatePlace(reuse = true)?.base
            ?: (sessions.state.value as? SessionState.SignedIn)?.session?.client?.primaryUrl
            ?: return null
        return admin.pageUrl(base).toString()
    }

    private fun laterKey(server: String) = stringPreferencesKey("later@$server")
}
