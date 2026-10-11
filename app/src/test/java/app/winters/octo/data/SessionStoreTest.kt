package app.winters.octo.data

import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.emptyPreferences
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.core.stringSetPreferencesKey
import app.winters.octo.livelists.accountKey
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File

// The kept servers: a phone signed in by an older version keeps its one
// server, now a list of one, still in use; the list is written with the
// next change, and the one in use stays where older versions look.
class SessionStoreTest {
    @get:Rule val folder = TemporaryFolder()

    // The store's values in memory: the file-backed store cannot replace
    // its file on a Windows JVM, which the phone never is.
    private class MemoryPrefs(start: Preferences = emptyPreferences()) : DataStore<Preferences> {
        private val state = MutableStateFlow(start)
        private val lock = Mutex()
        override val data: Flow<Preferences> = state

        override suspend fun updateData(transform: suspend (Preferences) -> Preferences): Preferences =
            lock.withLock { transform(state.value).also { state.value = it } }
    }

    private val url = "https://music.example.com/"
    private val connection = """{"homeUrl":"http://192.168.1.20:4533/","authMode":"Token","headersSealed":"c2VhbGVk","pins":{"music.example.com":"ab:cd"}}"""

    // Writes a session file exactly as the last one-server version did, and
    // gives back what a fresh store reads from that file.
    private fun oldFile(): Preferences = runBlocking {
        val file = File(folder.root, "session.preferences_pb")
        val writerJob = SupervisorJob()
        val writer = CoroutineScope(writerJob + Dispatchers.IO)
        PreferenceDataStoreFactory.create(scope = writer) { file }.edit { p ->
            p[stringPreferencesKey("server_url")] = url
            p[stringPreferencesKey("username")] = "winters"
            p[stringPreferencesKey("password_sealed")] = "c2VjcmV0"
            p[stringPreferencesKey("server_type")] = "navidrome"
            p[stringPreferencesKey("server_version")] = "0.58.0"
            p[booleanPreferencesKey("is_octo")] = false
            p[booleanPreferencesKey("octo_admin_reachable")] = false
            p[stringSetPreferencesKey("extensions")] = setOf("songLyrics:1", "apiKeyAuthentication:1")
            p[stringPreferencesKey("connection")] = connection
        }
        // A second store may open the file only once the first has fully let go of it.
        writerJob.cancelAndJoin()
        val readerJob = SupervisorJob()
        val reader = CoroutineScope(readerJob + Dispatchers.IO)
        try {
            PreferenceDataStoreFactory.create(scope = reader) { file }.data.first()
        } finally {
            readerJob.cancelAndJoin()
        }
    }

    @Test
    fun theOneServerOfAnOlderVersionIsAListOfOneStillInUse() = runBlocking {
        val read = SessionStore(MemoryPrefs(oldFile())).read()
        val kept = read.servers.single()
        assertEquals("the id is the name older versions gave its live lists", accountKey("winters", url), kept.id)
        assertEquals(kept.id, read.active)
        assertEquals(kept, read.inUse)
        assertEquals(url, kept.serverUrl)
        assertEquals("winters", kept.username)
        assertEquals("c2VjcmV0", kept.passwordSealed)
        assertEquals("navidrome", kept.serverType)
        assertEquals("0.58.0", kept.serverVersion)
        assertEquals(setOf("songLyrics:1", "apiKeyAuthentication:1"), kept.extensions)
        assertEquals("the connection, home address, headers and pins come along", connection, kept.connection)
        assertFalse(kept.signedOut)
        assertEquals("music.example.com", kept.name)
    }

    @Test
    fun theListIsWrittenWithTheNextChangeAndOlderVersionsStillFindTheServer() = runBlocking {
        val prefs = MemoryPrefs(oldFile())
        val store = SessionStore(prefs)
        val work = StoredServer("https://work.example.com/", "brandon", "d29yaw==", id = "w", label = "Work")
        store.update { it.copy(servers = it.servers + work) }
        val written = prefs.data.first()
        assertTrue(written[stringPreferencesKey("servers")].orEmpty().contains("work.example.com"))
        assertEquals(url, written[stringPreferencesKey("server_url")])
        assertEquals("c2VjcmV0", written[stringPreferencesKey("password_sealed")])
        assertEquals(connection, written[stringPreferencesKey("connection")])
        val again = SessionStore(prefs).read()
        assertEquals(listOf(accountKey("winters", url), "w"), again.servers.map { it.id })
        assertEquals(accountKey("winters", url), again.active)
    }

    @Test
    fun aServerSwitchedToIsTheOneOlderVersionsSee() = runBlocking {
        val prefs = MemoryPrefs(oldFile())
        val store = SessionStore(prefs)
        val work = StoredServer("https://work.example.com/", "brandon", "d29yaw==", id = "w", label = "Work")
        store.update { it.copy(servers = it.servers + work, active = "w") }
        assertEquals("https://work.example.com/", prefs.data.first()[stringPreferencesKey("server_url")])
        val read = SessionStore(prefs).read()
        assertEquals("w", read.active)
        assertEquals("its label stays", "Work", read.inUse?.label)
        assertEquals(2, read.servers.size)
    }

    @Test
    fun signingOutLeavesTheServerListedWithNoneInUse() = runBlocking {
        val prefs = MemoryPrefs(oldFile())
        val store = SessionStore(prefs)
        store.update { kept -> kept.replacing(kept.inUse!!.copy(signedOut = true, passwordSealed = "")).copy(active = null) }
        val written = prefs.data.first()
        assertNull("older versions see no server", written[stringPreferencesKey("server_url")])
        assertNull(written[stringPreferencesKey("password_sealed")])
        val read = SessionStore(prefs).read()
        assertNull(read.active)
        assertTrue(read.servers.single().signedOut)
        assertEquals("", read.servers.single().passwordSealed)
    }

    @Test
    fun aServerAnOlderVersionSignedInToSinceBecomesTheOneInUse() = runBlocking {
        val prefs = MemoryPrefs()
        val home = StoredServer(url, "winters", "aG9tZQ==", id = "h", label = "Home")
        val work = StoredServer("https://work.example.com/", "brandon", "", id = "w", label = "Work", signedOut = true)
        SessionStore(prefs).update { KeptServers(listOf(home, work), "h") }
        // An older version reads and writes only its one server.
        prefs.updateData { p ->
            p.toMutablePreferences().apply {
                this[stringPreferencesKey("server_url")] = "https://work.example.com/"
                this[stringPreferencesKey("username")] = "brandon"
                this[stringPreferencesKey("password_sealed")] = "bmV3"
            }
        }
        val read = SessionStore(prefs).read()
        assertEquals("w", read.active)
        assertEquals(listOf("h", "w"), read.servers.map { it.id })
        assertEquals("Work", read.inUse?.label)
        assertFalse(read.inUse!!.signedOut)
        assertEquals("bmV3", read.inUse!!.passwordSealed)
    }

    @Test
    fun aNewPhoneHasNoServers() = runBlocking {
        val read = SessionStore(MemoryPrefs()).read()
        assertTrue(read.servers.isEmpty())
        assertNull(read.inUse)
    }
}
