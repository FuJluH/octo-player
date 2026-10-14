package app.winters.octo.subsonic

import kotlinx.serialization.KSerializer
import kotlinx.serialization.Serializable
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonDecoder
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonPrimitive
import kotlin.math.roundToInt

// Every field has a default, so a server that leaves one out still parses.

@Serializable
data class ServerInfo(
    val status: String = "",
    val version: String = "",
    val type: String? = null,
    val serverVersion: String? = null,
    val openSubsonic: Boolean = false,
)

@Serializable
data class Extension(val name: String, val versions: List<Int> = emptyList())

@Serializable
data class User(
    val username: String = "",
    val adminRole: Boolean = false,
    // Whether the user may change their own settings and password. A server
    // that does not say lets them.
    val settingsRole: Boolean = true,
    val scrobblingEnabled: Boolean = false,
    val streamRole: Boolean = true,
)

@Serializable
data class ArtistRef(val id: String = "", val name: String = "")

@Serializable
data class Album(
    val id: String,
    val name: String = "",
    val artist: String = "",
    val artistId: String? = null,
    val displayArtist: String? = null,
    val artists: List<ArtistRef> = emptyList(),
    val coverArt: String? = null,
    val songCount: Int = 0,
    val duration: Int = 0,
    val year: Int? = null,
    val genre: String? = null,
    val created: String? = null,
    val played: String? = null,
    val playCount: Long = 0,
    val starred: String? = null,
    val isCompilation: Boolean = false,
    // OpenSubsonic extras: every genre, the release's MusicBrainz id, how
    // the title is filed, the names of its discs, when this edition and the
    // first edition came out, and whether it is explicit ("explicit",
    // "clean" or empty).
    @Serializable(with = GenreNames::class) val genres: List<String> = emptyList(),
    val musicBrainzId: String? = null,
    val sortName: String? = null,
    val discTitles: List<DiscTitle> = emptyList(),
    val originalReleaseDate: ItemDate? = null,
    val releaseDate: ItemDate? = null,
    val explicitStatus: String? = null,
    // What kind of release it is, from MusicBrainz tags ("Album", "EP",
    // "Single", "Compilation", "Live"...), on OpenSubsonic servers.
    @Serializable(with = LooseStrings::class) val releaseTypes: List<String> = emptyList(),
    // Octo: an album found online rather than one in the library, and how
    // many of its songs the library already holds, under any album. No
    // count when the server did not look.
    val isExternal: Boolean = false,
    val ownedCount: Int? = null,
    // The record labels it came out on, on OpenSubsonic servers.
    val recordLabels: List<RecordLabel> = emptyList(),
)

// A record label, as an OpenSubsonic server names one.
@Serializable
data class RecordLabel(val name: String = "")

// A date an OpenSubsonic server sends in parts, any of which can be missing.
@Serializable
data class ItemDate(val year: Int? = null, val month: Int? = null, val day: Int? = null)

// The name of one disc of an album, like "Live at Wembley".
@Serializable
data class DiscTitle(val disc: Int = 0, val title: String = "")

