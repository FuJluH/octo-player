package app.winters.octo.playback

import android.view.KeyEvent
import androidx.media3.common.Player

// Whether a station is on air in the player: a station is current and is
// playing or on its way to. A station that is stopped shows Play.
fun stationOnAir(mediaId: String?, playWhenReady: Boolean, playbackState: Int): Boolean =
    mediaId != null && isRadio(mediaId) && playWhenReady && playbackState != Player.STATE_IDLE && playbackState != Player.STATE_ENDED

// The player commands the phone's media controls get. While a station is
// on air they have no play/pause, so they draw no pause button; Stop
// stands in its place (see notificationButtons). Everything else is left
// as `commands` has it.
fun mediaControlCommands(commands: Set<Int>, onAir: Boolean): Set<Int> =
    if (onAir) commands - Player.COMMAND_PLAY_PAUSE else commands

// The extra buttons the phone's media controls show, in order.
enum class NotificationButton { Stop, Like, Unlike, Download, Close }

fun notificationButtons(heart: NotificationHeart, onAir: Boolean): List<NotificationButton> = buildList {
    if (onAir) add(NotificationButton.Stop)
    when (heart) {
        is NotificationHeart.Like -> add(if (heart.liked) NotificationButton.Unlike else NotificationButton.Like)
        NotificationHeart.Download -> add(NotificationButton.Download)
        NotificationHeart.None -> Unit
    }
    add(NotificationButton.Close)
}

// Whether a media key stops a station that is on air: the headset's button,
// play/pause, pause and stop all do. Play, next and previous are left to
// the player.
fun keyStopsStation(keyCode: Int): Boolean = keyCode in StopKeys

private val StopKeys = setOf(
    KeyEvent.KEYCODE_HEADSETHOOK,
    KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE,
    KeyEvent.KEYCODE_MEDIA_PAUSE,
    KeyEvent.KEYCODE_MEDIA_STOP,
)
