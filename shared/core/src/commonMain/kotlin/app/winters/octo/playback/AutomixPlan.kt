package app.winters.octo.playback

import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min

// Songs shorter than this get the plain crossfade, never a planned one.
const val SHORTEST_AUTOMIX_SONG_MS = 35_000L

// The shortest planned blend, and the longest that still counts as a cut.
const val SHORTEST_BLEND_MS = 1_800L
const val CUT_BLEND_MS = 2_400L

// The latest a blend may end: this long before the outgoing song's end.
const val END_MARGIN_MS = 250L

// The earliest a blend may start: this far into the song, this share of
// it, once the song has played long enough to count as played (half of it
// or COUNTS_AS_PLAYED_MS, whichever is less), and no more than
// LONGEST_EARLY_EXIT_MS before the latest end.
const val EARLIEST_START_MS = 30_000L
const val EARLIEST_START_SHARE = 0.5
const val COUNTS_AS_PLAYED_MS = 240_000L
const val LONGEST_EARLY_EXIT_MS = 45_000L

// The incoming song needs this long to get ready before the blend starts.
const val PRE_ROLL_MS = 3_000L

// Without a beat grid the start is tried every this many milliseconds.
const val START_STEP_MS = 250L

// The incoming song's entry moves onto a beat this close to its first sound.
const val ENTRY_SNAP_MS = 300.0

// Both songs play this much quieter through the overlap, so their sum
// does not clip.
const val OVERLAP_HEADROOM_DB = 1.0

// Songs in these genres get the plain crossfade, never a planned one.
val PLAIN_CROSSFADE_GENRES = Regex("classical|opera|spoken|audiobook|podcast|comedy", RegexOption.IGNORE_CASE)

// How the two songs meet.
enum class TransitionKind {
    // One song straight after the other, no overlap.
    GAPLESS,

    // The fixed crossfade at the end of the song.
    CROSSFADE,

    // A short planned swap.
    CUT,

    // A planned blend into a louder song.
    LIFT,

    // A planned blend.
    BLEND,
}

// What the player sets for planned transitions.
data class AutomixSettings(
    // The longest blend, from the crossfade slider; 0 turns crossfade off.
    val maxOverlapMs: Long,
    // Off plays the fixed crossfade at the end of each song.
    val smart: Boolean = true,
    val filterSweeps: Boolean = true,
    // Nudges the incoming song's speed to the outgoing song's tempo.
    val beatMatch: Boolean = false,
    // The shape of the fixed crossfade, with smart transitions off. Planned
    // blends keep their own curves.
    val fadeCurve: FadeCurve = FadeCurve.EqualPower,
)

// Where the player is when it plans, and what it knows besides the scouted
// sections. `nowMs` is the outgoing song's position and `playedMs` how
// much of it has actually been heard (less than nowMs after a seek
// forward). `bodyLevelDb` and `tempoPrior` come from a LiveTap of the
// outgoing song. A pace other than 1 or skip-silence moves media time
// away from the beat, so they turn off bar lock and tempo matching.
data class TransitionContext(
    val nowMs: Long = 0,
    val playedMs: Long = nowMs,
    val repeatOne: Boolean = false,
    val stopAtEndOfSong: Boolean = false,
    val pace: Double = 1.0,
    val skipSilence: Boolean = false,
    val currentGenre: String? = null,
    val nextGenre: String? = null,
    val bodyLevelDb: Double? = null,
    val tempoPrior: Double? = null,
)

