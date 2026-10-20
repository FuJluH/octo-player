package app.winters.octo.playback

import app.winters.octo.ui.family.appPicksQuality
import app.winters.octo.family.family
import app.winters.octo.family.FamilyHub
import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import androidx.annotation.OptIn
import androidx.core.net.toUri
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.ParserException
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DataSource
import androidx.media3.datasource.DataSpec
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.HttpDataSource
import androidx.media3.datasource.ResolvingDataSource
import androidx.media3.datasource.TransferListener
import androidx.media3.datasource.cache.CacheDataSource
import androidx.media3.datasource.cache.CacheKeyFactory
import androidx.media3.datasource.okhttp.OkHttpDataSource
import androidx.media3.exoplayer.drm.DrmSessionManagerProvider
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.exoplayer.source.MediaSource
import androidx.media3.exoplayer.upstream.DefaultLoadErrorHandlingPolicy
import androidx.media3.exoplayer.upstream.LoadErrorHandlingPolicy
import androidx.media3.exoplayer.upstream.LoadErrorHandlingPolicy.LoadErrorInfo
import androidx.media3.extractor.DefaultExtractorsFactory
import app.winters.octo.catalog.SourceTrackEntity
import app.winters.octo.data.SessionRepository
import app.winters.octo.data.SessionState
import app.winters.octo.offline.StreamCache
import app.winters.octo.player.PlayerSettings
import app.winters.octo.player.StreamPrefs
import app.winters.octo.server.sourceId
import app.winters.octo.subsonic.SubsonicClient
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import app.winters.octo.subsonic.OctoPurpose
import app.winters.octo.subsonic.markedFor
import app.winters.octo.subsonic.purpose
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.FileNotFoundException
import java.io.IOException
import javax.inject.Inject
import javax.inject.Singleton

// How long to wait for the saved sign-in to come back as the app starts.
private const val SESSION_WAIT_MS = 3_000L

// Why a server song cannot load: no connection, or no server signed in.
class StreamUnavailable(message: String) : IOException(message)

