package app.winters.octo.offline

import android.content.Context
import androidx.annotation.OptIn
import androidx.media3.common.util.UnstableApi
import androidx.media3.database.StandaloneDatabaseProvider
import androidx.media3.datasource.cache.Cache
import androidx.media3.datasource.cache.CacheEvictor
import androidx.media3.datasource.cache.CacheSpan
import androidx.media3.datasource.cache.ContentMetadata
import androidx.media3.datasource.cache.ContentMetadataMutations
import androidx.media3.datasource.cache.LeastRecentlyUsedCacheEvictor
import androidx.media3.datasource.cache.SimpleCache
import app.winters.octo.playback.SavedCopies
import app.winters.octo.playback.StreamShape
import app.winters.octo.playback.StreamShapes
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import javax.inject.Inject
import javax.inject.Singleton

// Server songs played lately, kept on the phone so they play again without
// the network: a rolling store that lets the least recently played go once
// it is full. Downloads are not kept here; they are real files that stay.
@OptIn(UnstableApi::class)
@Singleton
class StreamCache @Inject constructor(
    @ApplicationContext private val context: Context,
    settings: OfflineSettings,
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val evictor = ResizableEvictor()

    // Whether songs are kept at all; off until the saved setting is read.
    private val _enabled = MutableStateFlow(false)
    val enabled: StateFlow<Boolean> = _enabled

    // How much it holds now, for the settings.
    private val _usedBytes = MutableStateFlow(0L)
    val usedBytes: StateFlow<Long> = _usedBytes

    // Opened once, on first use. It holds whatever the last run kept until
    // the saved size is read and applied.
    val cache: SimpleCache by lazy {
        SimpleCache(File(context.cacheDir, "media"), evictor, StandaloneDatabaseProvider(context))
    }

    init {
        scope.launch {
            settings.prefs.map { it.cacheSize }.distinctUntilChanged().collect { size ->
                if (size == CacheSize.Off) {
                    _enabled.value = false
                    clearNow()
                } else {
                    evictor.resize(cache, size.bytes)
                    _enabled.value = true
                }
                refreshUsed()
            }
        }
    }

    // Whether all of a song is saved under this name.
    fun isFullySaved(key: String): Boolean {
        if (!_enabled.value) return false
        val length = ContentMetadata.getContentLength(cache.getContentMetadata(key))
        return length > 0 && cache.isCached(key, 0, length)
    }

    // Whether any of a song is saved under this name.
    fun isPartlySaved(key: String): Boolean = _enabled.value && cache.getCachedSpans(key).isNotEmpty()

    // The names of every song saved whole.
    fun fullySavedKeys(): Set<String> = if (!_enabled.value) emptySet() else cache.keys.filterTo(HashSet(), ::isFullySaved)

    // The saved songs as picking a song's saved name sees them: see
    // savedCopyKey. Nothing is saved while songs are not kept.
    val copies: SavedCopies = object : SavedCopies {
        override fun has(key: String): Boolean = isPartlySaved(key)

        override fun length(key: String): Long = ContentMetadata.getContentLength(cache.getContentMetadata(key))

        override fun notedSize(key: String): Long? = cache.getContentMetadata(key).get(FILE_SIZE, -1L).takeIf { it > 0 }

        override fun note(key: String, size: Long) {
            try {
                cache.applyContentMetadataMutations(key, ContentMetadataMutations().set(FILE_SIZE, size))
            } catch (e: Cache.CacheException) {
                // Unnoted, the copy is checked again next time.
            }
        }

        override fun drop(key: String) {
            cache.removeResource(key)
            refreshUsed()
        }
    }

    // What each saved copy was made from, as the server answered for it:
    // its type, noted here, and its whole length, which the player notes.
    val shapes: StreamShapes = object : StreamShapes {
        override fun shape(key: String): StreamShape? {
            if (!_enabled.value) return null
            val metadata = cache.getContentMetadata(key)
            val type = metadata.get(FILE_TYPE, null as String?)
            val total = ContentMetadata.getContentLength(metadata).takeIf { it > 0 }
            return if (type == null && total == null) null else StreamShape(type, total)
        }

        override fun note(key: String, shape: StreamShape) {
            val type = shape.type ?: return
            if (!_enabled.value || cache.getContentMetadata(key).get(FILE_TYPE, null as String?) != null) return
            try {
                cache.applyContentMetadataMutations(key, ContentMetadataMutations().set(FILE_TYPE, type))
            } catch (e: Cache.CacheException) {
                // Unnoted, the next answer notes it.
            }
        }

        // The copy goes, and with it what it was made from, even while
        // another reader still holds a part of it open.
        override fun drop(key: String) {
            try {
                cache.applyContentMetadataMutations(key, ContentMetadataMutations().remove(FILE_TYPE).remove(ContentMetadata.KEY_CONTENT_LENGTH))
            } catch (e: Cache.CacheException) {
                // The copy going below leaves nothing to describe.
            }
            copies.drop(key)
        }
    }

    suspend fun clear() = withContext(Dispatchers.IO) {
        clearNow()
        refreshUsed()
    }

    fun refreshUsed() {
        _usedBytes.value = cache.cacheSpace
    }

    private fun clearNow() {
        cache.keys.toList().forEach { key -> cache.removeResource(key) }
    }
}

// The server's size for the file a saved song was made from.
private const val FILE_SIZE = "octo_file_size"

// The type the server answered with for the file a saved song was made from.
private const val FILE_TYPE = "octo_file_type"

// Lets the least recently played songs go once the store is over its size,
// and takes a new size at any time. Each size is a fresh least-recently-used
// evictor that is shown every saved piece, oldest first, so what it lets go
// is always the oldest. The store calls evictors while holding its own lock,
// so the swap takes that lock too.
@OptIn(UnstableApi::class)
private class ResizableEvictor : CacheEvictor {
    // Keeps everything until the saved size is known.
    @Volatile private var inner = LeastRecentlyUsedCacheEvictor(Long.MAX_VALUE)

    fun resize(cache: SimpleCache, bytes: Long) {
        synchronized(cache) {
            val next = LeastRecentlyUsedCacheEvictor(bytes)
            inner = next
            val spans = cache.keys.flatMap { cache.getCachedSpans(it) }.sortedBy { it.lastTouchTimestamp }
            spans.forEach { next.onSpanAdded(cache, it) }
        }
    }

    override fun requiresCacheSpanTouches(): Boolean = true

    override fun onCacheInitialized() = inner.onCacheInitialized()

    override fun onStartFile(cache: Cache, key: String, position: Long, length: Long) = inner.onStartFile(cache, key, position, length)

    override fun onSpanAdded(cache: Cache, span: CacheSpan) = inner.onSpanAdded(cache, span)

    override fun onSpanRemoved(cache: Cache, span: CacheSpan) = inner.onSpanRemoved(cache, span)

    override fun onSpanTouched(cache: Cache, oldSpan: CacheSpan, newSpan: CacheSpan) = inner.onSpanTouched(cache, oldSpan, newSpan)
}
