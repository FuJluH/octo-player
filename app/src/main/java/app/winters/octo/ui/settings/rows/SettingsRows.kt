package app.winters.octo.ui.settings.rows

import androidx.annotation.DrawableRes
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.relocation.BringIntoViewRequester
import androidx.compose.foundation.relocation.bringIntoViewRequester
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.SubcomposeLayout
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.winters.octo.design.LineSlider
import app.winters.octo.design.OctoColors
import app.winters.octo.design.OctoIcons
import app.winters.octo.design.OctoSwitch
import app.winters.octo.design.OctoType
import app.winters.octo.design.SliderLook
import app.winters.octo.design.raisedPanel
import app.winters.octo.ui.common.LocalChoiceSheet
import app.winters.octo.ui.common.choiceAnchor
import app.winters.octo.ui.settings.SettingEntry
import kotlinx.coroutines.delay

private val GroupShape = RoundedCornerShape(20.dp)

// The row a search result pointed at, lit briefly once its page opens.
// Shown once, then done, so coming back to the page does not light it again.
class SettingsHighlight(val id: String?, val onShown: () -> Unit)

val LocalSettingsHighlight = compositionLocalOf { SettingsHighlight(null) {} }

// How long the pointed-at row stays lit, after the page has settled.
private const val SETTLE_MS = 350L
private const val HOLD_MS = 900L

// Rows in one raised panel, a hairline between each. A row that draws
// nothing takes no place and gets no line. The lines start under the text,
// so rows with icons pass a deeper inset. A title sits above the panel as
// a quiet capitalised label, as the desktop names its groups, led by the
// group's `icon` when it has one (a `brand` mark keeps its own colours).
@Composable
fun SettingsGroup(
    modifier: Modifier = Modifier,
    title: String? = null,
    footer: String? = null,
    separatorInset: Dp = 16.dp,
    @DrawableRes icon: Int? = null,
    brand: Boolean = false,
    content: @Composable () -> Unit,
) {
    Column(modifier.fillMaxWidth().padding(horizontal = 16.dp)) {
        title?.let {
            Row(
                Modifier
                    .padding(start = 16.dp, end = 16.dp, bottom = 8.dp)
                    .semantics(mergeDescendants = true) { heading() },
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(7.dp),
            ) {
                icon?.let { MarkOrIcon(it, brand, OctoColors.TextMuted, 15.dp) }
                Text(
                    it.uppercase(),
                    style = OctoType.label.copy(letterSpacing = 0.6.sp),
                    color = OctoColors.TextMuted,
                    modifier = Modifier.semantics { contentDescription = it },
                )
            }
        }
        SubcomposeLayout(Modifier.fillMaxWidth().raisedPanel(GroupShape)) { constraints ->
            val loose = constraints.copy(minHeight = 0)
            val rows = subcompose("rows", content).map { it.measure(loose) }.filter { it.height > 0 }
            val lines = subcompose("lines") {
                repeat((rows.size - 1).coerceAtLeast(0)) { Hairline(separatorInset) }
            }.map { it.measure(loose) }
            val height = rows.sumOf { it.height } + lines.sumOf { it.height }
            layout(constraints.maxWidth, height) {
                var y = 0
                rows.forEachIndexed { index, row ->
                    row.place(0, y)
                    y += row.height
                    lines.getOrNull(index)?.let { line ->
                        line.place(0, y)
                        y += line.height
                    }
                }
            }
        }
        footer?.let {
            Text(it, style = OctoType.caption, color = OctoColors.TextMuted, modifier = Modifier.padding(start = 16.dp, end = 16.dp, top = 8.dp))
        }
    }
}

// One physical pixel, starting under the rows' text.
@Composable
private fun Hairline(inset: Dp) {
    val onePixel = with(LocalDensity.current) { 1.toDp() }
    Box(
        Modifier
            .padding(start = inset)
            .fillMaxWidth()
            .height(onePixel)
            .background(OctoColors.TextPrimary.copy(alpha = 0.10f)),
    )
}

