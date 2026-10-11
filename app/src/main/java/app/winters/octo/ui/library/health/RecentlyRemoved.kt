package app.winters.octo.ui.library.health

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import app.winters.octo.data.LibraryFiles
import app.winters.octo.data.userMessage
import app.winters.octo.design.AccentButton
import app.winters.octo.design.ButtonSize
import app.winters.octo.design.OctoColors
import app.winters.octo.design.OctoType
import app.winters.octo.health.PUT_BACK
import app.winters.octo.health.RECENTLY_REMOVED
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.contentDescription
import app.winters.octo.health.restoreStep
import app.winters.octo.health.replacedText
import app.winters.octo.health.replacedSpoken
import app.winters.octo.health.countText
import app.winters.octo.health.goneText
import app.winters.octo.subsonic.LibraryTrash
import app.winters.octo.subsonic.SubsonicException
import app.winters.octo.subsonic.TrashedSong
import app.winters.octo.ui.common.BackButton
import app.winters.octo.ui.common.DetailTopGap
import app.winters.octo.ui.common.ScreenTitle
import dagger.hilt.android.lifecycle.HiltViewModel
import java.time.OffsetDateTime
import javax.inject.Inject
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.launch

// When the server deletes a song for good, from its "goneAt", or null when
// it keeps it until someone clears the trash or did not say.
fun goneAtMillis(text: String?): Long? =
    text?.takeIf(String::isNotBlank)?.let { runCatching { OffsetDateTime.parse(it).toInstant().toEpochMilli() }.getOrNull() }

// How long the server keeps a deleted song, in a sentence.
fun keepsFor(keepDays: Int): String =
    if (keepDays > 0) {
        "The server keeps a song deleted from disk for ${countText(keepDays, "day", "days")}, then deletes it for good."
    } else {
        "The server keeps a song deleted from disk until someone clears its trash."
    }

@HiltViewModel
class RecentlyRemovedViewModel @Inject constructor(private val files: LibraryFiles) : ViewModel() {
    // The server's trash; null until it answers.
    var trash by mutableStateOf<LibraryTrash?>(null)
        private set

    // Why the trash could not be read.
    var problem by mutableStateOf<String?>(null)
        private set

    val canRestore = files.actions

    // The server the trash shown is from: a song is put back there only.
    private var from: String? = null

    init {
        load()
        // Another server in use: its own trash is read instead.
        viewModelScope.launch {
            files.servers.drop(1).collect {
                trash = null
                problem = null
                load()
            }
        }
    }

    fun load() {
        viewModelScope.launch {
            val on = files.server()
            try {
                val read = files.trash()
                if (files.server() != on) return@launch
                from = on
                trash = read
                problem = null
            } catch (e: SubsonicException) {
                problem = "Could not read the server's trash. ${e.userMessage()}"
            }
        }
    }

    // Puts songs back in the library, then reads the trash again. How it
    // went is said in a line, with an Undo that deletes them again.
    fun putBack(songs: List<TrashedSong>) {
        if (songs.isEmpty()) return
        val ids = songs.mapTo(HashSet()) { it.id }
        trash = trash?.let { it.copy(songs = it.songs.filterNot { song -> song.id in ids }) }
        files.launch(songs.map { it.restoreStep() }, on = from) { _ ->
            load()
            false
        }
    }
}

// The songs deleted from the server's disk that are still in its trash,
// each with how long it has left and a way to put it back.
@Composable
fun RecentlyRemovedScreen(onBack: () -> Unit, vm: RecentlyRemovedViewModel = hiltViewModel()) {
    val actions by vm.canRestore.collectAsStateWithLifecycle()
    val canRestore = actions?.canRestore == true
    val now = remember { System.currentTimeMillis() }
    Box(Modifier.fillMaxSize()) {
        Column(Modifier.fillMaxSize().statusBarsPadding()) {
            Spacer(Modifier.height(DetailTopGap))
            ScreenTitle(RECENTLY_REMOVED)
            val trash = vm.trash
            val problem = vm.problem
            when {
                trash == null && problem != null -> Words(problem, muted = true)
                trash == null -> Loading()
                else -> LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(top = 4.dp, bottom = 140.dp)) {
                    item { Words(keepsFor(trash.keepDays), muted = true) }
                    if (trash.songs.isEmpty()) {
                        item { Words("Nothing is in the server's trash.", muted = true) }
                    } else if (canRestore && trash.songs.size > 1) {
                        item(key = "all") {
                            Row(Modifier.padding(start = 20.dp, end = 20.dp, top = 8.dp, bottom = 8.dp)) {
                                AccentButton("$PUT_BACK all", onClick = { vm.putBack(trash.songs) }, size = ButtonSize.Medium)
                            }
                        }
                    }
                    items(trash.songs) { song ->
                        TrashRow(song, goneText(goneAtMillis(song.goneAt), now), canRestore) { vm.putBack(listOf(song)) }
                    }
                }
            }
        }
        BackButton(onBack)
    }
}

@Composable
private fun TrashRow(song: TrashedSong, gone: String, canRestore: Boolean, onPutBack: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().heightIn(min = 60.dp).padding(start = 20.dp, end = 10.dp, top = 6.dp, bottom = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f)) {
            Text(song.title, style = OctoType.body, color = OctoColors.TextPrimary)
            val from = listOf(song.artist, song.album).filter(String::isNotBlank).joinToString(" • ")
            if (from.isNotEmpty()) Text(from, style = OctoType.caption, color = OctoColors.TextMuted)
            // A replaced song names both files: the one in the trash and the
            // one that took its place.
            if (song.replaced) {
                Text(
                    replacedText(song.was, song.now),
                    style = OctoType.caption,
                    color = OctoColors.TextSecondary,
                    modifier = Modifier.semantics { contentDescription = replacedSpoken(song.was, song.now) },
                )
            }
            Text(gone, style = OctoType.caption, color = OctoColors.TextMuted)
        }
        if (canRestore) RowButton(PUT_BACK, "$PUT_BACK ${song.title}", onPutBack)
    }
}
