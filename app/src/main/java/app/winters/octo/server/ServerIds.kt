package app.winters.octo.server

import app.winters.octo.catalog.FIND_PREFIX
import app.winters.octo.catalog.SourceDao
import app.winters.octo.catalog.isFind
import app.winters.octo.playback.isRadio

// The server's id for each song that has one: a library song's copy on
// the server `sourceId`, or a find's own id. Radio stations have none.
internal suspend fun SourceDao.serverIdsOf(sourceId: String, trackIds: List<String>): Map<String, String> {
    val library = trackIds.filterNot { isFind(it) || isRadio(it) }.distinct()
    val copies = library.chunked(900).flatMap { copiesOf(it) }
        .filter { it.sourceId == sourceId }
        .groupBy { it.mergedId }
        .mapValues { (_, group) -> group.map { it.nativeId }.min() }
    val finds = trackIds.filter(::isFind).associateWith { it.removePrefix(FIND_PREFIX) }
    return copies + finds
}
