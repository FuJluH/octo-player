package app.winters.octo.desktop.audio

import app.winters.octo.audio.TrackInfo
import app.winters.octo.desktop.player.DeviceFormat
import app.winters.octo.desktop.player.SongFormat
import app.winters.octo.desktop.player.libraryFormat
import app.winters.octo.subsonic.Song
import app.winters.octo.audio.OutputFormat as EngineFormat

// The decoder's word on a song, with the library's bit rate for a lossy
// one (the decoder does not say it). A song can arrive as another file than
// the one listed, so the bit rate is left out when the library lists
// another codec than the one opened.
fun songFormatOf(info: TrackInfo, song: Song?): SongFormat {
    val codec = info.codec.lowercase().let { codec ->
        // Plain samples are named for their file, WAV or AIFF; an opened
        // file has no suffix from a server, so its name says.
        val suffix = (song?.suffix ?: song?.id?.substringAfterLast('.', ""))?.lowercase()
        if (codec.startsWith("pcm")) suffix?.takeIf { it in setOf("wav", "aiff", "aif") } ?: "pcm" else codec
    }
    val listed = song?.let(::libraryFormat)?.codec
    return SongFormat(
        codec = codec,
        lossless = info.lossless,
        sampleRate = info.sampleRate.toInt().takeIf { it > 0 },
        bits = info.bitsPerSample?.toInt()?.takeIf { it > 0 },
        channels = info.channels.toInt().takeIf { it > 0 },
        bitRate = song?.bitRate?.takeIf { it > 0 && !info.lossless && (listed == null || listed == codec) },
    )
}

// What the engine says the device runs at.
fun deviceFormatOf(format: EngineFormat): DeviceFormat = DeviceFormat(
    sampleRate = format.sampleRate.toInt(),
    channels = format.channels.toInt(),
    bits = format.bits?.toInt(),
    float = format.sampleFormat.startsWith("f"),
)