@Serializable
data class Song(
    val id: String,
    val title: String = "",
    val album: String? = null,
    val albumId: String? = null,
    val artist: String? = null,
    val artistId: String? = null,
    val displayArtist: String? = null,
    val track: Int? = null,
    val discNumber: Int? = null,
    val year: Int? = null,
    val duration: Int = 0,
    val coverArt: String? = null,
    val suffix: String? = null,
    val contentType: String? = null,
    val bitRate: Int? = null,
    val samplingRate: Int? = null,
    val bitDepth: Int? = null,
    val size: Long? = null,
    val starred: String? = null,
    // What a full library copy also keeps: who the album is by, the genre,
    // when the song was added and last played, and how often.
    val displayAlbumArtist: String? = null,
    val genre: String? = null,
    val created: String? = null,
    val played: String? = null,
    val playCount: Long? = null,
    // How loud the song is, from an OpenSubsonic server, and the signed-in
    // user's rating of it from 1 to 5.
    val replayGain: SongReplayGain? = null,
    val userRating: Int? = null,
    // OpenSubsonic extras: every genre, each credited artist and album
    // artist, how the title is filed, the recording's MusicBrainz id, beats
    // per minute, the comment and composers, and whether it is explicit
    // ("explicit", "clean" or empty).
    @Serializable(with = GenreNames::class) val genres: List<String> = emptyList(),
    val artists: List<ArtistRef> = emptyList(),
    val albumArtists: List<ArtistRef> = emptyList(),
    val sortName: String? = null,
    val musicBrainzId: String? = null,
    @Serializable(with = LooseInt::class) val bpm: Int? = null,
    val comment: String? = null,
    val displayComposer: String? = null,
    val explicitStatus: String? = null,
    // The recording's ISRCs, as the server wrote them. OpenSubsonic sends a
    // list; a single code is read as a list of one.
    @Serializable(with = LooseStrings::class) val isrc: List<String> = emptyList(),
    // The folder the song's file is in, as the server's folder calls name
    // it, and the file's path in the library, when the server shares it.
    val parent: String? = null,
    val path: String? = null,
    // Octo's mark for a song that is not a file in the library: one it
    // found online, which it can stream or download. Such a song has no
    // path, size or date added.
    val isExternal: Boolean = false,
    // Which of Octo's radio sources suggested this song ("YouTube Music",
    // "Last.fm", "ListenBrainz", "Sounds alike", "Your library"). Only radio
    // answers carry it, and only from Octo.
    val octoSuggestedBy: String? = null,
    // Octo's mark, in a family, for a song in the signed-in member's own
    // library rather than the shared one. Only those can be removed by the
    // member. Unmarked on servers without Family.
    @Serializable(with = LooseBoolean::class) val octoPersonal: Boolean = false,
)

@Serializable
data class AlbumWithSongs(
    val id: String,
    val name: String = "",
    val artist: String = "",
    val artistId: String? = null,
    val displayArtist: String? = null,
    val coverArt: String? = null,
    val songCount: Int = 0,
    val duration: Int = 0,
    val year: Int? = null,
    val genre: String? = null,
    // When the server first took the album in.
    val created: String? = null,
    val song: List<Song> = emptyList(),
    // What the album list also says of it, for the album's own page: the
    // heart, the names of its discs, what kind of release it is, and its
    // OpenSubsonic genres and dates.
    val starred: String? = null,
    val isCompilation: Boolean = false,
    val discTitles: List<DiscTitle> = emptyList(),
    @Serializable(with = LooseStrings::class) val releaseTypes: List<String> = emptyList(),
    @Serializable(with = GenreNames::class) val genres: List<String> = emptyList(),
    val releaseDate: ItemDate? = null,
    val originalReleaseDate: ItemDate? = null,
)

@Serializable
data class Artist(
    val id: String,
    val name: String = "",
    val coverArt: String? = null,
    val albumCount: Int = 0,
    val starred: String? = null,
    // OpenSubsonic extras: the artist's MusicBrainz id and how the name is filed.
    val musicBrainzId: String? = null,
    val sortName: String? = null,
)

@Serializable
data class ArtistWithAlbums(
    val id: String,
    val name: String = "",
    val coverArt: String? = null,
    val albumCount: Int = 0,
    val album: List<Album> = emptyList(),
)

@Serializable
data class ArtistIndex(val name: String = "", val artist: List<Artist> = emptyList())

@Serializable
data class Artists(val index: List<ArtistIndex> = emptyList())

@Serializable
data class AlbumList(val album: List<Album> = emptyList())

// The OpenSubsonic extension an Octo server lists when it makes the lists
// "Made for you" (Liked Songs, New Releases, Rediscover, Deep Cuts). Each
// comes as a read-only playlist naming its kind in `octoList`.
const val OCTO_LISTS = "octoLists"

