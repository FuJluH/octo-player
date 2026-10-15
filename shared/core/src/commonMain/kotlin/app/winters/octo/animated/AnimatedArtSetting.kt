package app.winters.octo.animated

import app.winters.octo.subsonic.AnimatedArt
import app.winters.octo.subsonic.AnimatedClip

// How an album's animated art (Apple Music's animated covers, through an
// Octo server) shows in the app.
enum class AnimatedArtSetting(val key: String, val label: String, val about: String) {
    Square("square", "Square", "Plays in place of the cover on the player and on album pages."),
    FullScreen(
        "full_screen",
        "Full screen",
        "Fills the player when the album has a tall version, otherwise plays in place of the cover.",
    ),
    Off("off", "Off", "Always shows the still cover."),
    ;

    companion object {
        // Where the choice is kept, and what it is called.
        const val PREF_KEY = "animated_art"
        const val TITLE = "Animated art"
        const val ABOUT = "Apple Music's animated album covers, on Octo servers that offer them."

        val Default = Square

        fun fromKey(key: String?): AnimatedArtSetting = entries.firstOrNull { it.key == key } ?: Default
    }
}

// Where the player shows an album's animated art.
sealed interface PlayerLoop {
    // The square loop, in place of the cover.
    data class Cover(val clip: AnimatedClip) : PlayerLoop

    // The tall loop, filling the player behind the controls.
    data class Backdrop(val clip: AnimatedClip) : PlayerLoop

    // The still cover.
    data object None : PlayerLoop
}

// What the player shows for `art` with this setting: the tall loop behind
// everything when the setting is Full screen and the album has one, else
// the square loop in place of the cover.
fun AnimatedArtSetting.inPlayer(art: AnimatedArt?): PlayerLoop {
    if (this == AnimatedArtSetting.Off || art == null) return PlayerLoop.None
    val tall = art.tall?.takeIf { it.video.isNotBlank() }
    val square = art.square?.takeIf { it.video.isNotBlank() }
    return when {
        this == AnimatedArtSetting.FullScreen && tall != null -> PlayerLoop.Backdrop(tall)
        square != null -> PlayerLoop.Cover(square)
        else -> PlayerLoop.None
    }
}

// The loop an album page's header plays in place of its cover, if any.
fun AnimatedArtSetting.onAlbumPage(art: AnimatedArt?): AnimatedClip? =
    if (this == AnimatedArtSetting.Off) null else art?.square?.takeIf { it.video.isNotBlank() }
