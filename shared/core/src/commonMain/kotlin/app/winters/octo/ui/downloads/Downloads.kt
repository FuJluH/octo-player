package app.winters.octo.ui.downloads

import app.winters.octo.subsonic.Acquisition
import app.winters.octo.subsonic.AcquisitionEvent
import app.winters.octo.subsonic.AcquisitionKind
import app.winters.octo.subsonic.AcquisitionStage
import app.winters.octo.subsonic.FoundCandidate
import app.winters.octo.subsonic.FoundSongs
import app.winters.octo.subsonic.LogKind
import app.winters.octo.subsonic.Upgrade
import app.winters.octo.subsonic.UpgradeStage
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

// The downloads drawer, as the phone and the desktop both show it: one row
// for each download the server is doing for this person, or did lately,
// and the words for its log and for Find songs. The apps run the calls and
// draw; what each answer means is worked out here, once.

// The drawer's title, and the name of its button.
const val DOWNLOADS = "Downloads"

// The power user's way back into a search: the button and its page title.
const val FIND_SONGS = "Find songs"

// A finished upgrade the server keeps for a week shows this long in the
// drawer, as a finished download does.
const val FINISHED_SHOWN_MS = 3 * 60 * 60_000L

// What a row is for.
enum class RowKind { Download, Upgrade, Pick }

// Where a row has got to, as the drawer draws it.
enum class RowPhase {
    Waiting,
    Searching,
    Downloading,
    Checking,
    Adding,
    Done,
    Failed,
    ;

    val finished: Boolean get() = this == Done || this == Failed
}

// One row of the drawer.
data class DownloadRow(
    // The row's own key: a download's, or "upgrade:<id>" for a higher
    // quality copy that has not started downloading.
    val key: String,
    val title: String,
    val artist: String,
    val album: String?,
    // The picture to draw, by its id on the server.
    val coverArt: String?,
    val kind: RowKind,
    val phase: RowPhase,
    // How far, from 0 to 1, while it downloads and the server knows.
    val fraction: Float?,
    // The one line under the title: "Downloading from Soulseek, 42%".
    val status: String,
    // The copy being fetched, once chosen: "FLAC 16-bit 44.1 kHz".
    val quality: String?,
    val source: String?,
    val startedAt: String?,
    val updatedAt: String?,
    // The download whose log opens from this row, when there is one.
    val logKey: String?,
    // What Find songs looks for from this row: the library song once it is
    // there, otherwise the found song.
    val findId: String?,
    // The id the download was asked for with, when it is one.
    val askedId: String? = null,
) {
    val finished: Boolean get() = phase.finished
}

// The rows to show, running ones first and newest first within each:
// every download the server lists, and every higher quality copy asked
// for, joined to its download once it has one. Finished upgrades leave
// after FINISHED_SHOWN_MS, and rows in `hidden` (cleared here) not at all.
fun drawerRows(
    acquisitions: List<Acquisition>,
    upgrades: List<Upgrade>,
    now: Long = System.currentTimeMillis(),
    hidden: Set<String> = emptySet(),
): List<DownloadRow> {
    val byKey = upgrades.filter { it.acquisition != null }.associateBy { it.acquisition!! }
    val fromDownloads = acquisitions.map { rowOf(it, it.key?.let(byKey::get)) }
    val joined = fromDownloads.map { it.key }.toSet()
    val fromUpgrades = upgrades
        .groupBy { it.id }
        .mapNotNull { (_, entries) -> entries.firstOrNull { it.stage.pending } ?: entries.maxByOrNull { it.updatedAt.orEmpty() } }
        .filter { it.acquisition == null || it.acquisition !in joined }
        .map(::rowOf)
        .filter { !it.finished || ageMs(it.updatedAt, now)?.let { age -> age < FINISHED_SHOWN_MS } ?: false }
    return (fromDownloads + fromUpgrades)
        .filter { it.key !in hidden }
        .sortedWith(compareBy<DownloadRow> { it.finished }.thenByDescending { if (it.finished) it.updatedAt.orEmpty() else it.startedAt.orEmpty() })
}