// Streams songs from the signed-in server. It knows the connection and the
// streaming settings, and signs each request as a deck opens it, so a new
// address is made for every load and seek and none is ever kept. Songs
// played are saved on the phone as they stream, by song, never by address.
@OptIn(UnstableApi::class)
@Singleton
class Streams @Inject constructor(
    @ApplicationContext private val context: Context,
    private val sessions: SessionRepository,
    private val settings: PlayerSettings,
    private val http: OkHttpClient,
    private val saved: StreamCache,
    // A family account's device left to its account plays the file as it
    // is, and the server applies the account's quality.
    private val family: FamilyHub,
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private val connectivity = context.getSystemService(ConnectivityManager::class.java)

    // The settings as they are now, for choices made while a song loads.
    private val current: StateFlow<StreamPrefs> =
        settings.streamPrefs.stateIn(scope, SharingStarted.Eagerly, StreamPrefs())

    suspend fun prefs(): StreamPrefs = settings.streamPrefs.first()

    // The signed-in server, once the saved sign-in is back, or null.
    suspend fun client(): SubsonicClient? {
        val state = withTimeoutOrNull(SESSION_WAIT_MS) { sessions.state.first { it !is SessionState.Loading } }
        return (state as? SessionState.SignedIn)?.session?.client
    }

    // Whether the phone has a connection a stream could use.
    fun online(): Boolean =
        capabilities()?.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) == true

    // Whether the phone is online over Wi-Fi or a cable, not mobile data.
    fun onWifi(): Boolean = online() && !onMobileData()

    // Mobile data is any connection that is not Wi-Fi or a cable.
    private fun onMobileData(): Boolean {
        val caps = capabilities() ?: return false
        return !caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) &&
            !caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET)
    }

    private fun capabilities(): NetworkCapabilities? =
        connectivity.activeNetwork?.let(connectivity::getNetworkCapabilities)

    // The stream size for the connection the phone is on.
    private fun quality(prefs: StreamPrefs): StreamQuality {
        val familyOn = (sessions.state.value as? SessionState.SignedIn)?.session?.family == true
        return streamQualityFor(appPicksQuality(familyOn, family.model.deviceMode), onMobileData(), prefs)
    }

    // Where the queue keeps a server copy.
    fun uriFor(copy: SourceTrackEntity): String = streamUri(refFor(copy))

    fun refFor(copy: SourceTrackEntity): StreamRef =
        StreamRef(copy.sourceId, copy.nativeId, copy.mimeType, bitrateOf(copy), size = copy.sizeBytes?.takeIf { it > 0 })

    // Where the queue keeps any server song, by its server, its id there,
    // its type and its bits a second.
    fun uriFor(sourceId: String?, serverId: String, mimeType: String?, bitrate: Int?): String =
        streamUri(StreamRef(sourceId, serverId, mimeType, bitrate))

    // What the player will receive for a server copy on this connection.
    fun mimeTypeFor(copy: SourceTrackEntity, prefs: StreamPrefs): String? = mimeTypeFor(copy.mimeType, bitrateOf(copy), prefs)

    fun mimeTypeFor(mimeType: String?, bitrate: Int?, prefs: StreamPrefs): String? =
        streamRequest(mimeType, bitrate, quality(prefs)).mimeType(mimeType)

    // What a deck loads songs with: phone files as they are, server songs
    // from their saved copy when there is one, otherwise signed as they open
    // and saved as they play. Radio stations open their streams as they are
    // and keep trying through a dropped connection. One for each deck.
    fun mediaSourceFactory(): MediaSource.Factory = RadioAwareSources(
        songs = DefaultMediaSourceFactory(dataSourceFactory(networkFactory()), extractors()).setLoadErrorHandlingPolicy(Retries()),
        hls = DefaultMediaSourceFactory(networkFactory(), extractors()).setLoadErrorHandlingPolicy(RadioRetries()),
        streams = DefaultMediaSourceFactory(ReconnectingDataSource.Factory(networkFactory()), extractors()).setLoadErrorHandlingPolicy(RadioRetries()),
    )

    // What the scout reads songs with: the same chain the decks play from
    // (the pinned request, the saved copies, signing), so what it reads is
    // saved for playing too. It never names a signed address to its reader,
    // so opening the song again at another place goes through the whole
    // chain, and it reads from the server only when the server answers
    // requests for parts of the song.
    fun scoutSourceFactory(): DataSource.Factory =
        StableUriDataSource.Factory(dataSourceFactory(RangeGuardDataSource.Factory(networkFactory())))

    // A made-on-the-way MP3 has no seek table, so seek by its steady bitrate.
    fun extractors(): DefaultExtractorsFactory = DefaultExtractorsFactory().setConstantBitrateSeekingEnabled(true)

    private fun dataSourceFactory(network: DataSource.Factory): DataSource.Factory = streamSources(
        network = network,
        isStream = ::isStream,
        pin = ::pin,
        sign = ::sign,
        cached = ::cachedFactory,
        keeping = { saved.enabled.value },
        shapes = saved.shapes,
    )

    // Fills the saved copy of a song ahead of time, for the next songs in
    // the queue. Null while nothing is kept.
    fun savingSource(): CacheDataSource? =
        if (saved.enabled.value) cachedFactory(ShapeGuardDataSource.Factory(signedFactory(networkFactory()), ::isStream, saved.shapes)).createDataSource() else null

    // Reads a server song for downloading: from its saved copy when there is
    // one, otherwise from the server, without filling the saved copies.
    fun downloadSource(): DataSource {
        val signed = signedFactory(offlineNetworkFactory())
        if (!saved.enabled.value) return signed.createDataSource()
        return cachedFactory(signed).setCacheWriteDataSinkFactory(null).createDataSource()
    }

    // The song with the request it loads with fixed in its address: see
    // chooseRequest. Unchanged when no server is known for it.
    fun pinned(ref: StreamRef): StreamRef {
        if (ref.pinned != null) return ref
        val source = ref.sourceId ?: currentSourceId() ?: return ref
        val request = chooseRequest(source, ref, quality(current.value), saved::isFullySaved, saved::isPartlySaved) {
            savedCopyKey(source, ref, it, saved.copies)
        }
        return ref.copy(sourceId = source).pin(request)
    }

    // What another device on the Wi-Fi is sent for a server song: the
    // pinned request, or the one for streaming on Wi-Fi, since casting
    // always is.
    fun deviceRequest(ref: StreamRef): StreamRequest = ref.pinned ?: streamRequest(ref.mimeType, ref.bitrate, current.value.wifi)

    // A signed address for another device on the network to fetch a
    // server song from itself, at the address the phone is using now (the
    // home one while at home). Null with no server signed in.
    suspend fun deviceAddress(ref: StreamRef, request: StreamRequest): String? {
        val client = client() ?: return null
        if (fromAnotherServer(ref, currentSourceId())) return null
        return client.url("stream", mapOf("id" to ref.serverId) + request.params).toString()
    }

    // The type the server sends a song as for `request`, asked with its
    // first byte, or null when it does not say or cannot be reached. A song
    // asked for as it is can come as another file than listed. Marked like
    // an offline copy, so an Octo server does not count it as playing.
    suspend fun answeredType(ref: StreamRef, request: StreamRequest): String? {
        val address = deviceAddress(ref, request) ?: return null
        return withContext(Dispatchers.IO) {
            runCatching {
                val probe = Request.Builder().url(address).header("Range", "bytes=0-0").purpose(OctoPurpose.Offline).build()
                http.newCall(probe).execute().use { answer -> if (answer.isSuccessful) plainType(answer.header("Content-Type")) else null }
            }.getOrNull()
        }
    }

    // The name a song is saved under, or null when no server is known for it.
    fun cacheKey(ref: StreamRef): String? {
        val source = ref.sourceId ?: currentSourceId() ?: return null
        return savedCopyKey(source, ref, ref.request(quality(current.value)), saved.copies)
    }

    private fun networkFactory(): DataSource.Factory = DefaultDataSource.Factory(context, OkHttpDataSource.Factory(http))

    // The same, with every request marked as an offline copy. The server's
    // own addresses are told so (X-Octo-Purpose), and an Octo server does
    // not count it as playing; no other host hears of it.
    private fun offlineNetworkFactory(): DataSource.Factory = DefaultDataSource.Factory(context, OkHttpDataSource.Factory(offlineHttp))

    private val offlineHttp: OkHttpClient by lazy { http.markedFor(OctoPurpose.Offline) }

    private fun signedFactory(upstream: DataSource.Factory): DataSource.Factory = signedSources(upstream, ::isStream, ::sign)

    private fun cachedFactory(upstream: DataSource.Factory): CacheDataSource.Factory =
        CacheDataSource.Factory()
            .setCache(saved.cache)
            .setUpstreamDataSourceFactory(upstream)
            .setCacheKeyFactory(keys)
            // A saved copy that cannot be read is passed over for the server's.
            .setFlags(CacheDataSource.FLAG_IGNORE_CACHE_ON_ERROR)

    // Songs are saved by server, song, type, request and file size, never by
    // address.
    private val keys = CacheKeyFactory { spec ->
        parseStreamUri(spec.uri.toString())?.let(::cacheKey) ?: spec.key ?: spec.uri.toString()
    }

    private fun isStream(uri: Uri): Boolean = uri.scheme == STREAM_SCHEME

    fun currentSourceId(): String? = (sessions.state.value as? SessionState.SignedIn)?.session?.sourceId

    // Whether a song is another kept server's than the one in use.
    private fun fromAnotherServer(ref: StreamRef, inUse: String?): Boolean {
        val source = ref.sourceId ?: return false
        return source != inUse && sessions.servers.value.servers.any { it.sourceId == source }
    }

    // Runs on the loading thread, before the saved copy is looked for.
    private fun pin(uri: Uri): Uri {
        val ref = parseStreamUri(uri.toString()) ?: return uri
        return streamUri(pinned(ref)).toUri()
    }

    // Runs on the loading thread, each time a stream opens.
    private fun sign(uri: Uri): Uri {
        if (!online()) throw StreamUnavailable("No connection")
        val session = (sessions.state.value as? SessionState.SignedIn)?.session
            ?: throw StreamUnavailable("No server signed in")
        val client = session.client
        val ref = parseStreamUri(uri.toString()) ?: throw StreamUnavailable("No song id")
        // Another kept server's song never goes to this one, where its id
        // would be some other song. (A song kept under this server's old
        // address, before it was edited, still plays.)
        if (fromAnotherServer(ref, session.sourceId)) throw StreamUnavailable("Another server's song")
        val request = ref.request(quality(current.value))
        return client.url("stream", mapOf("id" to ref.serverId) + request.params).toString().toUri()
    }

    // A failed load is tried again as usual, except with no connection or
    // no server: then the song fails at once and is skipped, not waited on.
    // Another file for the song fails at once too, and the song is opened
    // again from its start (see the service's error handling).
    private inner class Retries : DefaultLoadErrorHandlingPolicy() {
        override fun getRetryDelayMsFor(loadErrorInfo: LoadErrorInfo): Long =
            if (loadErrorInfo.exception is StreamUnavailable || loadErrorInfo.exception is StreamChanged || !online()) {
                C.TIME_UNSET
            } else {
                super.getRetryDelayMsFor(loadErrorInfo)
            }
    }
}

