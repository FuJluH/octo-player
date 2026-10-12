package app.winters.octo.ui.output

import androidx.annotation.DrawableRes
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Icon
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.boundsInWindow
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.unit.IntRect
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.roundToIntRect
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import app.winters.octo.design.GlassPopup
import app.winters.octo.design.GlazeSelected
import app.winters.octo.design.GlowIcon
import app.winters.octo.design.OctoColors
import app.winters.octo.design.OctoIcons
import app.winters.octo.design.OctoType
import app.winters.octo.output.DeviceShape
import app.winters.octo.output.OutputChoice
import app.winters.octo.output.OutputDevice
import app.winters.octo.output.OutputFamily
import app.winters.octo.output.Outputs
import app.winters.octo.output.openSystemOutputs
import app.winters.octo.player.PlayerSettings
import app.winters.octo.ui.common.LocalHaze
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import javax.inject.Inject

@HiltViewModel
class OutputsViewModel @Inject constructor(private val outputs: Outputs, settings: PlayerSettings) : ViewModel() {
    val devices: StateFlow<List<OutputDevice>> = outputs.devices
    val current: StateFlow<OutputChoice> = outputs.current
    val searching: StateFlow<Boolean> = outputs.searching
    val renderersOn: StateFlow<Boolean> =
        settings.prefs.map { it.castRenderers }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), true)
    val families: Set<OutputFamily> get() = outputs.families

    fun startLooking() = outputs.startLooking()
    fun stopLooking() = outputs.stopLooking()
    fun choose(device: OutputDevice) = outputs.choose(device)
    fun choosePhone() = outputs.choosePhone()
}

// The Cast button: where the music plays. It lights up while casting and
// opens the list of devices beside itself.
@Composable
fun CastButton(modifier: Modifier = Modifier, model: OutputsViewModel = hiltViewModel()) {
    val current by model.current.collectAsStateWithLifecycle()
    var open by remember { mutableStateOf(false) }
    var anchor by remember { mutableStateOf<IntRect?>(null) }
    val casting = current is OutputChoice.Casting
    val tint = LocalContentColor.current
    Box(
        modifier
            .size(44.dp)
            .onGloballyPositioned { anchor = it.boundsInWindow().roundToIntRect() }
            .clickable(interactionSource = null, indication = null, role = Role.Button) { open = true }
            .semantics {
                contentDescription = "Cast"
                stateDescription = when (val now = current) {
                    is OutputChoice.Casting -> "Playing on ${now.device.name}"
                    is OutputChoice.Connecting -> "Connecting to ${now.device.name}"
                    OutputChoice.Phone -> "Playing on this phone"
                }
            },
        contentAlignment = Alignment.Center,
    ) {
        GlowIcon(
            painterResource(if (current is OutputChoice.Phone) OctoIcons.Cast else OctoIcons.CastConnected),
            tint = if (casting) tint else tint.copy(alpha = 0.45f),
            lit = casting,
            modifier = Modifier.size(22.dp),
        )
    }
    OutputSheet(open, anchor, onDismiss = { open = false }, model = model)
}

// The Cast button's card, holding the list of places to play.
@Composable
fun OutputSheet(visible: Boolean, anchor: IntRect?, onDismiss: () -> Unit, model: OutputsViewModel = hiltViewModel()) {
    GlassPopup(visible = visible, anchor = anchor, onDismiss = onDismiss, backdrop = LocalHaze.current, title = "Play on") {
        Column(Modifier.width(300.dp).verticalScroll(rememberScrollState()).padding(6.dp)) {
            OutputList(onDone = onDismiss, model = model)
        }
    }
}