// Octo's extension for stations that keep going: getStationSongs sends a
// station's next songs, leaving out the ones already queued.
const val OCTO_STATIONS = "octoStations"

@Serializable
data class StationSongs(val id: String = "", val name: String = "", val entry: List<Song> = emptyList())

// The kinds of Made for you list, in the order Home shows them.
val OCTO_LIST_KINDS = listOf("liked", "newReleases", "rediscover", "deepCuts")

@Serializable
data class Playlist(
    val id: String,
    val name: String = "",
    val comment: String? = null,
    val owner: String? = null,
    val public: Boolean = false,
    val songCount: Int = 0,
    val duration: Int = 0,
    val coverArt: String? = null,
    val changed: String? = null,
    // A playlist the server makes itself and nobody can edit, like a
    // station's list of songs, and when a generated one runs out.
    val readonly: Boolean = false,
    val created: String? = null,
    val validUntil: String? = null,
    // The kind of Made for you list this is, when Octo made it for the
    // listener; otherwise null.
    val octoList: String? = null,
    // Which of Octo's notice lists this is ("review", "duplicates"), when
    // it is one; otherwise null.
    val octoNotice: String? = null,
    // Shorter words for the list's cover than its name, when the server
    // gives them ("Popular" for "Popular right now").
    val octoCoverTitle: String? = null,
    // Which kind of list Octo made this as ("genre", "decade", "year",
    // "country", "artist", "chart", "forYou", "liked", "station"), from a
    // server that says; otherwise null.
    val octoGroup: String? = null,
)

@Serializable
data class Playlists(val playlist: List<Playlist> = emptyList())

@Serializable
data class PlaylistWithSongs(
    val id: String,
    val name: String = "",
    val comment: String? = null,
    val songCount: Int = 0,
    val duration: Int = 0,
    val coverArt: String? = null,
    val entry: List<Song> = emptyList(),
    // Who it belongs to, and when it was made and last changed, as the
    // list of playlists has them.
    val owner: String? = null,
    val public: Boolean = false,
    val created: String? = null,
    val changed: String? = null,
    val readonly: Boolean = false,
    val octoList: String? = null,
    val octoNotice: String? = null,
    val octoCoverTitle: String? = null,
)

// Where one of a playlist's songs sits on the server, for writing a
// playlist file. Kept apart from Song so the library's copy of every song
// does not carry its path.
@Serializable
data class SongPath(val id: String, val path: String? = null)

@Serializable
internal data class PlaylistPaths(val entry: List<SongPath> = emptyList())

@Serializable
data class SearchResult(
    val artist: List<Artist> = emptyList(),
    val album: List<Album> = emptyList(),
    val song: List<Song> = emptyList(),
)

@Serializable
data class Starred(
    val artist: List<Artist> = emptyList(),
    val album: List<Album> = emptyList(),
    val song: List<Song> = emptyList(),
)

enum class AlbumListType(val wire: String) {
    NEWEST("newest"),
    RECENT("recent"),
    FREQUENT("frequent"),
    RANDOM("random"),
    ALPHABETICAL("alphabeticalByName"),
}

@Serializable
data class SongList(val song: List<Song> = emptyList())

// A song's loudness as an OpenSubsonic server sends it: gains in decibels,
// peaks where 1 is full scale. The base gain is one the file already applies
// (an Opus header's, say); the fallback is what the server suggests for a
// song with no gain of its own. Any of them can be missing.
@Serializable
data class SongReplayGain(
    val trackGain: Float? = null,
    val albumGain: Float? = null,
    val trackPeak: Float? = null,
    val albumPeak: Float? = null,
    val baseGain: Float? = null,
    val fallbackGain: Float? = null,
)

// What a server knows about an artist beyond their music: a biography (HTML,
// often ending in a link to where it came from), pictures, and artists like
// them.
@Serializable
data class ArtistInfo(
    val biography: String? = null,
    val musicBrainzId: String? = null,
    val lastFmUrl: String? = null,
    val smallImageUrl: String? = null,
    val mediumImageUrl: String? = null,
    val largeImageUrl: String? = null,
    val similarArtist: List<Artist> = emptyList(),
)

