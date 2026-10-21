package app.winters.octo.desktop.lyrics

import app.winters.octo.desktop.lruMap
import app.winters.octo.desktop.server.Connection
import app.winters.octo.desktop.server.OCTO_LYRICS
import app.winters.octo.desktop.settings.LyricsPrefs
import app.winters.octo.desktop.settings.SettingsStore
import app.winters.octo.discovery.knownLengthMs
import app.winters.octo.lyrics.Lyrics
import app.winters.octo.lyrics.LyricsSource
import app.winters.octo.lyrics.OnlineCopy
import app.winters.octo.lyrics.OnlineLyrics
import app.winters.octo.lyrics.parseLyricsText
import app.winters.octo.lyrics.serverLyrics
import app.winters.octo.lyrics.songFileLyrics
import app.winters.octo.playback.RealLengths
import app.winters.octo.subsonic.LYRICS_AUTO
import app.winters.octo.subsonic.LYRICS_NONE
import app.winters.octo.subsonic.Song
import app.winters.octo.subsonic.SubsonicException
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.IOException
import java.util.Locale

// What finding a song's lyrics came to.
sealed interface LyricsAnswer {
    data class Found(val lyrics: Lyrics) : LyricsAnswer

    // Every source answered, with none.
    data object None : LyricsAnswer

    // The listener hid this song's lyrics.
    data object Hidden : LyricsAnswer

    // A source could not be reached, and nothing else had any.
    data object Failed : LyricsAnswer
}

// How a set of lyrics is timed, best first.
enum class LyricsKind(val label: String) {
    Words("Word by word"),
    Lines("Timed"),
    Plain("Not timed"),
    Instrumental("Instrumental"),
}

fun kindOf(lyrics: Lyrics): LyricsKind = when {
    lyrics.instrumental -> LyricsKind.Instrumental
    !lyrics.synced -> LyricsKind.Plain
    lyrics.lines.any { it.words.isNotEmpty() } -> LyricsKind.Words
    else -> LyricsKind.Lines
}

fun serverKindOf(kind: String): LyricsKind = when (kind.trim().lowercase()) {
    "word" -> LyricsKind.Words
    "line" -> LyricsKind.Lines
    "instrumental" -> LyricsKind.Instrumental
    else -> LyricsKind.Plain
}

// A source's name as the listener knows it, from the server's name for it.
fun lyricsSourceName(key: String): String = when (key.trim().lowercase()) {
    "kugou" -> "KuGou"
    "lrclib" -> "LRCLIB"
    "netease" -> "NetEase"
    "lyricsovh" -> "Lyrics.ovh"
    "", "pinned" -> "your server"
    else -> key.trim().replaceFirstChar(Char::uppercaseChar)
}

// Where lyrics came from, in plain words, for the lyrics menu.
fun sourceLine(lyrics: Lyrics): String {
    val pinned = lyrics.serverPick?.takeIf { lyrics.source == LyricsSource.Server }?.substringBefore(':')
    val from = if (pinned != null) "From ${lyricsSourceName(pinned)}" else lyrics.source.label
    return if (kindOf(lyrics) == LyricsKind.Words) "$from, word by word" else from
}

// One set of lyrics the listener can pick for a song.
sealed interface LyricsPick {
    // One of the copies the server's sources hold ("kugou:123"), or "auto"
    // to let the server choose; the server keeps it for every app.
    data class OnServer(val choice: String) : LyricsPick

    // The server's own answer, on a server that keeps no choices.
    data object Server : LyricsPick

    // The lyrics inside the song file.
    data object SongFile : LyricsPick

    // A copy in the online library, by its number.
    data class Online(val id: Long) : LyricsPick
}

// An entry in the chooser: what it is, where from, how it is timed and its
// first lines. A server copy has no lyrics here, only a preview.
data class LyricsOption(
    val pick: LyricsPick,
    val from: String,
    val detail: String,
    val kind: LyricsKind,
    val preview: List<String>,
    val lyrics: Lyrics? = null,
)

// How many songs' lyrics answers are kept in memory.
private const val LYRICS_ANSWERS_KEPT = 300

