package app.winters.octo.desktop.lyrics

import androidx.compose.runtime.tooling.CompositionData
import androidx.compose.runtime.tooling.CompositionGroup
import app.winters.octo.lyrics.LyricLine
import app.winters.octo.lyrics.LyricWord
import app.winters.octo.lyrics.Lyrics
import app.winters.octo.lyrics.LyricsSource
import app.winters.octo.lyrics.engine.LyricEngine

private val Words = listOf(
    "Under", "the", "silver", "light", "we", "keep", "on", "running", "through", "the", "night", "again",
    "every", "little", "thing", "you", "said", "is", "ringing", "in", "my", "head", "tonight", "forever",
)

// Word-timed lyrics like a real song's: a line every few seconds, each word
// timed, a held last word on every fourth line (so its letters bloom), a
// translation under every sixth, and a long wait after the twelfth for the
// interlude dots.
internal fun madeUpLyrics(lines: Int = 48): Lyrics {
    var at = 2_000L
    val out = mutableListOf<LyricLine>()
    for (i in 0 until lines) {
        if (i == 12) at += 7_000
        val count = 5 + i % 3
        val parts = (0 until count).map { Words[(i * 5 + it) % Words.size] }
        val text = parts.joinToString(" ")
        val start = at
        var from = 0
        val words = parts.mapIndexed { k, word ->
            val length = if (k == count - 1 && i % 4 == 1) 1_400L else 380L
            val last = k == count - 1
            LyricWord(at, at + length, if (last) word else "$word ", from, from + word.length).also {
                at += length
                from += word.length + 1
            }
        }
        out += LyricLine(start, at, text, words, translation = if (i % 6 == 3) "A line in the listener's own language" else null)
        at += 600
    }
    return Lyrics(synced = true, lines = out, source = LyricsSource.Server)
}

// The flowing view's engine, found among what a composition remembers.
internal fun CompositionData.lyricEngine(): LyricEngine? {
    fun walk(group: CompositionGroup): LyricEngine? {
        group.data.forEach { if (it is LyricEngine) return it }
        group.compositionGroups.forEach { child -> walk(child)?.let { return it } }
        return null
    }
    compositionGroups.forEach { group -> walk(group)?.let { return it } }
    return null
}
