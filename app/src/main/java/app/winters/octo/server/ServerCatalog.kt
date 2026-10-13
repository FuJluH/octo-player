package app.winters.octo.server

import app.winters.octo.catalog.ArtworkRef
import app.winters.octo.catalog.SourceAlbumEntity
import app.winters.octo.catalog.SourceArtistEntity
import app.winters.octo.catalog.SourceTrackEntity
import app.winters.octo.catalog.joinLines
import app.winters.octo.catalog.relinkKey
import app.winters.octo.catalog.searchKey
import app.winters.octo.catalog.sortKey
import app.winters.octo.device.explicitOf
import app.winters.octo.device.musicIds
import app.winters.octo.device.parseGenres
import app.winters.octo.subsonic.Album
import app.winters.octo.subsonic.Library
import app.winters.octo.subsonic.Song
import okhttp3.HttpUrl
import java.time.LocalDateTime
import java.time.OffsetDateTime
import java.time.ZoneOffset

private const val SERVER = "server"
private const val UNKNOWN_ARTIST = "Unknown artist"
private const val UNKNOWN_ALBUM = "Unknown album"

// The source a server's music is kept under: its host, and its port when
// that is not the usual one for the address. Always made from the server's
// main address, so moving between home and away keeps the same library.
fun serverSourceId(base: HttpUrl): String {
    val port = if (base.port == HttpUrl.defaultPort(base.scheme)) "" else ":${base.port}"
    return "$SERVER:${base.host}$port"
}

fun isServerSource(sourceId: String) = sourceId.startsWith("$SERVER:")

class ServerCatalog(
    val tracks: List<SourceTrackEntity>,
    val albums: List<SourceAlbumEntity>,
    val artists: List<SourceArtistEntity>,
) {
    val isEmpty get() = tracks.isEmpty() && albums.isEmpty() && artists.isEmpty()
}

// Of the rows made for music taken in ahead of a full copy, those that go
// in: songs the library lacks (`haveSongs`, by server id), albums it lacks
// (`haveAlbums`) or that were just read whole from the server (`readAlbums`,
// whose details and song counts replace the kept ones), and artists it
// lacks (`haveArtists`, by row id). An album made up from songs alone never
// replaces a kept one.
fun rowsToTakeIn(
    rows: ServerCatalog,
    haveSongs: Set<String>,
    haveAlbums: Set<String>,
    readAlbums: Set<String>,
    haveArtists: Set<String>,
): ServerCatalog = ServerCatalog(
    rows.tracks.filter { it.nativeId !in haveSongs },
    rows.albums.filter { it.nativeId !in haveAlbums || it.nativeId in readAlbums },
    rows.artists.filter { it.id !in haveArtists },
)

