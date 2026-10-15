package app.winters.octo.health

import app.winters.octo.subsonic.Album
import app.winters.octo.subsonic.LIBRARY_ACTION_JOIN_ALBUM
import app.winters.octo.subsonic.Song
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

// Every case in library-health-cases.json, the file the Octo server runs
// too, against its own copy of these checks. The songs are written as a
// Subsonic server answers them, so they are read here as the app reads a
// server's songs, through SubsonicHealth. A failure names the case, so a
// rule changed on one side shows up here before the two disagree. Each
// failing case is listed, not only the first.
class LibraryHealthCasesTest {
    private val json = Json { ignoreUnknownKeys = true }

    private val cases: JsonObject = javaClass.classLoader!!.getResource("library-health-cases.json")!!
        .readText().let { json.parseToJsonElement(it).jsonObject }

    private val all: List<JsonObject> = cases.getValue("cases").jsonArray.map { it.jsonObject }

    private fun text(element: JsonElement?): String? = when (element) {
        null, is JsonNull -> null
        else -> element.jsonPrimitive.content
    }

    private fun strings(element: JsonElement): List<String> = element.jsonArray.map { it.jsonPrimitive.content }

    // Strings in pairs or threes: [["a3", "year", "1998"], ...].
    private fun rows(element: JsonElement): List<List<String?>> = element.jsonArray.map { row -> row.jsonArray.map(::text) }

    // SubsonicHealth with what a case adds: release facts by album id, the
    // server's album list, places by song id, and the tags the reader keeps.
    private fun fields(case: JsonObject): HealthFields<Song> {
        val albums = case["albums"]?.let { json.decodeFromJsonElement(ListSerializer(Album.serializer()), it) }
        val base: HealthFields<Song> = if (albums != null) SubsonicAlbumHealth(albums) else SubsonicHealth
        val facts = case["facts"]?.jsonObject
        val places = case["places"]?.jsonObject
        val kept = case["seen"]?.let { strings(it).mapTo(HashSet(), HealthTag::valueOf) }
        fun fact(kind: String, song: Song) = text(facts?.get(kind)?.jsonObject?.get(song.albumId.orEmpty()))
        return object : HealthFields<Song> by base {
            override fun releaseId(song: Song) = if (facts != null) fact("releases", song) else base.releaseId(song)
            override fun releaseGroupId(song: Song) = fact("releaseGroups", song)
            override fun barcode(song: Song) = fact("barcodes", song)
            override fun labels(song: Song) = if (facts != null) listOfNotNull(fact("labels", song)) else base.labels(song)
            override fun place(song: Song) = text(places?.get(song.id)).orEmpty()
            override val seen: Set<HealthTag> = kept ?: base.seen
        }
    }

    // What went wrong in one case.
    private class Failures(private val case: String) {
        val found = ArrayList<String>()

        fun check(what: String, expected: Any?, actual: Any?) {
            if (expected != actual) found += "$case: $what expected $expected, got $actual"
        }

        // The same number of things, before each is checked.
        fun sameCount(what: String, expected: Int, actual: Int): Boolean {
            check("$what count", expected, actual)
            return expected == actual
        }
    }

    @Test
    fun theFileHasEveryCase() {
        assertEquals(56, all.size)
        assertEquals(all.size, all.map { text(it["name"]) }.distinct().size)
    }

    @Test
    fun everyCaseReportsWhatTheFileSays() {
        val failures = all.flatMap(::run)
        assertTrue("${failures.size} failing:\n" + failures.joinToString("\n"), failures.isEmpty())
    }

