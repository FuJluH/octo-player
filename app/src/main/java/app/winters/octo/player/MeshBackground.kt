package app.winters.octo.player

import android.graphics.RuntimeShader
import android.os.Build
import androidx.annotation.RequiresApi
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithCache
import androidx.compose.ui.graphics.ShaderBrush
import androidx.compose.ui.graphics.toArgb
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.repeatOnLifecycle
import kotlinx.coroutines.delay

// Four soft pools of colour that drift around the corners. Each pixel takes
// a blend of the four, the nearer pools counting for more, so the colours
// flow into each other with no edges. A slight ripple bends the blend, and
// a touch of grain keeps smooth gradients from banding. The ambient glow
// behind the rest of the app draws the same mesh, slower and fainter.
internal const val MESH = """
uniform float2 size;
uniform float time;
layout(color) uniform half4 c0;
layout(color) uniform half4 c1;
layout(color) uniform half4 c2;
layout(color) uniform half4 c3;

float weight(float2 uv, float2 p, float aspect) {
    float2 d = (uv - p) * float2(aspect, 1.0);
    return 1.0 / (dot(d, d) + 0.02);
}

half4 main(float2 coord) {
    float2 uv = coord / size;
    float aspect = size.x / size.y;
    uv += 0.05 * sin(uv.yx * 3.0 + time * 0.3);

    float2 p0 = float2(0.20 + 0.18 * sin(time * 0.20), 0.18 + 0.14 * cos(time * 0.31));
    float2 p1 = float2(0.82 + 0.16 * cos(time * 0.43), 0.26 + 0.16 * sin(time * 0.37));
    float2 p2 = float2(0.24 + 0.16 * cos(time * 0.53), 0.78 + 0.14 * sin(time * 0.61));
    float2 p3 = float2(0.80 + 0.14 * sin(time * 0.70), 0.84 + 0.12 * cos(time * 0.47));

    float w0 = weight(uv, p0, aspect);
    float w1 = weight(uv, p1, aspect);
    float w2 = weight(uv, p2, aspect);
    float w3 = weight(uv, p3, aspect);
    half3 color = half3((c0.rgb * w0 + c1.rgb * w1 + c2.rgb * w2 + c3.rgb * w3) / (w0 + w1 + w2 + w3));

    float grain = fract(sin(dot(coord, float2(12.9898, 78.233))) * 43758.5453);
    color += half3((grain - 0.5) * 0.008);
    return half4(color, 1.0);
}
"""

// The live background. It moves while music plays, slows almost to a stop
// when paused, and stops drawing new frames whenever the app is out of
// sight. Colours ease to each new song's over about half a second.
@RequiresApi(Build.VERSION_CODES.TIRAMISU)
@Composable
fun MeshBackground(colors: PlayerColors, playing: Boolean, modifier: Modifier = Modifier) {
    val c0 by animateColorAsState(colors.mesh[0], tween(520), label = "mesh 0")
    val c1 by animateColorAsState(colors.mesh[1], tween(520), label = "mesh 1")
    val c2 by animateColorAsState(colors.mesh[2], tween(520), label = "mesh 2")
    val c3 by animateColorAsState(colors.mesh[3], tween(520), label = "mesh 3")
    val motion by animateFloatAsState(if (playing) 1f else 0.15f, tween(1_200), label = "mesh motion")
    val speed by rememberUpdatedState(motion)

    // Time only moves forward at the current speed, so easing the speed
    // never makes the pools jump. New frames come as often as the speed
    // needs (`meshFrameMs`), not on every frame of the screen.
    val time = remember { mutableFloatStateOf(0f) }
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    LaunchedEffect(lifecycle) {
        lifecycle.repeatOnLifecycle(Lifecycle.State.STARTED) {
            var last = withFrameNanos { it }
            while (true) {
                delay(meshFrameMs(speed))
                withFrameNanos { now ->
                    time.floatValue += (now - last) / 1_000_000_000f * speed
                    last = now
                }
            }
        }
    }

    val shader = remember { RuntimeShader(MESH) }
    Box(
        modifier
            .fillMaxSize()
            .drawWithCache {
                val brush = ShaderBrush(shader)
                shader.setFloatUniform("size", size.width, size.height)
                onDrawBehind {
                    // Read here, in drawing, so each frame only redraws.
                    shader.setFloatUniform("time", time.floatValue)
                    shader.setColorUniform("c0", c0.toArgb())
                    shader.setColorUniform("c1", c1.toArgb())
                    shader.setColorUniform("c2", c2.toArgb())
                    shader.setColorUniform("c3", c3.toArgb())
                    drawRect(brush)
                }
            },
    )
}

// How long the mesh waits before its next frame at this speed (1 while
// music plays). At full speed the colour under any one pixel changes by
// about a level of brightness in a 30th of a second, which no eye picks
// out as a step, and slower it changes slower still, so it takes 30
// frames a second at full speed, fewer as it slows, and never under 10.
fun meshFrameMs(speed: Float): Long {
    val fps = (MESH_FULL_FPS * speed).coerceIn(MeshSlowestFps, MESH_FULL_FPS.toFloat())
    // Less a little, so the frame after the wait still lands on time.
    return (1_000f / fps).toLong() - MeshFrameSlackMs
}

const val MESH_FULL_FPS = 30
private const val MeshSlowestFps = 10f
private const val MeshFrameSlackMs = 4L

// Whether this phone can draw the live background.
val LiveBackgroundSupported = Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU
