package app.winters.octo.player

import androidx.datastore.preferences.core.emptyPreferences
import androidx.datastore.preferences.core.mutablePreferencesOf
import app.winters.octo.animated.AnimatedArtSetting
import org.junit.Assert.assertEquals
import org.junit.Test

// The Animated art choice as it is stored and read back.
class AnimatedArtPrefsTest {
    @Test
    fun nothingStoredMeansSquare() {
        assertEquals(AnimatedArtSetting.Square, animatedArtOf(emptyPreferences()))
    }

    @Test
    fun aChoiceIsStoredByItsKey() {
        assertEquals("animated_art", ANIMATED_ART.name)
        assertEquals(AnimatedArtSetting.FullScreen, animatedArtOf(mutablePreferencesOf(ANIMATED_ART to "full_screen")))
        assertEquals(AnimatedArtSetting.Off, animatedArtOf(mutablePreferencesOf(ANIMATED_ART to "off")))
        // Something this app does not know reads as Square.
        assertEquals(AnimatedArtSetting.Square, animatedArtOf(mutablePreferencesOf(ANIMATED_ART to "FullScreen")))
    }
}
