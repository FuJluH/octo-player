package app.winters.octo.desktop.perf

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.text.BasicText
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.ImageComposeScene
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.ExperimentalTextApi
import androidx.compose.ui.text.FontHinting
import androidx.compose.ui.text.FontRasterizationSettings
import androidx.compose.ui.text.FontSmoothing
import androidx.compose.ui.text.PlatformParagraphStyle
import androidx.compose.ui.text.PlatformTextStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.platform.SystemFont
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.winters.octo.design.OctoColors
import org.jetbrains.skia.Bitmap
import org.jetbrains.skia.Image
import org.jetbrains.skia.EncodedImageFormat
import org.jetbrains.skia.FontMgr
import org.jetbrains.skia.FontStyle
import org.jetbrains.skia.PixelGeometry
import org.jetbrains.skia.SurfaceProps
import org.junit.Assume.assumeTrue
import org.junit.Test
import java.io.File
import javax.swing.SwingUtilities

// The same words drawn each way the desktop could draw text, on the
// graphics card as the window draws: grey or colour (subpixel) smoothing,
// each hinting, on a surface that says its pixels are RGB or that does not,
// in the system's default face and in Segoe UI Variable. For choosing how
// text is drawn by eye, at native pixels. Only when asked:
// OCTO_SHOTS=1 ./gradlew :desktop:test --tests '*TextLookProbe*'; writes
// OCTO_SHOTS_DIR (else build/shots) text-look-*.png.
@OptIn(ExperimentalComposeUiApi::class, ExperimentalTextApi::class)
class TextLookProbe {
    private class Way(val name: String, val smoothing: FontSmoothing, val hinting: FontHinting, val geometry: PixelGeometry, val family: FontFamily?)

    @Test(timeout = 300_000)
    fun drawTheWords() {
        assumeTrue(System.getenv("OCTO_SHOTS") == "1")
        val gpu = offscreenGpu()
        assumeTrue(gpu != null)
        val out = File(System.getenv("OCTO_SHOTS_DIR") ?: "build/shots").apply { mkdirs() }
        val fonts = FontMgr.default
        val standard = fonts.legacyMakeTypeface("", FontStyle.NORMAL)
        println("default face: ${standard?.familyName}")
        val variable = fonts.matchFamilyStyle("Segoe UI Variable Text", FontStyle.NORMAL)?.let {
            FontFamily(listOf(FontWeight.Normal, FontWeight.Medium, FontWeight.SemiBold, FontWeight.Bold).map { w -> SystemFont("Segoe UI Variable Text", w) })
        }
        println("Segoe UI Variable Text: ${variable != null}")
        val ways = buildList {
            add(Way("now-grey-normal", FontSmoothing.AntiAlias, FontHinting.Normal, PixelGeometry.UNKNOWN, null))
            add(Way("lcd-unknown-surface", FontSmoothing.SubpixelAntiAlias, FontHinting.Normal, PixelGeometry.UNKNOWN, null))
            add(Way("lcd-rgb-normal", FontSmoothing.SubpixelAntiAlias, FontHinting.Normal, PixelGeometry.RGB_H, null))
            add(Way("lcd-rgb-slight", FontSmoothing.SubpixelAntiAlias, FontHinting.Slight, PixelGeometry.RGB_H, null))
            add(Way("lcd-rgb-full", FontSmoothing.SubpixelAntiAlias, FontHinting.Full, PixelGeometry.RGB_H, null))
            add(Way("grey-full", FontSmoothing.AntiAlias, FontHinting.Full, PixelGeometry.RGB_H, null))
            add(Way("grey-slight", FontSmoothing.AntiAlias, FontHinting.Slight, PixelGeometry.RGB_H, null))
            if (variable != null) add(Way("lcd-rgb-normal-variable", FontSmoothing.SubpixelAntiAlias, FontHinting.Normal, PixelGeometry.RGB_H, variable))
        }
        for (way in ways) {
            val width = 760
            val height = 300
            val settings = FontRasterizationSettings(smoothing = way.smoothing, hinting = way.hinting, subpixelPositioning = true, autoHintingForced = false)
            val base = TextStyle(fontFamily = way.family, platformStyle = PlatformTextStyle(null, PlatformParagraphStyle(settings)))
            lateinit var scene: ImageComposeScene
            SwingUtilities.invokeAndWait {
                scene = ImageComposeScene(width, height, Density(1f)) {
                    Row(Modifier.fillMaxSize()) {
                        Column(Modifier.width(260.dp).fillMaxSize().background(Color(0xFF3A0B07)).padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                            BasicText("Songs", style = base.copy(fontSize = 15.sp, color = OctoColors.TextSecondary))
                            BasicText("Albums", style = base.copy(fontSize = 15.sp, color = OctoColors.TextSecondary))
                            BasicText("Recently played", style = base.copy(fontSize = 15.sp, color = Color.White))
                            BasicText("PLAYLISTS", style = base.copy(fontSize = 12.sp, fontWeight = FontWeight.SemiBold, letterSpacing = 0.6.sp, color = OctoColors.TextMuted))
                        }
                        Column(Modifier.fillMaxSize().background(OctoColors.Background).padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                            BasicText("Paranoid Android", style = base.copy(fontSize = 14.sp, fontWeight = FontWeight.Medium, color = Color.White))
                            BasicText("Radiohead  ·  OK Computer  ·  6:27", style = base.copy(fontSize = 14.sp, color = OctoColors.TextSecondary))
                            BasicText("Karma Police", style = base.copy(fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = Color.White))
                            BasicText("Crossfade curve: picked for each blend", style = base.copy(fontSize = 13.sp, color = OctoColors.TextMuted))
                            BasicText("Library", style = base.copy(fontSize = 24.sp, fontWeight = FontWeight.Bold, color = Color.White))
                            BasicText("Cargo passed (1513 lib tests plus the registry tests).", style = base.copy(fontSize = 15.sp, color = Color(0xFFE8E8E8)))
                        }
                    }
                }
            }
            val target = GpuTarget(gpu!!, width, height, SurfaceProps(way.geometry))
            swapSurface(scene, target.surface)
            SwingUtilities.invokeAndWait {
                scene.render(0).close()
                scene.render(16_000_000).close()
            }
            target.finish()
            val bitmap = Bitmap().apply { allocN32Pixels(width, height) }
            target.surface.readPixels(bitmap, 0, 0)
            File(out, "text-look-${way.name}.png").writeBytes(Image.makeFromBitmap(bitmap).encodeToData(EncodedImageFormat.PNG)!!.bytes)
            SwingUtilities.invokeAndWait { scene.close() }
        }
    }
}
