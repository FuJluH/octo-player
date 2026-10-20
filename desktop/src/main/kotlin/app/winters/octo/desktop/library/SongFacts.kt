package app.winters.octo.desktop.library

import app.winters.octo.desktop.player.SongFormat
import app.winters.octo.desktop.player.codecName
import app.winters.octo.desktop.player.libraryFormat
import app.winters.octo.desktop.system.isOpenedFile
import app.winters.octo.server.serverTime
import app.winters.octo.subsonic.Song
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Locale

// One line of a song's details: what it is, and its value. `copyable`
// marks ids worth copying elsewhere.
data class SongFact(val label: String, val value: String, val copyable: Boolean = false)

// Everything the server says about a song, in the phone's words and order,
// leaving out what is not known. `server` names where it plays from. A
// song found online (`outside`) is not a file on the server, so it says
// how it streams instead, and nothing a file would have: no date added,
// size, bit depth or rating, and no plays until it has some.
// `opened` is the file the player opened for the song, when it is the one
// playing. A song can arrive as another file than the one listed: when the
// listing names a codec and the opened one is another, the format lines
// are the opened file's, and the listed file's type and size are left out.
fun songFacts(
    song: Song,
    server: String?,
    zone: ZoneId = ZoneId.systemDefault(),
    locale: Locale = Locale.getDefault(),
    outside: Boolean = false,
    opened: SongFormat? = null,
): List<SongFact> = buildList {
    fun add(label: String, value: String?, copyable: Boolean = false) {
        if (!value.isNullOrBlank()) add(SongFact(label, value, copyable))
    }
    add("Title", song.title)
    add("Artist", song.displayArtist ?: song.artist)
    add("Album", song.album)
    add("Album artist", song.displayAlbumArtist)
    add("Composer", song.displayComposer)
    add("Year", song.year?.takeIf { it > 0 }?.toString())
    val genres = (song.genres + listOfNotNull(song.genre)).filter(String::isNotBlank).distinctBy(String::lowercase)
    if (genres.isNotEmpty()) add(if (genres.size == 1) "Genre" else "Genres", genres.joinToString(", "))
    add("Track", song.track?.takeIf { it > 0 }?.toString())
    add("Disc", song.discNumber?.takeIf { it > 0 }?.toString())
    add("BPM", song.bpm?.takeIf { it > 0 }?.toString())
    add("Lyrics", when (song.explicitStatus?.lowercase()) {
        "explicit" -> "Explicit"
        "clean" -> "Clean"
        else -> null
    })
    add("Comment", song.comment)

    add("Length", lengthText(song.duration).takeIf { song.duration > 0 })
    val arrived = opened?.takeIf { now -> libraryFormat(song)?.codec.let { it != null && it != now.codec } }
    val format = arrived?.let { if (it.lossless) "${codecName(it.codec)}, lossless" else codecName(it.codec) } ?: formatName(song.suffix)
    val bitrate = (if (arrived != null) arrived.bitRate else song.bitRate)?.takeIf { it > 0 }?.let { "$it kbps" }
    if (outside) {
        add("Streams as", listOfNotNull(format, bitrate).joinToString(", "))
        add("Source", "Found online")
        add("Suggested by", song.octoSuggestedBy?.trim())
    } else {
        add("Format", format)
        if (arrived == null) add("File type", song.contentType)
        add("Bitrate", bitrate)
        add("Sample rate", (if (arrived != null) arrived.sampleRate else song.samplingRate)?.takeIf { it > 0 }?.let { sampleRateText(it, locale) })
        add("Bit depth", (if (arrived != null) arrived.bits else song.bitDepth)?.takeIf { it > 0 }?.let { "$it-bit" })
        if (arrived == null) add("File size", song.size?.takeIf { it > 0 }?.let { sizeText(it, locale) })
        add("Source", if (isOpenedFile(song.id)) "A file on this computer" else server ?: "Your server")
        add("Suggested by", song.octoSuggestedBy?.trim())
    }

    val dates = DateTimeFormatter.ofLocalizedDateTime(FormatStyle.MEDIUM, FormatStyle.SHORT).withLocale(locale).withZone(zone)
    if (!outside) add("Added", serverTime(song.created)?.let { dates.format(Instant.ofEpochMilli(it)) })
    val plays = song.playCount ?: 0
    if (!outside || plays > 0) add("Plays", "%,d".format(locale, plays))
    add("Last played", serverTime(song.played)?.let { dates.format(Instant.ofEpochMilli(it)) })
    if (!outside) add("Rating", song.userRating?.takeIf { it > 0 }?.let { if (it == 1) "1 star" else "$it stars" })

    val gain = song.replayGain
    add("Track gain", gain?.trackGain?.let { gainText(it, locale) })
    add("Track peak", gain?.trackPeak?.let { "%.3f".format(locale, it) })
    add("Album gain", gain?.albumGain?.let { gainText(it, locale) })
    add("Album peak", gain?.albumPeak?.let { "%.3f".format(locale, it) })

    if (song.isrc.isNotEmpty()) add(if (song.isrc.size == 1) "ISRC" else "ISRCs", song.isrc.joinToString("\n"), copyable = true)
    add("Recording MBID", song.musicBrainzId, copyable = true)
}

// The codec by its file suffix, and whether it keeps every bit.
fun formatName(suffix: String?): String? {
    val lower = suffix?.lowercase()?.takeIf(String::isNotBlank) ?: return null
    val lossless = lower in setOf("flac", "alac", "wav", "aiff", "aif", "ape", "wv", "dsf", "dff")
    val name = when (lower) {
        "m4a", "mp4" -> "AAC"
        "ogg", "oga" -> "Vorbis"
        else -> lower.uppercase(Locale.ROOT)
    }
    return if (lossless) "$name, lossless" else name
}

// 44100 reads as "44.1 kHz", 48000 as "48 kHz".
fun sampleRateText(hz: Int, locale: Locale = Locale.getDefault()): String =
    if (hz % 1000 == 0) "${hz / 1000} kHz" else "%.1f kHz".format(locale, hz / 1000.0)

// Kilobytes under a megabyte, megabytes under a gigabyte, gigabytes above.
fun sizeText(bytes: Long, locale: Locale = Locale.getDefault()): String = when {
    bytes < 1_048_576 -> "%.0f KB".format(locale, bytes / 1024.0)
    bytes < 1_073_741_824 -> "%.1f MB".format(locale, bytes / 1_048_576.0)
    else -> "%.2f GB".format(locale, bytes / 1_073_741_824.0)
}

// A gain in decibels with its sign, like "-7.2 dB".
fun gainText(db: Float, locale: Locale = Locale.getDefault()): String = "%+.1f dB".format(locale, db)
