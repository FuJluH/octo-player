package app.winters.octo.liveradio

import app.winters.octo.catalog.SongIdentity
import app.winters.octo.catalog.SongVerdict
import app.winters.octo.playback.RadioDetails
import app.winters.octo.playback.isRadio
import app.winters.octo.playback.radioDetailsOf
import app.winters.octo.playback.radioId
import app.winters.octo.playback.radioOf

// A Radio Browser station's queue id, with what the live player shows
// about it.
fun LiveStation.radioId(): String = radioId(streamUrl, name, hls, radioDetails())

fun LiveStation.radioDetails(): RadioDetails = RadioDetails(
    logo = favicon,
    codec = codec,
    bitrate = bitrate,
    country = country,
    countryCode = countryCode,
    state = state,
    tags = tags,
    homepage = homepage,
    uuid = uuid,
)

// The stations a live station was started from, as the queue holds them:
// Back and Next step through them in order and stop at the ends.
data class LiveLineup(val ids: List<String>, val index: Int) {
    val shows: Boolean get() = ids.size > 1
    val hasPrevious: Boolean get() = index > 0
    val hasNext: Boolean get() = index < ids.lastIndex
    val previous: Int? get() = (index - 1).takeIf { hasPrevious }
    val next: Int? get() = (index + 1).takeIf { hasNext }
}

// The lineup of a queue whose `current` entry is a live station: the queue
// itself when every entry in it is a station, else that station alone.
fun liveLineup(queueIds: List<String>, current: Int): LiveLineup? {
    val id = queueIds.getOrNull(current) ?: return null
    if (!isRadio(id)) return null
    if (queueIds.all(::isRadio)) return LiveLineup(queueIds, current)
    return LiveLineup(listOf(id), 0)
}

// The stations of a list as the queue plays them, each once by its stream
// (the first kept), and where the one tapped is among them.
fun <T> lineupOf(stations: List<T>, tapped: Int, streamOf: (T) -> String, idOf: (T) -> String): Pair<List<String>, Int> {
    val seen = HashSet<String>()
    val tappedKey = stations.getOrNull(tapped)?.let { liveStreamKey(streamOf(it)) }
    val kept = stations.filter { seen.add(liveStreamKey(streamOf(it))) }
    val index = kept.indexOfFirst { liveStreamKey(streamOf(it)) == tappedKey }.coerceAtLeast(0)
    return kept.map(idOf) to index
}

// The line a live station shows under its title: while it names a song,
// "Artist · Station"; while it names none, its tagline, else where it is
// and what it plays ("Los Angeles, California · Pop").
fun liveSubtitle(onAir: OnAir, station: String, details: RadioDetails): String {
    if (onAir.named) return listOf(onAir.artist, station).filter(String::isNotBlank).joinToString(" · ")
    if (onAir.tagline.isNotBlank()) return onAir.tagline
    val place = listOf(details.state, details.country.ifBlank { details.countryCode }).filter(String::isNotBlank).distinct().joinToString(", ")
    val genre = details.tags.firstOrNull()?.replaceFirstChar { it.uppercase() }.orEmpty()
    return listOf(place, genre).filter(String::isNotBlank).joinToString(" · ").ifEmpty { LIVE_RADIO_LINE }
}

// The title a live station shows: the song on air, else the station's name.
fun liveTitle(onAir: OnAir, station: String, streamUrl: String): String =
    onAir.title.ifBlank { station.ifBlank { streamUrl } }

const val LIVE_RADIO_LINE = "Live radio"

// The station's codec and bitrate, as the codec pill shows them: "AAC 128
// kbps", "MP3", or nothing.
fun liveCodecLine(details: RadioDetails): String {
    val codec = details.codec.trim().uppercase().takeUnless { it == "UNKNOWN" }.orEmpty()
    val rate = if (details.bitrate > 0) "${details.bitrate} kbps" else ""
    return listOf(codec, rate).filter(String::isNotEmpty).joinToString(" ")
}

// How long the listener has been on a station: "0:42", "12:04", "1:02:03".
fun listenedFor(ms: Long): String {
    val total = (ms.coerceAtLeast(0) / 1_000)
    val hours = total / 3_600
    val minutes = (total % 3_600) / 60
    val seconds = total % 60
    return if (hours > 0) "%d:%02d:%02d".format(hours, minutes, seconds) else "%d:%02d".format(minutes, seconds)
}