// The list of places music can play: this phone and its other outputs,
// Cast devices, then TVs and speakers found as media renderers. The one
// playing is the darker pill. It looks for devices only while it is shown.
// Choosing a place calls `onDone`.
@Composable
fun OutputList(onDone: () -> Unit, model: OutputsViewModel = hiltViewModel()) {
    DisposableEffect(model) {
        model.startLooking()
        onDispose { model.stopLooking() }
    }
    val devices by model.devices.collectAsStateWithLifecycle()
    val current by model.current.collectAsStateWithLifecycle()
    val searching by model.searching.collectAsStateWithLifecycle()
    val renderersOn by model.renderersOn.collectAsStateWithLifecycle()
    val context = LocalContext.current
    Column(Modifier.fillMaxWidth()) {
        GroupTitle("This phone")
        DeviceRow(
            icon = OctoIcons.Phone,
            label = "This phone",
            selected = current is OutputChoice.Phone,
        ) {
            model.choosePhone()
            onDone()
        }
        DeviceRow(icon = OctoIcons.Headphones, label = "Other outputs", detail = "Bluetooth, headphones or the speaker", selected = false) {
            openSystemOutputs(context)
            onDone()
        }

        val cast = devices.filter { it.family == OutputFamily.Cast }
        val renderers = devices.filter { it.family == OutputFamily.Renderer }
        if (cast.isNotEmpty()) {
            GroupTitle("Cast")
            cast.forEach { DeviceLine(it, current, model, onDone) }
        }
        if (renderers.isNotEmpty()) {
            GroupTitle("TVs and speakers")
            renderers.forEach { DeviceLine(it, current, model, onDone) }
        }
        if (devices.isEmpty()) {
            val kinds = if (renderersOn && OutputFamily.Renderer in model.families) "TVs and speakers" else "Cast devices"
            QuietLine(
                if (searching) {
                    "Looking for devices"
                } else {
                    "No devices found. $kinds show up here when they are on the same Wi-Fi as this phone."
                },
            )
        } else if (searching) {
            QuietLine("Looking for more devices")
        }
        if (current !is OutputChoice.Phone) QuietLine("Sound settings apply on this phone only")
    }
}

@Composable
private fun DeviceLine(device: OutputDevice, current: OutputChoice, model: OutputsViewModel, onDismiss: () -> Unit) {
    val connecting = (current as? OutputChoice.Connecting)?.device?.id == device.id
    val playing = (current as? OutputChoice.Casting)?.device?.id == device.id
    DeviceRow(
        icon = when (device.shape) {
            DeviceShape.Tv -> OctoIcons.Tv
            DeviceShape.Speaker -> OctoIcons.Speaker
            DeviceShape.Group -> OctoIcons.SpeakerGroup
        },
        label = device.name,
        detail = if (connecting) "Connecting" else device.detail,
        selected = playing,
    ) {
        model.choose(device)
        onDismiss()
    }
}

private val RowShape = RoundedCornerShape(14.dp)

@Composable
private fun GroupTitle(text: String) {
    Text(
        text,
        style = OctoType.label,
        color = OctoColors.TextSecondary,
        modifier = Modifier.padding(start = 14.dp, end = 14.dp, top = 10.dp, bottom = 6.dp),
    )
}

@Composable
private fun QuietLine(text: String) {
    Text(
        text,
        style = OctoType.caption,
        color = OctoColors.TextMuted,
        modifier = Modifier.padding(horizontal = 14.dp, vertical = 10.dp),
    )
}

// One place to play: its icon, name and a line about it, in the darker
// pill with a check when it is the one playing.
@Composable
private fun DeviceRow(@DrawableRes icon: Int, label: String, selected: Boolean, detail: String? = null, onClick: () -> Unit) {
    Box(
        Modifier
            .fillMaxWidth()
            .heightIn(min = 52.dp)
            .clip(RowShape)
            .selectable(selected = selected, role = Role.RadioButton, onClick = onClick),
        contentAlignment = Alignment.CenterStart,
    ) {
        if (selected) GlazeSelected(Modifier.matchParentSize(), shape = RowShape)
        Row(
            Modifier.padding(horizontal = 14.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Icon(
                painterResource(icon),
                contentDescription = null,
                tint = if (selected) Color.White else OctoColors.TextSecondary,
                modifier = Modifier.size(20.dp),
            )
            Column(Modifier.weight(1f)) {
                Text(label, style = OctoType.bodySmall, color = OctoColors.TextPrimary)
                detail?.let { Text(it, style = OctoType.caption, color = OctoColors.TextMuted) }
            }
            if (selected) {
                Icon(painterResource(OctoIcons.Check), contentDescription = null, tint = Color.White, modifier = Modifier.size(18.dp))
            } else {
                Spacer(Modifier.size(18.dp))
            }
        }
    }
}

// A small cast mark for the corner of the mini player while casting.
@Composable
fun CastingMark(modifier: Modifier = Modifier) {
    Box(
        modifier
            .size(18.dp)
            .clip(RoundedCornerShape(50))
            .background(Color.Black.copy(alpha = 0.72f)),
        contentAlignment = Alignment.Center,
    ) {
        Icon(painterResource(OctoIcons.CastConnected), contentDescription = null, tint = OctoColors.TextPrimary, modifier = Modifier.size(11.dp))
    }
}