// How to move from one song to the next. At startMs into the outgoing song
// the incoming song starts playing from entryMs, and over overlapMs the
// volumes follow automixOutGain / automixInGain with curve weight k (or,
// for a curve other than equal power, fadeOutGain / fadeInGain), both
// lowered by headroomDb. With a filterStrength above 0 the filter sweeps
// run through the overlap and are bypassed once it ends. beatMatchRate,
// when set, is the incoming song's playback rate through the blend.
// beatMs and beatAnchorMs, when set, are the outgoing song's beat length
// and one of its beats in song time: the blend is locked to the bar and the
// low-pass steps on the beat. `late` marks a blend placed at the end
// because there was no time or data to choose a better place. `reason`
// says why this plan was chosen.
data class TransitionPlan(
    val startMs: Long,
    val entryMs: Long,
    val overlapMs: Long,
    val kind: TransitionKind,
    val k: Double,
    val filterStrength: Double,
    val beatMatchRate: Double?,
    val beatMs: Double?,
    val beatAnchorMs: Double?,
    val late: Boolean,
    val headroomDb: Double,
    val reason: String,
    val curve: FadeCurve = FadeCurve.EqualPower,
) {
    val barLocked: Boolean get() = beatMs != null

    fun progressAt(outgoingMs: Double): Double =
        if (overlapMs <= 0) 1.0 else ((outgoingMs - startMs) / overlapMs).coerceIn(0.0, 1.0)

    fun outGain(t: Double): Double =
        if (curve == FadeCurve.EqualPower) automixOutGain(t, k) else fadeOutGain(curve, t, overlapMs.toDouble())

    fun inGain(t: Double): Double =
        if (curve == FadeCurve.EqualPower) automixInGain(t, k) else fadeInGain(curve, t, overlapMs.toDouble())

    // The outgoing song's beats inside the blend as places through it (0 to
    // 1). A beat within a twentieth of a beat of either end counts as the
    // end itself and is left out.
    fun beatProgress(): DoubleArray {
        val beat = beatMs ?: return DoubleArray(0)
        val anchor = beatAnchorMs ?: return DoubleArray(0)
        if (overlapMs <= 0 || beat <= 0) return DoubleArray(0)
        val grid = Tempo(60_000.0 / beat, TEMPO_CONFIDENT, 1.0, beat, anchor, anchor)
        val margin = beat / 20
        return grid.beatsBetween(startMs + margin, startMs + overlapMs - margin)
            .map { (it - startMs) / overlapMs }
            .toDoubleArray()
    }

    // The outgoing low-pass: stepped on the beat when the blend is locked
    // to the bar, gliding over an eighth of a bar.
    fun outgoingLowPassAt(t: Double): Double {
        val beat = beatMs
        if (beat == null || overlapMs <= 0) return outgoingLowPassHz(t, filterStrength)
        return steppedOutgoingLowPassHz(t, filterStrength, beatProgress(), beat * BEATS_PER_BAR / 8 / overlapMs)
    }

    fun outgoingHighPassAt(t: Double): Double = outgoingHighPassHz(t, filterStrength)

    fun incomingHighPassAt(t: Double): Double = incomingHighPassHz(t, filterStrength)

    // The incoming song's playback rate `sinceEntryMs` after it came in.
    fun incomingRateAt(sinceEntryMs: Double): Double =
        beatMatchRate?.let { beatMatchRateAt(it, sinceEntryMs, overlapMs.toDouble()) } ?: 1.0
}

