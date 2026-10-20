package app.winters.octo.desktop.ui

import org.junit.Test
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

// The wash reaches the window's graphics card context through skiko's
// insides; a skiko laid out otherwise would leave it on its fallback
// without a word, so its layout is checked here.
class WindowGpuTest {
    @Test
    fun thisSkikoIsLaidOutAsTheLookupExpects() {
        assertTrue(WindowGpu.understood)
        for (name in listOf("Direct3DRedrawer", "WindowsOpenGLRedrawer", "LinuxOpenGLRedrawer", "MetalRedrawer", "AngleRedrawer")) {
            val type = Class.forName("org.jetbrains.skiko.redrawer.$name")
            assertNotNull(WindowGpu.handlerFieldOf(type), "$name keeps its context handler where the lookup finds it")
        }
    }
}
