package app.winters.octo.ui.common

import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import app.winters.octo.catalog.isFind
import app.winters.octo.design.Glaze
import app.winters.octo.design.OctoIcons
import app.winters.octo.discovery.AdoptedSongs
import app.winters.octo.discovery.DownloadPhase
import app.winters.octo.discovery.Downloads
import app.winters.octo.player.PlayerSettings
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import javax.inject.Inject
import kotlin.math.sqrt

// What TalkBack adds for artwork of something not in the library.
const val NotInLibraryText = "Not in your library"

// Songs found online that have since been downloaded into the library, so
// their artwork goes back to clean before the list around them refreshes.
val LocalAdoptedFinds = compositionLocalOf<Set<String>> { emptySet() }

// The same finds, each with the library song it became, so a find's row
// can turn into that song. Null until known.
val LocalAdoptions = compositionLocalOf<Map<String, String>?> { null }

// Where a find's row follows the library song it became.
val LocalAdoptedSongs = staticCompositionLocalOf<AdoptedSongs?> { null }

// Whether songs found online are left out everywhere ("Library songs
// only"), and how to switch it from a screen.
val LocalLibraryOnly = compositionLocalOf { false }
val LocalSetLibraryOnly = staticCompositionLocalOf<(Boolean) -> Unit> { {} }

@HiltViewModel
class AdoptedFindsViewModel @Inject constructor(
    downloads: Downloads,
    private val player: PlayerSettings,
    val songs: AdoptedSongs,
) : ViewModel() {
    // "Library songs only", for every screen.
    val libraryOnly: StateFlow<Boolean> = player.prefs
        .map { it.libraryOnly }
        .distinctUntilChanged()
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), false)

    fun setLibraryOnly(on: Boolean) {
        viewModelScope.launch { player.setLibraryOnly(on) }
    }

    val adopted: StateFlow<Set<String>> = downloads.phases
        .map(::adoptedFinds)
        .distinctUntilChanged()
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptySet())

    val adoptions: StateFlow<Map<String, String>?> = downloads.adoptions

    // Octo's own Reduce motion, beside the phone's.
    val reduceMotion: StateFlow<Boolean> = player.prefs
        .map { it.reduceMotion }
        .distinctUntilChanged()
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), false)
}

// Gives everything inside the songs found online that are now in the library.
@Composable
fun ProvideAdoptedFinds(vm: AdoptedFindsViewModel = hiltViewModel(), content: @Composable () -> Unit) {
    val adopted by vm.adopted.collectAsStateWithLifecycle()
    val adoptions by vm.adoptions.collectAsStateWithLifecycle()
    val appCalm by vm.reduceMotion.collectAsStateWithLifecycle()
    val libraryOnly by vm.libraryOnly.collectAsStateWithLifecycle()
    CompositionLocalProvider(
        LocalLibraryOnly provides libraryOnly,
        LocalSetLibraryOnly provides vm::setLibraryOnly,
        LocalAdoptedFinds provides adopted,
        LocalAdoptions provides adoptions,
        LocalAdoptedSongs provides vm.songs,
        LocalReduceMotion provides (appCalm || rememberSystemReduceMotion()),
        content = content,
    )
}

// The finds whose download has arrived in the library.
fun adoptedFinds(phases: Map<String, DownloadPhase>): Set<String> =
    phases.filterValues { it == DownloadPhase.Done }.keys.toSet()

// Whether a song is one found online and not in the library yet.
fun isOutsideLibrary(trackId: String?, adopted: Set<String>): Boolean =
    trackId != null && isFind(trackId) && trackId !in adopted

@Composable
fun isOutsideLibrary(trackId: String?): Boolean = isOutsideLibrary(trackId, LocalAdoptedFinds.current)

// How a song row says a song is not in the library: the add button at its
// end, the small plus on its artwork, or nothing. A row says it once, so a
// row with the button has no mark.
enum class AddSign { Button, Mark, None }

