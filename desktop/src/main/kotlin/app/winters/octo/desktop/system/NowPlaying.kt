package app.winters.octo.desktop.system

import app.winters.octo.desktop.player.PlayerState
import app.winters.octo.desktop.player.RepeatMode
import app.winters.octo.discovery.knownLengthMs
import app.winters.octo.subsonic.Song

// The song the system should show, taken from the player: what the media
// controls, the tray, the notifications and the mini player all read.
data class NowPlaying(
    // The queue entry, which tells two plays of the same song apart.
    val entryKey: Long,
    val songId: String,
    val title: String,
    val artist: String,
    val album: String,
    val albumArtist: String,
    val durationMs: Long,
    val coverId: String?,
    val trackNumber: Int?,
    val discNumber: Int?,
    val genres: List<String>,
    val playing: Boolean,
    // Previous always works with a song in: it goes back or starts over.
    val canPrevious: Boolean,
    val canNext: Boolean,
    // How fast the song plays, 1 for as recorded.
    val speed: Float = 1f,
    // Waiting for sound while playing: the place does not move on.
    val buffering: Boolean = false,
    // A live station: no length, no place to seek to, and Back and Next
    // change station.
    val live: Boolean = false,
    // Whether the station names a song now.
    val liveNamed: Boolean = false,
    // A live station's picture on the web: the song's artwork, else the
    // station's logo; null for the drawn cover.
    val artUrl: String? = null,
    // The station's name and stream, for its drawn cover.
    val station: String = "",
    val stream: String = "",
) {
    // How fast the place in the song moves on right now: 0 while paused,
    // waiting for sound, or on a live station, which has no place.
    val rate: Double get() = if (playing && !buffering && !live) speed.toDouble() else 0.0
}

// The album to show. An outside song whose album nobody knows reaches the
// app with its own title as the album, which Octo sends so iPhone Subsonic
// apps do not hide the song; Discord, the tray and the notices would show it
// as an album. A library single named after its song keeps its album.
internal fun shownAlbum(song: Song): String {
    val album = song.album.orEmpty()
    return if (song.isExternal && album.trim().equals(song.title.trim(), ignoreCase = true)) "" else album
}

// Whether an address is a picture on the web, which the system and Discord
// may be given (a station's own, never the server's signed one).
fun isWebPicture(url: String?): Boolean = url != null && (url.startsWith("https://", ignoreCase = true) || url.startsWith("http://", ignoreCase = true))

// What the system shows for the player's state, or null with nothing in.
fun nowPlayingOf(state: PlayerState): NowPlaying? {
    val entry = state.current ?: return null
    val song = entry.song
    val opened = openedFileOf(song.id)
    val live = state.live
    val canNext = state.upcoming.isNotEmpty() || (state.repeat == RepeatMode.All && state.queue.isNotEmpty())
    return NowPlaying(
        entryKey = entry.key,
        songId = song.id,
        title = song.title.ifBlank { opened?.let { titleFromFileName(it.path) } ?: "Unknown song" },
        artist = (song.displayArtist ?: song.artist).orEmpty(),
        album = shownAlbum(song),
        albumArtist = (song.displayAlbumArtist ?: song.albumArtists.joinToString(", ") { it.name }.ifBlank { null }).orEmpty(),
        durationMs = if (live != null) 0 else state.durationMs.takeIf { it > 0 } ?: knownLengthMs(song),
        coverId = song.coverArt,
        trackNumber = song.track,
        discNumber = song.discNumber,
        genres = song.genres.ifEmpty { listOfNotNull(song.genre) },
        playing = state.playing,
        // In a lineup of stations, Back and Next step through it and stop
        // at its ends; a station among songs goes back to the song before.
        canPrevious = when {
            live == null -> true
            live.lineup.shows -> live.lineup.hasPrevious
            else -> state.played.isNotEmpty()
        },
        canNext = if (live != null && live.lineup.shows) live.lineup.hasNext else canNext,
        speed = state.speed.takeIf { it.isFinite() && it > 0f } ?: 1f,
        buffering = state.buffering,
        live = live != null,
        liveNamed = live?.named == true,
        artUrl = live?.shown?.cover?.takeIf(::isWebPicture),
        station = live?.shown?.station.orEmpty(),
        stream = live?.shown?.streamUrl.orEmpty(),
    )
}