@Serializable
data class RadioStation(
    val id: String,
    val name: String = "",
    val streamUrl: String = "",
    val coverArt: String? = null,
    val homePageUrl: String? = null,
)

@Serializable
data class RadioStations(val internetRadioStation: List<RadioStation> = emptyList())

// A library folder. Servers send its id as a number or as a string, so it
// is read as either and kept as text.
@Serializable
data class MusicFolder(@Serializable(with = LooseString::class) val id: String, val name: String = "")

@Serializable
data class MusicFolders(val musicFolder: List<MusicFolder> = emptyList())

@Serializable
data class TokenInfo(val username: String? = null)

// Reads a number or a string as text.
internal object LooseString : KSerializer<String> {
    override val descriptor = PrimitiveSerialDescriptor("LooseString", PrimitiveKind.STRING)

    override fun deserialize(decoder: Decoder): String =
        (decoder as? JsonDecoder)?.decodeJsonElement()?.jsonPrimitive?.content ?: decoder.decodeString()

    override fun serialize(encoder: Encoder, value: String) = encoder.encodeString(value)
}

// Genre names, as OpenSubsonic sends them ([{"name": "Rock"}]) or as a
// plain list of names. Anything else reads as no genres, so one odd field
// never stops a library from loading.
internal object GenreNames : KSerializer<List<String>> {
    override val descriptor = ListSerializer(String.serializer()).descriptor

    override fun deserialize(decoder: Decoder): List<String> {
        val element = (decoder as? JsonDecoder)?.decodeJsonElement() ?: return emptyList()
        val items = element as? JsonArray ?: listOf(element)
        return items.mapNotNull { item ->
            when (item) {
                is JsonObject -> (item["name"] as? JsonPrimitive)?.contentOrNull
                is JsonPrimitive -> item.contentOrNull
                else -> null
            }?.trim()?.takeIf(String::isNotEmpty)
        }
    }

    override fun serialize(encoder: Encoder, value: List<String>) =
        ListSerializer(String.serializer()).serialize(encoder, value)
}

// Text sent as a list or as one value. Blanks are dropped, and anything
// else reads as nothing, so one odd field never stops a library from
// loading.
internal object LooseStrings : KSerializer<List<String>> {
    override val descriptor = ListSerializer(String.serializer()).descriptor

    override fun deserialize(decoder: Decoder): List<String> {
        val element = (decoder as? JsonDecoder)?.decodeJsonElement() ?: return emptyList()
        val items = element as? JsonArray ?: listOf(element)
        return items.mapNotNull { item -> (item as? JsonPrimitive)?.takeIf { it.isString }?.content?.trim()?.takeIf(String::isNotEmpty) }
    }

    override fun serialize(encoder: Encoder, value: List<String>) =
        ListSerializer(String.serializer()).serialize(encoder, value)
}

// A yes or no sent as a boolean or as text ("true"), as an answer turned
// from XML attributes may carry it. Anything else reads as no.
internal object LooseBoolean : KSerializer<Boolean> {
    override val descriptor = PrimitiveSerialDescriptor("LooseBoolean", PrimitiveKind.BOOLEAN)

    override fun deserialize(decoder: Decoder): Boolean {
        val primitive = (decoder as? JsonDecoder)?.decodeJsonElement() as? JsonPrimitive ?: return false
        return primitive.booleanOrNull ?: primitive.contentOrNull?.trim().equals("true", ignoreCase = true)
    }

    override fun serialize(encoder: Encoder, value: Boolean) = encoder.encodeBoolean(value)
}

// A whole number sent as a number or as text ("120", "120.5"). Anything
// that is not one reads as 0, which servers use for unknown.
internal object LooseInt : KSerializer<Int> {
    override val descriptor = PrimitiveSerialDescriptor("LooseInt", PrimitiveKind.INT)

