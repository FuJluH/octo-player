package app.winters.octo.ui.common

import androidx.annotation.DrawableRes
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.hoverable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsHoveredAsState
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import app.winters.octo.design.GlazeSelected
import app.winters.octo.design.MenuRowHeight
import app.winters.octo.design.OctoColors
import app.winters.octo.design.menuRowPress
import app.winters.octo.design.OctoIcons
import app.winters.octo.design.OctoType

// How one option in a glass menu is drawn: whether it is the chosen one, and
// whether a line parts it from the option above. No line touches the chosen
// option's pill, so the pill reads as set into the glass.
data class MenuRowLook(val selected: Boolean, val lineAbove: Boolean)

fun menuRowLooks(count: Int, selected: Int): List<MenuRowLook> = List(count) { index ->
    MenuRowLook(
        selected = index == selected,
        lineAbove = index > 0 && index != selected && index - 1 != selected,
    )
}

// The card is padded 6dp, so the pill's corners follow the card's 20dp.
private val OptionShape = RoundedCornerShape(14.dp)

private val LineColour = OctoColors.TextPrimary.copy(alpha = 0.08f)

// How wide a glass menu is, so its pages line up as it turns from one to
// the next.
val MenuWidth = 288.dp

// The options of a menu, one above the other with hairlines between, the
// chosen one in the darker pill with a white check. `selected` below zero
// means none is chosen, as when the menu asks for an action.
@Composable
fun GlassMenuOptions(options: List<Choice>, selected: Int, onPick: (Int) -> Unit, modifier: Modifier = Modifier) {
    val looks = remember(options.size, selected) { menuRowLooks(options.size, selected) }
    Column(if (selected >= 0) modifier.selectableGroup() else modifier) {
        options.forEachIndexed { index, option ->
            // Always 1dp, drawn or not, so the rows never shift.
            if (index > 0) MenuLine(looks[index].lineAbove)
            MenuOption(option, looks[index].selected, pickable = selected >= 0) { onPick(index) }
        }
    }
}

// A quiet heading at the top of a menu.
@Composable
fun GlassMenuTitle(text: String) {
    Text(
        text,
        style = OctoType.label,
        color = OctoColors.TextSecondary,
        modifier = Modifier.padding(start = 14.dp, end = 14.dp, top = 10.dp, bottom = 6.dp),
    )
}

@Composable
private fun MenuLine(drawn: Boolean) {
    Box(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = 14.dp)
            .height(1.dp)
            .background(if (drawn) LineColour else Color.Transparent),
    )
}

// A row under the finger (or a mouse) shows the quiet accent-tinted pill,
// at once, in place of a ripple.
@Composable
private fun rowHeld(interaction: MutableInteractionSource): Boolean {
    val pressed by interaction.collectIsPressedAsState()
    val hovered by interaction.collectIsHoveredAsState()
    return pressed || hovered
}

@Composable
private fun MenuOption(option: Choice, selected: Boolean, pickable: Boolean, onClick: () -> Unit) {
    val interaction = remember { MutableInteractionSource() }
    val held = rowHeld(interaction)
    Box(
        Modifier
            .fillMaxWidth()
            .heightIn(min = MenuRowHeight.Touch)
            .menuRowPress(OptionShape) { if (held && !selected) 1f else 0f }
            .clip(OptionShape)
            .hoverable(interaction)
            .then(
                if (pickable) {
                    Modifier.selectable(selected = selected, enabled = option.enabled, interactionSource = interaction, indication = null, role = Role.RadioButton, onClick = onClick)
                } else {
                    Modifier.clickable(enabled = option.enabled, interactionSource = interaction, indication = null, role = Role.Button, onClick = onClick)
                },
            ),
        contentAlignment = Alignment.CenterStart,
    ) {
        if (selected) GlazeSelected(Modifier.matchParentSize(), shape = OptionShape)
        Row(
            Modifier.padding(horizontal = 14.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            option.leading?.invoke()
            Column(Modifier.weight(1f)) {
                Text(option.label, style = OctoType.bodySmall, color = if (option.enabled) OctoColors.TextPrimary else OctoColors.TextMuted)
                option.detail?.let { Text(it, style = OctoType.caption, color = OctoColors.TextMuted) }
            }
            // The check's room is kept on every line, so the menu's width
            // does not depend on which one is chosen.
            if (selected) {
                Icon(painterResource(OctoIcons.Check), contentDescription = null, tint = Color.White, modifier = Modifier.size(18.dp))
            } else if (pickable) {
                Spacer(Modifier.size(18.dp))
            }
        }
    }
}

// A page of a glass menu: a heading that stays put, then the rest, which
// scrolls when it is taller than the menu may be.
@Composable
fun GlassMenuPage(
    modifier: Modifier = Modifier,
    width: Dp = MenuWidth,
    header: @Composable ColumnScope.() -> Unit = {},
    body: @Composable ColumnScope.() -> Unit,
) {
    Column(modifier.width(width).padding(6.dp)) {
        header()
        Column(Modifier.weight(1f, fill = false).verticalScroll(rememberScrollState()), content = body)
    }
}

// Groups of rows, a hairline between one group and the next and none
// inside a group. Empty groups are left out.
@Composable
fun <T> GlassMenuGroups(groups: List<List<T>>, row: @Composable (T) -> Unit) {
    groups.filter { it.isNotEmpty() }.forEachIndexed { index, group ->
        if (index > 0) GlassMenuSeparator()
        group.forEach { row(it) }
    }
}

// The hairline between two groups of a menu.
@Composable
fun GlassMenuSeparator() {
    Box(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = 14.dp, vertical = 4.dp)
            .height(1.dp)
            .background(LineColour),
    )
}

