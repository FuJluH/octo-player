package app.winters.octo.playback

import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import androidx.annotation.OptIn
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackParameters
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import app.winters.octo.sound.TAP_LEVEL_HEARD_MS
import app.winters.octo.sound.DeckSound
import app.winters.octo.sound.DeckTransition
import app.winters.octo.sound.TapReading
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.roundToInt

// How often to check on the song: rarely while the end is far off, and
// every frame or so near it and during the blend.
private const val FAR_CHECK_MS = 1_000L
private const val NEAR_CHECK_MS = 40L

// The planner needs the end of the playing song and the start of the next
// once the song has played this long.
private const val SCOUT_AFTER_MS = 1_000L

// The song's body level from what has been heard counts once this much
// has been heard.
private const val LEVEL_HEARD_MS = TAP_LEVEL_HEARD_MS

// A little past that, so the second reading surely has it.
private const val REREAD_MARGIN_MS = 500L

// A tempo-matched song eases back to its own speed in steps this small.
private const val RATE_STEP = 0.0025

// Runs the transition between two decks. While a song plays it reads the
// end of it and the start of the next song, and plans where and how they
// meet (planTransition). Each comes from the server's transition profile of
// the song when the server has one (`profiles`), else from scouting it.
// Ahead of the blend it loads the spare deck with
// the same queue, the same shuffle order and the next song, parked where
// the next song's silent run-up starts. A little before the blend the spare
// plays, silent, and is lined up with the playing song by its position. At
// the blend the player hands over to the spare, while the old deck plays
// on until the plan ends it. Volume and filters are run by each deck's own
// sound processor, on that deck's song time, once armed with the plan;
// this only arms them. Anything the listener does mid-blend (skip, seek,
// pause, editing the queue) ends the blend at once.
@OptIn(UnstableApi::class)
internal class Crossfader(
    private val player: OctoPlayer,
    private var spare: ExoPlayer,
    private val soundOf: (ExoPlayer) -> DeckSound?,
    private val scout: Scout?,
    private val profiles: ProfileSource? = null,
    // Real lengths learned by playing, for a song whose listing was wrong.
    private val lengths: RealLengths = RealLengths(),
) : Player.Listener {
    // How transitions are planned; a longest blend of 0 turns them off.
    var settings = AutomixSettings(maxOverlapMs = 0)
        set(value) {
            if (field == value) return
            field = value
            interrupt()
        }

    // The longest blend, or 0 when crossfade is off.
    val fadeMs: Long get() = settings.maxOverlapMs

    private val handler = Handler(Looper.getMainLooper())
    private val check = Runnable { step() }

    // The queue position the spare is loaded with, if it is loaded, and the
    // plan it was loaded for.
    private var loadedFor = C.INDEX_UNSET
    private var loadedPlan: TransitionPlan? = null

    // The last next song that was not ready in time, so it is said once.
    private var notReadyFor: String? = null

    // The plan for the coming transition, and what it was made from.
    private var plan: TransitionPlan? = null
    private var planKey: PlanKey? = null

    // The silence gate the playing song was armed with, for an early fade.
    private var outgoingGate: Double? = null

    // The silent run-up: lining the spare up with the playing song.
    private var aligner: Aligner? = null
    private var alignment: Aligner.Step.Settled? = null

    // During the blend: the deck playing out the old song, and the plan.
    private var outgoing: ExoPlayer? = null
    private var blending: TransitionPlan? = null

    // A tempo-matched song easing back to its own speed.
    private var easing: Easing? = null

    // The scouted end of the playing song and start of the next.
    private var tail: Scouted? = null
    private var head: Scouted? = null
    private var reading: Reading? = null

    // Where the song was at the last check, to see it jump.
    private var lastPosition = -1L
    private var lastCheckAt = 0L

    private class Scouted(val entryId: String, var job: Scout.Job?) {
        var done = false
        var analysis: SectionAnalysis? = null

        // The server's profile of the song, when the analysis came from it.
        var profile: TransitionProfile? = null
    }

    private class Reading(val entryId: String, val job: Scout.Job?, val askedAtMs: Long) {
        var done = false
        var value: TapReading? = null

        // Read before its level counts, it is read again once the song has
        // played far enough for it to (`positionMs` in song time, at
        // `speed`), so the level gets used.
        fun wantsMore(positionMs: Long, speed: Float): Boolean =
            done && tapReadsAgain(value?.heardMs, askedAtMs, positionMs, speed, LEVEL_HEARD_MS + REREAD_MARGIN_MS)

        val levelHeard: Boolean get() = (value?.heardMs ?: 0L) >= LEVEL_HEARD_MS
    }

    private class Easing(val deck: ExoPlayer, val plan: TransitionPlan, val enteredAt: Long, var rate: Float, val after: PlaybackParameters)

    // Everything a plan depends on besides the clock. A change means a new plan.
    private data class PlanKey(
        val current: String?,
        val next: String?,
        val currentMs: Long,
        val nextMs: Long,
        val settings: AutomixSettings,
        val repeatOne: Boolean,
        val stopAtEnd: Boolean,
        val speed: Float,
        val skipSilence: Boolean,
        val tail: Boolean,
        val head: Boolean,
        val reading: Boolean,
        val levelHeard: Boolean,
    )

    override fun onIsPlayingChanged(isPlaying: Boolean) {
        if (isPlaying) {
            schedule(0)
        } else {
            val deck = player.deck
            if (outgoing != null && isRebuffering(deck.playWhenReady, deck.playbackState, deck.playbackSuppressionReason)) {
                // The incoming song is waiting for its sound: the blend goes
                // on once it has it, each deck on its own song time.
                schedule(NEAR_CHECK_MS)
                return
            }
            // A pause, a call or unplugged headphones: no half-finished blend.
            finishFade()
            dropRunUp()
            handler.removeCallbacks(check)
        }
    }

    override fun onMediaItemTransition(mediaItem: MediaItem?, reason: Int) {
        // The song changed some other way, so what the spare holds is stale.
        if (outgoing == null) {
            dropPlan()
            unloadSpare()
        }
    }

    // Called before anything that changes what plays or where.
    fun interrupt() {
        finishFade()
        stopEasing()
        dropPlan()
        unloadSpare()
        schedule(0)
    }

    fun release() {
        handler.removeCallbacks(check)
        finishFade()
        tail?.job?.cancel()
        head?.job?.cancel()
        reading?.job?.cancel()
        scout?.release()
        spare.release()
    }

    private fun step() {
        easeRate()
        if (outgoing != null) {
            blendStep()
            return
        }
        val deck = player.deck
        if (!deck.isPlaying) {
            lastPosition = -1
            // Briefly not playing while it loads after a seek: keep watching.
            // Truly paused: stop until playing starts again.
            if (deck.playWhenReady) schedule(NEAR_CHECK_MS)
            return
        }
        val next = deck.nextMediaItemIndex
        val current = deck.currentMediaItem
        if (fadeMs <= 0 || next == C.INDEX_UNSET || current == null) {
            dropPlan()
            unloadSpare()
            schedule(FAR_CHECK_MS)
            return
        }
        val position = deck.currentPosition
        val speed = deck.playbackParameters.speed
        if (jumped(position, speed)) {
            dropRunUp()
            dropPlan()
        }
        val songs = songsFor(deck, next) ?: run {
            schedule(FAR_CHECK_MS)
            return
        }
        val (currentSong, nextSong) = songs
        val repeatOne = deck.repeatMode == Player.REPEAT_MODE_ONE
        val stopAtEnd = deck.pauseAtEndOfMediaItems
        // In real time: at 1.5x speed the song's last 6 seconds pass in 4.
        val remaining = ((currentSong.durationMs - position) / speed).toLong()
        val plain = crossfadeLength(currentSong, nextSong, fadeMs, repeatOne, stopAtEnd)
        val waiting = plain == 0L && waitsOnLength(currentSong, nextSong, fadeMs, repeatOne, stopAtEnd)
        if (waiting) {
            // The next song's length is only known once it has opened, so
            // open it early on the spare and decide once it says.
            dropPlan()
            val lead = loadLeadMs(0, fadeMs, lengthKnown = false)
            if (loadedFor != next && remaining <= lead) load(next, null)
            schedule(if (remaining > lead + FAR_CHECK_MS) FAR_CHECK_MS else NEAR_CHECK_MS)
            return
        }
        if (plain == 0L) {
            // Played gaplessly, by the usual rules: nothing to plan.
            dropPlan()
            unloadSpare()
            schedule(FAR_CHECK_MS)
            return
        }
        if (aligner == null) {
            scoutAhead(deck, current, deck.getMediaItemAt(next), position, currentSong.durationMs)
            val key = keyFor(current, deck.getMediaItemAt(next), currentSong, nextSong, repeatOne, stopAtEnd, speed, deck.skipSilenceEnabled)
            if (key != planKey && readyToPlan(key, remaining)) {
                makePlan(deck, key, currentSong, nextSong, position, repeatOne, stopAtEnd, speed, deck.getMediaItemAt(next))
            }
        }
        val p = plan
        if (p == null) {
            // Waiting on the scouts; they call back as soon as they are done.
            schedule(if (remaining > fadeMs + PLAN_LOAD_LEAD_MS * 2) FAR_CHECK_MS else NEAR_CHECK_MS)
            return
        }
        if (p.kind == TransitionKind.GAPLESS) {
            unloadSpare()
            schedule(FAR_CHECK_MS)
            return
        }
        val toStart = ((p.startMs - position) / speed).toLong()
        if (loadedFor != next && toStart <= PLAN_LOAD_LEAD_MS) load(next, p)
        if (loadedFor == next && loadedPlan !== p) repark(p)
        if (loadedFor == next) {
            if (aligner == null && position >= p.preRollAtMs() - NEAR_CHECK_MS) {
                if (spare.playbackState == Player.STATE_READY) {
                    startRunUp(p, position)
                } else {
                    // The next song is not ready for its run-up: the playing
                    // song is left alone, and a later plan is made once it is.
                    val nextEntry = planKey?.next
                    if (notReadyFor != nextEntry) Log.i("Octo", "automix: the next song was not ready for its run-up")
                    notReadyFor = nextEntry
                    dropPlan()
                    schedule(NEAR_CHECK_MS)
                    return
                }
            }
            if (aligner != null) {
                if (position >= p.startMs) {
                    handOver(p)
                    schedule(NEAR_CHECK_MS)
                    return
                }
                runUp(p, position)
            }
        }
        schedule(if (toStart > PLAN_LOAD_LEAD_MS + FAR_CHECK_MS) FAR_CHECK_MS else NEAR_CHECK_MS)
    }

    // The playing song and the next one as the crossfade sees them, each by
    // its real length: what its deck measured once it holds the song, else
    // its listed length, corrected where playing it before found it wrong.
    // Null with nothing next.
    private fun songsFor(deck: ExoPlayer, next: Int): Pair<FadeSong, FadeSong>? {
        if (next == C.INDEX_UNSET) return null
        val current = deck.currentMediaItem ?: return null
        val item = deck.getMediaItemAt(next)
        return current.fadeSong(lengthOf(deck)) to item.fadeSong(nextLengthOf(item, next))
    }

    // How long the song is: what the deck measured, or the listed length
    // (corrected where playing it before found it wrong) for a stream that
    // has not said.
    private fun lengthOf(deck: ExoPlayer): Long {
        val item = deck.currentMediaItem ?: return 0
        return songLengthMs(lengths.lengthMs(item.mediaId, item.mediaMetadata.durationMs ?: 0), deck.duration)
    }

    // How long the next song is: what the spare measured once it holds that
    // song, else the listed length, corrected where it was found wrong.
    private fun nextLengthOf(item: MediaItem, index: Int): Long {
        val listed = lengths.lengthMs(item.mediaId, item.mediaMetadata.durationMs ?: 0)
        val spareMs = if (loadedFor == index && spare.currentMediaItem?.mediaId == item.mediaId) spare.duration else C.TIME_UNSET
        return nextSongLengthMs(listed, spareMs.takeIf { it != C.TIME_UNSET })
    }

    // Whether the song moved more than a plan can follow since the last check.
    private fun jumped(position: Long, speed: Float): Boolean {
        val now = SystemClock.elapsedRealtime()
        val expected = lastPosition + (now - lastCheckAt) * speed
        val moved = lastPosition >= 0 && abs(position - expected) > REPLAN_JUMP_MS
        lastPosition = position
        lastCheckAt = now
        return moved
    }

    // Reads the end of the playing song once it has played a second, and the
    // start of the next song as soon as it is known, each once per queue
    // entry: from the server's profile of the song when it has one, else by
    // scouting it.
    private fun scoutAhead(deck: ExoPlayer, current: MediaItem, next: MediaItem, position: Long, lengthMs: Long) {
        val scout = scout ?: return
        if (!settings.smart) return
        val currentEntry = current.entryId ?: current.mediaId
        if (tail?.entryId != currentEntry && position >= SCOUT_AFTER_MS && lengthMs >= SHORTEST_AUTOMIX_SONG_MS) {
            tail?.job?.cancel()
            val scouted = Scouted(currentEntry, null)
            tail = scouted
            withProfile(current, scouted, TransitionProfile::tailAnalysis) {
                val uri = current.localConfiguration?.uri
                if (uri == null) {
                    scouted.done = true
                } else {
                    lateinit var job: Scout.Job
                    job = scout.read(uri, max(0L, lengthMs - TAIL_SCOUT_MS), lengthMs, tailAnalyzer(current.mediaMetadata.tagBpm())) { analysis ->
                        if (tail === scouted && scouted.job === job) {
                            scouted.analysis = analysis
                            scouted.done = true
                            schedule(0)
                        }
                    }
                    scouted.job = job
                }
            }
        }
        val nextEntry = next.entryId ?: next.mediaId
        if (head?.entryId != nextEntry) {
            head?.job?.cancel()
            val scouted = Scouted(nextEntry, null)
            head = scouted
            withProfile(next, scouted, TransitionProfile::headAnalysis) {
                val uri = next.localConfiguration?.uri
                if (uri == null) {
                    scouted.done = true
                } else {
                    lateinit var job: Scout.Job
                    job = scout.read(uri, 0, HEAD_SCOUT_MS, headAnalyzer(next.mediaMetadata.tagBpm())) { analysis ->
                        if (head === scouted && scouted.job === job) {
                            scouted.analysis = analysis
                            scouted.done = true
                            schedule(0)
                        }
                    }
                    scouted.job = job
                }
            }
        }
        // Once both are in, what the deck has heard of this song; again
        // once its level has been heard long enough to count.
        val again = reading?.entryId == currentEntry && reading?.wantsMore(position, deck.playbackParameters.speed) == true
        if ((reading?.entryId != currentEntry || again) && tail?.done == true && head?.done == true) {
            val sound = soundOf(deck)
            val tagBpm = current.mediaMetadata.tagBpm()
            reading?.job?.cancel()
            lateinit var job: Scout.Job
            job = scout.run({ sound?.reading(currentEntry, tagBpm) }) { value ->
                if (reading?.job === job) {
                    reading?.value = value
                    reading?.done = true
                    schedule(0)
                }
            }
            reading = Reading(currentEntry, job, position)
        }
    }

    // Fills `scouted` from the server's profile of the song when it has one,
    // at once when it is already here; otherwise, or once the server says it
    // has none, runs `scoutIt`.
    private fun withProfile(item: MediaItem, scouted: Scouted, part: (TransitionProfile) -> SectionAnalysis, scoutIt: () -> Unit) {
        val source = profiles ?: return scoutIt()
        val fill = { profile: TransitionProfile ->
            scouted.profile = profile
            scouted.analysis = part(profile)
            scouted.done = true
        }
        val uri = item.localConfiguration?.uri?.toString()
        source.cached(uri)?.let { return fill(it) }
        if (!source.request(uri) { profile ->
                if (tail !== scouted && head !== scouted) return@request
                if (profile != null) fill(profile) else scoutIt()
                schedule(0)
            }
        ) {
            scoutIt()
        }
    }

    private fun keyFor(
        current: MediaItem,
        next: MediaItem,
        currentSong: FadeSong,
        nextSong: FadeSong,
        repeatOne: Boolean,
        stopAtEnd: Boolean,
        speed: Float,
        skipSilence: Boolean,
    ): PlanKey {
        val currentEntry = current.entryId ?: current.mediaId
        val nextEntry = next.entryId ?: next.mediaId
        return PlanKey(
            current = currentEntry,
            next = nextEntry,
            currentMs = currentSong.durationMs,
            nextMs = nextSong.durationMs,
            settings = settings,
            repeatOne = repeatOne,
            stopAtEnd = stopAtEnd,
            speed = speed,
            skipSilence = skipSilence,
            tail = tail?.entryId == currentEntry && tail?.done == true,
            head = head?.entryId == nextEntry && head?.done == true,
            reading = reading?.entryId == currentEntry && reading?.done == true,
            levelHeard = reading?.entryId == currentEntry && reading?.levelHeard == true,
        )
    }

    // A plan is made once everything it could use is in, or when there is
    // no more time to wait; plain crossfades need nothing.
    private fun readyToPlan(key: PlanKey, remaining: Long): Boolean {
        if (!settings.smart || scout == null) return true
        if (key.tail && key.head && key.reading) return true
        return remaining <= fadeMs + PLAN_LOAD_LEAD_MS + PRE_ROLL_MS + FAR_CHECK_MS
    }

    private fun makePlan(
        deck: ExoPlayer,
        key: PlanKey,
        currentSong: FadeSong,
        nextSong: FadeSong,
        position: Long,
        repeatOne: Boolean,
        stopAtEnd: Boolean,
        speed: Float,
        nextItem: MediaItem,
    ) {
        val heard = reading?.takeIf { it.entryId == key.current }?.value
        val served = tail?.takeIf { it.entryId == key.current }?.profile
        val (level, tempoPrior) = heardFor(served, heard?.takeIf { it.heardMs >= LEVEL_HEARD_MS }?.bodyLevelDb, heard?.tempoPrior)
        val context = TransitionContext(
            nowMs = position,
            playedMs = heard?.let { (it.heardMs * speed).toLong() } ?: position,
            repeatOne = repeatOne,
            stopAtEndOfSong = stopAtEnd,
            pace = speed.toDouble(),
            skipSilence = deck.skipSilenceEnabled,
            currentGenre = deck.currentMediaItem?.mediaMetadata?.genre?.toString(),
            nextGenre = nextItem.mediaMetadata.genre?.toString(),
            bodyLevelDb = level,
            tempoPrior = tempoPrior,
        )
        val tailAnalysis = tail?.takeIf { it.entryId == key.current }?.analysis
        val headAnalysis = head?.takeIf { it.entryId == key.next }?.analysis
        val made = planTransition(currentSong, nextSong, tailAnalysis, headAnalysis, settings.atSpeed(speed), context)
        planKey = key
        val sound = soundOf(deck)
        if (made.kind != TransitionKind.GAPLESS && sound?.shapesTransitions != true) {
            // The song's sound path was set up before crossfade came on, so
            // nothing can shape it: it plays out as it is.
            plan = planTransition(currentSong, nextSong, null, null, settings.copy(maxOverlapMs = 0), context)
            Log.i("Octo", "automix: this song started before crossfade was on, so it plays out")
            return
        }
        plan = made
        sound?.arm(null)
        if (made.kind == TransitionKind.GAPLESS) return
        // The playing song is armed once the next one is ready for its
        // run-up, so a late plan whose start has passed never fades it out
        // while the next song is still loading.
        outgoingGate = tailAnalysis?.let { analysis -> level?.let(analysis::withBodyLevel) ?: analysis }?.features?.gateDb
            ?: level?.let { max(SILENCE_FLOOR_DB, it - SILENCE_BELOW_BODY_DB) }
    }

    // The spare gets the same songs in the same shuffle order, parked
    // silently where the next song's run-up starts (the song's start when
    // there is no plan yet).
    private fun load(next: Int, plan: TransitionPlan?) {
        val deck = player.deck
        val from = plan?.preRollFromMs() ?: 0L
        spare.setMediaItems(List(deck.mediaItemCount, deck::getMediaItemAt), next, from)
        // The same kind of order too, so songs added after the blend still
        // land where they are asked for.
        spare.setShuffleOrder(QueueShuffleOrder(shuffleOrderOf(deck)))
        spare.shuffleModeEnabled = deck.shuffleModeEnabled
        spare.repeatMode = deck.repeatMode
        // The same pace, so the blend does not jump in speed or pitch; a
        // tempo-matched song gets its rate from the start of its run-up.
        spare.playbackParameters = pacedFor(plan, deck.playbackParameters)
        spare.skipSilenceEnabled = deck.skipSilenceEnabled
        spare.volume = 0f
        spare.playWhenReady = false
        armIncoming(plan, deck.getMediaItemAt(next))
        spare.prepare()
        loadedFor = next
        loadedPlan = plan
    }

    // A new plan for a song already loaded: armed again and moved to the
    // new run-up start, which also drops any sound it had worked out ahead
    // for the old plan.
    private fun repark(plan: TransitionPlan) {
        val item = spare.currentMediaItem ?: return
        armIncoming(plan, item)
        spare.playbackParameters = pacedFor(plan, player.deck.playbackParameters)
        // Parked there already, it is not moved: a move would make it load
        // again, and a plan made again while it loads would never find it ready.
        if (needsRepark(spare.currentPosition, plan.preRollFromMs())) spare.seekTo(plan.preRollFromMs())
        loadedPlan = plan
    }

    private fun pacedFor(plan: TransitionPlan?, pace: PlaybackParameters): PlaybackParameters {
        val rate = plan?.beatMatchRate ?: return pace
        return PlaybackParameters(rate.toFloat(), pace.pitch)
    }

    private fun armIncoming(plan: TransitionPlan?, item: MediaItem) {
        soundOf(spare)?.arm(plan?.let { DeckTransition(item.entryId, it, incoming = true) })
    }

    // The run-up: the spare plays, still silent, from where the next song
    // should be now.
    private fun startRunUp(plan: TransitionPlan, position: Long) {
        val entry = player.deck.currentMediaItem?.let { it.entryId ?: it.mediaId }
        soundOf(player.deck)?.arm(DeckTransition(entry, plan, incoming = false, gateDb = outgoingGate))
        val target = plan.incomingAtMs(position.toDouble()).toLong()
        if (target > spare.currentPosition + NEAR_CHECK_MS) spare.seekTo(target)
        spare.play()
        aligner = Aligner(plan)
        alignment = null
    }

    private fun runUp(plan: TransitionPlan, position: Long) {
        val aligner = aligner ?: return
        if (alignment != null) return
        when (val step = aligner.observe(SystemClock.elapsedRealtime(), position.toDouble(), spare.currentPosition.toDouble(), spare.isPlaying)) {
            is Aligner.Step.Seek -> spare.seekTo(step.toMs)
            is Aligner.Step.Settled -> settle(plan, step)
            Aligner.Step.Wait -> Unit
        }
    }

    // The decks are lined up as far as they will be. Too far apart for the
    // beat, the playing song's low-pass sweeps smoothly instead of in steps.
    private fun settle(plan: TransitionPlan, step: Aligner.Step.Settled) {
        alignment = step
        if (plan.barLocked && !step.locked) {
            val entry = player.deck.currentMediaItem?.let { it.entryId ?: it.mediaId }
            soundOf(player.deck)?.arm(DeckTransition(entry, plan, incoming = false, stepped = false, gateDb = outgoingGate))
        }
    }

    private fun handOver(plan: TransitionPlan) {
        val from = player.deck
        val into = spare
        val settled = alignment ?: aligner?.finish()?.also { settle(plan, it) }
        aligner = null
        // The old deck plays this song out, then stops instead of going on.
        from.pauseAtEndOfMediaItems = true
        outgoing = from
        blending = plan
        // Once the blend is over, the old deck is the spare for next time.
        spare = from
        loadedFor = C.INDEX_UNSET
        loadedPlan = null
        this.plan = null
        planKey = null
        val aligned = settled?.errorMs?.let { "aligned to ${it.roundToInt()} ms" + if (plan.barLocked && settled.locked) ", on the beat" else "" }
            ?: "alignment not measured"
        Log.i("Octo", "automix: ${plan.reason}; $aligned")
        plan.beatMatchRate?.let { easing = Easing(into, plan, SystemClock.elapsedRealtime(), it.toFloat(), from.playbackParameters) }
        player.handOver(into, from)
    }

    private fun blendStep() {
        val from = outgoing ?: return
        val plan = blending
        val over = plan == null || from.currentPosition >= plan.startMs + plan.overlapMs ||
            from.playbackState == Player.STATE_ENDED || !from.playWhenReady
        if (over) finishFade() else schedule(NEAR_CHECK_MS)
        if (outgoing == null) schedule(if (easing != null) NEAR_CHECK_MS else 0)
    }

    // Eases a tempo-matched song back to its own speed after the blend, in
    // small steps; the listener changing the speed ends it.
    private fun easeRate() {
        val ease = easing ?: return
        if (ease.deck !== player.deck || abs(ease.deck.playbackParameters.speed - ease.rate) > 1e-4) {
            easing = null
            return
        }
        val since = (SystemClock.elapsedRealtime() - ease.enteredAt).toDouble()
        val target = ease.plan.incomingRateAt(since)
        val done = target == 1.0
        if (done || abs(target - ease.rate) >= RATE_STEP) {
            ease.rate = if (done) ease.after.speed else target.toFloat()
            ease.deck.playbackParameters = PlaybackParameters(ease.rate, ease.after.pitch)
            if (done) easing = null
        }
    }

    private fun stopEasing() {
        val ease = easing ?: return
        easing = null
        if (ease.deck === player.deck) ease.deck.playbackParameters = ease.after
    }

    private fun finishFade() {
        val from = outgoing ?: return
        val plan = blending
        outgoing = null
        blending = null
        if (plan != null && plan.overlapMs > 0) {
            val progress = (from.currentPosition - plan.startMs).toFloat() / plan.overlapMs
            if (progress < 0.95f) Log.i("Octo", "automix: blend cut short at ${(progress.coerceIn(0f, 1f) * 100).toInt()}%")
        }
        soundOf(from)?.arm(null)
        from.stop()
        from.clearMediaItems()
        from.pauseAtEndOfMediaItems = false
        // The incoming song is past its part by now, or is cut short: either
        // way it plays on untouched.
        soundOf(player.deck)?.arm(null)
        player.endFade()
    }

    // Stops a run-up: the spare goes quiet and back to where it was parked.
    private fun dropRunUp() {
        if (aligner == null) return
        aligner = null
        alignment = null
        unloadSpare()
    }

    // Forgets the plan, and the playing deck's part in it.
    private fun dropPlan() {
        if (outgoing != null) return
        if (aligner != null) dropRunUp()
        if (plan != null) soundOf(player.deck)?.arm(null)
        plan = null
        planKey = null
    }

    private fun unloadSpare() {
        if (loadedFor == C.INDEX_UNSET) return
        loadedFor = C.INDEX_UNSET
        loadedPlan = null
        aligner = null
        alignment = null
        soundOf(spare)?.arm(null)
        spare.stop()
        spare.clearMediaItems()
    }

    private fun schedule(delayMs: Long) {
        handler.removeCallbacks(check)
        // A song easing back to its own speed is looked at often.
        handler.postDelayed(check, if (easing != null) minOf(delayMs, NEAR_CHECK_MS * 5) else delayMs)
    }
}

// The play order the deck is using right now, shuffle included.
internal fun shuffleOrderOf(player: Player): IntArray {
    val timeline = player.currentTimeline
    return buildList {
        var i = timeline.getFirstWindowIndex(true)
        while (i != C.INDEX_UNSET) {
            add(i)
            i = timeline.getNextWindowIndex(i, Player.REPEAT_MODE_OFF, true)
        }
    }.toIntArray()
}

private fun MediaItem.fadeSong(durationMs: Long): FadeSong {
    val extras = mediaMetadata.extras
    return FadeSong(
        albumId = extras?.getString(EXTRA_ALBUM_ID),
        albumOrder = extras?.getInt(EXTRA_ALBUM_ORDER, -1)?.takeIf { it >= 0 },
        durationMs = durationMs,
    )
}
