package app.winters.octo.animated

import android.content.Context
import android.media.MediaCodecList
import android.os.Handler
import androidx.annotation.OptIn
import androidx.core.net.toUri
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.database.StandaloneDatabaseProvider
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.cache.CacheDataSource
import androidx.media3.datasource.cache.LeastRecentlyUsedCacheEvictor
import androidx.media3.datasource.cache.SimpleCache
import androidx.media3.datasource.okhttp.OkHttpDataSource
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.Renderer
import androidx.media3.exoplayer.audio.AudioRendererEventListener
import androidx.media3.exoplayer.audio.AudioSink
import androidx.media3.exoplayer.hls.HlsMediaSource
import androidx.media3.exoplayer.mediacodec.MediaCodecSelector
import androidx.media3.exoplayer.source.MediaSource
import androidx.media3.exoplayer.source.ProgressiveMediaSource
import androidx.media3.exoplayer.trackselection.DefaultTrackSelector
import app.winters.octo.subsonic.AnimatedClip
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import okhttp3.OkHttpClient
import java.io.File
import javax.inject.Inject
import javax.inject.Singleton

// How much of the loops streamed from Apple or the server is kept on the
// phone, so each one is fetched once. A loop is a few MB.
private const val LOOP_CACHE_BYTES = 200L * 1024 * 1024

// How many picked versions are remembered, by clip and size.
private const val PICKS_KEPT = 64

// The video players for animated art, and what they play: a loop kept with
// a downloaded album as its file, or a streamed one as the single version
// of it that suits the space on screen, through a cache. They never make a
// sound, never ask for audio focus, and have nothing to do with the music
// player or its session.
@OptIn(UnstableApi::class)
@Singleton
class LoopPlayers @Inject constructor(
    @ApplicationContext private val context: Context,
    http: OkHttpClient,
) {
    private val fetcher = LoopFetcher(http)

    // The formats picked from: HEVC too where the phone decodes it in
    // hardware (Apple's H.264 stops short of a large screen's size).
    val codecs: Set<LoopCodec> by lazy { playableLoopCodecs() }

    private val cache: SimpleCache by lazy {
        SimpleCache(
            File(context.cacheDir, "animated-loops"),
            LeastRecentlyUsedCacheEvictor(LOOP_CACHE_BYTES),
            StandaloneDatabaseProvider(context),
        )
    }

    private val streamed by lazy {
        CacheDataSource.Factory()
            .setCache(cache)
            .setUpstreamDataSourceFactory(OkHttpDataSource.Factory(http))
            .setFlags(CacheDataSource.FLAG_IGNORE_CACHE_ON_ERROR)
    }

    // The version picked for each clip at each size, so a page opened again
    // starts at once.
    private val picks = object : LinkedHashMap<String, String>(16, 0.75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, String>?) = size > PICKS_KEPT
    }
    private val picking = Mutex()

    // A player for one loop: muted, looping, video only.
    fun create(): ExoPlayer {
        val selector = DefaultTrackSelector(context).apply {
            setParameters(buildUponParameters().setTrackTypeDisabled(C.TRACK_TYPE_AUDIO, true).setTrackTypeDisabled(C.TRACK_TYPE_TEXT, true))
        }
        return ExoPlayer.Builder(context, VideoOnlyRenderers(context))
            .setTrackSelector(selector)
            // Not the music's: no focus asked for, no pausing when headphones go.
            .setAudioAttributes(AudioAttributes.DEFAULT, false)
            .setHandleAudioBecomingNoisy(false)
            .setWakeMode(C.WAKE_MODE_NONE)
            .setUsePlatformDiagnostics(false)
            .build()
            .apply {
                volume = 0f
                repeatMode = Player.REPEAT_MODE_ONE
                playWhenReady = false
            }
    }

    // What plays `clip` in a space `width` by `height` pixels: its file
    // when it is kept on the phone, else the one version of it that suits
    // the space. Null when the clip cannot be read just now.
    suspend fun sourceFor(clip: AnimatedClip, width: Int, height: Int): MediaSource? {
        val address = clip.video.toUri()
        if (address.scheme == "file") {
            return ProgressiveMediaSource.Factory(DefaultDataSource.Factory(context)).createMediaSource(MediaItem.fromUri(address))
        }
        val key = "${clip.video}|${width}x$height"
        val variant = picking.withLock { picks[key] } ?: fetcher.pick(clip, width, height, codecs)?.url?.toString()?.also { url ->
            picking.withLock { picks[key] = url }
        } ?: return null
        val item = MediaItem.Builder().setUri(variant).setMimeType(MimeTypes.APPLICATION_M3U8).build()
        return HlsMediaSource.Factory(streamed).setAllowChunklessPreparation(true).createMediaSource(item)
    }
}

// H.264, and HEVC when a hardware decoder for it is on the phone.
fun playableLoopCodecs(): Set<LoopCodec> {
    val hevc = runCatching {
        MediaCodecList(MediaCodecList.REGULAR_CODECS).codecInfos.any { info ->
            !info.isEncoder && info.isHardwareAccelerated && info.supportedTypes.any { it.equals(MimeTypes.VIDEO_H265, ignoreCase = true) }
        }
    }.getOrDefault(false)
    return if (hevc) setOf(LoopCodec.Avc, LoopCodec.Hevc) else setOf(LoopCodec.Avc)
}

// Renderers for a loop: the video one only, so nothing it plays can reach
// the speakers.
@OptIn(UnstableApi::class)
private class VideoOnlyRenderers(context: Context) : DefaultRenderersFactory(context) {
    override fun buildAudioSink(context: Context, enableFloatOutput: Boolean, enableAudioOutputPlaybackParameters: Boolean): AudioSink? = null

    override fun buildAudioRenderers(
        context: Context,
        extensionRendererMode: Int,
        mediaCodecSelector: MediaCodecSelector,
        enableDecoderFallback: Boolean,
        audioSink: AudioSink,
        eventHandler: Handler,
        eventListener: AudioRendererEventListener,
        out: ArrayList<Renderer>,
    ) = Unit
}
