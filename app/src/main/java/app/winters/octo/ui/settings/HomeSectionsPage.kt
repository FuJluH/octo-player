package app.winters.octo.ui.settings

import androidx.compose.animation.animateColorAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import app.winters.octo.design.GlassPopup
import app.winters.octo.design.OctoColors
import app.winters.octo.design.OctoSwitch
import app.winters.octo.design.OctoType
import app.winters.octo.design.raisedPanel
import app.winters.octo.home.DefaultHomeSections
import app.winters.octo.home.HOME_SECTIONS_NOTE
import app.winters.octo.home.HOME_SECTIONS_TITLE
import app.winters.octo.home.HomeSection
import app.winters.octo.home.HomeSectionEntry
import app.winters.octo.home.RESET_HOME_SECTIONS
import app.winters.octo.home.RESET_HOME_SECTIONS_ASK
import app.winters.octo.home.RESET_HOME_SECTIONS_DETAIL
import app.winters.octo.home.moveHomeSection
import app.winters.octo.home.toggleHomeSection
import app.winters.octo.ui.common.DragHandle
import app.winters.octo.ui.common.LocalHaze
import app.winters.octo.ui.common.PopupQuestion
import app.winters.octo.ui.common.rememberOpenedBeside
import app.winters.octo.ui.home.HomePrefs
import app.winters.octo.ui.settings.rows.SettingsPageFrame
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import sh.calvin.reorderable.ReorderableColumn

// Home's shelves in their order, each shown or hidden, kept as one string.
// A change shows on the page at once and is written behind it, so a row
// dropped in a new place stays there.
@HiltViewModel
class HomeSectionsViewModel @Inject constructor(private val prefs: HomePrefs) : ViewModel() {
    private val shown = MutableStateFlow<List<HomeSectionEntry>?>(null)
    val sections: StateFlow<List<HomeSectionEntry>?> = shown

    init {
        viewModelScope.launch { prefs.homeSections.collect { shown.value = it } }
    }

    private fun set(entries: List<HomeSectionEntry>) {
        shown.value = entries
        viewModelScope.launch { prefs.setHomeSections(entries) }
    }

    fun move(section: HomeSection, to: Int) {
        val entries = sections.value ?: return
        set(moveHomeSection(entries, section, to))
    }

    fun setShown(section: HomeSection, shown: Boolean) {
        val entries = sections.value ?: return
        set(toggleHomeSection(entries, section, shown))
    }

    fun reset() {
        shown.value = DefaultHomeSections
        viewModelScope.launch { prefs.resetHomeSections() }
    }
}

private val GroupShape = RoundedCornerShape(20.dp)

// Home's shelves in their order: each row's handle drags it to a new place
// (or a long press anywhere on the row), and its switch shows or hides it on
// Home. Every change is kept and reaches Home at once. A button at the
// bottom puts the usual order back, after asking.
@Composable
fun HomeSectionsPage(onBack: () -> Unit, vm: HomeSectionsViewModel = hiltViewModel()) {
    val entries = vm.sections.collectAsStateWithLifecycle().value ?: return
    var askingReset by remember { mutableStateOf(false) }
    val haptics = LocalHapticFeedback.current

    SettingsPageFrame(HOME_SECTIONS_TITLE, onBack) {
        Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp)) {
            Text(
                "ON HOME",
                style = OctoType.label.copy(letterSpacing = 0.6.sp),
                color = OctoColors.TextMuted,
                modifier = Modifier.padding(start = 16.dp, end = 16.dp, bottom = 8.dp).semantics { heading() },
            )
            ReorderableColumn(
                list = entries,
                onSettle = { from, to -> entries.getOrNull(from)?.let { vm.move(it.section, to) } },
                onMove = { haptics.performHapticFeedback(HapticFeedbackType.SegmentFrequentTick) },
                modifier = Modifier.fillMaxWidth().raisedPanel(GroupShape),
            ) { index, entry, dragging ->
                key(entry.section) {
                    ReorderableItem {
                        val fill by animateColorAsState(if (dragging) OctoColors.Accent.copy(alpha = 0.12f) else OctoColors.Accent.copy(alpha = 0f), label = "lift")
                        Column(Modifier.background(fill)) {
                            if (index > 0) Hairline()
                            SectionRow(
                                entry,
                                onShown = { vm.setShown(entry.section, it) },
                                handle = Modifier.draggableHandle(
                                    onDragStarted = { haptics.performHapticFeedback(HapticFeedbackType.GestureThresholdActivate) },
                                    onDragStopped = { haptics.performHapticFeedback(HapticFeedbackType.GestureEnd) },
                                ),
                                row = Modifier.longPressDraggableHandle(
                                    onDragStarted = { haptics.performHapticFeedback(HapticFeedbackType.GestureThresholdActivate) },
                                    onDragStopped = { haptics.performHapticFeedback(HapticFeedbackType.GestureEnd) },
                                ),
                            )
                        }
                    }
                }
            }
            Text(
                HOME_SECTIONS_NOTE,
                style = OctoType.caption,
                color = OctoColors.TextMuted,
                modifier = Modifier.padding(start = 16.dp, end = 16.dp, top = 8.dp),
            )
        }
        val changed = entries != DefaultHomeSections
        Box(Modifier.fillMaxWidth().padding(horizontal = 16.dp).raisedPanel(GroupShape)) {
            Text(
                RESET_HOME_SECTIONS,
                style = OctoType.body,
                color = if (changed) OctoColors.Accent else OctoColors.TextMuted,
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable(enabled = changed, role = Role.Button) { askingReset = true }
                    .heightIn(min = 52.dp)
                    .padding(horizontal = 16.dp, vertical = 15.dp),
                textAlign = TextAlign.Center,
            )
        }
    }
    GlassPopup(
        visible = askingReset,
        anchor = rememberOpenedBeside(askingReset),
        onDismiss = { askingReset = false },
        backdrop = LocalHaze.current,
    ) {
        PopupQuestion(
            RESET_HOME_SECTIONS_ASK,
            RESET_HOME_SECTIONS_DETAIL,
            "Reset",
            onConfirm = {
                askingReset = false
                vm.reset()
            },
            onCancel = { askingReset = false },
        )
    }
}

// One shelf: the handle that drags it, its name as Home shows it (dimmed
// while hidden), and the switch that shows or hides it.
@Composable
private fun SectionRow(entry: HomeSectionEntry, onShown: (Boolean) -> Unit, handle: Modifier, row: Modifier) {
    Row(
        row
            .fillMaxWidth()
            .toggleable(value = entry.shown, role = Role.Switch, onValueChange = onShown)
            .heightIn(min = 56.dp)
            .padding(start = 4.dp, end = 16.dp, top = 6.dp, bottom = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        DragHandle(handle)
        Text(
            entry.section.title,
            style = OctoType.body,
            color = if (entry.shown) OctoColors.TextPrimary else OctoColors.TextMuted,
            modifier = Modifier.weight(1f),
        )
        OctoSwitch(checked = entry.shown, onCheckedChange = onShown, modifier = Modifier.clearAndSetSemantics { })
    }
}

// One physical pixel between rows, starting under the names.
@Composable
private fun Hairline() {
    val onePixel = with(LocalDensity.current) { 1.toDp() }
    Box(
        Modifier
            .padding(start = 52.dp)
            .fillMaxWidth()
            .height(onePixel)
            .background(OctoColors.TextPrimary.copy(alpha = 0.10f)),
    )
}