// A download as a row. `upgrade` is the higher quality copy it fetches,
// whose verdict comes after the download's own end.
fun rowOf(acquisition: Acquisition, upgrade: Upgrade? = null): DownloadRow {
    val kind = when (acquisition.kind) {
        AcquisitionKind.UPGRADE -> RowKind.Upgrade
        AcquisitionKind.PICK -> RowKind.Pick
        else -> if (upgrade != null) RowKind.Upgrade else RowKind.Download
    }
    var phase = phaseOf(acquisition.stage)
    var status = statusOf(acquisition)
    // The upgrade's own answer is the last word: in the library is not yet
    // "upgraded", and a download that failed may still have kept your copy.
    if (upgrade != null) {
        when (upgrade.stage) {
            UpgradeStage.Upgraded -> { phase = RowPhase.Done; status = upgrade.detail?.let(::sentence) ?: "Upgraded" }
            UpgradeStage.NotFound -> { phase = RowPhase.Failed; status = "No higher quality copy found" }
            UpgradeStage.Failed, UpgradeStage.Skipped -> { phase = RowPhase.Failed; status = upgrade.detail?.let(::sentence) ?: "Your copy is unchanged" }
            UpgradeStage.Rehearsed -> { phase = RowPhase.Done; status = "Only rehearsed; nothing changed" }
            // Downloaded, but still being judged before it takes the old one's place.
            else -> if (phase.finished) { phase = RowPhase.Checking; status = "Checking it before it replaces your copy" }
        }
    }
    val title = acquisition.title.ifBlank { upgrade?.title.orEmpty() }
    return DownloadRow(
        key = acquisition.key ?: "${acquisition.id}:${acquisition.startedAt.orEmpty()}",
        title = title.ifBlank { "A song" },
        artist = acquisition.artist.ifBlank { upgrade?.artist.orEmpty() },
        album = acquisition.album ?: upgrade?.album,
        coverArt = acquisition.coverArt ?: acquisition.libraryId ?: acquisition.id.takeIf(String::isNotBlank),
        kind = kind,
        phase = phase,
        fraction = if (phase == RowPhase.Downloading) acquisition.fraction else null,
        status = status,
        quality = acquisition.quality,
        source = acquisition.source,
        startedAt = acquisition.startedAt,
        updatedAt = maxOf(acquisition.updatedAt.orEmpty(), upgrade?.updatedAt.orEmpty()).ifEmpty { null },
        logKey = acquisition.key,
        findId = upgrade?.id ?: acquisition.libraryId ?: acquisition.id.takeIf(String::isNotBlank),
        askedId = acquisition.id.takeIf(String::isNotBlank),
    )
}

// A higher quality copy that has no download of its own yet, or whose
// download is gone from the server's list.
fun rowOf(upgrade: Upgrade): DownloadRow {
    val (phase, status) = when (upgrade.stage) {
        UpgradeStage.Queued -> RowPhase.Waiting to "Waiting its turn"
        UpgradeStage.Waiting -> RowPhase.Waiting to "Waiting for Soulseek"
        UpgradeStage.Working -> RowPhase.Searching to "Looking for a higher quality copy"
        UpgradeStage.Upgraded -> RowPhase.Done to (upgrade.detail?.let(::sentence) ?: "Upgraded")
        UpgradeStage.NotFound -> RowPhase.Failed to "No higher quality copy found"
        UpgradeStage.Rehearsed -> RowPhase.Done to "Only rehearsed; nothing changed"
        UpgradeStage.Skipped, UpgradeStage.Failed -> RowPhase.Failed to (upgrade.detail?.let(::sentence) ?: "Your copy is unchanged")
        UpgradeStage.Unknown -> RowPhase.Searching to "Looking for a higher quality copy"
    }
    return DownloadRow(
        key = "upgrade:${upgrade.id}",
        title = upgrade.title.ifBlank { "A song" },
        artist = upgrade.artist,
        album = upgrade.album,
        coverArt = upgrade.id,
        kind = if (upgrade.picked != null) RowKind.Pick else RowKind.Upgrade,
        phase = phase,
        fraction = upgrade.fraction.takeIf { phase == RowPhase.Searching },
        status = status,
        quality = null,
        source = null,
        startedAt = upgrade.updatedAt,
        updatedAt = upgrade.updatedAt,
        logKey = upgrade.acquisition,
        findId = upgrade.id,
    )
}

