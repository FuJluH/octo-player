package app.winters.octo.desktop.audio

import app.winters.octo.playback.radioOf
import app.winters.octo.subsonic.Song

// How a live station shows while its stream names what it plays: that
// title as the song, and the station's name (its address when it has none)
// as the artist. Any other song, or a station with no title yet, shows as
// it is.
fun onAir(song: Song, streamTitle: String?): Song {
    val title = streamTitle?.trim()?.takeIf(String::isNotEmpty) ?: return song
    val (stream, station) = radioOf(song.id) ?: return song
    return song.copy(title = title, artist = station.ifEmpty { stream }, displayArtist = null)
}