    override fun deserialize(decoder: Decoder): Int {
        val primitive = (decoder as? JsonDecoder)?.decodeJsonElement() as? JsonPrimitive ?: return 0
        return primitive.intOrNull
            ?: primitive.contentOrNull?.trim()?.toDoubleOrNull()?.takeIf { it.isFinite() }?.roundToInt()
            ?: 0
    }

    override fun serialize(encoder: Encoder, value: Int) = encoder.encodeInt(value)
}

// Lyrics a server keeps for a song (OpenSubsonic songLyrics). There can be
// several: synced and plain, other languages, and with version 2 a
// translation or pronunciation beside the main one.
@Serializable
data class LyricsList(val structuredLyrics: List<StructuredLyrics> = emptyList())

@Serializable
data class StructuredLyrics(
    val lang: String = "und",
    val synced: Boolean = false,
    val line: List<LyricsLine> = emptyList(),
    val displayArtist: String? = null,
    val displayTitle: String? = null,
    // Milliseconds to move every time by. It follows the LRC offset tag:
    // above zero, the words come sooner.
    val offset: Double = 0.0,
    // "main", "translation" or "pronunciation". Missing means main.
    val kind: String? = null,
    // Who sings, when the lines are split between voices.
    val agents: List<LyricsAgent> = emptyList(),
    // Word timings, one or more per line, matched to a line by its index.
    val cueLine: List<CueLine> = emptyList(),
)

@Serializable
data class LyricsLine(
    // Milliseconds from the start of the song; missing when not synced.
    val start: Long? = null,
    val value: String = "",
)

@Serializable
data class LyricsAgent(
    val id: String = "",
    // "main", "voice" (another singer), "bg" (backing vocals) or "group".
    val role: String = "main",
    val name: String? = null,
)

@Serializable
data class CueLine(
    val index: Int = 0,
    val agentId: String? = null,
    val start: Long? = null,
    val end: Long? = null,
    val value: String = "",
    val cue: List<Cue> = emptyList(),
)

// One timed word or syllable. Its place in the cue line's value is given in
// UTF-8 bytes, both ends included, not in characters.
@Serializable
data class Cue(
    val start: Long = 0,
    val end: Long? = null,
    val value: String = "",
    val byteStart: Int = 0,
    val byteEnd: Int = 0,
)

// The older lyrics call's answer: one block of plain text.
@Serializable
data class PlainLyrics(val artist: String? = null, val title: String? = null, val value: String? = null)

// A folder on the server, as its folder listings name it. Older servers
// send ids as numbers, so they are read as either and kept as text.
@Serializable
data class DirectoryRef(
    @Serializable(with = LooseString::class) val id: String,
    val name: String = "",
    // What some servers add: a cover, and how many albums or songs it holds.
    val coverArt: String? = null,
    val albumCount: Int? = null,
    val songCount: Int? = null,
)

// The top of the server's folders: the folders at its root and any songs
// sitting loose there.
data class FolderIndex(val folders: List<DirectoryRef>, val songs: List<Song>)

// One folder on the server: its folders, then its songs, in the order the
// server sent them, and the folder it is in when the server says.
data class MusicDirectory(val id: String, val name: String, val folders: List<DirectoryRef>, val songs: List<Song>, val parent: String? = null)

// The folder calls as they come over the wire. The root's folders arrive
// grouped by first letter; a folder's children mix folders and songs.
@Serializable
internal data class IndexesWire(
    val index: List<IndexGroupWire> = emptyList(),
    val child: List<kotlinx.serialization.json.JsonObject> = emptyList(),
)

@Serializable
internal data class IndexGroupWire(val name: String = "", val artist: List<DirectoryRef> = emptyList())

@Serializable
internal data class DirectoryWire(
    @Serializable(with = LooseString::class) val id: String,
    val name: String = "",
    @Serializable(with = LooseString::class) val parent: String? = null,
    val child: List<kotlinx.serialization.json.JsonObject> = emptyList(),
)