// What every row shares: its height and padding, a tap when it has one,
// and the brief light when search pointed at it.
@Composable
internal fun RowFrame(
    entry: SettingEntry?,
    modifier: Modifier = Modifier,
    minHeight: Dp = 56.dp,
    content: @Composable RowScope.() -> Unit,
) {
    val highlight = LocalSettingsHighlight.current
    val glow = remember { Animatable(0f) }
    val requester = remember { BringIntoViewRequester() }
    if (entry != null && highlight.id == entry.id) {
        LaunchedEffect(highlight) {
            highlight.onShown()
            delay(SETTLE_MS)
            requester.bringIntoView()
            glow.animateTo(1f, tween(250))
            delay(HOLD_MS)
            glow.animateTo(0f, tween(700))
        }
    }
    Row(
        Modifier
            .fillMaxWidth()
            .bringIntoViewRequester(requester)
            .drawBehind { if (glow.value > 0f) drawRect(OctoColors.Accent.copy(alpha = 0.14f * glow.value)) }
            .then(modifier)
            .heightIn(min = minHeight)
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        content = content,
    )
}

// A title with an optional line under it, taking the row's spare width.
@Composable
private fun RowScope.Label(title: String, below: String?, enabled: Boolean = true, belowColor: Color = OctoColors.TextMuted, titleColor: Color = OctoColors.TextPrimary) {
    Column(Modifier.weight(1f)) {
        Text(title, style = OctoType.body, color = if (enabled) titleColor else OctoColors.TextMuted)
        below?.let { Text(it, style = OctoType.caption, color = belowColor, modifier = Modifier.padding(top = 2.dp)) }
    }
}

// A setting that is on or off. The whole row flips it.
@Composable
fun SwitchRow(
    entry: SettingEntry?,
    checked: Boolean,
    onChange: (Boolean) -> Unit,
    helper: String? = null,
    enabled: Boolean = true,
    title: String = entry?.title.orEmpty(),
) {
    RowFrame(entry, Modifier.toggleable(value = checked, enabled = enabled, role = Role.Switch, onValueChange = onChange)) {
        Label(title, helper, enabled)
        OctoSwitch(checked = checked, onCheckedChange = onChange, enabled = enabled, modifier = Modifier.clearAndSetSemantics { })
    }
}

// A setting with a few answers: its title on the left, the current one on
// the right, as the desktop reads them, and a chevron. Tapping it pops the
// answers up beside the row.
@Composable
fun ChoiceRow(
    entry: SettingEntry?,
    value: String,
    onClick: () -> Unit,
    enabled: Boolean = true,
    title: String = entry?.title.orEmpty(),
    helper: String? = null,
) {
    val sheet = LocalChoiceSheet.current
    RowFrame(entry, Modifier.choiceAnchor(sheet).clickable(enabled = enabled, role = Role.Button, onClick = onClick)) {
        Label(title, helper, enabled)
        Reading(value, enabled)
        Icon(
            painterResource(OctoIcons.Chevron),
            contentDescription = null,
            tint = OctoColors.TextMuted,
            modifier = Modifier.size(18.dp).alpha(if (enabled) 1f else 0.5f),
        )
    }
}

// A row's current value on its right: quieter than the title, kept to the
// end of the line, and never taking more than its share of the row. It
// fills that share so the words, and the chevron after them, sit at the
// row's end rather than halfway along it.
@Composable
private fun RowScope.Reading(value: String, enabled: Boolean = true) {
    Text(
        value,
        style = OctoType.bodySmall,
        color = if (enabled) OctoColors.TextSecondary else OctoColors.TextMuted,
        textAlign = TextAlign.End,
        maxLines = 2,
        overflow = TextOverflow.Ellipsis,
        modifier = Modifier.weight(0.8f),
    )
}

// An icon tinted to its place, or a brand's mark in its own colours.
@Composable
internal fun MarkOrIcon(@DrawableRes icon: Int, brand: Boolean, tint: Color, size: Dp) {
    if (brand) {
        Image(painterResource(icon), contentDescription = null, modifier = Modifier.size(size))
    } else {
        Icon(painterResource(icon), contentDescription = null, tint = tint, modifier = Modifier.size(size))
    }
}

