package app.winters.octo.playback

import android.content.Context
import android.media.AudioAttributes as PlatformAudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.Handler
import android.os.Looper
import androidx.annotation.OptIn
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.ForwardingSimpleBasePlayer
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackParameters
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.RenderersFactory
import androidx.media3.exoplayer.source.MediaSource
import app.winters.octo.sound.DeckSound
import com.google.common.util.concurrent.Futures
import com.google.common.util.concurrent.ListenableFuture

// One engine that plays audio. Crossfade runs two of these; audio focus is
// handled above them, so each deck ignores it. `sources` opens both phone
// files and streams, `renderers` puts Octo's sound shaping in the audio
// path, and both decks play in one audio session, so an equalizer app
// attached to it hears both. `loads` decides when a stream has enough to
// start.
@OptIn(UnstableApi::class)
fun buildDeck(context: Context, sources: MediaSource.Factory, renderers: RenderersFactory, audioSessionId: Int, loads: OctoLoadControl): ExoPlayer =
    ExoPlayer.Builder(context, renderers, sources)
        .setLoadControl(loads)
        .setAudioAttributes(
            AudioAttributes.Builder()
                .setUsage(C.USAGE_MEDIA)
                .setContentType(C.AUDIO_CONTENT_TYPE_MUSIC)
                .build(),
            /* handleAudioFocus = */ false,
        )
        .setHandleAudioBecomingNoisy(true)
        .setWakeMode(C.WAKE_MODE_LOCAL)
        .build()
        .also { if (audioSessionId != C.AUDIO_SESSION_ID_UNSET) it.audioSessionId = audioSessionId }

// Asks the phone for the right to play, and hears when a call, a
// navigation prompt or another app wants it back.
class AudioFocus(context: Context, private val onChange: (Int) -> Unit) {
    private val audio = context.getSystemService(AudioManager::class.java)
    private val request = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
        .setAudioAttributes(
            PlatformAudioAttributes.Builder()
                .setUsage(PlatformAudioAttributes.USAGE_MEDIA)
                .setContentType(PlatformAudioAttributes.CONTENT_TYPE_MUSIC)
                .build(),
        )
        .setOnAudioFocusChangeListener({ onChange(it) }, Handler(Looper.getMainLooper()))
        .build()
    private var held = false

    fun request(): Boolean {
        if (!held) held = audio.requestAudioFocus(request) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
        return held
    }

    fun abandon() {
        if (held) audio.abandonAudioFocusRequest(request)
        held = false
    }
}

private const val DUCKED_VOLUME = 0.2f

// Whether a replacement keeps every item (by id and queue entry) where it
// was, so only its words change.
internal fun wordsOnly(before: List<Pair<String, String?>>, after: List<Pair<String, String?>>): Boolean =
    before.isNotEmpty() && before == after && after.all { it.second != null }

