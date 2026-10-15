package app.winters.octo.playback

import androidx.media3.common.Player
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.roundToLong

// The next song starts playing silently this long (in the playing song's
// time) before it comes in, so the two can be lined up while nobody hears it.
const val PRE_ROLL_LEAD_MS = 2_500L

// The next song is loaded at least this long before the blend starts:
// songs from outside the library are slow to start.
const val PLAN_LOAD_LEAD_MS = 15_000L

// The decks are measured this long after the next one starts playing, and
// this long after it plays again following a correction.
const val ALIGN_FIRST_MS = 1_000L
const val ALIGN_AGAIN_MS = 400L

// An offset this small is left alone.
const val ALIGN_TOLERANCE_MS = 10.0

// The filters step on the beat only when the decks are lined up this closely.
const val BAR_LOCK_TOLERANCE_MS = 15.0

// Corrections tried before the blend goes ahead as it is.
const val ALIGN_MOST_SEEKS = 3

// A correction needs the next song to play for a while before the blend;
// with less than this left it is not tried.
const val ALIGN_LAST_CHANCE_MS = 400L

// A position that moves this far from where it should be means the plan
// no longer fits.
const val REPLAN_JUMP_MS = 2_000L

// Whether a deck that stopped playing is only waiting for its sound to
// arrive (a rebuffer), which a blend rides out, rather than paused by the
// listener or held back by a call.
fun isRebuffering(playWhenReady: Boolean, playbackState: Int, suppressionReason: Int): Boolean =
    playWhenReady && playbackState == Player.STATE_BUFFERING && suppressionReason == Player.PLAYBACK_SUPPRESSION_REASON_NONE

// The settings the planner gets at a playback speed: the longest blend is
// in song time, so at 1.5x speed an 8 s blend covers 12 s of the songs and
// still lasts 8 s, as on the desktop.
fun AutomixSettings.atSpeed(speed: Float): AutomixSettings =
    if (speed == 1f) this else copy(maxOverlapMs = (maxOverlapMs * speed.toDouble()).roundToLong())

// The playing song's level and tempo as the planner is told them: with the
// song's end from the server's profile, that end is already measured
// against the whole song, so no level goes with it, and its tempo is the
// whole song's from the profile, else what was heard.
fun heardFor(profile: TransitionProfile?, heardLevelDb: Double?, heardTempo: Double?): Pair<Double?, Double?> =
    if (profile == null) heardLevelDb to heardTempo else null to (profile.tempoPrior ?: heardTempo)

// Whether a tap reading taken at song time `askedAtMs`, having heard
// `heardMs` then (null when the tap was not on the song), is worth taking
// again at `positionMs` (song time, played at `speed`): only when it had
// heard less than `enoughMs` then and would have heard that much by now.
fun tapReadsAgain(heardMs: Long?, askedAtMs: Long, positionMs: Long, speed: Float, enoughMs: Long): Boolean {
    if (heardMs == null || heardMs >= enoughMs || speed <= 0f) return false
    return heardMs + ((positionMs - askedAtMs) / speed).toLong() >= enoughMs
}

// The incoming song's playback rate through the blend.
fun TransitionPlan.incomingRate(): Double = beatMatchRate ?: 1.0

// What a scouted end of a song and start of the next go through: the
// shared analysis, with the song's tag tempo picking its tempo's octave.
fun tailAnalyzer(tagBpm: Double?): (SectionEnvelope) -> SectionAnalysis = { analyzeTail(it, tagBpm) }

fun headAnalyzer(tagBpm: Double?): (SectionEnvelope) -> SectionAnalysis = { analyzeHead(it, tagBpm) }

// Whether a spare parked at `positionMs` must move to `targetMs`: not when
// it is there already, give or take a frame or two.
fun needsRepark(positionMs: Long, targetMs: Long): Boolean = abs(positionMs - targetMs) > PARK_TOLERANCE_MS

// A spare this close to where it should be parked is left there.
const val PARK_TOLERANCE_MS = 40L

// Where the incoming song starts its silent run-up.
fun TransitionPlan.preRollFromMs(): Long =
    if (overlapMs <= 0) 0 else max(0L, entryMs - (PRE_ROLL_LEAD_MS * incomingRate()).toLong())

// Where in the playing song the incoming song starts its run-up.
fun TransitionPlan.preRollAtMs(): Double = startMs - (entryMs - preRollFromMs()) / incomingRate()

// Where the incoming song should be when the playing song is at `outgoingMs`.
fun TransitionPlan.incomingAtMs(outgoingMs: Double): Double = entryMs + (outgoingMs - startMs) * incomingRate()

// How far the incoming song runs ahead of where it should be, in the
// playing song's time: negative when it is behind.
fun TransitionPlan.alignmentErrorMs(outgoingMs: Double, incomingMs: Double): Double =
    (incomingMs - entryMs) / incomingRate() - (outgoingMs - startMs)

// Lines the incoming song up with the playing one during its silent
// run-up. It is told the two positions as they come and answers what to
// do: wait, move the incoming song to a position (it is still silent), or
// go ahead with the offset it ended on. A deck that is moved stops and
// starts again, which itself costs a little time; the lag seen after each
// move is added to the next.
class Aligner(private val plan: TransitionPlan) {
    sealed interface Step {
        data object Wait : Step

        data class Seek(val toMs: Long) : Step

        // `errorMs` is the offset at the last measure, null if none was
        // made; `locked` says whether it is close enough to step on the beat.
        data class Settled(val errorMs: Double?, val locked: Boolean) : Step
    }

    private var playingSince: Long? = null
    private var seeks = 0
    private var lag = 0.0
    private var lastError: Double? = null
    private var settled: Step.Settled? = null

    // `nowMs` is a clock in real milliseconds; `outgoingMs` and
    // `incomingMs` are the two songs' positions read at that moment.
    fun observe(nowMs: Long, outgoingMs: Double, incomingMs: Double, incomingPlaying: Boolean): Step {
        settled?.let { return it }
        // Time left before the blend, in the playing song's time.
        val left = plan.startMs - outgoingMs
        if (!incomingPlaying) {
            playingSince = null
            return if (left <= 0) settle() else Step.Wait
        }
        val since = playingSince ?: nowMs.also { playingSince = it }
        val wait = if (seeks == 0) ALIGN_FIRST_MS else ALIGN_AGAIN_MS
        if (nowMs - since < wait) {
            return if (left <= 0) settle() else Step.Wait
        }
        val error = plan.alignmentErrorMs(outgoingMs, incomingMs)
        if (seeks > 0) lag -= error
        lastError = error
        if (abs(error) <= ALIGN_TOLERANCE_MS || seeks >= ALIGN_MOST_SEEKS || left < ALIGN_LAST_CHANCE_MS) return settle()
        seeks++
        playingSince = null
        // Where it should be now, plus the time a move is seen to cost.
        val target = plan.incomingAtMs(outgoingMs + lag)
        return Step.Seek(target.toLong().coerceAtLeast(0))
    }

    // Goes ahead with whatever was measured last; the blend is starting.
    fun finish(): Step.Settled = settled ?: settle()

    private fun settle(): Step.Settled {
        val error = lastError
        return Step.Settled(error, error != null && abs(error) < BAR_LOCK_TOLERANCE_MS).also { settled = it }
    }
}
