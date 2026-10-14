package app.winters.octo.data

import app.winters.octo.connection.ConnectionChooser
import app.winters.octo.connection.ConnectionSecurity
import app.winters.octo.connection.ConnectionSettings
import app.winters.octo.connection.FolderChoice
import app.winters.octo.connection.ServerClients
import app.winters.octo.connection.StoredConnection
import app.winters.octo.connection.cleanHeaders
import app.winters.octo.connection.decodeConnection
import app.winters.octo.connection.encodeConnection
import app.winters.octo.connection.fingerprint
import app.winters.octo.connection.mask
import app.winters.octo.connection.opened
import app.winters.octo.connection.sealed
import app.winters.octo.server.PasswordChange
import app.winters.octo.server.ServerCheck
import app.winters.octo.server.Reach
import app.winters.octo.server.changeOwnPassword
import app.winters.octo.server.freshServerId
import app.winters.octo.server.passwordRefusedWords
import app.winters.octo.server.serverName
import app.winters.octo.server.serverSourceId
import app.winters.octo.server.switchFailedWords
import app.winters.octo.subsonic.AuthMode
import app.winters.octo.subsonic.Credentials
import app.winters.octo.subsonic.MusicFolder
import app.winters.octo.subsonic.ScanStatus
import app.winters.octo.subsonic.ServerInfo
import app.winters.octo.subsonic.SubsonicClient
import app.winters.octo.subsonic.SubsonicException
import app.winters.octo.subsonic.normalizeServerUrl
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.OkHttpClient
import java.util.concurrent.TimeUnit
import javax.inject.Inject
import javax.inject.Singleton
import javax.net.ssl.SSLException

// The OpenSubsonic extension a server lists when it takes API keys.
const val API_KEY_EXTENSION = "apiKeyAuthentication"

// How long the home address gets to answer before the main one is used.
private const val HOME_PING_SECONDS = 2L

// How long a kept server not in use gets to answer a quick look.
private const val GLANCE_SECONDS = 6L

class Session(
    val client: SubsonicClient,
    val serverType: String?,
    val serverVersion: String?,
    val isOcto: Boolean,
    val adminReachable: Boolean,
    val extensions: Set<String>,
    val connection: ConnectionSettings = ConnectionSettings(),
    // Which kept server this is: everything the phone keeps for the account
    // is kept under it.
    val id: String = "",
    // The name the listener gave it.
    val label: String = "",
) {
    // The source the library is kept under: from the main address, whichever
    // address calls go to.
    val sourceId: String get() = serverSourceId(client.primaryUrl)

    val takesApiKeys: Boolean get() = extensions.any { it.startsWith("$API_KEY_EXTENSION:") }

    // What the server is called: its name, else its host.
    val name: String get() = serverName(label, client.primaryUrl.toString())
}

sealed interface SessionState {
    data object Loading : SessionState
    data object SignedOut : SessionState
    class SignedIn(val session: Session) : SessionState
}

// Whose things are in use: the kept server's id, or null with none in use.
// Null too while the saved sign-in is still being read.
val SessionState.accountId: String? get() = (this as? SessionState.SignedIn)?.session?.id

// What the sign-in form sends. The secret is the password, or the key when
// signing in with an API key. When editing the connection, an empty secret
// keeps the saved one, and so does a header left without a value.
class SignInRequest(
    val address: String,
    val username: String,
    val secret: String,
    val authMode: AuthMode = AuthMode.Token,
    val home: String = "",
    val headers: List<HeaderDraft> = emptyList(),
    val pins: Map<String, String> = emptyMap(),
    val clientCertAlias: String? = null,
    // A name of the listener's own, or null to keep the one it has.
    val label: String? = null,
) {
    override fun toString() = "SignInRequest(address=$address, username=$username, secret=${mask(secret)}, authMode=$authMode)"
}

