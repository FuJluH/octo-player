package app.winters.octo.liveradio

import app.winters.octo.catalog.ArtworkRef
import app.winters.octo.discovery.Station
import app.winters.octo.playback.RadioDetails
import app.winters.octo.playback.radioId
import app.winters.octo.subsonic.RadioStationDetails

// The queue id of a station on the Live radio shelf, with what the player
// shows about it.
fun LiveShelfEntry.radioId(): String = when (this) {
    is LiveShelfEntry.Server -> station.radioId(kept)
    is LiveShelfEntry.Kept -> station.radioId()
}

// The stream of a station on the Live radio shelf.
val LiveShelfEntry.streamUrl: String get() = when (this) {
    is LiveShelfEntry.Server -> station.streamUrl.orEmpty()
    is LiveShelfEntry.Kept -> station.streamUrl
}

// A station added to the server, by its stream: its cover on the server,
// its home page, and what the same stream kept on this phone knows (its
// logo, codec and place, and whether it streams as HLS).
fun Station.radioId(kept: LiveStation? = null): String {
    val cover = (ArtworkRef.decode(artwork) as? ArtworkRef.Server)?.coverId.orEmpty()
    val known = kept?.radioDetails() ?: RadioDetails()
    val details = known.copy(coverArt = cover, homepage = homepage ?: known.homepage)
    return radioId(streamUrl.orEmpty(), name, kept?.hls == true, details)
}

// A station on the server's Radio stations screen: its home page and its
// cover on the server.
fun RadioStationDetails.radioId(): String =
    radioId(streamUrl, name, details = RadioDetails(coverArt = coverArt.orEmpty(), homepage = homePageUrl.orEmpty()))