// In a list that offers the button, a find keeps it after it is added, so
// the check has its moment before the row turns into the library song.
// Elsewhere a find gets the mark until it is in the library.
fun rowAddSign(trackId: String, adopted: Set<String>, offersAdd: Boolean): AddSign = when {
    !isFind(trackId) -> AddSign.None
    offersAdd -> AddSign.Button
    trackId in adopted -> AddSign.None
    else -> AddSign.Mark
}

// Whether a row keeps an empty space where the add button would be, so its
// length lines up with the rows that have one. Only where the list gives its
// library songs that space (`librarySpace`): a list mixing them with finds
// does, search among them. A find's row that turned into its library song ends the same way.
fun rowKeepsAddSpace(sign: AddSign, librarySpace: Boolean): Boolean = librarySpace && sign != AddSign.Button

// What a song row has after its length: the add button, the button's space
// left empty, or what the list puts there (maybe nothing).
enum class RowEnd { AddButton, AddSpace, Trailing }

fun rowEnd(sign: AddSign, librarySpace: Boolean, hasTrailing: Boolean): RowEnd = when {
    sign == AddSign.Button -> RowEnd.AddButton
    !hasTrailing && rowKeepsAddSpace(sign, librarySpace) -> RowEnd.AddSpace
    else -> RowEnd.Trailing
}

// What TalkBack says for a picture, with the note for one not in the library.
fun artworkDescription(description: String?, outside: Boolean): String? = when {
    !outside -> description
    description.isNullOrEmpty() -> NotInLibraryText
    else -> "$description, ${NotInLibraryText.lowercase()}"
}

// The quiet line on an album page from the server, beside its add button,
// where the big cover carries no mark. Only for an album partly in the
// library: the button already says the rest is not.
fun albumLibraryNote(songs: Int, outside: Int): String? = when {
    outside <= 0 || outside >= songs -> null
    else -> "${songs - outside} of $songs in your library"
}

// The words for adding the songs of an album the library lacks, as the
// desktop says them.
fun addMissingLabel(count: Int): String = if (count == 1) "Add the missing song" else "Add the $count missing songs"

// How big the mark is for artwork of a given side: an eighth of it, never
// so small the plus blurs, nor big enough to crowd a large cover.
private const val MarkShare = 0.125f
private val MarkMin = 12.dp
private val MarkMax = 20.dp

fun notInLibraryMarkSize(art: Dp): Dp = (art * MarkShare).coerceIn(MarkMin, MarkMax)

// How far the mark sits in from the bottom and right edges. On a square
// cover, just clear of the rounded corner. On a round picture, along the
// diagonal, far enough in that the whole disc stays inside the circle.
fun notInLibraryMarkInset(art: Dp, mark: Dp, round: Boolean): Dp {
    val margin = (art * 0.04f).coerceAtLeast(3.dp)
    if (!round) return margin
    val radius = art / 2
    val centre = radius - (radius - margin - mark / 2) / sqrt(2f)
    return centre - mark / 2
}

// Dark enough under the plus to read on a white cover; the glass edge is
// what shows it on a dark one.
private val MarkFilm = Color.Black.copy(alpha = 0.42f)

// A small glass disc in the bottom right of the artwork, holding a thin
// plus: the same plus as the add button, quieter. It is only a sign; the
// card opens where the button is.
@Composable
internal fun BoxScope.NotInLibraryMark(art: Dp, round: Boolean) {
    val mark = notInLibraryMarkSize(art)
    val inset = notInLibraryMarkInset(art, mark, round)
    Glaze(
        Modifier.align(Alignment.BottomEnd).padding(end = inset, bottom = inset).size(mark),
        shape = CircleShape,
        film = MarkFilm,
    ) {
        Icon(
            painterResource(OctoIcons.NotInLibrary),
            contentDescription = null,
            tint = Color.White.copy(alpha = 0.9f),
            modifier = Modifier.size(mark * 0.68f),
        )
    }
}