// A song a search found, as the live heart weighs it.
data class HeartCandidate(val id: String, val title: String, val artist: String, val inLibrary: Boolean)

// The search to run for the song on air.
fun heartQuery(onAir: OnAir): String = listOf(onAir.artist, onAir.title).filter(String::isNotBlank).joinToString(" ")

// The one song the heart stars for what is on air, or null when no search
// result is surely it: the title and the artist must both agree (case,
// punctuation, accents and "feat." credits aside), and a different version
// (a remix, a live take) never counts. A song in the library wins over one
// from outside it.
fun heartMatch(onAir: OnAir, candidates: List<HeartCandidate>): HeartCandidate? {
    if (!onAir.named || onAir.artist.isBlank()) return null
    return candidates
        .filter { it.title.isNotBlank() && it.artist.isNotBlank() }
        .mapNotNull { candidate ->
            val match = SongIdentity.same(onAir.title, onAir.artist, candidate.title, candidate.artist)
            candidate.takeIf { match.verdict == SongVerdict.Same && match.confidence >= HEART_CONFIDENCE }?.let { it to match.confidence }
        }
        .sortedWith(compareByDescending<Pair<HeartCandidate, Double>> { it.first.inLibrary }.thenByDescending { it.second })
        .firstOrNull()?.first
}

private const val HEART_CONFIDENCE = 0.85

// What the live player shows for the item `id`, from what its stream named
// last (`streamTitle`, `streamUrl`).
data class LiveShown(
    val title: String,
    val subtitle: String,
    val station: String,
    val streamUrl: String,
    val onAir: OnAir,
    val details: RadioDetails,
) {
    // The cover to show: the song's artwork, else the station's logo; empty
    // for the drawn cover.
    val cover: String get() = onAir.artwork.ifBlank { details.logo }
}

fun liveShown(id: String, streamTitle: String?, streamUrl: String? = null): LiveShown? {
    val (stream, station) = radioOf(id) ?: return null
    val details = radioDetailsOf(id)
    val name = station.ifBlank { stream }
    val air = onAir(streamTitle, streamUrl, name)
    return LiveShown(liveTitle(air, name, stream), liveSubtitle(air, name, details), name, stream, air, details)
}

// The button beside the song on air. A song in the library gets the heart;
// a song Octo finds outside it, or none it is sure of, gets the plus, since
// tapping adds it (or searches for it); nothing named gets no button.
sealed interface LiveSongButton {
    data object None : LiveSongButton
    // The song is in the library: the heart, filled once starred.
    data class Heart(val starred: Boolean) : LiveSongButton
    // An outside song Octo can bring in; `adding` while it is on its way.
    data class Add(val adding: Boolean) : LiveSongButton
    // No song Octo is sure of: the plus opens Search with the query.
    data object Search : LiveSongButton
}

// `match` is the song the lookup found (null while it is still looking or
// found none), `looked` whether the lookup has answered, `starred` whether
// that song is starred, `inLibrary` whether it is in the library now (an
// added outside song lands there), `adding` whether it is on its way.
fun liveSongButton(onAir: OnAir, match: HeartCandidate?, looked: Boolean, starred: Boolean, inLibrary: Boolean, adding: Boolean): LiveSongButton = when {
    !onAir.named -> LiveSongButton.None
    match == null -> if (looked) LiveSongButton.Search else LiveSongButton.Add(adding = false)
    match.inLibrary || inLibrary -> LiveSongButton.Heart(starred)
    else -> LiveSongButton.Add(adding || starred)
}

// What a reader hears for the button: "Heart Petal by Ariana Grande", "Add
// Petal by Ariana Grande to your library", "Search for Petal by Ariana
// Grande".
fun liveSongButtonLabel(button: LiveSongButton, onAir: OnAir): String {
    val song = if (onAir.artist.isBlank()) onAir.title else "${onAir.title} by ${onAir.artist}"
    return when (button) {
        LiveSongButton.None -> ""
        is LiveSongButton.Heart -> if (button.starred) "Remove heart from $song" else "Heart $song"
        is LiveSongButton.Add -> if (button.adding) "Adding $song to your library" else "Add $song to your library"
        LiveSongButton.Search -> "Search for $song"
    }
}
