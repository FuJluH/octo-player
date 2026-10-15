package app.winters.octo.desktop.ui

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import app.winters.octo.design.OctoAccent
import app.winters.octo.design.OctoColors
import app.winters.octo.desktop.a11y.A11yScene
import app.winters.octo.desktop.a11y.name
import app.winters.octo.desktop.nav.Page
import app.winters.octo.desktop.pages.showSection
import app.winters.octo.theme.AccentChoice
import app.winters.octo.theme.accentFromArt
import org.jetbrains.skia.EncodedImageFormat
import org.jetbrains.skia.Paint
import org.jetbrains.skia.Surface
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File

// The accent picker in Settings > Appearance: the saved choice is the one
// checked, picking another saves it and redraws the app in it, and From
// the album art follows the playing cover. With OCTO_SHOTS=1 the frames
// are kept (in OCTO_SHOTS_DIR when set).
class AccentShotsTest {
    @get:Rule val folder = TemporaryFolder()

    @After
    fun backToOctosOwn() = OctoColors.useAccent(OctoAccent)

    private fun keep(scene: A11yScene, name: String, ms: Long = 1_500) {
        val image = scene.settle(ms)
        if (System.getenv("OCTO_SHOTS") != "1") return
        val dir = File(System.getenv("OCTO_SHOTS_DIR") ?: "build/shots").apply { mkdirs() }
        File(dir, "$name.png").writeBytes(image.encodeToData(EncodedImageFormat.PNG)!!.bytes)
    }

    private fun A11yScene.swatch(label: String) = nodes().first { node ->
        node.name() == label && node.config.getOrNull(SemanticsProperties.Selected) != null
    }

    private fun A11yScene.openAppearance() {
        onUi {
            showSection("Settings", "look")
            app.navigator.go(Page.Settings)
        }
        render(6)
    }

    @Test(timeout = 120_000)
    fun theSavedAccentIsCheckedAndPickingAnotherRedrawsTheApp() {
        A11yScene(folder.newFolder(), look = { it.copy(appearance = it.appearance.copy(accent = AccentChoice.Coral)) }).use { s ->
            s.openAppearance()
            keep(s, "accent-settings-coral")
            assertEquals(Color(AccentChoice.Coral.argb!!), OctoColors.Accent)
            assertEquals(true, s.swatch("Coral").config.getOrNull(SemanticsProperties.Selected))
            assertEquals(false, s.swatch("Octo").config.getOrNull(SemanticsProperties.Selected))
            val words = s.nodes().map { it.name() }
            assertTrue(words.any { it.startsWith("Coral: Selections, sliders, switches and buttons") })

            s.onUi { s.swatch("Mint").config[SemanticsActions.OnClick].action?.invoke() }
            s.render(4)
            assertEquals(AccentChoice.Mint, s.app.settings.current.appearance.accent)
            assertEquals(Color(AccentChoice.Mint.argb!!), OctoColors.Accent)
            assertEquals(true, s.swatch("Mint").config.getOrNull(SemanticsProperties.Selected))
            keep(s, "accent-settings-mint")

            // The desktop player bar: its cover has no ring and no play
            // button over it; play and pause are the transport's own.
            s.onUi {
                s.app.play(s.app.library!!.index!!.songs, 0)
                s.app.player.togglePlay()
                s.app.navigator.go(Page.Songs)
            }
            keep(s, "desktop-player-bar-paused", 2_000)
        }
    }

    @Test(timeout = 120_000)
    fun fromTheAlbumArtFollowsThePlayingCover() {
        val red = Surface.makeRasterN32Premul(300, 300).run {
            canvas.clear(0xFFC81E2C.toInt())
            canvas.drawCircle(150f, 150f, 60f, Paint().apply { color = 0xFF8A1020.toInt() })
            makeImageSnapshot().encodeToData(EncodedImageFormat.PNG)!!.bytes
        }
        A11yScene(folder.newFolder(), cover = red, coverId = "accent-red", look = { it.copy(appearance = it.appearance.copy(accent = AccentChoice.FromArt)) }).use { s ->
            // Nothing playing: Octo's own.
            s.render(4)
            assertEquals(OctoAccent, OctoColors.Accent)
            s.onUi { s.app.play(s.app.library!!.index!!.songs, 0) }
            val until = System.currentTimeMillis() + 15_000
            while (OctoColors.Accent == OctoAccent && System.currentTimeMillis() < until) s.render(2)
            val accent = OctoColors.Accent
            val expected = accentFromArt(0xFFC81E2C.toInt())!!
            // A red cover gives a light red accent, readable on the page.
            assertTrue("accent $accent", accent.red > accent.green && accent.red > accent.blue)
            assertTrue(Color(expected).red > Color(expected).blue)
            s.openAppearance()
            keep(s, "accent-settings-from-art", 2_000)
        }
    }
}