fun phaseOf(stage: AcquisitionStage): RowPhase = when (stage) {
    AcquisitionStage.Queued -> RowPhase.Waiting
    AcquisitionStage.Searching, AcquisitionStage.Unknown -> RowPhase.Searching
    AcquisitionStage.Downloading -> RowPhase.Downloading
    AcquisitionStage.Verifying -> RowPhase.Checking
    AcquisitionStage.Importing -> RowPhase.Adding
    AcquisitionStage.Done -> RowPhase.Done
    AcquisitionStage.Failed -> RowPhase.Failed
}

// The line under a download's title.
fun statusOf(acquisition: Acquisition): String = when (acquisition.stage) {
    AcquisitionStage.Queued -> acquisition.ahead?.takeIf { it > 0 }?.let { "Waiting, $it ahead" } ?: "Waiting its turn"
    AcquisitionStage.Searching, AcquisitionStage.Unknown ->
        acquisition.note?.let(::sentence) ?: acquisition.source?.let { "Looking on $it" } ?: "Looking for a copy"
    AcquisitionStage.Downloading -> buildString {
        append("Downloading")
        acquisition.source?.takeIf(String::isNotBlank)?.let { append(" from $it") }
        acquisition.fraction?.let { append(", ${(it * 100).toInt()}%") }
    }
    AcquisitionStage.Verifying -> "Checking the file"
    AcquisitionStage.Importing -> "Adding to your library"
    AcquisitionStage.Done -> "In your library"
    AcquisitionStage.Failed -> acquisition.error?.let(::sentence) ?: "Could not get it"
}

// "What it is for", as a small word beside the title, or null for a plain
// download.
fun kindLabel(kind: RowKind): String? = when (kind) {
    RowKind.Download -> null
    RowKind.Upgrade -> "Higher quality"
    RowKind.Pick -> "Picked"
}

// The line over the list: "2 on the way, 5 finished".
fun drawerSummary(rows: List<DownloadRow>): String {
    val running = runningCount(rows)
    val finished = rows.size - running
    return listOfNotNull(
        running.takeIf { it > 0 }?.let { "$it on the way" },
        finished.takeIf { it > 0 }?.let { "$it finished" },
    ).joinToString(", ")
}

// What the drawer says with nothing in it.
const val DOWNLOADS_EMPTY = "Nothing downloading. Songs you add show here, with every step on the way."

// What Find songs says about picking, for a song in the library and one
// that is not. A server that asks first about a copy that is not better
// says the second line; an older one only takes a better copy.
const val FIND_REPLACES = "Only a better copy can take your copy's place, and yours stays until the new one passes every check."
const val FIND_REPLACES_ASKS = "Picking a copy asks you before it replaces yours. Yours stays until the new one passes every check."

fun findReplaces(asksFirst: Boolean): String = if (asksFirst) FIND_REPLACES_ASKS else FIND_REPLACES
const val FIND_DOWNLOADS = "Pick a copy to download that one. It goes through the same checks as any download."

// Why no copy can be picked yet: the list still grows while sources answer.
const val FIND_PICK_WAIT = "You can pick a copy once the search is done."

// A pick from a list that a new search has since replaced.
const val FIND_LIST_CHANGED = "The list changed. Pick a copy from it again."

// Whether a copy on the list can be picked: once the search is done, and
// only a copy the server named.
fun canPick(found: FoundSongs?, copy: FoundCandidate): Boolean =
    found != null && !found.searching && (copy.id != null || copy.index != null)

// A copy's key on the list: its id, or its place on a server older than ids.
fun copyKey(copy: FoundCandidate): String = copy.id?.let { "id:$it" } ?: copy.index?.let { "at:$it" } ?: "copy:${copy.hashCode()}"

