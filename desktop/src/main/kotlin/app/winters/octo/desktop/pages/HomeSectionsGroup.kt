package app.winters.octo.desktop.pages

import androidx.compose.animation.animateColorAsState
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.selection.toggleable
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.focusProperties
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.input.pointer.PointerIcon
import androidx.compose.ui.input.pointer.pointerHoverIcon
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.hideFromAccessibility
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import app.winters.octo.design.Corner
import app.winters.octo.design.DesktopType
import app.winters.octo.design.FocusRing
import app.winters.octo.design.GlazeCapsule
import app.winters.octo.design.LocalPopups
import app.winters.octo.design.MenuTitle
import app.winters.octo.design.OctoColors
import app.winters.octo.design.OctoSwitch
import app.winters.octo.design.PopupPadding
import app.winters.octo.design.RowHeight
import app.winters.octo.design.SeparatorColor
import app.winters.octo.design.Space
import app.winters.octo.design.Txt
import app.winters.octo.design.hoverLift
import app.winters.octo.desktop.AppState
import app.winters.octo.desktop.home.DesktopHomeSections
import app.winters.octo.home.DefaultHomeSections
import app.winters.octo.home.HOME_SECTIONS_NOTE
import app.winters.octo.home.HOME_SECTIONS_TITLE
import app.winters.octo.home.HomeSectionEntry
import app.winters.octo.home.RESET_HOME_SECTIONS
import app.winters.octo.home.RESET_HOME_SECTIONS_ASK
import app.winters.octo.home.RESET_HOME_SECTIONS_DETAIL
import app.winters.octo.home.encodeHomeSections
import app.winters.octo.home.homeSectionOrder
import app.winters.octo.home.homeSectionsSummary
import app.winters.octo.home.moveListedHomeSection
import app.winters.octo.home.toggleHomeSection
import sh.calvin.reorderable.ReorderableColumn

// Appearance's Home group: Home's shelves in their order, each row's handle
// dragging it to a new place and its switch showing or hiding it on Home.
// Every change is saved and reaches Home at once. Only the shelves this app
// draws are listed; the others keep their places in the saved order, which
// the phone shares. A button under them puts the usual order back, after
// asking.
@Composable
internal fun HomeSectionsGroup(app: AppState, stored: String?) {
    val entries = remember(stored) { homeSectionOrder(stored) }
    val listed = entries.filter { it.section in DesktopHomeSections }
    fun save(next: List<HomeSectionEntry>) = app.settings.update { it.copy(appearance = it.appearance.copy(homeSections = encodeHomeSections(next))) }
    val popups = LocalPopups.current
    Column(Modifier.fillMaxWidth()) {
        Group("Home") {
            SettingRow(HOME_SECTIONS_TITLE, homeSectionsSummary(entries))
            ReorderableColumn(
                list = listed,
                onSettle = { from, to -> save(moveListedHomeSection(entries, DesktopHomeSections, from, to)) },
                modifier = Modifier.fillMaxWidth(),
            ) { index, entry, dragging ->
                key(entry.section) {
                    ReorderableItem {
                        val fill by animateColorAsState(OctoColors.Accent.copy(alpha = if (dragging) 0.12f else 0f), label = "lift")
                        Column(Modifier.background(fill)) {
                            if (index > 0) Hairline()
                            SectionRow(entry, { shown -> save(toggleHomeSection(entries, entry.section, shown)) }, Modifier.draggableHandle())
                        }
                    }
                }
            }
        }
        Txt(HOME_SECTIONS_NOTE, DesktopType.meta, OctoColors.TextMuted, Modifier.padding(start = RowInset, end = RowInset, top = Space.S), maxLines = 3)
        val changed = entries != DefaultHomeSections
        Row(Modifier.fillMaxWidth().padding(top = Space.M), horizontalArrangement = Arrangement.End) {
            GlazeCapsule(null, RESET_HOME_SECTIONS, {
                popups.showCentred { close ->
                    MenuTitle(RESET_HOME_SECTIONS_ASK)
                    PopupPadding {
                        Txt(RESET_HOME_SECTIONS_DETAIL, DesktopType.body, OctoColors.TextPrimary, maxLines = 3)
                        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(Space.M, Alignment.End)) {
                            GlazeCapsule(null, "Cancel", close)
                            GlazeCapsule(null, "Reset", {
                                close()
                                app.settings.update { it.copy(appearance = it.appearance.copy(homeSections = null)) }
                            }, lit = true)
                        }
                    }
                }
            }, enabled = changed)
        }
    }
}

// One shelf: the handle that drags it, its name as Home shows it (dimmed
// while hidden), and the switch that shows or hides it. The whole row flips
// the switch.
@Composable
private fun SectionRow(entry: HomeSectionEntry, change: (Boolean) -> Unit, handle: Modifier) {
    Row(
        Modifier
            .fillMaxWidth()
            .hoverLift()
            .toggleable(value = entry.shown, interactionSource = null, indication = FocusRing(Corner.RowShape), role = Role.Switch, onValueChange = change)
            .heightIn(min = RowHeight.Roomy)
            .padding(start = Space.S, end = RowInset, top = Space.S, bottom = Space.S),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Space.M),
    ) {
        Handle(handle)
        Txt(entry.section.title, DesktopType.body, if (entry.shown) OctoColors.TextPrimary else OctoColors.TextMuted, Modifier.weight(1f))
        OctoSwitch(entry.shown, change, Modifier.focusProperties { canFocus = false }.semantics { hideFromAccessibility() })
    }
}

// Two short lines to grab a row by.
@Composable
private fun Handle(modifier: Modifier) {
    Box(
        modifier.size(32.dp).pointerHoverIcon(PointerIcon.Hand).semantics { contentDescription = "Reorder" },
        contentAlignment = Alignment.Center,
    ) {
        Canvas(Modifier.size(width = 16.dp, height = 7.dp)) {
            val stroke = 2.dp.toPx()
            listOf(stroke / 2, size.height - stroke / 2).forEach { y ->
                drawLine(OctoColors.TextMuted, Offset(0f, y), Offset(size.width, y), stroke, StrokeCap.Round)
            }
        }
    }
}

// One physical pixel between rows, in line with the words.
@Composable
private fun Hairline() {
    val onePixel = with(LocalDensity.current) { 1.toDp() }
    Box(Modifier.padding(horizontal = RowInset).fillMaxWidth().height(onePixel).background(SeparatorColor))
}