// A setting along a range: its title and value, and the line to drag.
@Composable
fun SliderRow(
    entry: SettingEntry?,
    value: String,
    fraction: () -> Float,
    onSeek: (Float) -> Unit,
    title: String = entry?.title.orEmpty(),
) {
    RowFrame(entry) {
        Column(Modifier.weight(1f)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(title, style = OctoType.body, color = OctoColors.TextPrimary, modifier = Modifier.weight(1f))
                Text(value, style = OctoType.bodySmall.copy(fontFeatureSettings = "tnum"), color = OctoColors.TextSecondary)
            }
            LineSlider(
                fraction = fraction,
                onSeek = onSeek,
                live = true,
                look = SliderLook.Jewel,
                modifier = Modifier.semantics { contentDescription = title },
            )
        }
    }
}

// Something to do, or another page to open: its title, and a chevron,
// a word on the right, or a spinner while it works.
@Composable
fun ActionRow(
    entry: SettingEntry?,
    onClick: () -> Unit,
    helper: String? = null,
    trailing: String? = null,
    chevron: Boolean = trailing == null,
    busy: Boolean = false,
    enabled: Boolean = true,
    destructive: Boolean = false,
    title: String = entry?.title.orEmpty(),
) {
    RowFrame(entry, Modifier.clickable(enabled = enabled && !busy, role = Role.Button, onClick = onClick)) {
        Label(title, helper, enabled, titleColor = if (destructive) OctoColors.Error else OctoColors.TextPrimary)
        when {
            busy -> CircularProgressIndicator(color = OctoColors.Accent, strokeWidth = 2.dp, modifier = Modifier.size(18.dp))
            trailing != null -> Reading(trailing, enabled)
            else -> Unit
        }
        if (chevron && !busy) {
            Icon(
                painterResource(OctoIcons.Chevron),
                contentDescription = null,
                tint = OctoColors.TextMuted,
                modifier = Modifier.size(20.dp).alpha(if (enabled) 1f else 0.5f),
            )
        }
    }
}

// A fact to read: a title and its value.
@Composable
fun InfoRow(entry: SettingEntry?, value: String, title: String = entry?.title.orEmpty(), helper: String? = null) {
    RowFrame(entry) {
        Label(title, helper)
        Reading(value)
    }
}

// A few words inside a group: what a part does, or what went wrong.
@Composable
fun NoteRow(text: String, entry: SettingEntry? = null, color: Color = OctoColors.TextMuted) {
    RowFrame(entry, minHeight = 0.dp) {
        Text(text, style = OctoType.caption, color = color, modifier = Modifier.weight(1f))
    }
}

// A way into a page: its icon, title, and one line on how it is set now.
@Composable
fun CategoryRow(@DrawableRes icon: Int, title: String, summary: String, mark: String? = null, onClick: () -> Unit) {
    RowFrame(null, Modifier.clickable(role = Role.Button, onClick = onClick)) {
        IconTile(icon)
        Column(Modifier.weight(1f).padding(start = 4.dp)) {
            Text(title, style = OctoType.body, color = OctoColors.TextPrimary)
            if (summary.isNotEmpty()) {
                Text(summary, style = OctoType.caption, color = OctoColors.TextMuted, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
        // A small dot when something waits on the page, `mark` saying what.
        if (mark != null) {
            Box(Modifier.size(8.dp).background(OctoColors.Accent, CircleShape).semantics { contentDescription = mark })
        }
        Icon(painterResource(OctoIcons.Chevron), contentDescription = null, tint = OctoColors.TextMuted, modifier = Modifier.size(20.dp))
    }
}

// A row's icon on a small tinted tile, so a list of pages reads at a glance.
@Composable
fun IconTile(@DrawableRes icon: Int) {
    Box(
        Modifier
            .size(IconTileSize)
            .background(OctoColors.Accent.copy(alpha = 0.14f), IconTileShape),
        contentAlignment = Alignment.Center,
    ) {
        Icon(painterResource(icon), contentDescription = null, tint = OctoColors.Accent, modifier = Modifier.size(20.dp))
    }
}

private val IconTileSize = 34.dp
private val IconTileShape = RoundedCornerShape(10.dp)

// The inset for a group of rows with icons: the lines start under the titles.
val IconRowInset = 66.dp