    private fun run(case: JsonObject): List<String> {
        val failed = Failures(text(case["name"])!!)
        val songs = case.getValue("songs").jsonArray.map { json.decodeFromJsonElement(Song.serializer(), it) }
        val fields = fields(case)
        val report = checkLibrary(songs, fields)
        val expect = case.getValue("expect").jsonObject

        expect["duplicates"]?.jsonArray?.let { sets ->
            if (failed.sameCount("duplicates", sets.size, report.duplicates.size)) {
                sets.forEachIndexed { i, set -> checkSet(failed, "duplicates[$i]", set.jsonObject, report.duplicates[i], fields) }
            }
        }
        expect["splitAlbums"]?.jsonArray?.let { splits ->
            if (failed.sameCount("splitAlbums", splits.size, report.splitAlbums.size)) {
                splits.forEachIndexed { i, split -> checkSplit(failed, "splitAlbums[$i]", split.jsonObject, report.splitAlbums[i], fields) }
            }
        }
        expect["missing"]?.jsonObject?.forEach { (tag, titles) ->
            failed.check("missing $tag", strings(titles), report.missing[HealthTag.valueOf(tag)].orEmpty().map { it.title })
        }
        expect["missingAbsent"]?.let { tags ->
            for (tag in strings(tags)) failed.check("missing $tag present", false, HealthTag.valueOf(tag) in report.missing)
        }
        expect["missingKeys"]?.let { failed.check("missing tags", strings(it), report.missing.keys.map(HealthTag::name)) }
        expect["songsOf"]?.jsonObject?.forEach { (check, titles) ->
            failed.check("songs of $check", strings(titles), report.songs(HealthCheck.valueOf(check)).map { it.title })
        }
        expect["noLength"]?.let { failed.check("noLength", strings(it), report.noLength.map { song -> song.title }) }
        expect["findings"]?.let { failed.check("findings", strings(it), report.findings.map(HealthCheck::name)) }
        expect["counts"]?.jsonObject?.forEach { (check, count) ->
            failed.check("count of $check", count.jsonPrimitive.int, report.count(HealthCheck.valueOf(check)))
        }
        expect["overview"]?.let { failed.check("overview", text(it), report.overview()) }
        expect["without"]?.jsonObject?.let { without ->
            val after = report.without(strings(without.getValue("ids")).toSet(), fields)
            failed.check("duplicates after removing", without.getValue("duplicates").jsonPrimitive.int, after.duplicates.size)
            without.getValue("songsOf").jsonObject.forEach { (check, ids) ->
                failed.check("songs of $check after removing", strings(ids), after.songs(HealthCheck.valueOf(check)).map { it.id })
            }
        }
        expect["fix"]?.jsonObject?.let { fix ->
            if (failed.sameCount("duplicates to fix", 1, report.duplicates.size)) checkFix(failed, fix, report.duplicates[0], fields)
        }
        expect["fillsFromAlbum"]?.jsonObject?.let { fills ->
            val tag = HealthTag.valueOf(text(fills["tag"])!!)
            val wanting = fills["missing"]?.let { ids -> strings(ids).toSet().let { wanted -> songs.filter { it.id in wanted } } }
                ?: report.missing[tag].orEmpty()
            val found = fillsFromAlbum(wanting, songs, tag, fields)
            failed.check("fills from album", rows(fills.getValue("fills")), found.map { (song, change) -> listOf(song.id, change.tag, change.value) })
        }
        return failed.found
    }

    private fun checkSet(failed: Failures, at: String, expect: JsonObject, set: DuplicateGroup<Song>, fields: HealthFields<Song>) {
        expect["copies"]?.let { failed.check("$at copies", strings(it), set.copies.map { song -> song.id }) }
        expect["size"]?.let { failed.check("$at size", it.jsonPrimitive.int, set.copies.size) }
        expect["basis"]?.let { failed.check("$at basis", text(it), set.basis.name) }
        expect["best"]?.let { failed.check("$at best", text(it), set.bestReason.name) }
        expect["heading"]?.let { failed.check("$at heading", text(it), set.heading(fields)) }
        expect["summary"]?.let { failed.check("$at summary", text(it), set.summary(fields)) }
    }

