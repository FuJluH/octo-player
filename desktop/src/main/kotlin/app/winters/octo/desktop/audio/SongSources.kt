package app.winters.octo.desktop.audio

import java.io.File
import app.winters.octo.audio.HttpHeader
import app.winters.octo.audio.QueueItem
import app.winters.octo.audio.ReplayGainInfo
import app.winters.octo.desktop.player.QueueEntry
import app.winters.octo.desktop.system.isOpenedFile
import app.winters.octo.desktop.system.openedFileOf
import app.winters.octo.discovery.knownLengthMs
import app.winters.octo.playback.isRadio
import app.winters.octo.playback.radioOf
import app.winters.octo.subsonic.Song
import app.winters.octo.subsonic.SubsonicClient
import app.winters.octo.playback.radioIsHls

// Where the engine fetches a song from: a file path, or a signed stream
// address, with any extra request headers it needs.
data class SongAddress(val source: String, val headers: Map<String, String> = emptyMap())

// Turns a song into the address the engine plays it from, or null when it
// cannot be played now (signed out, say).
fun interface SongSources {
    fun addressOf(song: Song): SongAddress?
}

// Songs from the signed-in server, as the phone streams them: the file as
// it is ("format=raw", the original quality) or, at a smaller `quality`, an
// MP3 the server makes on the way, at an address signed the way every
// other call is, with the server's extra headers. The engine reuses the
// address for range requests and reconnects (a made MP3 it opens again at
// a time instead), so it is signed when the song is queued. A song found
// online that the server has since fetched into the library (`landed`
// names its library id) plays from that file.
class ServerSongs(
    private val headers: () -> Map<String, String> = { emptyMap() },
    private val landed: (String) -> String? = { null },
    // What the stream asks for: the file as it is unless this app picks a
    // lower quality (see streamParams).
    private val params: () -> Map<String, String> = { mapOf("format" to "raw") },
    private val client: () -> SubsonicClient?,
) : SongSources {
    override fun addressOf(song: Song): SongAddress? {
        val server = client() ?: return null
        val id = landed(song.id) ?: song.id
        return SongAddress(server.url("stream", mapOf("id" to id) + params()).toString(), headers())
    }
}

// A song's id on the server, for asking the server about it: the library
// copy of a song found online once it has one, and nothing for a file on
// this computer.
fun serverSongId(song: Song, landed: (String) -> String?): String? = when {
    song.id.startsWith(LOCAL_PREFIX) || isOpenedFile(song.id) -> null
    else -> landed(song.id) ?: song.id
}

// Songs whose id starts with this are files on this computer, the rest of
// the id being the path.
const val LOCAL_PREFIX = "local:"

// Files on this computer by path, live radio from its station's own
// address, and everything else from the server.
class LocalOrServer(
    private val server: SongSources,
    // A copy kept on this computer, played in place of the server's.
    private val kept: (String) -> File? = { null },
) : SongSources {
    override fun addressOf(song: Song): SongAddress? =
        when {
            kept(song.id) != null -> SongAddress(kept(song.id)!!.absolutePath)
            song.id.startsWith(LOCAL_PREFIX) -> SongAddress(song.id.removePrefix(LOCAL_PREFIX))
            // The station's own server, so none of Octo's headers go along.
            isRadio(song.id) -> radioOf(song.id)?.let { (stream, _) -> SongAddress(stream) }
            // A file opened from the system (a double click, a drop): the
            // file itself, or the address it was opened from.
            isOpenedFile(song.id) -> openedFileOf(song.id)?.let { SongAddress(it.path?.absolutePath ?: it.uri) }
            else -> server.addressOf(song)
        }
}

// The engine's name for a queue entry, handed back in its events.
fun itemId(key: Long): String = "q:$key"

fun keyOfItem(id: String?): Long? = id?.removePrefix("q:")?.toLongOrNull()

// Disc and track in one number, for telling an album played in order.
fun albumOrder(song: Song): Int? = song.track?.let { (song.discNumber ?: 1) * 1000 + it }

// A queue entry as the engine takes it. The length goes along when it is
// known: without it the engine cannot plan a crossfade and joins songs
// gaplessly instead. A song found online often comes with Octo's 3:00
// guess, which is left out, so the engine takes the length from the file
// as the phone does. A song that cannot be reached gets an address that fails, so
// the engine reports it and moves on, as it does for any broken file. Live
// radio is a live stream, with no length at all.
fun queueItem(entry: QueueEntry, sources: SongSources): QueueItem {
    val song = entry.song
    val address = sources.addressOf(song)
    val live = isRadio(song.id)
    val gain = song.replayGain?.let {
        if (it.trackGain == null && it.albumGain == null) null else ReplayGainInfo(it.trackGain, it.trackPeak, it.albumGain, it.albumPeak)
    }
    return QueueItem(
        id = itemId(entry.key),
        source = address?.source ?: UNREACHABLE,
        albumId = song.albumId,
        albumOrder = albumOrder(song),
        durationMs = knownLengthMs(song).takeIf { it > 0 && !live }?.toULong(),
        replayGain = gain,
        headers = address?.headers.orEmpty().map { (name, value) -> HttpHeader(name, value) },
        genre = genreOf(song),
        bpm = song.bpm?.takeIf { it > 0 }?.toDouble(),
        live = live,
        hls = live && radioIsHls(song.id),
    )
}


// Every genre a song has, in one line: a song in any genre that is never
// mixed (classical, a podcast) gets the plain crossfade.
fun genreOf(song: Song): String? = (listOfNotNull(song.genre) + song.genres).distinct().joinToString("; ").ifEmpty { null }

// An address no file has, for a song with nowhere to play from.
private const val UNREACHABLE = "octo-unreachable:"
