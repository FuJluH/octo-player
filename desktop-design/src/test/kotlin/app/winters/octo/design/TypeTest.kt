package app.winters.octo.design

import androidx.compose.ui.text.ExperimentalTextApi
import androidx.compose.ui.text.FontHinting
import androidx.compose.ui.text.FontSmoothing
import androidx.compose.ui.text.TextStyle
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class TypeTest {
    // Every style on both scales, read from the objects so a new one is covered too.
    private fun stylesOf(scale: Any): Map<String, TextStyle> = scale.javaClass.declaredFields
        .filter { it.type == TextStyle::class.java }
        .associate { field -> field.isAccessible = true; field.name to field.get(scale) as TextStyle }

    private val styles = stylesOf(DesktopType).mapKeys { "DesktopType.${it.key}" } + stylesOf(OctoType).mapKeys { "OctoType.${it.key}" }

    @OptIn(ExperimentalTextApi::class)
    @Test
    fun everyStyleIsDrawnTheSameCrispWay() {
        assertTrue(styles.size >= 16)
        for ((name, style) in styles) {
            assertEquals(name, TextDrawing, style.platformStyle?.paragraphStyle?.fontRasterizationSettings)
        }
        // Unless the start asked for colour smoothing (TextLook.colour),
        // grey smoothing; fitted to the grid either way, since no fitting
        // blurs small text.
        assertEquals(if (TextLook.colour) FontSmoothing.SubpixelAntiAlias else FontSmoothing.AntiAlias, TextDrawing.smoothing)
        assertNotEquals(FontHinting.None, TextDrawing.hinting)
    }

    @Test
    fun sizesAreWholePixels() {
        for ((name, style) in styles) {
            val size = style.fontSize.value
            assertEquals(name, size.toInt().toFloat(), size, 0f)
        }
    }

    @Test
    fun theDesktopReadsAStepUpFromThePhone() {
        // The phone's body text is 14 and its small print 12.
        assertEquals(15f, DesktopType.body.fontSize.value, 0f)
        assertEquals(13f, DesktopType.meta.fontSize.value, 0f)
        assertEquals(DesktopType.body, OctoType.bodySmall)
        assertEquals(DesktopType.meta, OctoType.caption)
        assertTrue(DesktopType.table.fontSize.value >= 14f)
    }
}