// Turns what a server lists into its source's rows, shaped like the
// phone's so the two merge: a song's artist id is its album artist's, its
// keys come from the same functions, and times added are in seconds.
fun buildServerCatalog(sourceId: String, library: Library): ServerCatalog {
    fun id(native: String) = "$sourceId:$native"
    fun art(coverId: String?, fallbackId: String? = null) =
        coverId?.takeIf(String::isNotEmpty)?.let { ArtworkRef.Server(sourceId, it, fallbackId = fallbackId).encode() }

    // A library that changes while it is read can repeat a song across pages.
    // A song the server marks as outside the library (Octo lists an album's
    // missing tracks with it) is not a library song, so it is not kept.
    val songs = library.songs.filterNot { it.isExternal }.distinctBy { it.id }

    // A song whose album was added after the album list was read still
    // gets an album, made from its songs.
    val listed = library.albums.associateBy { it.id }
    val unlisted = songs.filter { albumKey(it) !in listed }.groupBy(::albumKey)
        .map { (key, group) -> albumFromSongs(key, group) }

    val albumsByKey = (listed.values + unlisted).associateBy { it.id }
    // Each artist's MusicBrainz id, where the server knows it.
    val artistIds = library.artists.mapNotNull { artist -> musicId(artist.musicBrainzId)?.let { artist.id to it } }.toMap()

    // Each album's first song's own cover, drawn in place of the album's when
    // the server answers that with its stand-in picture. One per album, so
    // its songs still share one picture and one stored cover.
    val firstSongCovers = songs.groupBy(::albumKey).mapValues { (_, group) -> inAlbumOrder(group).first().coverArt }

    val albumRows = albumsByKey.values.associate { album ->
        val title = album.name.ifBlank { UNKNOWN_ALBUM }
        val artist = album.artist.ifBlank { UNKNOWN_ARTIST }
        album.id to SourceAlbumEntity(
            id = id(album.id),
            sourceId = sourceId,
            nativeId = album.id,
            title = title,
            searchKey = searchKey("$title $artist"),
            sortKey = sortKey(title),
            artist = artist,
            artistId = id(album.artistId?.takeIf(String::isNotEmpty) ?: "artist:${searchKey(artist)}"),
            // The year it shows: the first edition's where known.
            year = albumYears(album).let { it.original ?: it.year },
            songCount = album.songCount,
            durationMs = album.duration * 1000L,
            addedAt = seconds(album.created) ?: 0,
            artwork = art(album.coverArt, firstSongCovers[album.id]),
            releaseTypes = joinLines(album.releaseTypes.map(String::trim).filter(String::isNotEmpty)),
        )
    }

    val tracks = songs.groupBy(::albumKey).flatMap { (key, group) ->
        val album = albumRows.getValue(key)
        val listedAlbum = albumsByKey[key]
        val albumYear = listedAlbum?.let(::albumYears)
        inAlbumOrder(group).mapIndexed { index, song ->
            val title = song.title.ifBlank { "Untitled" }
            val durationMs = song.duration * 1000L
            val year = song.year.positive() ?: albumYear?.year
            val genres = song.genres.ifEmpty { parseGenres(listOfNotNull(song.genre)) }
            SourceTrackEntity(
                id = id(song.id),
                sourceId = sourceId,
                nativeId = song.id,
                title = title,
                searchKey = searchKey(title),
                sortKey = sortKey(title),
                artist = (song.displayArtist ?: song.artist)?.takeIf(String::isNotBlank) ?: album.artist,
                artistId = album.artistId,
                album = album.title,
                albumId = album.id,
                trackNo = song.track.positive(),
                discNo = song.discNumber.positive(),
                year = year,
                durationMs = durationMs,
                // Navidrome's "created" for a song is when its scan first saw
                // the file (the file's modified time only when the server is
                // set to sort recently added by it). Subsonic and OpenSubsonic
                // send nothing nearer to when the song was really got, so the
                // merge takes the earliest time any copy has, usually the
                // phone file's own.
                addedAt = seconds(song.created) ?: album.addedAt,
                mimeType = mimeFor(song.suffix) ?: song.contentType,
                sizeBytes = song.size,
                // The album's cover first, so an album's songs share one picture.
                artwork = album.artwork ?: art(song.coverArt),
                uri = null,
                albumOrder = index,
                relinkKey = relinkKey(album.artist, album.title, song.discNumber.positive(), song.track.positive(), title, durationMs),
                genre = genres.firstOrNull() ?: song.genre?.trim().orEmpty(),
                bitrate = song.bitRate.positive()?.times(1000),
                sampleRate = song.samplingRate.positive(),
                bitDepth = song.bitDepth.positive(),
                playCount = song.playCount?.toInt(),
                lastPlayedAt = epochMs(song.played),
                starredAt = epochMs(song.starred),
                trackGain = song.replayGain?.trackGain.finite(),
                albumGain = song.replayGain?.albumGain.finite(),
                trackPeak = song.replayGain?.trackPeak.finite()?.takeIf { it > 0f },
                albumPeak = song.replayGain?.albumPeak.finite()?.takeIf { it > 0f },
                baseGain = song.replayGain?.baseGain.finite(),
                fallbackGain = song.replayGain?.fallbackGain.finite(),
                rating = song.userRating?.coerceIn(0, 5),
                // The album's first-edition year, which cannot be after this one's.
                originalYear = albumYear?.original?.takeIf { year == null || it <= year },
                genres = joinLines(genres),
                artists = joinLines(song.artists.map { it.name.trim() }.filter(String::isNotEmpty)),
                composer = song.displayComposer.orBlankNull(),
                bpm = song.bpm.positive(),
                comment = song.comment.orBlankNull(),
                // The song's own mark only: an album is marked explicit when
                // any one of its songs is, which says nothing of the others.
                explicit = explicitOf(song.explicitStatus.orEmpty()),
                discTitle = listedAlbum?.discTitles?.firstOrNull { it.disc == (song.discNumber.positive() ?: 1) }?.title.orBlankNull(),
                mbRecordingId = musicId(song.musicBrainzId),
                mbAlbumId = musicId(listedAlbum?.musicBrainzId),
                mbArtistIds = joinLines(song.artists.mapNotNull { artistIds[it.id] }.distinct()),
                personal = song.octoPersonal,
            )
        }
    }

    // Artists are the album artists, as the phone's are, named as the
    // server's artist list names them.
    val listedArtists = library.artists.associateBy { id(it.id) }
    val songsBy = tracks.groupingBy { it.artistId }.eachCount()
    val artists = albumRows.values.groupBy { it.artistId }.map { (artistId, owned) ->
        val listedArtist = listedArtists[artistId]
        val name = listedArtist?.name?.takeIf(String::isNotBlank) ?: owned.first().artist
        SourceArtistEntity(
            id = artistId,
            sourceId = sourceId,
            name = name,
            searchKey = searchKey(name),
            sortKey = sortKey(name),
            albumCount = owned.size,
            songCount = songsBy[artistId] ?: 0,
            artwork = owned.maxBy { it.addedAt }.artwork ?: art(listedArtist?.coverArt),
        )
    }

    return ServerCatalog(tracks, albumRows.values.toList(), artists)
}