// A station's stream is opened again after it drops, a few times, waiting
// longer each time, even with no connection for a moment. A stream that
// was refused or gone, or is not audio, fails at once.
@OptIn(UnstableApi::class)
internal class RadioRetries : DefaultLoadErrorHandlingPolicy() {
    override fun getRetryDelayMsFor(loadErrorInfo: LoadErrorInfo): Long =
        radioRetryDelayMs(loadErrorInfo.errorCount, lastingRadioError(loadErrorInfo.exception))

    override fun getMinimumLoadableRetryCount(dataType: Int): Int = RADIO_RETRIES
}

// Errors that opening the stream again would only repeat.
internal fun lastingRadioError(error: IOException): Boolean = when (error) {
    is ParserException, is FileNotFoundException, is HttpDataSource.CleartextNotPermittedException -> true
    is HttpDataSource.InvalidResponseCodeException -> error.responseCode in 400..499 && error.responseCode != 408 && error.responseCode != 429
    else -> false
}

// Radio stations go to their own loaders, everything else to the songs':
// an HLS station to one that reads its playlist and parts as they are, any
// other to one whose stream, should it end, is opened again
// (ReconnectingDataSource).
@OptIn(UnstableApi::class)
internal class RadioAwareSources(
    private val songs: MediaSource.Factory,
    private val hls: MediaSource.Factory,
    private val streams: MediaSource.Factory,
) : MediaSource.Factory {
    override fun setDrmSessionManagerProvider(drmSessionManagerProvider: DrmSessionManagerProvider): MediaSource.Factory = apply {
        listOf(songs, hls, streams).forEach { it.setDrmSessionManagerProvider(drmSessionManagerProvider) }
    }

    // Songs only: stations keep their own retries.
    override fun setLoadErrorHandlingPolicy(loadErrorHandlingPolicy: LoadErrorHandlingPolicy): MediaSource.Factory = apply {
        songs.setLoadErrorHandlingPolicy(loadErrorHandlingPolicy)
    }

    override fun getSupportedTypes(): IntArray = (songs.supportedTypes + hls.supportedTypes).distinct().toIntArray()

    override fun createMediaSource(mediaItem: MediaItem): MediaSource = when (radioLoader(mediaItem.mediaId)) {
        RadioLoader.None -> songs.createMediaSource(mediaItem)
        RadioLoader.Hls -> hls.createMediaSource(mediaItem)
        RadioLoader.Stream -> streams.createMediaSource(mediaItem)
    }
}

