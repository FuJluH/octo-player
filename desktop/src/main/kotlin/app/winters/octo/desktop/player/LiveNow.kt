package app.winters.octo.desktop.player

import app.winters.octo.liveradio.LiveLineup
import app.winters.octo.liveradio.LiveShown
import app.winters.octo.liveradio.liveLineup
import app.winters.octo.liveradio.liveShown
import app.winters.octo.playback.isRadio
import app.winters.octo.subsonic.Song

// What the player shows while a live station plays: what the station has
// on air (the song, its artist and artwork, or the station itself), and the
// stations Back and Next step through.
data class LiveNow(val shown: LiveShown, val lineup: LiveLineup) {
    // Whether the station names a song now, which the heart can star.
    val named: Boolean get() = shown.onAir.named

    // The song on air as "Artist - Title", or the title alone; empty while
    // the station names none.
    val songName: String get() = if (!named) "" else listOf(shown.onAir.artist, shown.onAir.title).filter(String::isNotBlank).joinToString(" - ")
}

// Whether every entry of a queue is a live station: a lineup, which plays
// in its own order with no shuffle, no repeat and no Autoplay.
fun isLineup(songs: List<Song>): Boolean = songs.isNotEmpty() && songs.all { isRadio(it.id) }

internal fun PlayQueue.isLineup(): Boolean = size > 0 && songs.all { isRadio(it.song.id) }

// The lineup of the queue as it plays now, or null when no station plays.
internal fun PlayQueue.lineupNow(): LiveLineup? {
    if (currentEntry == null) return null
    val order = playOrder
    val entries = songs
    return liveLineup(order.map { entries[it].song.id }, order.indexOf(current))
}

// The queue position Back (or Next, `forward`) goes to in a lineup: null at
// its ends, and null when the queue is no lineup.
internal fun PlayQueue.lineupStep(forward: Boolean): Int? {
    if (!isLineup()) return null
    val lineup = lineupNow() ?: return null
    val at = (if (forward) lineup.next else lineup.previous) ?: return null
    return playOrder.getOrNull(at)
}

// What the player shows for its current entry, a station: from what its
// stream named last.
internal fun PlayQueue.liveNow(streamTitle: String?, streamUrl: String?): LiveNow? {
    val current = currentEntry ?: return null
    val shown = liveShown(current.song.id, streamTitle, streamUrl) ?: return null
    val lineup = lineupNow() ?: return null
    return LiveNow(shown, lineup)
}

// A station's entry as every screen and the system show it while it plays:
// the song on air as the title, its artist as the artist and the station as
// the album; while it names none, the station as the title and its tagline
// or place as the artist. Only the playing entry carries it, so a saved
// queue keeps the station.
fun shownLive(song: Song, shown: LiveShown): Song {
    val named = shown.onAir.named
    return song.copy(
        title = shown.title,
        artist = if (named) shown.onAir.artist.ifBlank { shown.station } else shown.subtitle,
        displayArtist = null,
        artistId = null,
        album = if (named) shown.station else "",
        albumId = null,
        coverArt = shown.details.coverArt.ifBlank { null } ?: song.coverArt,
    )
}
