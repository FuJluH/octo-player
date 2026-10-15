package app.winters.octo.animated

import app.winters.octo.subsonic.AnimatedArt

// Where the full player shows the song's animated art: as the setting says
// (see inPlayer), except that sideways, with no room for the tall loop,
// Full screen plays the square one in the cover's place, and a live
// station shows none.
fun playerLoop(setting: AnimatedArtSetting, art: AnimatedArt?, upright: Boolean, live: Boolean): PlayerLoop = when {
    live -> PlayerLoop.None
    !upright && setting == AnimatedArtSetting.FullScreen -> AnimatedArtSetting.Square.inPlayer(art)
    else -> setting.inPlayer(art)
}