// A kept server's connection, as the form starts from when editing it. No
// secret is in here: the password, key and header values stay sealed.
class ConnectionDraft(
    val address: String,
    val username: String,
    val authMode: AuthMode,
    val home: String,
    val headers: List<HeaderDraft>,
    val pins: Map<String, String>,
    val clientCertAlias: String?,
    val takesApiKeys: Boolean,
    val label: String = "",
)

// A quick look at the signed-in server: how long it took to answer (null
// when it did not), and its folders scan, when it says.
class ServerLook(val answerMs: Long?, val scan: ScanStatus?)

sealed interface SignInError {
    data object BadAddress : SignInError
    data object BadHomeAddress : SignInError

    // Editing the connection in a way that needs a secret not saved yet.
    data object MissingSecret : SignInError
    class Failed(val cause: SubsonicException) : SignInError

    // The server showed a certificate the phone does not trust. The user
    // may choose to trust exactly this one, for this host only.
    class Untrusted(val host: String, val fingerprint: String) : SignInError

    // Another kept server already has this address and username.
    class AlreadyKept(val name: String) : SignInError

    // The server being edited is no longer in the list.
    data object Gone : SignInError
}

// How moving to another kept server went.
sealed interface SwitchResult {
    // `from` is the server in use before, if any.
    class Done(val session: Session, val from: Session?) : SwitchResult

    // Its password is not kept here (signed out), or the server no longer
    // takes it: ask for it.
    class NeedsPassword(val server: StoredServer, val note: String? = null) : SwitchResult

    class Failed(val message: String) : SwitchResult
}