// The one player the rest of the phone sees: the lock screen, the
// notification, headphones and the app all talk to this. It forwards to the
// deck that is playing, and hands over to the other deck for a crossfade
// without anything outside noticing. It also owns audio focus.
//
// `soundOf` gives each deck's sound processor, which runs a transition's
// volume and filters; `scout` reads ahead in songs to plan transitions, and
// `profiles` gives the server's transition profiles of songs in its place.
@OptIn(UnstableApi::class)
class OctoPlayer(
    context: Context,
    initial: ExoPlayer,
    spare: ExoPlayer,
    soundOf: (ExoPlayer) -> DeckSound? = { null },
    scout: Scout? = null,
    profiles: ProfileSource? = null,
    lengths: RealLengths = RealLengths(),
) : ForwardingSimpleBasePlayer(initial), SleepTarget, EditableQueue {
    var deck: ExoPlayer = initial
        private set

    private var ducked = false

    // During a crossfade: the deck playing out the old song.
    private var outgoing: ExoPlayer? = null

    private val fader = Crossfader(this, spare, soundOf, scout, profiles, lengths).also(::addListener)

    // Both decks, whichever is playing, so speed and skipping silence can be
    // set on each and a crossfade hands over at the same pace.
    private val decks = listOf(initial, spare)

    // The next queue entry id to give out.
    private var nextEntry = 0L

    init {
        // Songs put into a shuffled queue land where they were asked for,
        // never at random.
        decks.forEach { it.setShuffleOrder(QueueShuffleOrder(IntArray(0))) }
    }

    // Whether a crossfade is under way, so a song change now is the song
    // ending on its own.
    override val isBlending: Boolean get() = outgoing != null

    override val currentKey: String? get() = currentMediaItem?.entryId

    override fun hasEntry(key: String): Boolean = (0 until mediaItemCount).any { getMediaItemAt(it).entryId == key }

    // How transitions between songs are made: the longest blend (0 for
    // none) and how it is planned.
    var automix: AutomixSettings
        get() = fader.settings
        set(value) {
            fader.settings = value
        }

    // The longest blend, or 0 for none.
    val crossfadeMs: Long get() = fader.fadeMs

    // Skips quiet stretches inside songs, on both decks.
    var skipSilence: Boolean
        get() = deck.skipSilenceEnabled
        set(value) {
            decks.forEach { it.skipSilenceEnabled = value }
        }

    override var sleepFade = 1f
        set(value) {
            field = value
            applyVolume()
        }

    override var pauseAtEndOfSong: Boolean
        get() = deck.pauseAtEndOfMediaItems
        set(value) {
            deck.pauseAtEndOfMediaItems = value
        }

    private var resumeWhenFocusReturns = false
    private val focus: AudioFocus = AudioFocus(context) { change ->
        when (change) {
            AudioManager.AUDIOFOCUS_LOSS -> {
                // Another app is playing now; stay paused.
                resumeWhenFocusReturns = false
                pause()
                releaseFocus()
            }
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT -> {
                // A call or a short interruption: pause, and come back after.
                resumeWhenFocusReturns = isPlaying || resumeWhenFocusReturns
                deck.pause()
            }
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> duck(true)
            AudioManager.AUDIOFOCUS_GAIN -> {
                duck(false)
                if (resumeWhenFocusReturns) {
                    // A station comes back live, not from where it paused.
                    if (onStation) rejoin()
                    deck.play()
                }
                resumeWhenFocusReturns = false
            }
        }
    }

    // Playing needs focus; if the phone says no (a call is on), stay paused.
    override fun handleSetPlayWhenReady(playWhenReady: Boolean): ListenableFuture<*> {
        if (playWhenReady && !focus.request()) return Futures.immediateVoidFuture()
        if (!playWhenReady) {
            resumeWhenFocusReturns = false
            fader.interrupt()
        }
        if (onStation) {
            // A station has no pause: it stops, and lets the stream go.
            if (!playWhenReady) {
                deck.pause()
                deck.stop()
                releaseFocus()
                return Futures.immediateVoidFuture()
            }
            // Play joins what is on air now. Audio held from before a pause
            // (headphones pulled out, say) or a stopped stream is let go and
            // the stream opened afresh; one just opened plays as it is.
            if (!deck.playWhenReady && deck.playbackState != Player.STATE_BUFFERING) rejoin()
        }
        return super.handleSetPlayWhenReady(playWhenReady)
    }

    // A stopped station opens at the live edge, never where it stopped.
    override fun handlePrepare(): ListenableFuture<*> {
        if (onStation && deck.playbackState == Player.STATE_IDLE) deck.seekToDefaultPosition()
        return super.handlePrepare()
    }

    // Whether a live station is on.
    private val onStation: Boolean get() = deck.currentMediaItem?.mediaId?.let(::isRadio) == true

    // Opens the station's stream afresh, at the live edge.
    private fun rejoin() {
        if (deck.playbackState != Player.STATE_IDLE) deck.stop()
        deck.seekToDefaultPosition()
        deck.prepare()
    }

    // Anything that changes what plays or where ends a blend first, so the
    // old song never keeps sounding under the new choice.
    override fun handleSeek(mediaItemIndex: Int, positionMs: Long, seekCommand: Int): ListenableFuture<*> {
        fader.interrupt()
        return super.handleSeek(mediaItemIndex, positionMs, seekCommand)
    }

    override fun handleSetMediaItems(mediaItems: List<MediaItem>, startIndex: Int, startPositionMs: Long): ListenableFuture<*> {
        fader.interrupt()
        return super.handleSetMediaItems(stamped(mediaItems), startIndex, startPositionMs)
    }

    // Songs the listener adds at the end go before any Autoplay songs still
    // to come, since those only fill in once the listener's own run out.
    // Under shuffle, added songs take their place in the play order by the
    // rules in ShuffleQueue.kt instead of a random one.
    override fun handleAddMediaItems(index: Int, mediaItems: List<MediaItem>): ListenableFuture<*> {
        fader.interrupt()
        val size = deck.mediaItemCount
        if (size == 0 || mediaItems.isEmpty()) return super.handleAddMediaItems(index, stamped(mediaItems))
        val order = shuffleOrderOf(deck)
        val current = deck.currentMediaItemIndex
        val autoplay = List(size) { deck.getMediaItemAt(it).isAutoplay }
        val adding = mediaItems.all { it.isAutoplay }
        val next = playingNext
        val at = if (adding || next) index else ownSongsAt(index, upcoming(deck), autoplay)
        val beforeAutoplay = !adding && autoplay.getOrElse(at) { false }
        val rank = shuffleRankFor(order, at, size, current, playNext = next, beforeAutoplay = beforeAutoplay)
        val result = super.handleAddMediaItems(at, stamped(mediaItems))
        if (deck.mediaItemCount == size + mediaItems.size) {
            deck.setShuffleOrder(QueueShuffleOrder(insertIntoShuffle(order, at, mediaItems.size, rank)))
        }
        return result
    }

    // "Play next": the songs go right after the song that is on, in the
    // queue and, under shuffle, in the play order too. Told apart from "Add
    // to queue", since both add at the end while the last song is on.
    private var playingNext = false

    override fun addNext(items: List<MediaItem>) {
        if (items.isEmpty()) return
        playingNext = true
        try {
            addMediaItems((currentMediaItemIndex + 1).coerceAtMost(mediaItemCount), items)
        } finally {
            playingNext = false
        }
    }

    // Sets the play order for shuffle, as saved or as it was before an edit.
    override fun setPlayOrder(order: IntArray) {
        if (order.size == deck.mediaItemCount) deck.setShuffleOrder(QueueShuffleOrder(order))
    }

    // Puts songs back where they were, exactly, entry ids and all, for an
    // undo. `runs` are queue positions and the songs that go there, lowest
    // first; `order` is the play order once they are all back.
    override fun putBack(runs: List<Pair<Int, List<MediaItem>>>, order: IntArray) {
        fader.interrupt()
        runs.forEach { (at, items) -> deck.addMediaItems(at, items) }
        setPlayOrder(order)
    }

    // Takes out runs of songs, last run first. The rest keep their play order.
    override fun removeRuns(runs: List<IntRange>) {
        fader.interrupt()
        runs.forEach { deck.removeMediaItems(it.first, it.last + 1) }
    }

    // Each song gets a queue entry id as it goes in, unless it has one.
    private fun stamped(items: List<MediaItem>): List<MediaItem> =
        items.map { if (it.entryId != null) it else it.withEntry("q:${nextEntry++}") }

    override fun handleRemoveMediaItems(fromIndex: Int, toIndex: Int): ListenableFuture<*> {
        fader.interrupt()
        return super.handleRemoveMediaItems(fromIndex, toIndex)
    }

    override fun handleMoveMediaItems(fromIndex: Int, toIndex: Int, newIndex: Int): ListenableFuture<*> {
        fader.interrupt()
        return super.handleMoveMediaItems(fromIndex, toIndex, newIndex)
    }

    // Items put back with new words only (a station's song title, say) are
    // the same items in the same places: a blend under way goes on.
    override fun handleReplaceMediaItems(fromIndex: Int, toIndex: Int, mediaItems: List<MediaItem>): ListenableFuture<*> {
        val before = (fromIndex until toIndex.coerceAtMost(deck.mediaItemCount)).map { deck.getMediaItemAt(it).let { item -> item.mediaId to item.entryId } }
        if (!wordsOnly(before, mediaItems.map { it.mediaId to it.entryId })) fader.interrupt()
        return super.handleReplaceMediaItems(fromIndex, toIndex, stamped(mediaItems))
    }

    override fun handleSetShuffleModeEnabled(shuffleModeEnabled: Boolean): ListenableFuture<*> {
        fader.interrupt()
        return super.handleSetShuffleModeEnabled(shuffleModeEnabled)
    }

    override fun handleSetRepeatMode(repeatMode: Int): ListenableFuture<*> {
        fader.interrupt()
        return super.handleSetRepeatMode(repeatMode)
    }

    // Speed and pitch go to both decks, so the next song in a crossfade
    // starts at the same pace as the one playing out.
    override fun handleSetPlaybackParameters(playbackParameters: PlaybackParameters): ListenableFuture<*> {
        decks.forEach { it.playbackParameters = playbackParameters }
        return Futures.immediateVoidFuture()
    }

    override fun handleStop(): ListenableFuture<*> {
        fader.interrupt()
        releaseFocus()
        return super.handleStop()
    }

    override fun handleRelease(): ListenableFuture<*> {
        fader.release()
        releaseFocus()
        return super.handleRelease()
    }

    // The blend begins: the incoming deck (already playing, its processor
    // holding it silent until its entry) becomes the one everything talks
    // to, while the outgoing one keeps sounding. Their processors run the
    // volumes from here; the decks' own volume only carries ducking and the
    // sleep timer's fade.
    internal fun handOver(into: ExoPlayer, from: ExoPlayer) {
        outgoing = from
        deck = into
        applyVolume()
        if (!into.playWhenReady) into.play()
        setPlayer(into)
    }

    internal fun endFade() {
        outgoing = null
        applyVolume()
    }

    private fun duck(on: Boolean) {
        ducked = on
        applyVolume()
    }

    // The one place the playing decks' volume is set, so ducking and the
    // sleep timer's fade multiply instead of undoing each other. A spare
    // running up to a blend stays at 0 until it is handed over.
    private fun applyVolume() {
        val level = (if (ducked) DUCKED_VOLUME else 1f) * sleepFade
        deck.volume = level
        outgoing?.volume = level
    }

    private fun releaseFocus(): Unit = focus.abandon()
}