// The library's copy of a song, in words: "Your copy: MP3 220 kbps, 7.0 MB".
fun ownedCopyText(quality: String?, size: Long?, locale: Locale = Locale.getDefault()): String? {
    val what = listOfNotNull(quality?.takeIf(String::isNotBlank), size?.takeIf { it > 0 }?.let { bytesText(it, locale) })
    return if (what.isEmpty()) null else "Your copy: ${what.joinToString(", ")}"
}

// How many rows are still running, for the drawer's button.
fun runningCount(rows: List<DownloadRow>): Int = rows.count { !it.finished }

// The overall progress the drawer's button shows: the mean of the rows
// downloading, or null when none says how far it is.
fun overallFraction(rows: List<DownloadRow>): Float? =
    rows.mapNotNull { it.fraction.takeIf { _ -> !it.finished } }.takeIf { it.isNotEmpty() }?.average()?.toFloat()

// ---------------------------------------------------------------------------
// The pill
// ---------------------------------------------------------------------------

// The running row the pill speaks for: the one furthest along, and of
// those the one that started first, so the pill does not hop between two
// songs at the same step.
fun pillLead(rows: List<DownloadRow>): DownloadRow? =
    rows.filter { !it.finished }
        .sortedWith(compareByDescending<DownloadRow> { it.phase.ordinal }.thenBy { it.startedAt.orEmpty() })
        .firstOrNull()

// The step a row is on, in a word or two: "Downloading 42%", "Checking".
fun stepWords(row: DownloadRow): String = when (row.phase) {
    RowPhase.Waiting -> "Waiting"
    RowPhase.Searching -> "Searching"
    RowPhase.Downloading -> row.fraction?.let { "Downloading ${(it.coerceIn(0f, 1f) * 100).toInt()}%" } ?: "Downloading"
    RowPhase.Checking -> "Checking"
    RowPhase.Adding -> "Adding"
    RowPhase.Done -> "Done"
    RowPhase.Failed -> "Failed"
}

// A song asked for from this device that has not reached the library: the
// id it was asked for with on the server, and when it was asked for.
data class AskedSong(val serverId: String, val askedAt: Long)

// The longest a song asked for here is counted while no list asked for
// after it has come back, as when the server cannot be reached.
const val ASKED_UNLISTED_MS = 2 * 60_000L

// How many songs the pill counts: the drawer's running rows, and songs
// asked for here that no list could show yet. The server puts a download
// on its list before it answers the ask, so the first list asked for after
// the ask settles it: listed, the song is one of the rows; not listed
// (refused, forgotten, ended and cleared), it is not on its way. Until such
// a list comes back an ask counts, for ASKED_UNLISTED_MS at most.
// `listedSince` is when the newest list that came back was asked for, or
// null before any did.
fun pillCount(rows: List<DownloadRow>, asked: List<AskedSong>, listedSince: Long?, now: Long): Int =
    runningCount(rows) + unlisted(rows, asked, listedSince, now).size

// How long until pillCount may change with no new list or ask: when the
// first ask it counts runs out, or null when it counts none.
fun pillRecheckMs(rows: List<DownloadRow>, asked: List<AskedSong>, listedSince: Long?, now: Long): Long? =
    unlisted(rows, asked, listedSince, now).minOfOrNull { it.askedAt + ASKED_UNLISTED_MS - now }

// The asks pillCount counts beside the rows: not on a running row, asked
// for after the newest list that came back was asked for, and lately.
private fun unlisted(rows: List<DownloadRow>, asked: List<AskedSong>, listedSince: Long?, now: Long): List<AskedSong> {
    val running = rows.filter { !it.finished }.flatMapTo(HashSet()) { listOfNotNull(it.askedId, it.findId) }
    return asked.filter { ask ->
        ask.serverId !in running &&
            (listedSince == null || listedSince < ask.askedAt) &&
            now - ask.askedAt in 0 until ASKED_UNLISTED_MS
    }
}

