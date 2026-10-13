package app.winters.octo.desktop

import app.winters.octo.desktop.liveradio.liveSong
import app.winters.octo.desktop.server.userMessage
import app.winters.octo.liveradio.LiveStation
import app.winters.octo.subsonic.SubsonicException
import kotlinx.coroutines.launch

// What the Live radio page, Home's Live radio shelf and Settings > Radio
// stations do with a live station.

// Plays a live stream under its name. A station from the catalog (`uuid`)
// is counted there as started.
fun AppState.playLive(name: String, streamUrl: String, uuid: String = "") {
    if (streamUrl.isBlank()) return
    play(listOf(liveSong(name, streamUrl)), source = name.ifBlank { null })
    liveRadio.started(uuid)
}

fun AppState.playLive(station: LiveStation) = playLive(station.name, station.streamUrl, station.uuid)

// Keeps a catalog station on this computer, or takes it off.
fun AppState.keepLive(station: LiveStation) {
    liveRadio.keep(station)
    passingNotice("Kept ${station.name}. It's on Home under Live radio.")
}

fun AppState.dropLive(station: LiveStation) {
    liveRadio.drop(station.uuid)
    passingNotice("Removed ${station.name}.")
}

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
