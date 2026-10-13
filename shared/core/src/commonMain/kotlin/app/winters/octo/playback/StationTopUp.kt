package app.winters.octo.playback

// How few songs may be left to come before more of a station's are added,
// and how many are asked for each time: the queue keeps a long run of the
// station ahead, so a slow answer never leaves it short.
const val STATION_TOP_UP_AT = 20
const val STATION_BATCH = 25

// How many of the station's songs already queued go with the ask, so the
// server sends none of them again.
const val STATION_AFTER = 100

// The station to ask for more songs, if any: fewer than STATION_TOP_UP_AT
// songs come after the one playing (`current`, an index into `sources`) and
// a station's songs are among it and those to come. The last such station
// carries on, after any songs the listener queued behind it.
fun stationToTopUp(sources: List<QueueSource>, current: Int): QueueSource.Station? {
    if (current !in sources.indices || sources.size - 1 - current >= STATION_TOP_UP_AT) return null
    return sources.subList(current, sources.size).lastOrNull { it is QueueSource.Station } as? QueueSource.Station
}

// The ids of the station's songs in the queue, the latest STATION_AFTER of
// them, in queue order: what a top-up must not send again.
fun <T> stationSongsQueued(items: List<T>, station: QueueSource.Station, sourceOf: (T) -> QueueSource, idOf: (T) -> String): List<String> =
    items.filter { (sourceOf(it) as? QueueSource.Station)?.id == station.id }.map(idOf).takeLast(STATION_AFTER)

// Whether a server list id is one of Octo's stations: "or" and 20 base62
// digits. Octo's other lists start "og" and end with their songs.
fun isStationId(id: String): Boolean = id.length == 22 && id.startsWith("or")