// Plans the move from the playing song to the next one. `tail` is the
// analysis of the end of the playing song (analyzeTail) and `head` of the
// start of the next one (analyzeHead), either null when it is not ready.
// Every rule of crossfadeLength still holds: when it gives no crossfade the
// songs play gaplessly. With smart transitions off the plan is the
// equal-power crossfade (fixedCrossfadePlan); for a song under 35 s or in a
// genre that should not be mixed, the fixed crossfade with the plain curve.
// Only the crossfade with smart transitions off takes the settings'
// fadeCurve. Without the tail, or when no start is left at least PRE_ROLL_MS ahead,
// the plan is a late one: the blend at the end, with the curve and the
// filters but no bar lock.
fun planTransition(
    current: FadeSong,
    next: FadeSong?,
    tail: SectionAnalysis?,
    head: SectionAnalysis?,
    settings: AutomixSettings,
    context: TransitionContext = TransitionContext(),
): TransitionPlan {
    val plain = crossfadeLength(current, next, settings.maxOverlapMs, context.repeatOne, context.stopAtEndOfSong)
    if (plain == 0L || next == null) {
        return gaplessPlan(current, gaplessReason(current, next, settings.maxOverlapMs, context.repeatOne, context.stopAtEndOfSong))
    }
    val lenA = current.durationMs
    val lenB = next.durationMs
    if (!settings.smart) return fixedCrossfadePlan(lenA, plain, "smart transitions off", settings.fadeCurve)
    listOfNotNull(context.currentGenre, context.nextGenre).firstOrNull { PLAIN_CROSSFADE_GENRES.containsMatchIn(it) }?.let {
        return crossfadePlan(lenA, plain, "genre $it")
    }
    if (lenA < SHORTEST_AUTOMIX_SONG_MS || lenB < SHORTEST_AUTOMIX_SONG_MS) {
        return crossfadePlan(lenA, plain, "a song under ${SHORTEST_AUTOMIX_SONG_MS / 1000} s")
    }

    val limit = min(settings.maxOverlapMs.toDouble(), min(lenA, lenB) / 2.0)
    val sweeps = if (settings.filterSweeps) FILTER_STRENGTH else 0.0
    val headFeatures = head?.features?.takeIf { it.soundStartMs != null }
    val headEntry = headFeatures?.soundStartMs ?: 0L
    val canLock = context.pace == 1.0 && !context.skipSilence
    val fixedEnd = (lenA - END_MARGIN_MS).toDouble()

    if (tail == null) {
        return latePlan(lenA, fixedEnd, limit, context.nowMs, headEntry, null, head, sweeps, "no analysis of this song's end")
    }
    val measured = context.bodyLevelDb?.let(tail::withBodyLevel) ?: tail
    val a = measured.features
    val soundEndA = a.soundEndMs
    val outroA = a.outroStartMs
    if (soundEndA == null || outroA == null) {
        return latePlan(lenA, fixedEnd, limit, context.nowMs, headEntry, null, head, sweeps, "this song's end is silent")
    }

    val latestEnd = min(soundEndA, lenA - END_MARGIN_MS).toDouble()
    val outroStart = min(outroA.toDouble(), latestEnd)
    var tempoA = a.tempo?.takeIf { it.confident }
    val prior = context.tempoPrior
    if (tempoA != null && prior != null && prior > 0) {
        // The end must keep the tempo the whole song has.
        val moved = tempoA.inOctaveOf(prior)
        tempoA = if (abs(moved.bpm / prior - 1) <= 0.04) moved else null
    }
    val tempoB = headFeatures?.tempo?.takeIf { it.confident }
    val lockA = tempoA?.takeIf { canLock && tempoB != null }
    val lockB = tempoB?.takeIf { lockA != null }
    val ratio = if (lockA != null && lockB != null) foldTempoRatio(lockA.bpm / lockB.bpm) else null

    val soundStartB = headEntry.toDouble()
    var entry = soundStartB
    if (lockB != null) {
        val beat = lockB.nearestBeat(entry)
        if (abs(beat - entry) <= ENTRY_SNAP_MS) entry = max(0.0, beat)
    }

    var bars = 0
    var overlap = if (lockA != null && ratio != null) {
        bars = if (abs(ratio - 1) > 0.08) 2 else 4
        bars * lockA.barMs
    } else {
        latestEnd - outroStart
    }
    // The next song's quiet start plays under the end of this one, so the
    // blend lasts at least until the next song is near its full level.
    val quietStart = headFeatures?.introEndMs?.let { max(0.0, it - entry) } ?: 0.0
    val lengthened = quietStart > overlap
    if (lengthened) {
        if (lockA != null && bars > 0) {
            bars = ceil(quietStart / lockA.barMs - 1e-9).toInt()
            overlap = bars * lockA.barMs
        } else {
            overlap = quietStart
        }
    }
    overlap = min(max(overlap, SHORTEST_BLEND_MS.toDouble()), limit)
    if (lockA != null && bars > 0 && overlap < bars * lockA.barMs) {
        // Cut back to whole bars that fit, when that is still long enough.
        bars = floor(limit / lockA.barMs + 1e-9).toInt()
        val whole = bars * lockA.barMs
        if (bars >= 1 && whole >= SHORTEST_BLEND_MS) overlap = whole else bars = 0
    }
    overlap = floor(overlap + 0.5)

    // Where the song will count as played, at the current pace of listening.
    val countsAsPlayed = context.nowMs + max(0L, min(lenA / 2, COUNTS_AS_PLAYED_MS) - context.playedMs)
    val lo = maxOf(
        maxOf(EARLIEST_START_SHARE * lenA, EARLIEST_START_MS.toDouble(), countsAsPlayed.toDouble()),
        latestEnd - LONGEST_EARLY_EXIT_MS,
        tail.envelope.startMs.toDouble(),
        (context.nowMs + PRE_ROLL_MS).toDouble(),
    )
    val hi = latestEnd - overlap
    if (hi < lo) {
        return latePlan(lenA, latestEnd, overlap, context.nowMs, headEntry, measured, head, sweeps, "no start left before ${seconds(hi.toLong())}")
    }

    // Bar lines when the blend is locked to the bar, otherwise a fixed step
    // back from the latest start.
    val barLines = lockA?.barsBetween(lo, hi).orEmpty()
    val onBars = barLines.isNotEmpty()
    val candidates = barLines.ifEmpty {
        generateSequence(hi) { it - START_STEP_MS }.takeWhile { it >= lo - 1e-6 }.toList().asReversed()
    }
    val phraseAnchor = lockA?.let { it.downbeatMs + roundHalfUp((outroStart - it.downbeatMs) / it.barMs) * it.barMs }
    val fullDb = a.bodyDb - 3

    var bestStart = candidates.last()
    var bestScore = Double.NEGATIVE_INFINITY
    for (start in candidates) {
        var score = -0.08 * (latestEnd - (start + overlap)) / 1000
        if (outroStart < latestEnd - 1000) score -= 0.15 * abs(start - outroStart) / 1000
        if (a.boundariesMs.any { abs(it - start) <= 250 }) score += 1.0
        if (lockA != null && phraseAnchor != null && onBars) {
            score += 0.6
            val barsBack = roundHalfUp((phraseAnchor - start) / lockA.barMs).toLong()
            if (barsBack % 8 == 0L) score += 0.8
        }
        score -= 1.5 * measured.shareAtLeast(start, start + overlap, fullDb)
        if (score >= bestScore) {
            bestScore = score
            bestStart = start
        }
    }

    var rate: Double? = null
    if (settings.beatMatch && lockA != null && lockB != null && ratio != null) {
        val gap = abs(ratio - 1)
        if (gap >= 0.005 && gap <= 0.04) {
            rate = ratio.coerceIn(0.94, 1.06)
            entry = max(0.0, lockB.downbeatFrom(soundStartB - ENTRY_SNAP_MS))
        }
    }

    val kind = kindOf(overlap, measured, head, bestStart, entry)
    val start = floor(bestStart + 0.5).toLong()
    val entryMs = floor(entry + 0.5).toLong()
    val reason = buildString {
        append(kind.name.lowercase())
        append(" at ").append(seconds(start)).append(" over ").append(seconds(overlap.toLong()))
        if (bars > 0 && lockA != null) append(" (").append(bars).append(" bars of ").append(decimals(lockA.displayBpm, 1)).append(" BPM)")
        append(", next song from ").append(seconds(entryMs))
        if (lengthened) append(" (full from ").append(seconds((entry + quietStart).toLong())).append(")")
        append(", outro at ").append(seconds(outroStart.toLong()))
        append(", latest end ").append(seconds(latestEnd.toLong()))
        if (head == null) append(", no analysis of the next song's start")
        rate?.let { append(", rate ").append(decimals(it, 3)) }
    }
    return TransitionPlan(
        startMs = start,
        entryMs = entryMs,
        overlapMs = overlap.toLong(),
        kind = kind,
        k = curveOf(kind),
        filterStrength = sweeps,
        beatMatchRate = rate,
        beatMs = lockA?.beatMs,
        beatAnchorMs = lockA?.firstBeatMs,
        late = false,
        headroomDb = OVERLAP_HEADROOM_DB,
        reason = reason,
    )
}

