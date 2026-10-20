package app.winters.octo.desktop.ui

import androidx.compose.runtime.staticCompositionLocalOf
import org.jetbrains.skia.DirectContext
import org.jetbrains.skiko.SkiaLayer
import java.awt.Component
import java.awt.Container
import java.awt.Window
import java.lang.reflect.Field
import java.lang.reflect.Method

// The graphics card context a window draws with, for drawing that keeps its
// own surfaces from frame to frame (the wash's working squares) instead of
// asking Skia for new textures each frame, which it keeps as spares long
// after. skiko keeps the context to itself, so it is reached through its
// insides; null when they are not as expected (another skiko), the window
// draws without the card, or it has not drawn yet, and the drawing falls
// back to its own way. Used on the window's thread, while it draws.
class WindowGpu(private val window: Window) {
    private var layer: SkiaLayer? = null

    fun context(): DirectContext? {
        val found = layer ?: findLayer(window)?.also { layer = it } ?: return null
        return contextOf(found)
    }

    companion object {
        private val redrawer: Method? by lazy {
            runCatching { SkiaLayer::class.java.getMethod("getRedrawer\$skiko") }.getOrNull()
        }
        private val handlerClass: Class<*>? by lazy {
            runCatching { Class.forName("org.jetbrains.skiko.context.ContextHandler") }.getOrNull()
        }
        private val getContext: Method? by lazy {
            runCatching { handlerClass?.getDeclaredMethod("getContext")?.apply { isAccessible = true } }.getOrNull()
        }
        // The context handler field, by redrawer class (Direct3D, OpenGL and
        // Metal each have their own).
        private val handlerFields = HashMap<Class<*>, Field?>()

        // Whether this skiko is laid out the way the lookup expects.
        val understood: Boolean get() = redrawer != null && handlerClass != null && getContext != null

        fun contextOf(layer: SkiaLayer): DirectContext? = runCatching {
            val drawer = redrawer?.invoke(layer) ?: return null
            val field = synchronized(handlerFields) {
                handlerFields.getOrPut(drawer.javaClass) { handlerFieldOf(drawer.javaClass) }
            } ?: return null
            val handler = field.get(drawer) ?: return null
            getContext?.invoke(handler) as? DirectContext
        }.getOrNull()

        internal fun handlerFieldOf(type: Class<*>): Field? {
            val wanted = handlerClass ?: return null
            var at: Class<*>? = type
            while (at != null) {
                at.declaredFields.firstOrNull { wanted.isAssignableFrom(it.type) }?.let { return it.apply { isAccessible = true } }
                at = at.superclass
            }
            return null
        }

        private fun findLayer(component: Component): SkiaLayer? {
            if (component is SkiaLayer) return component
            if (component is Container) component.components.forEach { child -> findLayer(child)?.let { return it } }
            return null
        }
    }
}

// The window's graphics card context, where there is one to reach.
val LocalWindowGpu = staticCompositionLocalOf<WindowGpu?> { null }