    private fun checkSplit(failed: Failures, at: String, expect: JsonObject, album: SplitAlbum<Song>, fields: HealthFields<Song>) {
        expect["parts"]?.let { failed.check("$at parts", strings(it), album.parts.map(AlbumPart<Song>::albumId)) }
        expect["sizes"]?.let { sizes -> failed.check("$at sizes", sizes.jsonArray.map { it.jsonPrimitive.int }, album.parts.map { it.songs.size }) }
        expect["artist"]?.let { failed.check("$at artist", text(it), album.artist) }
        expect["heading"]?.let { failed.check("$at heading", text(it), album.heading()) }
        expect["summary"]?.let { failed.check("$at summary", text(it), album.summary()) }
        expect["reasons"]?.jsonArray?.let { reasons ->
            if (failed.sameCount("$at reasons", reasons.size, album.reasons.size)) {
                reasons.forEachIndexed { i, element ->
                    val want = element.jsonObject
                    val got = album.reasons[i]
                    failed.check("$at reasons[$i] basis", text(want["basis"]), got.basis.name)
                    want["artist"]?.let { failed.check("$at reasons[$i] artist", text(it), got.artist) }
                    want["other"]?.let { failed.check("$at reasons[$i] other", text(it), got.other) }
                    want["song"]?.let { failed.check("$at reasons[$i] song", text(it), got.song) }
                }
            }
        }
        expect["reasonWords"]?.let { failed.check("$at reason words", strings(it), album.reasons.map(SplitReason::words)) }
        expect["differences"]?.jsonArray?.let { differences ->
            if (failed.sameCount("$at differences", differences.size, album.differences.size)) {
                differences.forEachIndexed { i, element ->
                    val want = element.jsonObject
                    failed.check("$at differences[$i] kind", text(want["kind"]), album.differences[i].kind.name)
                    failed.check("$at differences[$i] values", strings(want.getValue("values")), album.differences[i].values)
                }
            }
        }
        val join = albumJoin(album)
        expect["joinMoving"]?.let { failed.check("$at join moves", strings(it).sorted(), join.moving.map { song -> song.id }.sorted()) }
        expect["joinLeadAlbum"]?.let { lead ->
            failed.check("$at join lead album", text(lead), join.lead.albumId)
            for (step in join.steps(fields)) {
                failed.check("$at join step action", LIBRARY_ACTION_JOIN_ALBUM, step.action)
                failed.check("$at join step like", join.lead.id, step.with["like"])
            }
        }
        expect["joinWords"]?.let { failed.check("$at join words", text(it), join.words) }
    }

    private fun checkFix(failed: Failures, expect: JsonObject, set: DuplicateGroup<Song>, fields: HealthFields<Song>) {
        val pick = expect["pick"]?.let { picked -> set.copies.single { it.id == text(picked) } }
        val fix = duplicateFix(set, fields, pick ?: set.best)
        expect["keep"]?.let { failed.check("fix keeps", text(it), fix.keep.id) }
        expect["remove"]?.let { failed.check("fix removes", strings(it), fix.remove.map { song -> song.id }) }
        expect["why"]?.let { failed.check("fix why", text(it), fix.why) }
        expect["fills"]?.jsonObject?.let { fills ->
            failed.check("fix fills", fills.mapValues { (_, value) -> text(value) }, fix.fills.associate { it.tag to it.value })
        }
        expect["fillsFrom"]?.let { from ->
            for (change in fix.fills) {
                failed.check("fix fill ${change.tag} from", text(from), change.from)
                failed.check("fix fill ${change.tag} now", null, change.now)
            }
        }
        if ("note" in expect) failed.check("fix note", text(expect["note"]), fix.note)
        expect["differs"]?.jsonArray?.let { differs ->
            if (failed.sameCount("fix differs", differs.size, fix.differs.size)) {
                differs.forEachIndexed { i, element ->
                    val want = element.jsonObject
                    failed.check("fix differs[$i] tag", text(want["tag"]), fix.differs[i].tag)
                    failed.check("fix differs[$i] values", rows(want.getValue("values")), fix.differs[i].values.map { (id, value) -> listOf(id, value) })
                }
            }
        }
    }
}