// A tempo ratio folded by halving or doubling into 0.707 to 1.414, so a
// song at half or double the tempo counts as the same tempo.
fun foldTempoRatio(ratio: Double): Double {
    if (ratio <= 0) return ratio
    var r = ratio
    while (r > 1.4142135623730951) r /= 2
    while (r < 0.7071067811865476) r *= 2
    return r
}

// A cut for a short overlap; a lift when the next song's first 8 s are at
// least 3 dB louder than this song through the overlap; else a blend.
private fun kindOf(overlap: Double, tail: SectionAnalysis?, head: SectionAnalysis?, start: Double, entry: Double): TransitionKind = when {
    overlap <= CUT_BLEND_MS -> TransitionKind.CUT
    tail != null && head != null && head.levelDb(entry, entry + 8_000) >= tail.levelDb(start, start + overlap) + 3 -> TransitionKind.LIFT
    else -> TransitionKind.BLEND
}

private fun curveOf(kind: TransitionKind): Double = when (kind) {
    TransitionKind.CUT -> CUT_CURVE
    TransitionKind.LIFT -> LIFT_CURVE
    TransitionKind.BLEND -> BLEND_CURVE
    else -> CROSSFADE_CURVE
}

// The blend at the end: ending at latestEnd, over `overlap` or whatever is
// left after nowMs, with the curve and filters but no bar lock. Too little
// left to blend plays gaplessly.
private fun latePlan(
    lenA: Long,
    latestEnd: Double,
    overlap: Double,
    nowMs: Long,
    entryMs: Long,
    tail: SectionAnalysis?,
    head: SectionAnalysis?,
    sweeps: Double,
    why: String,
): TransitionPlan {
    val start = max(nowMs.toDouble(), latestEnd - overlap)
    val length = floor(latestEnd - start + 0.5)
    if (length < SHORTEST_FADE_MS) return gaplessPlan(FadeSong(null, null, lenA), "too late to blend: $why")
    val kind = kindOf(length, tail, head, start, entryMs.toDouble())
    val startMs = floor(start + 0.5).toLong()
    return TransitionPlan(
        startMs = startMs,
        entryMs = entryMs,
        overlapMs = length.toLong(),
        kind = kind,
        k = curveOf(kind),
        filterStrength = sweeps,
        beatMatchRate = null,
        beatMs = null,
        beatAnchorMs = null,
        late = true,
        headroomDb = OVERLAP_HEADROOM_DB,
        reason = "late ${kind.name.lowercase()} at ${seconds(startMs)} over ${seconds(length.toLong())}, next song from ${seconds(entryMs)}: $why",
    )
}

