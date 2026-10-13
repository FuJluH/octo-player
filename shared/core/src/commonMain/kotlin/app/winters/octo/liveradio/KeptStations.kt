package app.winters.octo.liveradio

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

// The live stations a listener kept on this device, newest first. Each app
// saves it as JSON (`encoded`) in its own store and its backups.
@Serializable
data class KeptStations(val stations: List<LiveStation> = emptyList()) {
    fun has(uuid: String): Boolean = stations.any { it.uuid == uuid }

    // Kept once, at the top; a station kept again moves there with what the
    // catalog says now.
    fun keep(station: LiveStation): KeptStations =
        KeptStations(listOf(station.copy(distanceMeters = null)) + stations.filterNot { it.uuid == station.uuid })

    fun drop(uuid: String): KeptStations = KeptStations(stations.filterNot { it.uuid == uuid })

    fun encoded(): String = keptJson.encodeToString(serializer(), this)

    companion object {
        // What was saved, or nothing kept when it cannot be read.
        fun decoded(text: String?): KeptStations =
            text?.let { runCatching { keptJson.decodeFromString(serializer(), it) }.getOrNull() } ?: KeptStations()
    }
}

private val keptJson = Json { ignoreUnknownKeys = true }