// Which loader an item takes.
internal enum class RadioLoader { None, Hls, Stream }

// A station marked HLS, or whose address ends in .m3u8, is HLS; any other
// station is one stream.
internal fun radioLoader(id: String): RadioLoader {
    val (stream, _) = radioOf(id) ?: return RadioLoader.None
    if (radioIsHls(id)) return RadioLoader.Hls
    val path = stream.substringBefore('?').substringBefore('#').lowercase()
    return if (path.endsWith(".m3u8")) RadioLoader.Hls else RadioLoader.Stream
}

// The chain a song is read through. Server songs get their request pinned
// in their address, then are read from their saved copy while songs are
// kept (filling it from the server as they go), or straight from the
// server, signed as they open. Everything else (phone files) opens from
// `network` as it is. Every answer for a server song is checked against the
// file it began as and its saved copy's (`shapes`): see
// ShapeGuardDataSource. One reader keeps one source of each kind for all
// its opens, so the check sees every answer the reader had.
@OptIn(UnstableApi::class)
internal fun streamSources(
    network: DataSource.Factory,
    isStream: (Uri) -> Boolean,
    pin: (Uri) -> Uri,
    sign: (Uri) -> Uri,
    cached: (DataSource.Factory) -> DataSource.Factory,
    keeping: () -> Boolean,
    shapes: StreamShapes? = null,
): DataSource.Factory {
    val signed = ShapeGuardDataSource.Factory(signedSources(network, isStream, sign), isStream, shapes)
    val saved = cached(signed)
    val split = DataSource.Factory {
        val phone by lazy { network.createDataSource() }
        val kept by lazy { saved.createDataSource() }
        val direct by lazy { signed.createDataSource() }
        SplitDataSource { spec ->
            when {
                !isStream(spec.uri) -> phone
                keeping() -> kept
                else -> direct
            }
        }
    }
    return ResolvingDataSource.Factory(split) { spec -> if (isStream(spec.uri)) spec.withUri(pin(spec.uri)) else spec }
}

