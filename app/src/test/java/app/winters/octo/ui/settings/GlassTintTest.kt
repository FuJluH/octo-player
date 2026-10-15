package app.winters.octo.ui.settings

import androidx.compose.ui.graphics.Color
import app.winters.octo.backup.Backup
import app.winters.octo.backup.BackupRead
import app.winters.octo.backup.decodeBackup
import app.winters.octo.backup.encodeBackup
import app.winters.octo.design.OctoAccent
import app.winters.octo.design.OctoColors
import app.winters.octo.player.PlayerPrefs
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

class GlassTintTest {
    private val coral = Color(0xFFEF9687)

    @After
    fun backToOcto() {
        OctoColors.useAccent(OctoAccent)
        OctoColors.tintGlass(false)
    }

    @Test
    fun theGlassKeepsOctosBlueGrayUntilItIsAskedToTakeTheAccent() {
        OctoColors.useAccent(coral)
        OctoColors.tintGlass(false)
        assertEquals(coral, OctoColors.Accent)
        assertEquals(OctoAccent, OctoColors.GlassAccent)

        OctoColors.tintGlass(true)
        assertEquals(coral, OctoColors.GlassAccent)
    }

    @Test
    fun theGlassIsLeftAloneByDefaultAndTheChoiceIsBackedUp() {
        assertFalse(PlayerPrefs().glassTint)
        val read = decodeBackup(encodeBackup(Backup(player = PlayerPrefs(glassTint = true)))) as BackupRead.Read
        assertEquals(true, read.backup.player?.glassTint)
    }
}
