package app.winters.octo.desktop.perf

import androidx.compose.ui.ImageComposeScene
import org.jetbrains.skia.ColorSpace
import org.jetbrains.skia.Surface
import org.jetbrains.skia.SurfaceColorFormat
import org.jetbrains.skia.SurfaceOrigin
import org.jetbrains.skia.SurfaceProps
import org.jetbrains.skiko.graphicapi.DirectXOffscreenContext

// A Direct3D texture off screen and a Skia surface over it, for timing
// Compose frames as the window draws them (on the graphics card).
internal class GpuTarget(private val context: DirectXOffscreenContext, width: Int, height: Int, props: SurfaceProps = SurfaceProps()) : AutoCloseable {
    private val texture = context.Texture(width, height)
    val surface: Surface = Surface.makeFromBackendRenderTarget(
        context.directContext,
        texture.backendRenderTarget,
        SurfaceOrigin.TOP_LEFT,
        SurfaceColorFormat.BGRA_8888,
        ColorSpace.sRGB,
        props,
    )!!

    // Waits until the graphics card has drawn everything sent so far.
    fun finish() {
        context.directContext.flushAndSubmit(surface, true)
        texture.waitForCompletion()
    }

    override fun close() {
        surface.close()
        texture.close()
    }
}

// The graphics card off screen, or null where Direct3D is not available.
internal fun offscreenGpu(): DirectXOffscreenContext? = runCatching { DirectXOffscreenContext() }.getOrNull()

// An ImageComposeScene draws into a surface of its own on the processor;
// for timing it is handed the graphics card's instead.
internal fun swapSurface(scene: ImageComposeScene, surface: Surface) {
    val field = ImageComposeScene::class.java.getDeclaredField("surface").apply { isAccessible = true }
    (field.get(scene) as Surface).close()
    field.set(scene, surface)
}
