package app.winters.octo.desktop

import androidx.compose.ui.graphics.asSkiaBitmap
import app.winters.octo.covers.CoverSpec
import app.winters.octo.covers.coverPaletteKey
import app.winters.octo.desktop.liveradio.LIVE_RADIO
import app.winters.octo.desktop.liveradio.ShelfStation
import app.winters.octo.desktop.liveradio.liveSong
import app.winters.octo.desktop.liveradio.liveCoverOrder
import app.winters.octo.desktop.nav.Page
import app.winters.octo.desktop.server.userMessage
import app.winters.octo.liveradio.LiveStation
import app.winters.octo.liveradio.lineupOf
import app.winters.octo.liveradio.radioDetails
import app.winters.octo.liveradio.radioId
import app.winters.octo.playback.RadioDetails
import app.winters.octo.playback.radioDetailsOf
import app.winters.octo.playback.radioId
import app.winters.octo.playback.radioIsHls
import app.winters.octo.playback.radioOf
import app.winters.octo.subsonic.RadioStation
import app.winters.octo.subsonic.RadioStationDetails
import app.winters.octo.subsonic.SubsonicException
import app.winters.octo.liveradio.OnAir
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import org.jetbrains.skia.EncodedImageFormat
import org.jetbrains.skia.Image
import java.awt.Toolkit
import java.awt.datatransfer.StringSelection

// What the Live radio page, Home's Live radio shelf and Settings > Radio
// stations do with a live station.

// Plays the station `tapped` of a list of station ids, with the whole list
// queued in its order (each stream once), so Back and Next step through it.
// `source` names the list in the queue.
fun AppState.playStations(ids: List<String>, tapped: Int, source: String) {
    if (ids.isEmpty()) return
    val (lineup, at) = lineupOf(ids, tapped.coerceIn(ids.indices), streamOf = { radioOf(it)?.first.orEmpty() }, idOf = { it })
    play(lineup.map(::liveSong), at, source = source)
}

// A catalog station from a list (the Live radio page's results, the kept
// stations), with the list around it.
fun AppState.playLive(station: LiveStation, list: List<LiveStation> = listOf(station), source: String = station.name) {
    val at = list.indexOfFirst { it.uuid == station.uuid && it.streamUrl == station.streamUrl }
    if (at < 0) return playStations(listOf(station.radioId()), 0, source)
    playStations(list.map { it.radioId() }, at, source)
}

// A station on Home's Live radio shelf, with the shelf around it.
fun AppState.playShelf(station: ShelfStation, shelf: List<ShelfStation>) {
    val at = shelf.indexOf(station).takeIf { it >= 0 } ?: return playStations(listOf(station.radioId()), 0, LIVE_RADIO)
    playStations(shelf.map { it.radioId() }, at, LIVE_RADIO)
}

// One of the server's stations, with its other streams around it.
fun AppState.playServerStation(station: RadioStationDetails, stations: List<RadioStationDetails>) {
    val streams = stations.filter { it.streamUrl.isNotBlank() }
    val at = streams.indexOfFirst { it.id == station.id }.takeIf { it >= 0 } ?: return playStations(listOf(station.radioId()), 0, LIVE_RADIO)
    playStations(streams.map { it.radioId() }, at, LIVE_RADIO)
}

// A shelf card's station id, with what is known of it: the kept station's
// details, the logo, and the server's picture.
fun ShelfStation.radioId(): String {
    val details = kept?.radioDetails() ?: RadioDetails()
    return radioId(streamUrl, name, kept?.hls == true, details.copy(logo = details.logo.ifBlank { logo }, coverArt = coverArt.orEmpty(), homepage = details.homepage.ifBlank { homepage }))
}

fun RadioStationDetails.radioId(): String =
    radioId(streamUrl, name.ifBlank { streamUrl }, details = RadioDetails(coverArt = coverArt.orEmpty(), homepage = homePageUrl.orEmpty()))

fun RadioStation.radioId(): String = radioId(streamUrl, name.ifBlank { streamUrl }, details = RadioDetails(coverArt = coverArt.orEmpty(), homepage = homePageUrl.orEmpty()))