private fun albumKey(song: Song): String = song.albumId?.takeIf(String::isNotEmpty) ?: "album:${searchKey(song.album.orEmpty())}"

private fun albumFromSongs(key: String, songs: List<Song>): Album {
    val first = songs.first()
    return Album(
        id = key,
        name = first.album.orEmpty(),
        artist = listOfNotNull(
            first.displayAlbumArtist,
            first.albumArtists.joinToString(", ") { it.name.trim() },
            first.artist,
        ).firstOrNull(String::isNotBlank).orEmpty(),
        coverArt = first.coverArt,
        songCount = songs.size,
        duration = songs.sumOf { it.duration },
        year = songs.firstNotNullOfOrNull { it.year.positive() },
        created = songs.mapNotNull { it.created }.maxOrNull(),
    )
}

// Disc, then track number, then title.
private fun inAlbumOrder(songs: List<Song>): List<Song> =
    songs.sortedWith(
        compareBy<Song> { it.discNumber.positive() ?: 1 }
            .thenBy { it.track.positive() ?: Int.MAX_VALUE }
            .thenBy { sortKey(it.title) },
    )

// This edition's year and the first edition's, as an album gives them. The
// older year field is this edition's; the release dates are OpenSubsonic's.
private class AlbumYears(val year: Int?, val original: Int?)

private fun albumYears(album: Album): AlbumYears {
    val year = album.year.positive() ?: album.releaseDate?.year.positive()
    val original = album.originalReleaseDate?.year.positive()
    return AlbumYears(year, original?.takeIf { year == null || it <= year })
}

private fun String?.orBlankNull(): String? = this?.trim()?.takeIf(String::isNotEmpty)

// A MusicBrainz id when the text is one, in lower case.
private fun musicId(text: String?): String? = musicIds(listOfNotNull(text)).firstOrNull()

// Servers send 0 for a number they do not know.
private fun Int?.positive(): Int? = this?.takeIf { it > 0 }

private fun Float?.finite(): Float? = this?.takeIf { it.isFinite() }

// The kind of file, from its extension.
internal fun mimeFor(suffix: String?): String? = when (suffix?.lowercase()) {
    "flac" -> "audio/flac"
    "mp3" -> "audio/mpeg"
    "m4a", "m4b", "mp4", "alac" -> "audio/mp4"
    "aac" -> "audio/aac"
    "ogg", "oga", "opus" -> "audio/ogg"
    "wav" -> "audio/wav"
    "aif", "aiff" -> "audio/aiff"
    "wv" -> "audio/x-wavpack"
    "ape" -> "audio/x-ape"
    "dsf" -> "audio/x-dsf"
    else -> null
}

// A server's date and time, as milliseconds since 1970. One with no zone is
// taken as UTC.
internal fun epochMs(text: String?): Long? = text?.let {
    runCatching { OffsetDateTime.parse(it).toInstant().toEpochMilli() }.getOrNull()
        ?: runCatching { LocalDateTime.parse(it).toInstant(ZoneOffset.UTC).toEpochMilli() }.getOrNull()
}

private fun seconds(text: String?): Long? = epochMs(text)?.div(1000)