private fun gaplessPlan(current: FadeSong, reason: String) = TransitionPlan(
    startMs = max(0L, current.durationMs),
    entryMs = 0,
    overlapMs = 0,
    kind = TransitionKind.GAPLESS,
    k = CROSSFADE_CURVE,
    filterStrength = 0.0,
    beatMatchRate = null,
    beatMs = null,
    beatAnchorMs = null,
    late = false,
    headroomDb = 0.0,
    reason = "gapless: $reason",
)

// The crossfade at the end of the song, as it was before planned
// transitions: no curve weight and no filters. Equal power with no headroom
// unless `curve` picks another shape; mix only brings its own headroom.
fun fixedCrossfadePlan(lenA: Long, length: Long, why: String, curve: FadeCurve = FadeCurve.EqualPower): TransitionPlan {
    val start = max(0L, lenA - length)
    return TransitionPlan(
        startMs = start,
        entryMs = 0,
        overlapMs = length,
        kind = TransitionKind.CROSSFADE,
        k = 0.0,
        filterStrength = 0.0,
        beatMatchRate = null,
        beatMs = null,
        beatAnchorMs = null,
        late = false,
        headroomDb = fadeHeadroomDb(curve),
        reason = "crossfade at ${seconds(start)} over ${seconds(length)}: $why",
        curve = curve,
    )
}

private fun crossfadePlan(lenA: Long, length: Long, why: String) = TransitionPlan(
    startMs = lenA - length,
    entryMs = 0,
    overlapMs = length,
    kind = TransitionKind.CROSSFADE,
    k = CROSSFADE_CURVE,
    filterStrength = 0.0,
    beatMatchRate = null,
    beatMs = null,
    beatAnchorMs = null,
    late = false,
    headroomDb = OVERLAP_HEADROOM_DB,
    reason = "crossfade at ${seconds(lenA - length)} over ${seconds(length)}: $why",
)

private fun gaplessReason(current: FadeSong, next: FadeSong?, fadeMs: Long, repeatOne: Boolean, stopAtEndOfSong: Boolean): String = when {
    fadeMs <= 0 -> "crossfade off"
    next == null -> "nothing next"
    repeatOne -> "repeat one"
    stopAtEndOfSong -> "stopping at the end of the song"
    current.durationMs <= 0 || next.durationMs <= 0 -> "a song's length is unknown"
    current.albumId != null && current.albumId == next.albumId -> "the album plays in order"
    else -> "a song too short to blend"
}

// Milliseconds as seconds with two decimals, like "182.50 s".
private fun seconds(ms: Long): String {
    val sign = if (ms < 0) "-" else ""
    val abs = abs(ms)
    val hundredths = (abs % 1000) / 10
    return "$sign${abs / 1000}.${hundredths.toString().padStart(2, '0')} s"
}

// A positive number with a fixed count of decimals, like "120.0".
private fun decimals(x: Double, places: Int): String {
    var scale = 1L
    repeat(places) { scale *= 10 }
    val scaled = floor(x * scale + 0.5).toLong()
    return "${scaled / scale}.${(scaled % scale).toString().padStart(places, '0')}"
}