// The servers kept on the phone, and the one in use: signing in, adding
// another, switching between them, editing, signing out and removing. Each
// server's password, key, header values and client certificate name are
// stored only sealed.
@Singleton
class SessionRepository @Inject constructor(
    private val store: SessionStore,
    private val vault: CredentialVault,
    private val probe: OctoProbe,
    private val http: OkHttpClient,
    private val security: ConnectionSecurity,
    private val chooser: ConnectionChooser,
    private val clients: ServerClients,
    private val handoff: SessionHandoff,
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private val _state = MutableStateFlow<SessionState>(SessionState.Loading)
    val state: StateFlow<SessionState> = _state

    // Every kept server in order, and the one in use.
    private val _servers = MutableStateFlow(KeptServers())
    val servers: StateFlow<KeptServers> = _servers

    // A quick client for asking whether the home address answers.
    private val quick: OkHttpClient by lazy { http.newBuilder().callTimeout(HOME_PING_SECONDS, TimeUnit.SECONDS).build() }

    // Changes to the session happen one at a time.
    private val changes = Mutex()

    // The sign-in in use, kept for rebuilding the client when a setting changes.
    @Volatile private var credentials: Credentials? = null

    init {
        scope.launch {
            _state.value = changes.withLock { restore() }
            refreshExtensions()
        }
    }

    // What the server offers is saved at sign-in, and a server gains
    // extensions over time: an Octo signed in to before it listed its own
    // ones would never be known as Octo. So each start asks again, and keeps
    // what was saved when the server does not answer.
    private suspend fun refreshExtensions() {
        val session = (_state.value as? SessionState.SignedIn)?.session ?: return
        val fresh = runCatching { session.client.extensions() }.getOrNull()
            ?.flatMap { ext -> ext.versions.map { "${ext.name}:$it" } }?.toSet() ?: return
        if (fresh.isEmpty() || fresh == session.extensions) return
        changes.withLock {
            // Only while the same session is still the one in use.
            val current = (_state.value as? SessionState.SignedIn)?.session
            if (current !== session) return@withLock
            _servers.value.find(session.id)?.let { saved ->
                _servers.value = store.update { it.replacing(saved.copy(extensions = fresh)) }
            }
            _state.value = SessionState.SignedIn(session.withExtensions(fresh))
        }
    }

    // Asks the server in use what it is again, after it changed: an update
    // brings a new version, and can bring new extensions. What it does not
    // say stays as it was.
    suspend fun refreshServerFacts() {
        val session = current ?: return
        val info = runCatching { session.client.ping() }.getOrNull() ?: return
        val fresh = runCatching { session.client.extensions() }.getOrNull()
            ?.flatMap { ext -> ext.versions.map { "${ext.name}:$it" } }?.toSet()
            ?.takeIf { it.isNotEmpty() } ?: session.extensions
        changes.withLock {
            // Only while the same session is still the one in use.
            if (current !== session) return@withLock
            val type = info.type ?: session.serverType
            val version = info.serverVersion ?: session.serverVersion
            _servers.value.find(session.id)?.let { saved ->
                _servers.value = store.update { it.replacing(saved.copy(serverType = type, serverVersion = version, extensions = fresh)) }
            }
            _state.value = SessionState.SignedIn(
                Session(session.client, type, version, session.isOcto, session.adminReachable, fresh, session.connection, session.id, session.label),
            )
        }
    }

    private val current: Session? get() = (_state.value as? SessionState.SignedIn)?.session

    suspend fun signIn(address: String, username: String, password: String): SignInError? =
        signIn(SignInRequest(address, username, password))

    // Signs in and makes the server the one in use: a new server joins the
    // list, one already kept is brought up to date. Returns null on success.
    suspend fun signIn(request: SignInRequest): SignInError? = changes.withLock { keep(request, base = null, use = true) }

    // Keeps a server beside the others without leaving the one in use. The
    // same account again is brought up to date rather than kept twice.
    suspend fun add(request: SignInRequest): SignInError? = changes.withLock { keep(request, base = null, use = false) }

    // Changes a kept server's address, username, headers or way of signing
    // in, after signing in with the new details works. Empty secrets keep
    // the saved ones. The server in use is signed in to again.
    suspend fun edit(id: String, request: SignInRequest): SignInError? = changes.withLock {
        val base = _servers.value.find(id) ?: return@withLock SignInError.Gone
        keep(request, base, use = id == _servers.value.active && current != null)
    }

    // Gives a kept server a name of its own; an empty one shows its host.
    suspend fun rename(id: String, label: String) = changes.withLock {
        val kept = _servers.value.find(id) ?: return@withLock
        _servers.value = store.update { it.replacing(kept.copy(label = label.trim())) }
        current?.takeIf { it.id == id }?.let { now ->
            _state.value = SessionState.SignedIn(now.relabelled(label.trim()))
        }
    }

    private suspend fun keep(request: SignInRequest, base: StoredServer?, use: Boolean): SignInError? {
        val main = normalizeServerUrl(request.address) ?: return SignInError.BadAddress
        val home = if (request.home.isBlank()) null
        else (normalizeServerUrl(request.home) ?: return SignInError.BadHomeAddress).takeIf { it != main }
        val username = request.username.trim()
        val kept = _servers.value
        // The same account already kept, when not the one edited.
        val twin = kept.servers.firstOrNull { it.serverUrl == main.toString() && it.username == username && it.id != base?.id }
        if (base != null && twin != null) return SignInError.AlreadyKept(twin.name)
        val before = base ?: twin
        val savedConnection = before?.let(::openedConnection)
        val secret = request.secret.ifEmpty { before?.let { savedSecret(it, request.authMode) } ?: return SignInError.MissingSecret }
        val settings = ConnectionSettings(
            home = home,
            authMode = request.authMode,
            headers = cleanHeaders(resolveHeaders(request.headers, savedConnection?.headers.orEmpty())),
            pins = request.pins,
            clientCertAlias = request.clientCertAlias,
            // The folder stays when only the way in changed.
            folder = savedConnection?.takeIf { before?.serverUrl == main.toString() }?.folder,
        )
        var creds = Credentials(username, secret, request.authMode)
        val inUse = current

        // Tries the connection with the new settings, and puts the ones in
        // use back if it does not work, or once it has when the server is
        // only being kept.
        applySecurity(main, settings)
        suspend fun putBack() = if (inUse != null) applySecurity(inUse.client.primaryUrl, inUse.connection) else security.clear()
        val reached = try {
            reach(main, home, creds)
        } catch (e: SubsonicException) {
            // The certificate is read before the settings go back, which forgets it.
            val question = untrusted(e, main, home)
            putBack()
            return question ?: SignInError.Failed(e)
        }
        // A home address with a certificate the phone does not trust is
        // asked about now, while the user is here to answer.
        if (home != null && reached.url != home) {
            val homeError = runCatching { SubsonicClient(home, creds, quick).ping() }.exceptionOrNull()
            if (homeError is SubsonicException) {
                untrusted(homeError, home, null)?.let { question ->
                    putBack()
                    return question
                }
            }
        }

        val client = SubsonicClient(reached.url, creds, http)
        // With an API key the server says whose it is.
        if (request.authMode == AuthMode.ApiKey) {
            val owner = runCatching { client.tokenInfo() }.getOrNull()
            if (!owner.isNullOrBlank()) creds = creds.named(owner)
        }
        val extensions = runCatching { client.extensions() }.getOrDefault(emptyList())
            .flatMap { ext -> ext.versions.map { "${ext.name}:$it" } }.toSet()
        // The status page is the only Octo signal for now, so the two match.
        val admin = probe.adminReachable(reached.url)
        val taken = kept.servers.map { it.id }.toSet() - setOfNotNull(before?.id)
        val id = when {
            before == null -> freshServerId(creds.username, main.toString(), taken)
            // Another account on the server gets its own plays and queue.
            before.username != creds.username -> freshServerId(creds.username, main.toString(), taken)
            else -> before.id
        }
        val saved = StoredServer(
            serverUrl = main.toString(),
            username = creds.username,
            passwordSealed = vault.seal(secret),
            serverType = reached.info.type,
            serverVersion = reached.info.serverVersion,
            isOcto = admin,
            octoAdminReachable = admin,
            extensions = extensions,
            connection = encodeConnection(settings.sealed(vault::seal)),
            id = id,
            label = request.label?.trim() ?: before?.label.orEmpty(),
        )
        if (!use) {
            putBack()
            _servers.value = store.update { now ->
                val list = if (before == null) now.servers + saved else now.servers.map { if (it.id == before.id) saved else it }
                now.copy(servers = list)
            }
            return null
        }
        // Another account in use puts its things away first.
        if (inUse != null && inUse.id != id) handoff.leave(inUse, id)
        _servers.value = store.update { now ->
            val list = if (before == null) now.servers + saved else now.servers.map { if (it.id == before.id) saved else it }
            now.copy(servers = list, active = id)
        }
        _state.value = SessionState.SignedIn(activate(main, settings, creds, saved))
        return null
    }

    // Makes another kept server the one in use, signed in with its saved
    // secret. It is asked first, with a client of its own, so one out of
    // reach leaves everything as it was; what it says about itself is kept
    // fresh. The server in use puts its things away before the new one is.
    suspend fun switchTo(id: String): SwitchResult = changes.withLock {
        val server = _servers.value.find(id) ?: return@withLock SwitchResult.Failed("That server isn't in your list any more.")
        val from = current
        if (from?.id == id) return@withLock SwitchResult.Done(from, null)
        if (server.signedOut || server.passwordSealed.isEmpty()) return@withLock SwitchResult.NeedsPassword(server)
        val secret = vault.open(server.passwordSealed) ?: return@withLock SwitchResult.NeedsPassword(server)
        val settings = openedConnection(server) ?: return@withLock SwitchResult.NeedsPassword(server)
        val main = server.serverUrl.toHttpUrlOrNull()
            ?: return@withLock SwitchResult.Failed("That server's address can't be read. Edit it and try again.")
        val creds = Credentials(server.username, secret, settings.authMode)
        val own = clients.forServer(main, settings, GLANCE_SECONDS)
        val info = try {
            reachWith(own, main, settings.home, creds).info
        } catch (e: SubsonicException) {
            if (e is SubsonicException.WrongCredentials) return@withLock SwitchResult.NeedsPassword(server, passwordRefusedWords(server.name))
            return@withLock SwitchResult.Failed(switchFailedWords(server.name, e.userMessage()))
        }
        val extensions = runCatching { SubsonicClient(main, creds, own).extensions() }.getOrNull()
            ?.flatMap { ext -> ext.versions.map { "${ext.name}:$it" } }?.toSet()
        val fresh = server.copy(
            serverType = info.type ?: server.serverType,
            serverVersion = info.serverVersion ?: server.serverVersion,
            extensions = extensions ?: server.extensions,
        )
        if (from != null) handoff.leave(from, id)
        _servers.value = store.update { it.replacing(fresh).copy(active = id) }
        val session = activate(main, settings, creds, fresh)
        _state.value = SessionState.SignedIn(session)
        SwitchResult.Done(session, from)
    }

    // How a kept server answers a quick look, with a client of its own.
    // One signed out of is not asked.
    suspend fun check(id: String): ServerCheck {
        val server = _servers.value.find(id) ?: return ServerCheck(Reach.Unknown)
        val inUse = current?.takeIf { it.id == id }
        val client = if (inUse != null) {
            inUse.client
        } else {
            if (server.signedOut || server.passwordSealed.isEmpty()) return ServerCheck(Reach.Unknown)
            val secret = vault.open(server.passwordSealed) ?: return ServerCheck(Reach.Unknown)
            val settings = openedConnection(server) ?: return ServerCheck(Reach.Unknown)
            val main = server.serverUrl.toHttpUrlOrNull() ?: return ServerCheck(Reach.Unreachable)
            SubsonicClient(main, Credentials(server.username, secret, settings.authMode), clients.forServer(main, settings, GLANCE_SECONDS))
        }
        val start = System.nanoTime()
        return try {
            client.ping()
            ServerCheck(Reach.Answers, (System.nanoTime() - start) / 1_000_000)
        } catch (e: SubsonicException) {
            ServerCheck(if (e is SubsonicException.WrongCredentials) Reach.WrongPassword else Reach.Unreachable)
        }
    }

    // Signs out of the server in use: disconnecting keeps it in the list,
    // without its password.
    suspend fun signOut() = signOut(null)

    // Signs out of a kept server, the one in use when `id` is null. It stays
    // in the list without its password, so signing in again needs only that;
    // its header values stay sealed.
    suspend fun signOut(id: String?) = changes.withLock {
        val kept = _servers.value
        val server = kept.find(id ?: kept.active) ?: return@withLock
        val inUse = current?.takeIf { it.id == server.id }
        if (inUse != null) handoff.leave(inUse, null)
        _servers.value = store.update { now ->
            val out = now.replacing(server.copy(signedOut = true, passwordSealed = ""))
            if (now.active == server.id) out.copy(active = null) else out
        }
        if (inUse != null) leaveSession()
    }

    // Takes a server off the list, with its password. Its music and
    // playlists stay on the server. Answers the server removed, if it was kept.
    suspend fun remove(id: String): StoredServer? = changes.withLock {
        val server = _servers.value.find(id) ?: return@withLock null
        val inUse = current?.takeIf { it.id == id }
        if (inUse != null) handoff.leave(inUse, null)
        _servers.value = store.update { now ->
            now.copy(servers = now.servers.filterNot { it.id == id }, active = now.active.takeIf { it != id })
        }
        if (inUse != null) leaveSession()
        // With no server kept, nothing sealed is left to open.
        if (_servers.value.servers.isEmpty()) vault.forget()
        server
    }

    private fun leaveSession() {
        credentials = null
        chooser.clear()
        security.clear()
        _state.value = SessionState.SignedOut
    }

    // Changes the signed-in user's password on the server. The current one is
    // checked first; on success the new one is sealed in place of the old,
    // and the client in use already signs in with it.
    // A family member's password goes through the family's own call, which
    // signs every other app and device out.
    suspend fun changePassword(current: String, new: String, family: Boolean = false): PasswordChange {
        val session = this.current ?: return PasswordChange.Failed("Connect a server first.")
        val result = changeOwnPassword(session.client, current, new, family)
        if (result != PasswordChange.Changed) return result
        changes.withLock {
            _servers.value.find(session.id)?.let { saved ->
                _servers.value = store.update { it.replacing(saved.copy(passwordSealed = vault.seal(new))) }
            }
            credentials = credentials?.let { Credentials(it.username, new, it.mode) }
        }
        return result
    }

    // How quickly the signed-in server answers, in milliseconds, and how its
    // folders scan stands; null for what it would not say.
    suspend fun look(): ServerLook? {
        val session = current ?: return null
        val start = System.nanoTime()
        val answered = runCatching { session.client.ping() }.isSuccess
        val ms = if (answered) (System.nanoTime() - start) / 1_000_000 else null
        val scan = runCatching { session.client.scanStatus() }.getOrNull()
        return ServerLook(ms, scan)
    }

    // The library folders on the signed-in server.
    suspend fun musicFolders(): List<MusicFolder> {
        val session = current ?: return emptyList()
        return session.client.musicFolders()
    }

    // Limits the library to one folder, or null for all of them. The caller
    // copies the library again afterwards.
    suspend fun chooseMusicFolder(folder: FolderChoice?) = changes.withLock {
        val session = current ?: return@withLock
        val creds = credentials ?: return@withLock
        val saved = _servers.value.find(session.id) ?: return@withLock
        val settings = session.connection.copy(folder = folder)
        val updated = saved.copy(connection = encodeConnection(settings.sealed(vault::seal)))
        _servers.value = store.update { it.replacing(updated) }
        _state.value = SessionState.SignedIn(activate(session.client.primaryUrl, settings, creds, updated))
    }

    // A kept server's connection for the edit form, the one in use when `id`
    // is null, with no secrets in it.
    fun connectionDraft(id: String? = null): ConnectionDraft? {
        val server = _servers.value.find(id ?: current?.id) ?: return null
        val connection = openedConnection(server) ?: decodeConnection(server.connection.orEmpty())?.let { stored ->
            // Secrets that can no longer be opened are asked for again.
            ConnectionSettings(home = stored.homeUrl?.toHttpUrlOrNull(), authMode = stored.authMode, pins = stored.pins, folder = stored.folder)
        } ?: ConnectionSettings()
        return ConnectionDraft(
            address = server.serverUrl.removeSuffix("/"),
            username = server.username,
            authMode = connection.authMode,
            home = connection.home?.toString()?.removeSuffix("/").orEmpty(),
            headers = connection.headers.map { HeaderDraft(it.name, "", saved = true) },
            pins = connection.pins,
            clientCertAlias = connection.clientCertAlias,
            takesApiKeys = server.extensions.any { it.startsWith("$API_KEY_EXTENSION:") },
            label = server.label,
        )
    }

    private suspend fun restore(): SessionState {
        val kept = store.read()
        _servers.value = kept
        val saved = kept.inUse ?: return SessionState.SignedOut
        val secret = vault.open(saved.passwordSealed)
        val settings = openedConnection(saved)
        val main = saved.serverUrl.toHttpUrlOrNull()
        if (secret == null || settings == null || main == null) {
            // The keystore lost its key (a backup restored on a new phone):
            // the server stays in the list, to sign in to again.
            _servers.value = store.update { now -> now.replacing(saved.copy(signedOut = true, passwordSealed = "")).copy(active = null) }
            return SessionState.SignedOut
        }
        applySecurity(main, settings)
        return SessionState.SignedIn(activate(main, settings, Credentials(saved.username, secret, settings.authMode), saved))
    }

    // Makes a signed-in session: the network set up for the server, the
    // address chooser started, and a client whose calls follow it.
    private suspend fun activate(main: HttpUrl, settings: ConnectionSettings, creds: Credentials, saved: StoredServer): Session {
        applySecurity(main, settings)
        credentials = creds
        chooser.use(main, settings.home) { url -> answersAt(url, creds) }
        val client = SubsonicClient(main, creds, http, musicFolderId = settings.folder?.id, route = { chooser.activeUrl(main) })
        return Session(
            client,
            saved.serverType,
            saved.serverVersion,
            saved.isOcto,
            saved.octoAdminReachable,
            saved.extensions,
            settings,
            id = saved.id,
            label = saved.label,
        )
    }

    private fun Session.relabelled(label: String) =
        Session(client, serverType, serverVersion, isOcto, adminReachable, extensions, connection, id, label)

    private fun Session.withExtensions(fresh: Set<String>) =
        Session(client, serverType, serverVersion, isOcto, adminReachable, fresh, connection, id, label)

    private suspend fun applySecurity(main: HttpUrl, settings: ConnectionSettings) {
        security.configure(main, settings)
        // Open connections were made under the old trust; start fresh. Closing
        // an HTTPS connection sends its goodbye over the network, which Android
        // refuses on the main thread, so it happens on the IO threads.
        withContext(Dispatchers.IO) { http.connectionPool.evictAll() }
    }

    // A kept server's connection with its secrets opened, or null when one
    // can no longer be opened.
    private fun openedConnection(server: StoredServer): ConnectionSettings? {
        val stored = server.connection?.let { decodeConnection(it) } ?: StoredConnection()
        return stored.opened(vault::open)
    }

    // A kept server's saved secret, when it fits the way of signing in
    // asked for: a saved password serves token or legacy sign-in, a saved
    // key only a key.
    private fun savedSecret(server: StoredServer, mode: AuthMode): String? {
        if (server.passwordSealed.isEmpty()) return null
        val stored = server.connection?.let { decodeConnection(it) } ?: StoredConnection()
        val sameKind = (stored.authMode == AuthMode.ApiKey) == (mode == AuthMode.ApiKey)
        return if (sameKind) vault.open(server.passwordSealed) else null
    }

    private class Reached(val url: HttpUrl, val info: ServerInfo)

    private suspend fun reach(main: HttpUrl, home: HttpUrl?, creds: Credentials): Reached = reachWith(http, main, home, creds)

    // Pings the main address. When that cannot connect and there is a home
    // address, pings that instead: at home the main address may not loop back.
    private suspend fun reachWith(client: OkHttpClient, main: HttpUrl, home: HttpUrl?, creds: Credentials): Reached = try {
        Reached(main, SubsonicClient(main, creds, client).ping())
    } catch (e: SubsonicException.Unreachable) {
        if (home == null || e.cause is SSLException) throw e
        val info = runCatching { SubsonicClient(home, creds, client).ping() }.getOrNull() ?: throw e
        Reached(home, info)
    }

    // Whether the home address answers like the server does.
    private suspend fun answersAt(url: HttpUrl, creds: Credentials): Boolean = try {
        SubsonicClient(url, creds, quick).ping()
        true
    } catch (e: SubsonicException) {
        // An error from the server itself still means it is there.
        e !is SubsonicException.Unreachable && e !is SubsonicException.NotSubsonic
    }

    // A failure caused by a certificate the phone does not trust, as a
    // question for the user. Null for any other failure.
    private fun untrusted(e: SubsonicException, vararg urls: HttpUrl?): SignInError.Untrusted? {
        if (e !is SubsonicException.Unreachable || e.cause !is SSLException) return null
        for (url in urls.filterNotNull()) {
            val leaf = security.takeRejected(url.host) ?: continue
            return SignInError.Untrusted(url.host, leaf.fingerprint())
        }
        return null
    }
}