@OptIn(UnstableApi::class)
private fun signedSources(upstream: DataSource.Factory, isStream: (Uri) -> Boolean, sign: (Uri) -> Uri): DataSource.Factory =
    ResolvingDataSource.Factory(upstream) { spec -> if (isStream(spec.uri)) spec.withUri(sign(spec.uri)) else spec }

// Opens server songs and everything else from different sources, picked
// as each one opens. A source picked again is told of the listeners once.
@OptIn(UnstableApi::class)
private class SplitDataSource(private val pick: (DataSpec) -> DataSource) : DataSource {
    private val listeners = ArrayList<TransferListener>()
    private val told = HashMap<DataSource, Int>()
    private var current: DataSource? = null

    override fun addTransferListener(transferListener: TransferListener) {
        listeners += transferListener
    }

    override fun open(dataSpec: DataSpec): Long {
        val source = pick(dataSpec)
        val already = told[source] ?: 0
        listeners.drop(already).forEach(source::addTransferListener)
        told[source] = listeners.size
        current = source
        return source.open(dataSpec)
    }

    override fun read(buffer: ByteArray, offset: Int, length: Int): Int = checkNotNull(current).read(buffer, offset, length)

    override fun getUri(): Uri? = current?.uri

    override fun getResponseHeaders(): Map<String, List<String>> = current?.responseHeaders ?: emptyMap()

    override fun close() {
        try {
            current?.close()
        } finally {
            current = null
        }
    }
}

// The quality a stream asks for: this app's, for the connection the phone
// is on, when it picks; otherwise the file as it is, and the server applies
// the account's choice.
fun streamQualityFor(appPicks: Boolean, onMobile: Boolean, prefs: StreamPrefs): StreamQuality = when {
    !appPicks -> StreamQuality.Original
    onMobile -> prefs.mobile
    else -> prefs.wifi
}
