package app.winters.octo.player

// How the upright player shares its height, in dp. From the top: the album
// line, the artwork, then the song's blocks (its name, the progress or
// live bar, the play controls, the volume, the row of switches). The
// artwork sits a fixed margin under the album line and grows to the full
// width when there is room; whatever room is left over is shared between
// the gaps under it, by their weights, so a tall phone spreads everything
// out instead of piling the controls at the bottom. On a short phone every
// gap keeps its least and the artwork gives way first; when the artwork
// would be small, the volume line is left out (the phone's own buttons
// still set it), as on a short sideways screen.
//
// Song and live station blocks are the same heights (see PlayerOverlay), so
// switching between them keeps the artwork where it is.
data class PlayerRhythm(
    // The artwork's side.
    val art: Float,
    // The gap under the album line, then the gap under the artwork and
    // under each block shown, the last being the room left at the bottom.
    val gaps: List<Float>,
    // Whether the volume line shows.
    val volume: Boolean,
)

// The gap under the album line, which keeps the artwork near the top.
const val RHYTHM_TOP_GAP = 8f

// Each gap under the artwork and the blocks: its least, and its share of
// the room left over. The first is under the artwork, the last at the
// bottom.
private val GapLeast = listOf(20f, 4f, 4f, 4f, 8f, 16f)
private val GapWeight = listOf(3f, 1f, 1.5f, 1f, 1.5f, 2f)

// The artwork's least share of the width before the volume line gives up
// its room to it.
private const val ART_SHARE_FOR_VOLUME = 0.62f

// `blocks` are the heights of the song's name, the bar, the controls, the
// volume line and the switches, in that order; `volumeAt` is where the
// volume line is among them.
fun playerRhythm(height: Float, width: Float, header: Float, blocks: List<Float>, volumeAt: Int = 3): PlayerRhythm {
    fun layout(withVolume: Boolean): PlayerRhythm {
        val shown = blocks.filterIndexed { i, _ -> withVolume || i != volumeAt }
        val least = GapLeast.filterIndexed { i, _ -> withVolume || i != volumeAt + 1 }
        val weight = GapWeight.filterIndexed { i, _ -> withVolume || i != volumeAt + 1 }
        val fixed = header + RHYTHM_TOP_GAP + shown.sum() + least.sum()
        val art = (height - fixed).coerceIn(0f, width.coerceAtLeast(0f))
        val spare = (height - fixed - art).coerceAtLeast(0f)
        val total = weight.sum()
        val gaps = listOf(RHYTHM_TOP_GAP) + least.mapIndexed { i, it -> it + spare * weight[i] / total }
        return PlayerRhythm(art, gaps, withVolume)
    }
    val full = layout(withVolume = true)
    if (full.art >= width * ART_SHARE_FOR_VOLUME) return full
    val without = layout(withVolume = false)
    return if (without.art > full.art) without else full
}