// Finds a song's lyrics the way the phone does: the server first (on an
// Octo server that keeps lyrics choices, its answer is final, and its
// choices hold for every app), then the lyrics inside the song file, then
// the online library when allowed. The last few hundred answers are kept
// in memory; `revision` goes up for a song whose lyrics must be fetched
// again.
class LyricsSources(
    private val connection: () -> Connection?,
    private val http: OkHttpClient,
    private val online: OnlineLyrics,
    private val settings: SettingsStore,
    // Real lengths learned by playing, which the online library matches by.
    private val lengths: RealLengths = RealLengths(),
) {
    // Answers already found, for the server signed in to and whether the
    // online library could be asked, so neither change shows an old answer.
    private data class AnswerKey(val server: String?, val online: Boolean, val songId: String)

    // The last few hundred songs' answers; older ones are asked for again.
    private val answers = lruMap<AnswerKey, LyricsAnswer>(LYRICS_ANSWERS_KEPT)

    private fun keyFor(songId: String) =
        AnswerKey(settings.current.server?.let { "${it.username}@${it.address}" }, prefs.online, songId)
    private val _revisions = MutableStateFlow<Map<String, Int>>(emptyMap())
    val revisions: StateFlow<Map<String, Int>> = _revisions

    private val prefs: LyricsPrefs get() = settings.current.lyrics

    // Whether the signed-in server keeps a lyrics choice for every app.
    fun serverDecides(): Boolean = connection()?.supports(OCTO_LYRICS) == true

    suspend fun answerFor(song: Song): LyricsAnswer {
        if (song.id in prefs.hidden) return LyricsAnswer.Hidden
        val key = keyFor(song.id)
        synchronized(answers) { answers[key] }?.let { return it }
        val answer = search(song)
        if (answer != LyricsAnswer.Failed) synchronized(answers) { answers[key] = answer }
        return answer
    }

    private suspend fun search(song: Song): LyricsAnswer {
        // Lyrics the listener picked, while their source still has them.
        when (val picked = pickOf(prefs.picks[song.id])) {
            is LyricsPick.Online -> if (prefs.online) attempt { online.byId(picked.id) }?.let { return LyricsAnswer.Found(it) }
            LyricsPick.SongFile -> attempt { fromSongFile(song) }?.let { return LyricsAnswer.Found(it) }
            else -> Unit
        }
        val decides = serverDecides()
        var plain: Lyrics? = null
        var complete = true
        var serverAnswered = false
        val steps = buildList<suspend () -> Lyrics?> {
            add { fromServer(song).also { serverAnswered = true } }
            add { fromSongFile(song) }
            if (prefs.online && song.title.isNotBlank() && !song.artist.isNullOrBlank()) {
                add { if (decides && serverAnswered) null else online.find(song.title, song.artist.orEmpty(), song.album.orEmpty(), lengthOf(song)) }
            }
        }
        for ((index, step) in steps.withIndex()) {
            val found = try {
                step()
            } catch (e: CancellationException) {
                currentCoroutineContext().ensureActive()
                complete = false
                null
            } catch (e: Exception) {
                complete = false
                null
            }
            if (found == null || found.isEmpty) continue
            // The server's answer is final where it keeps the choice.
            if (found.synced || (index == 0 && decides)) return LyricsAnswer.Found(found)
            if (plain == null) plain = found
        }
        return when {
            plain != null -> LyricsAnswer.Found(plain)
            complete -> LyricsAnswer.None
            else -> LyricsAnswer.Failed
        }
    }

    // The length the online library matches a song by: its real one once
    // playing it found the listing wrong, else the listed one, unless that
    // is Octo's guess. Read when the online library is asked, after the
    // server, by when the song playing has usually opened.
    private fun lengthOf(song: Song): Long = lengths.lengthMs(song.id, knownLengthMs(song))

    private suspend fun <T> attempt(fetch: suspend () -> T?): T? = try {
        fetch()
    } catch (e: CancellationException) {
        throw e
    } catch (e: Exception) {
        null
    }

    // The server's lyrics: by song id where it lists songLyrics (version 2
    // adds word timings), otherwise by artist and title.
    private suspend fun fromServer(song: Song): Lyrics? {
        val server = connection() ?: return null
        val client = server.client
        return try {
            if (server.lyricsByIdOn) {
                serverLyrics(client.lyricsBySongId(song.id, enhanced = server.supports("songLyrics", 2)), Locale.getDefault().language)
            } else {
                client.lyrics(song.artist.orEmpty(), song.title)?.let { parseLyricsText(it, LyricsSource.Server) }
            }
        } catch (e: SubsonicException.NotFound) {
            null
        } catch (e: SubsonicException.Unreachable) {
            throw IOException("Server unreachable", e)
        }
    }

    // The lyrics inside the song file, read from the head of its stream.
    private suspend fun fromSongFile(song: Song): Lyrics? = withContext(Dispatchers.IO) {
        val client = connection()?.client ?: return@withContext null
        val url = client.url("stream", mapOf("id" to song.id, "format" to "raw"))
        http.newCall(Request.Builder().url(url).build()).execute().use { response ->
            if (!response.isSuccessful) return@withContext null
            val tags = SongTags.read(response.body.byteStream())
            songFileLyrics(tags)?.let { parseLyricsText(it, LyricsSource.SongFile) }
        }
    }

    // ---- Choosing ----

    // Everything that can be found for the song, for the chooser. On a
    // server that keeps lyrics choices: its automatic answer and the copies
    // its sources hold, then the song file's. Otherwise: the server's, the
    // song file's, and the online library's copies.
    suspend fun optionsFor(song: Song): List<LyricsOption> = coroutineScope {
        val file = async { attempt { fromSongFile(song) } }
        val own = buildList {
            file.await()?.let { add(option(LyricsPick.SongFile, "From the song file", it)) }
        }
        val server = connection()
        if (server != null && serverDecides()) {
            val listed = attempt { server.client.lyricsCandidates(song.id) }
            val answer = attempt { fromServer(song) }
            if (listed != null) {
                return@coroutineScope buildList {
                    add(LyricsOption(LyricsPick.OnServer(LYRICS_AUTO), "Automatic", "Let your server find the best match", answer?.let(::kindOf) ?: LyricsKind.Plain, answer?.let(::previewOf).orEmpty(), answer))
                    listed.candidate.filter { it.id.isNotBlank() }.forEach { copy ->
                        val about = listOfNotNull(
                            listOf(copy.title, copy.artist).filter(String::isNotBlank).joinToString(" by ").ifEmpty { null },
                            copy.duration?.let { "${it / 60}:${(it % 60).toString().padStart(2, '0')}" },
                        ).joinToString(", ")
                        add(LyricsOption(LyricsPick.OnServer(copy.id), "From ${lyricsSourceName(copy.source.ifBlank { copy.id.substringBefore(':', "") })}", about, serverKindOf(copy.kind), copy.preview.map(String::trim).filter(String::isNotEmpty).take(2)))
                    }
                    addAll(own)
                }
            }
        }
        val fromServer = async { attempt { fromServer(song) } }
        val copies = async {
            if (prefs.online && song.title.isNotBlank() && !song.artist.isNullOrBlank()) {
                attempt { online.copiesOf(song.title, song.artist.orEmpty(), song.album.orEmpty(), lengthOf(song)) }.orEmpty()
            } else {
                emptyList()
            }
        }
        buildList {
            fromServer.await()?.let { add(option(LyricsPick.Server, "From your server", it)) }
            addAll(own)
            copies.await().forEach { add(it.option()) }
        }
    }

    // What a search typed in the chooser finds: the server's sources where
    // they keep the choice ("artist - title", or a title), otherwise the
    // online library. Throws IOException when it cannot be asked.
    suspend fun searchFor(song: Song, query: String): List<LyricsOption> {
        val server = connection()
        if (server != null && serverDecides()) {
            val words = query.trim()
            val parts = words.split(" - ", limit = 2).map(String::trim)
            val (title, artist) = if (parts.size == 2 && parts.all(String::isNotEmpty)) parts[1] to parts[0] else words to null
            val found = try {
                server.client.lyricsCandidates(song.id, title, artist)
            } catch (e: SubsonicException) {
                throw IOException(e.message, e)
            }
            return found.candidate.filter { it.id.isNotBlank() }.map { copy ->
                LyricsOption(LyricsPick.OnServer(copy.id), "From ${lyricsSourceName(copy.source)}", "${copy.title} by ${copy.artist}", serverKindOf(copy.kind), copy.preview.take(2))
            }
        }
        // The online library only when the listener allows it.
        if (!prefs.online) return emptyList()
        return online.search(query).map { it.option() }
    }

    // Whether the chooser has anywhere to search: the server's sources, or
    // the online library when it may be asked.
    fun canSearch(): Boolean = serverDecides() || prefs.online

    // Uses these lyrics for the song from now on. A server copy (or
    // "Automatic") is sent to the server, for every app, and clears this
    // computer's own pick; anything else is kept here.
    suspend fun choose(song: Song, option: LyricsOption) {
        when (val pick = option.pick) {
            is LyricsPick.OnServer -> {
                val server = connection() ?: throw IOException("Not signed in")
                try {
                    server.client.setLyricsChoice(song.id, pick.choice)
                } catch (e: SubsonicException) {
                    throw IOException(e.message, e)
                }
                keepPick(song.id, null)
            }
            LyricsPick.Server -> keepPick(song.id, null)
            LyricsPick.SongFile -> keepPick(song.id, "file")
            is LyricsPick.Online -> keepPick(song.id, "online:${pick.id}")
        }
        settings.update { it.copy(lyrics = it.lyrics.copy(hidden = it.lyrics.hidden - song.id)) }
        refresh(song.id)
    }

    // Hides the song's lyrics here, and on the server too where it keeps
    // the choice.
    suspend fun hide(song: Song) {
        if (serverDecides()) runCatching { connection()?.client?.setLyricsChoice(song.id, LYRICS_NONE) }
        settings.update { it.copy(lyrics = it.lyrics.copy(hidden = it.lyrics.hidden + song.id)) }
        refresh(song.id)
    }

    suspend fun show(song: Song) {
        if (serverDecides()) runCatching { connection()?.client?.setLyricsChoice(song.id, LYRICS_AUTO) }
        settings.update { it.copy(lyrics = it.lyrics.copy(hidden = it.lyrics.hidden - song.id)) }
        refresh(song.id)
    }

    // Asks for the song's lyrics again.
    fun refresh(songId: String) {
        synchronized(answers) { answers.keys.removeAll { it.songId == songId } }
        _revisions.update { it + (songId to (it[songId] ?: 0) + 1) }
    }

    private fun keepPick(songId: String, pick: String?) {
        settings.update { s ->
            val picks = if (pick == null) s.lyrics.picks - songId else s.lyrics.picks + (songId to pick)
            s.copy(lyrics = s.lyrics.copy(picks = picks))
        }
    }

    private fun pickOf(text: String?): LyricsPick? = when {
        text == null -> null
        text == "file" -> LyricsPick.SongFile
        text.startsWith("online:") -> text.removePrefix("online:").toLongOrNull()?.let(LyricsPick::Online)
        else -> null
    }

    private fun option(pick: LyricsPick, from: String, lyrics: Lyrics) =
        LyricsOption(pick, from, "", kindOf(lyrics), previewOf(lyrics), lyrics)

    private fun OnlineCopy.option() = LyricsOption(
        LyricsPick.Online(id),
        "From LRCLIB",
        listOf("$title by $artist", album.ifBlank { null }).filterNotNull().joinToString(", "),
        kindOf(lyrics),
        previewOf(lyrics),
        lyrics,
    )
}

// The first two lines with words, to tell copies apart at a glance.
fun previewOf(lyrics: Lyrics): List<String> =
    lyrics.lines.asSequence().map { it.text.trim() }.filter { it.isNotEmpty() }.take(2).toList()
