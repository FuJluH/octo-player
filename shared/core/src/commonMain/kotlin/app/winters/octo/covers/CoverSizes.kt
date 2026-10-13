package app.winters.octo.covers

// Covers are fetched at one of these sizes, in pixels, so one download
// serves every size up to it.
val CoverBuckets: List<Int> = listOf(150, 300, 600, 1200)

// The size a cover wanted `px` wide is fetched at: the smallest bucket at
// least that big, or the largest.
fun coverBucket(px: Int): Int = CoverBuckets.firstOrNull { it >= px } ?: CoverBuckets.last()

// The size the covers the player shows now and next are fetched at: the
// largest, which the player's card asks for, so every smaller ask for the
// same cover (the mini bar, the lyrics bar, the background, the system's
// player, a widget) is answered from that one copy.
val AheadCoverBucket: Int = CoverBuckets.last()

// The kept sizes that answer an ask for a cover at `px`, best first: its
// own bucket, then the larger ones from the smallest up, which shrink to
// it. With `anySize`, for a picture to show while the asked size comes,
// the smaller ones follow, from the largest down.
fun keptCoverOrder(px: Int, anySize: Boolean = false): List<Int> {
    val bucket = coverBucket(px)
    val larger = CoverBuckets.filter { it >= bucket }
    return if (anySize) larger + CoverBuckets.filter { it < bucket }.reversed() else larger
}

// The first size in `keptCoverOrder` that `kept` says is kept, or null when
// none is and the cover must be fetched.
fun keptCoverSize(px: Int, anySize: Boolean = false, kept: (Int) -> Boolean): Int? =
    keptCoverOrder(px, anySize).firstOrNull(kept)