// One action in a glass menu: a white icon, what it does, and a line about
// it when there is one. One that cannot be chosen right now is dimmed. One
// that `opensPage` shows a small chevron, since it leads on. A
// `destructive` one (deleting, removing) says so in soft red words; its
// icon stays white like every other.
@Composable
fun GlassMenuAction(
    @DrawableRes icon: Int?,
    label: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    detail: String? = null,
    enabled: Boolean = true,
    opensPage: Boolean = false,
    destructive: Boolean = false,
) {
    val interaction = remember { MutableInteractionSource() }
    val held = rowHeld(interaction)
    Row(
        modifier
            .fillMaxWidth()
            .heightIn(min = MenuRowHeight.Touch)
            .menuRowPress(OptionShape) { if (held && enabled) 1f else 0f }
            .clip(OptionShape)
            .hoverable(interaction, enabled = enabled)
            .clickable(interactionSource = interaction, indication = null, enabled = enabled, role = Role.Button, onClick = onClick)
            .padding(horizontal = 14.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        if (icon != null) {
            Icon(
                painterResource(icon),
                contentDescription = null,
                tint = if (enabled) Color.White else OctoColors.TextMuted,
                modifier = Modifier.size(20.dp),
            )
        }
        Column(Modifier.weight(1f)) {
            Text(
                label,
                style = OctoType.bodySmall,
                color = when {
                    !enabled -> OctoColors.TextMuted
                    destructive -> OctoColors.Destructive
                    else -> OctoColors.TextPrimary
                },
            )
            detail?.let { Text(it, style = OctoType.caption, color = OctoColors.TextMuted) }
        }
        if (opensPage) {
            Icon(painterResource(OctoIcons.Chevron), contentDescription = null, tint = OctoColors.TextMuted, modifier = Modifier.size(18.dp))
        }
    }
}

// What a menu is about, at its top: a small picture, a name, and a line
// under it.
@Composable
fun GlassMenuHeader(title: String, subtitle: String?, picture: @Composable () -> Unit) {
    Row(
        Modifier.fillMaxWidth().padding(start = 10.dp, end = 10.dp, top = 6.dp, bottom = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        picture()
        Column(Modifier.weight(1f)) {
            Text(
                title,
                style = OctoType.bodySmall.copy(fontWeight = FontWeight.SemiBold),
                color = OctoColors.TextPrimary,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
            if (!subtitle.isNullOrBlank()) {
                Text(subtitle, style = OctoType.caption, color = OctoColors.TextMuted, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
    }
}

// The top of a page opened from a menu: a small back chevron and the
// page's name. The chevron goes back to the page before.
@Composable
fun GlassMenuBack(title: String, onBack: () -> Unit) {
    val interaction = remember { MutableInteractionSource() }
    val held = rowHeld(interaction)
    Row(
        Modifier
            .fillMaxWidth()
            .heightIn(min = MenuRowHeight.Touch)
            .menuRowPress(OptionShape) { if (held) 1f else 0f }
            .clip(OptionShape)
            .hoverable(interaction)
            .clickable(interactionSource = interaction, indication = null, role = Role.Button, onClickLabel = "Back", onClick = onBack)
            .padding(start = 6.dp, end = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Icon(painterResource(OctoIcons.ChevronBack), contentDescription = null, tint = Color.White, modifier = Modifier.size(18.dp))
        Text(
            title,
            style = OctoType.label,
            color = OctoColors.TextPrimary,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.weight(1f).semantics { heading() },
        )
    }
    GlassMenuSeparator()
}

// A heading for a menu page that has nothing to go back to.
@Composable
fun GlassMenuHeading(title: String) {
    Text(
        title,
        style = OctoType.label,
        color = OctoColors.TextPrimary,
        maxLines = 2,
        overflow = TextOverflow.Ellipsis,
        modifier = Modifier.padding(start = 14.dp, end = 14.dp, top = 10.dp, bottom = 6.dp).semantics { heading() },
    )
}

// A quiet line of words inside a menu, for a note or an empty list.
@Composable
fun GlassMenuNote(text: String, modifier: Modifier = Modifier, color: Color = OctoColors.TextMuted) {
    Text(text, style = OctoType.caption, color = color, modifier = modifier.padding(horizontal = 14.dp, vertical = 8.dp))
}
