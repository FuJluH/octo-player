package app.winters.octo.playback

import android.view.KeyEvent
import androidx.media3.common.Player
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

// The phone's media controls while a station is on air: Stop where a song
// has Pause, and the keys that would pause it stop it.
class LiveTransportTest {
    private val station = radioId("https://stream.revma.ihrhls.com/zc185", "102.7 KIIS FM")

    @Test
    fun aStationIsOnAirWhilePlayingOrOnItsWay() {
        assertTrue(stationOnAir(station, playWhenReady = true, Player.STATE_READY))
        assertTrue(stationOnAir(station, playWhenReady = true, Player.STATE_BUFFERING))
        // Stopped, or let go: Play shows.
        assertFalse(stationOnAir(station, playWhenReady = false, Player.STATE_READY))
        assertFalse(stationOnAir(station, playWhenReady = true, Player.STATE_IDLE))
        assertFalse(stationOnAir(station, playWhenReady = true, Player.STATE_ENDED))
        // A song is never a station.
        assertFalse(stationOnAir("song-1", playWhenReady = true, Player.STATE_READY))
        assertFalse(stationOnAir(null, playWhenReady = true, Player.STATE_READY))
    }

    @Test
    fun onAirTheMediaControlsHaveNoPlayPause() {
        val all = setOf(Player.COMMAND_PLAY_PAUSE, Player.COMMAND_STOP, Player.COMMAND_SEEK_TO_NEXT, Player.COMMAND_SEEK_TO_PREVIOUS)
        assertEquals(all - Player.COMMAND_PLAY_PAUSE, mediaControlCommands(all, onAir = true))
        assertEquals(all, mediaControlCommands(all, onAir = false))
    }

    @Test
    fun onAirStopComesFirstThenTheHeartThenClose() {
        assertEquals(
            listOf(NotificationButton.Stop, NotificationButton.Close),
            notificationButtons(NotificationHeart.None, onAir = true),
        )
        // A stopped station: Play is back in the middle, so no Stop.
        assertEquals(listOf(NotificationButton.Close), notificationButtons(NotificationHeart.None, onAir = false))
        // Songs keep their heart and Close.
        assertEquals(
            listOf(NotificationButton.Unlike, NotificationButton.Close),
            notificationButtons(NotificationHeart.Like(liked = true), onAir = false),
        )
        assertEquals(
            listOf(NotificationButton.Download, NotificationButton.Close),
            notificationButtons(NotificationHeart.Download, onAir = false),
        )
    }

    @Test
    fun theKeysThatWouldPauseAStationStopIt() {
        listOf(KeyEvent.KEYCODE_HEADSETHOOK, KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE, KeyEvent.KEYCODE_MEDIA_PAUSE, KeyEvent.KEYCODE_MEDIA_STOP)
            .forEach { assertTrue("$it", keyStopsStation(it)) }
        listOf(KeyEvent.KEYCODE_MEDIA_PLAY, KeyEvent.KEYCODE_MEDIA_NEXT, KeyEvent.KEYCODE_MEDIA_PREVIOUS)
            .forEach { assertFalse("$it", keyStopsStation(it)) }
    }
}