// What the pill says aloud: "Downloading 42%, Da Funk. 2 more on the way".
fun pillSpoken(rows: List<DownloadRow>): String {
    val lead = pillLead(rows) ?: return ""
    val more = runningCount(rows) - 1
    return "${stepWords(lead)}, ${lead.title}" + if (more > 0) ". $more more on the way" else ""
}

// ---------------------------------------------------------------------------
// The steps
// ---------------------------------------------------------------------------

// The steps every download walks, as the log's head draws them.
enum class DownloadStep(val label: String) {
    Find("Find"),
    Download("Download"),
    Check("Check"),
    Add("Add"),
}

// Where a row is on those steps: the step it is on, or DownloadStep.entries.size
// once it is in. A failed row stops on the step its log last reached.
fun stepOf(row: DownloadRow, events: List<AcquisitionEvent> = emptyList()): Int = when (row.phase) {
    RowPhase.Waiting, RowPhase.Searching -> DownloadStep.Find.ordinal
    RowPhase.Downloading -> DownloadStep.Download.ordinal
    RowPhase.Checking -> DownloadStep.Check.ordinal
    RowPhase.Adding -> DownloadStep.Add.ordinal
    RowPhase.Done -> DownloadStep.entries.size
    RowPhase.Failed -> events.lastOrNull { markOf(it.logKind) !in AFTERWORDS }?.let { stepOfMark(markOf(it.logKind)) } ?: DownloadStep.Find.ordinal
}

// The step a log line belongs to.
fun stepOfMark(mark: LogMark): Int = when (mark) {
    LogMark.Queued, LogMark.Search, LogMark.Found, LogMark.Note -> DownloadStep.Find.ordinal
    LogMark.Try, LogMark.Transfer -> DownloadStep.Download.ordinal
    LogMark.Check -> DownloadStep.Check.ordinal
    LogMark.Tags, LogMark.Cover, LogMark.Lyrics, LogMark.Library -> DownloadStep.Add.ordinal
    LogMark.Done -> DownloadStep.entries.size
    LogMark.Failed -> DownloadStep.Find.ordinal
}

// Lines that say how it ended, not which step it reached.
private val AFTERWORDS = setOf(LogMark.Failed, LogMark.Note, LogMark.Done)

// ---------------------------------------------------------------------------
// The log
// ---------------------------------------------------------------------------

// What a line of the log is drawn with. The apps pick an icon for each.
enum class LogMark { Queued, Search, Found, Try, Transfer, Check, Tags, Cover, Lyrics, Library, Done, Failed, Note }

fun markOf(kind: LogKind): LogMark = when (kind) {
    LogKind.Queued -> LogMark.Queued
    LogKind.Search -> LogMark.Search
    LogKind.Found -> LogMark.Found
    LogKind.Try -> LogMark.Try
    LogKind.Transfer -> LogMark.Transfer
    LogKind.Check -> LogMark.Check
    LogKind.Tags -> LogMark.Tags
    LogKind.Cover -> LogMark.Cover
    LogKind.Lyrics -> LogMark.Lyrics
    LogKind.Library -> LogMark.Library
    LogKind.Done -> LogMark.Done
    LogKind.Failed -> LogMark.Failed
    LogKind.Note, LogKind.Unknown -> LogMark.Note
}

// The clock time of a line, "18:04:31", in this computer's time zone.
fun logTime(at: String?, zone: ZoneId = ZoneId.systemDefault()): String =
    at?.let { runCatching { Instant.parse(it) }.getOrNull() }
        ?.let { DateTimeFormatter.ofPattern("HH:mm:ss", Locale.ROOT).withZone(zone).format(it) }
        .orEmpty()

// The facts of a copy, in the order a person weighs them: its quality, its
// size and length, then where it comes from and how soon.
fun candidateFacts(copy: FoundCandidate, locale: Locale = Locale.getDefault()): List<String> = buildList {
    (copy.quality ?: copy.format?.uppercase(Locale.ROOT))?.takeIf(String::isNotBlank)?.let(::add)
    copy.size?.takeIf { it > 0 }?.let { add(bytesText(it, locale)) }
    copy.length?.takeIf { it > 0 }?.let { add(clockText(it)) }
    copy.source.takeIf(String::isNotBlank)?.let(::add)
    copy.peer?.takeIf(String::isNotBlank)?.let(::add)
    val queue = copy.queueLength
    when {
        copy.freeSlot == true -> add("Free to send now")
        queue != null && queue > 0 -> add("$queue in queue")
    }
    copy.speed?.takeIf { it > 0 }?.let { add(speedText(it, locale)) }
}

