package app.winters.octo.design

import androidx.compose.foundation.layout.statusBarsPadding
import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.animate
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.Orientation
import androidx.compose.foundation.gestures.draggable
import androidx.compose.foundation.gestures.rememberDraggableState
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.dropShadow
import androidx.compose.ui.draw.innerShadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.shadow.Shadow
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.DpOffset
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch

private val SheetShape = RoundedCornerShape(topStart = 28.dp, topEnd = 28.dp)

// Solid enough to read on over any background, with a little accent in it.
val SheetFill: Color get() = mix(OctoColors.Background, OctoColors.GlassAccent, 0.05f).copy(alpha = 0.97f)

// A panel that rises from the bottom over a dimmed screen, at most 70% of
// the screen tall; what does not fit scrolls. Tapping the dim area, pulling the panel down, or back
// closes it. Place it last inside a full-screen box so it sits on top.
// `tall` lets it grow as tall as its content, up to the status bar, opened
// all the way at once. `scrolls` false hands the content the room as it is,
// for a sheet that scrolls part of itself and keeps the rest in place (a
// footer that stays put).
@Composable
fun GlassSheet(
    visible: Boolean,
    onDismiss: () -> Unit,
    tall: Boolean = false,
    scrolls: Boolean = true,
    content: @Composable ColumnScope.() -> Unit,
) {
    val dismiss by rememberUpdatedState(onDismiss)
    BackHandler(enabled = visible) { dismiss() }
    val motion = motionScale()

    Box(Modifier.fillMaxSize()) {
        AnimatedVisibility(visible, enter = fadeIn(octoTween(motion, OctoDuration.Card)), exit = fadeOut(octoTween(motion, OctoDuration.Card))) {
            Box(
                Modifier
                    .fillMaxSize()
                    .background(Color.Black.copy(alpha = 0.45f))
                    .clickable(interactionSource = null, indication = null) { dismiss() },
            )
        }
        AnimatedVisibility(
            visible,
            enter = slideInVertically(spring(0.85f, 400f)) { it },
            exit = slideOutVertically(octoTween(motion, OctoDuration.Card, OctoEasing.EaseIn)) { it },
            modifier = Modifier.align(Alignment.BottomCenter).then(if (tall) Modifier.statusBarsPadding() else Modifier),
        ) {
            BoxWithConstraints {
                val scope = rememberCoroutineScope()
                val density = LocalDensity.current
                var pull by remember { mutableFloatStateOf(0f) }
                Column(
                    Modifier
                        .fillMaxWidth()
                        .heightIn(max = if (tall) maxHeight else maxHeight * 0.7f)
                        .graphicsLayer { translationY = pull }
                        .dropShadow(SheetShape, Shadow(radius = shadowBlur(32f), color = Color.Black.copy(alpha = 0.4f)))
                        .clip(SheetShape)
                        .background(SheetFill)
                        // Light along the top edge, as on the other glass.
                        .innerShadow(SheetShape, Shadow(radius = 0.dp, color = Color.White.copy(alpha = 0.10f), offset = DpOffset(0.dp, 1.dp)))
                        // Swallows taps so they do not reach the dim area.
                        .clickable(interactionSource = null, indication = null) {}
                        .navigationBarsPadding(),
                ) {
                    // The handle: pulling it down closes the sheet.
                    Box(
                        Modifier
                            .fillMaxWidth()
                            .draggable(
                                orientation = Orientation.Vertical,
                                state = rememberDraggableState { delta -> pull = (pull + delta).coerceAtLeast(0f) },
                                onDragStopped = { velocity ->
                                    val far = with(density) { 96.dp.toPx() }
                                    val fast = with(density) { 1_200.dp.toPx() }
                                    if (pull > far || velocity > fast) {
                                        dismiss()
                                    } else {
                                        scope.launch { animate(pull, 0f, animationSpec = spring(0.8f, 400f)) { v, _ -> pull = v } }
                                    }
                                },
                            )
                            .padding(vertical = 12.dp),
                        contentAlignment = Alignment.Center,
                    ) {
                        Box(Modifier.size(width = 36.dp, height = 4.dp).clip(CircleShape).background(OctoColors.TextMuted))
                    }
                    // The lines scroll under the handle when there are more
                    // than fit.
                    if (scrolls) SheetColumn(content = content) else content()
                }
            }
        }
    }
}