// The play queue a server keeps for the signed-in user, so another device
// can pick it up. The older form names the current song by id; the
// OpenSubsonic index-based form gives its place in the list, which works
// when a song is in the queue twice. Position is in milliseconds into the
// current song; changed is when it was saved, and changedBy the name of
// the client that saved it.
@Serializable
data class PlayQueue(
    val entry: List<Song> = emptyList(),
    val current: String? = null,
    val position: Long = 0,
    val username: String? = null,
    val changed: String? = null,
    val changedBy: String? = null,
)

@Serializable
data class PlayQueueByIndex(
    val entry: List<Song> = emptyList(),
    val currentIndex: Int? = null,
    val position: Long = 0,
    val username: String? = null,
    val changed: String? = null,
    val changedBy: String? = null,
)

// A link anyone can open to listen to some songs or an album. Expires is
// when it stops working, missing for never; visitCount is how often it was
// opened.
@Serializable
data class Share(
    val id: String,
    val url: String = "",
    val description: String? = null,
    val username: String? = null,
    val created: String? = null,
    val expires: String? = null,
    val lastVisited: String? = null,
    val visitCount: Int = 0,
    val entry: List<Song> = emptyList(),
)

@Serializable
data class Shares(val share: List<Share> = emptyList())

// Whether the server is reading its music folders now, and how many songs
// it has counted so far.
@Serializable
data class ScanStatus(
    val scanning: Boolean = false,
    val count: Long = 0,
    val folderCount: Long? = null,
    val lastScan: String? = null,
)

// A song someone is playing right now, who they are, how many minutes ago
// it started, and on which player.
@Serializable
data class NowPlayingEntry(
    val id: String,
    val title: String = "",
    val artist: String? = null,
    val album: String? = null,
    val coverArt: String? = null,
    val username: String = "",
    val minutesAgo: Int = 0,
    @Serializable(with = LooseString::class) val playerId: String? = null,
    val playerName: String? = null,
)

@Serializable
data class NowPlayingList(val entry: List<NowPlayingEntry> = emptyList())

// An internet radio station with everything a server keeps about it, for
// editing: its name, stream and home page.
@Serializable
data class RadioStationDetails(
    val id: String,
    val name: String = "",
    val streamUrl: String = "",
    val homePageUrl: String? = null,
    val coverArt: String? = null,
)

@Serializable
data class RadioStationDetailsList(val internetRadioStation: List<RadioStationDetails> = emptyList())

// The OpenSubsonic extension for saving the queue by place in the list.
const val INDEX_BASED_QUEUE = "indexBasedQueue"

// What a queue save sends: every song id in order, and where playback is.
// In the index-based form the current song is its place in the list;
// otherwise it is the song's id. An empty queue sends no current song.
fun queueSaveParams(ids: List<String>, currentIndex: Int, positionMs: Long, indexBased: Boolean): List<Pair<String, String>> =
    buildList {
        ids.forEach { add("id" to it) }
        val index = currentIndex.takeIf { it in ids.indices } ?: return@buildList
        if (indexBased) add("currentIndex" to "$index") else add("current" to ids[index])
        add("position" to "${positionMs.coerceAtLeast(0)}")
    }

// What creating a share sends: the ids (songs, or one album), an optional
// description, and when it expires, in milliseconds since 1970. No expiry
// means the link never expires.
fun shareParams(ids: List<String>, description: String?, expiresAtMs: Long?): List<Pair<String, String>> =
    buildList {
        ids.forEach { add("id" to it) }
        description?.takeIf(String::isNotBlank)?.let { add("description" to it) }
        expiresAtMs?.let { add("expires" to "$it") }
    }

// What adding or changing a radio station sends. A blank home page is left out.
fun stationParams(streamUrl: String, name: String, homepageUrl: String?): List<Pair<String, String>> =
    buildList {
        add("streamUrl" to streamUrl.trim())
        add("name" to name.trim())
        homepageUrl?.trim()?.takeIf(String::isNotEmpty)?.let { add("homepageUrl" to it) }
    }