// The catalog station a station id stands for, as it would be kept: by its
// catalog id, so only a station from the catalog can be.
fun liveStationOf(id: String): LiveStation? {
    val (stream, name) = radioOf(id) ?: return null
    val details = radioDetailsOf(id)
    if (details.uuid.isBlank()) return null
    return LiveStation(
        uuid = details.uuid,
        name = name.ifBlank { stream },
        streamUrl = stream,
        favicon = details.logo,
        codec = details.codec,
        bitrate = details.bitrate,
        hls = radioIsHls(id),
        country = details.country,
        countryCode = details.countryCode,
        state = details.state,
        tags = details.tags,
        homepage = details.homepage,
    )
}

// Keeps a catalog station on this computer, or takes it off.
fun AppState.keepLive(station: LiveStation) {
    liveRadio.keep(station)
    passingNotice("Kept ${station.name}. It's on Home under Live radio.")
}

fun AppState.dropLive(station: LiveStation) {
    liveRadio.drop(station.uuid)
    passingNotice("Removed ${station.name}.")
}

// Whether a catalog station is kept on this computer.
fun AppState.isKept(station: LiveStation): Boolean = liveRadio.kept().has(station.uuid)

// Adds a catalog station to the server in use, for everyone on it; only
// an admin may. Home's shelves and the station list are read again.
fun AppState.addLiveToServer(station: LiveStation) {
    val client = connection?.client ?: return
    scope.launch {
        try {
            client.createRadioStation(station.streamUrl, station.name)
            liveRadio.readServerStations()
            home?.liveChanged()
            passingNotice("Added ${station.name} to your server.")
        } catch (e: SubsonicException) {
            notice = "Couldn't add ${station.name} to your server: ${e.userMessage()}"
        }
    }
}

// The cover of the song a station has on air as Octo has it, once the
// search for it found it surely.
fun AppState.liveSongCover(title: String, artist: String): String? =
    liveHeart.match?.song?.coverArt?.takeIf { liveHeart.onAir.title == title && liveHeart.onAir.artist == artist }

// Opens Search with these words in it, from anywhere, the full player too.
fun AppState.searchFor(words: String) {
    if (words.isBlank()) return
    fullPlayer = false
    navigator.go(Page.Search)
    search?.type(words)
}

// Puts words on the clipboard, saying so in passing.
fun AppState.copyWords(words: String, said: String) {
    if (words.isBlank()) return
    val copied = runCatching { Toolkit.getDefaultToolkit().systemClipboard.setContents(StringSelection(words), null) }.isSuccess
    if (copied) passingNotice(said)
}

// A station's drawn cover as a PNG, as the shelf draws it, for the
// system's player when the station has no picture of its own.
suspend fun AppState.drawnStationPicture(name: String, stream: String, side: Int = 600): ByteArray? = runCatching {
    val order = liveCoverOrder(name, stream)
    val client = connection?.client
    val palette = playlistArt.palette(client, order, coverPaletteKey(client?.primaryUrl?.host.orEmpty(), order.sources + listOfNotNull(order.stamp)))
    val bitmap = playlistArt.art(CoverSpec(order.id, order.name, order.line, order.footer, palette, order.coverTitle, order.glyph), side)
    val image = Image.makeFromBitmap(bitmap.asSkiaBitmap())
    try {
        image.encodeToData(EncodedImageFormat.PNG)?.bytes
    } finally {
        image.close()
    }
}.getOrNull()

// Follows the station playing: the heart empties when the song on air
// changes, and the catalog hears of each catalog station started, once per
// start.
internal fun AppState.followLive() {
    scope.launch {
        player.state.map { it.live?.shown?.onAir ?: OnAir.Nothing }.distinctUntilChanged().collect { liveHeart.follow(it) }
    }
    scope.launch {
        var counted: Long? = null
        player.state.map { state -> state.current?.key?.takeIf { state.playing && state.live != null } to state.live?.shown?.details?.uuid.orEmpty() }
            .distinctUntilChanged()
            .collect { (key, uuid) ->
                if (key == null || key == counted) return@collect
                counted = key
                liveRadio.started(uuid)
            }
    }
}