// A copy's kind in one short word for its badge: "FLAC", "MP3", or null.
fun copyBadge(copy: FoundCandidate): String? =
    (copy.format?.trim()?.trimStart('.') ?: copy.quality?.substringBefore(' '))
        ?.takeIf(String::isNotBlank)?.uppercase(Locale.ROOT)

// A copy's facts beside its badge: the quality's remainder ("16-bit
// 44.1 kHz") in place of the whole quality, then the rest as candidateFacts.
fun badgeFacts(copy: FoundCandidate, locale: Locale = Locale.getDefault()): List<String> {
    val facts = candidateFacts(copy, locale)
    val badge = copyBadge(copy) ?: return facts
    val first = facts.firstOrNull() ?: return facts
    if (!first.uppercase(Locale.ROOT).startsWith(badge)) return facts
    val rest = first.substring(badge.length).trim()
    return (if (rest.isEmpty()) emptyList() else listOf(rest)) + facts.drop(1)
}

// "1st choice" beside the copy Octo would try first, "2nd choice" and on.
fun rankWords(rank: Int): String {
    val suffix = if (rank % 100 in 11..13) "th" else when (rank % 10) { 1 -> "st"; 2 -> "nd"; 3 -> "rd"; else -> "th" }
    return "$rank$suffix choice"
}

// How many copies a log line shows before "Show all".
const val LOG_COPIES_SHOWN = 3

// The line a copy is known by: its title, or its file's name.
fun candidateTitle(copy: FoundCandidate): String =
    copy.title?.takeIf(String::isNotBlank) ?: copy.file?.takeIf(String::isNotBlank) ?: copy.source

// "Octo's first choice", or the server's reason for passing it over.
fun candidateVerdict(copy: FoundCandidate): String? = when {
    copy.rank == 1 -> "Octo's first choice"
    copy.rank != null -> "Octo's choice ${copy.rank}"
    else -> copy.note?.let(::sentence)
}

// Whether a copy is lossless, by its kind.
fun isLosslessCopy(copy: FoundCandidate): Boolean =
    copy.format?.trim()?.trimStart('.')?.lowercase(Locale.ROOT)?.substringBefore(' ')?.substringBefore('-') in LOSSLESS

private val LOSSLESS = setOf("flac", "wav", "alac", "ape", "aiff", "aif", "wv")

// Kilobytes under a megabyte, megabytes above.
fun bytesText(bytes: Long, locale: Locale = Locale.getDefault()): String = when {
    bytes < 1_048_576 -> "%.0f KB".format(locale, bytes / 1024.0)
    bytes < 1_073_741_824 -> "%.1f MB".format(locale, bytes / 1_048_576.0)
    else -> "%.2f GB".format(locale, bytes / 1_073_741_824.0)
}

// "3:07".
fun clockText(seconds: Int): String = "%d:%02d".format(Locale.ROOT, seconds / 60, seconds % 60)

// Bytes a second as "1.4 MB/s" or "340 KB/s".
fun speedText(bytesPerSecond: Int, locale: Locale = Locale.getDefault()): String =
    if (bytesPerSecond >= 1_048_576) "%.1f MB/s".format(locale, bytesPerSecond / 1_048_576.0)
    else "%d KB/s".format(locale, maxOf(1, bytesPerSecond / 1024))

// How long ago an ISO time was, or null when it cannot be read.
internal fun ageMs(at: String?, now: Long): Long? =
    at?.let { runCatching { Instant.parse(it).toEpochMilli() }.getOrNull() }?.let { now - it }

// The server's words as one line: trimmed, without a closing full stop.
internal fun sentence(text: String): String? = text.trim().trimEnd('.').trim().ifEmpty { null }
