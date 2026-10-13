package app.winters.octo.discovery

import app.winters.octo.data.Session
import app.winters.octo.data.SessionRepository
import app.winters.octo.data.SessionState
import app.winters.octo.data.runsOcto
import app.winters.octo.subsonic.ChartChoices
import app.winters.octo.subsonic.OCTO_TOP_SONGS
import app.winters.octo.subsonic.OCTO_TOP_SONGS_CHARTS
import app.winters.octo.subsonic.SubsonicException
import java.util.concurrent.ConcurrentHashMap
import javax.inject.Inject
import javax.inject.Singleton

// How long a chart is kept before it is asked for again, and the list of
// charts the server's country has.
private const val CHART_KEPT_MS = 60 * 60 * 1000L
private const val CHOICES_KEPT_MS = 24 * 60 * 60 * 1000L

// A chart as the app shows it: which chart, its name, who ranked it, the
// country it is for, and its songs.
data class ChartList(
    val chart: String,
    val name: String?,
    val source: String,
    val country: String?,
    val songs: List<RankedTrack>,
)

// What asking for a chart came to: its list, no charts on the server, or
// no answer (the server could not be reached, or another is in use now).
sealed interface ChartAnswer {
    data class Got(val list: ChartList) : ChartAnswer
    data object None : ChartAnswer
    data object Failed : ChartAnswer
}

// The Charts page's server side: which charts the server's country has
// (Popular right now, Best New Songs, Trending Songs, the genres) and each
// chart's songs, kept per server and chart. Only a server that lists
// octoTopSongs version 2 has them; one signed in to before it did is asked
// once, live.
@Singleton
class ChartLists @Inject constructor(
    private val sessions: SessionRepository,
    private val discovery: Discovery,
) {
    private val offered = ConcurrentHashMap<String, Boolean>()
    private val lists = ConcurrentHashMap<String, Pair<Long, ChartList>>()
    private val choices = ConcurrentHashMap<String, Pair<Long, ChartChoices>>()

    // Whether the server in use has charts.
    suspend fun offered(): Boolean {
        val session = session() ?: return false
        return offers(session)
    }

    // The charts the server's country has, kept a day per server.
    suspend fun choices(): ChartChoices? {
        val session = session() ?: return null
        val key = serverKey(session)
        val now = System.currentTimeMillis()
        choices[key]?.let { (at, kept) -> if (now - at < CHOICES_KEPT_MS) return kept }
        if (!offers(session)) return null
        val got = answerOf { session.client.charts() } ?: return null
        if (session()?.id != session.id) return null
        choices[key] = now to got
        return got
    }

    // A chart's songs, kept an hour per server and chart: its songs are
    // matched to that server's library. Null when there is none to give.
    suspend fun chart(chart: String): ChartList? = (answer(chart) as? ChartAnswer.Got)?.list

    // The same, telling a server without charts from one that did not answer.
    suspend fun answer(chart: String): ChartAnswer {
        val session = session() ?: return ChartAnswer.Failed
        val key = "${serverKey(session)}|$chart"
        val now = System.currentTimeMillis()
        lists[key]?.let { (at, kept) -> if (now - at < CHART_KEPT_MS) return ChartAnswer.Got(kept) }
        when (offersIfKnown(session)) {
            null -> return ChartAnswer.Failed
            false -> return ChartAnswer.None
            true -> Unit
        }
        val list = answerOf { session.client.topChart(chartSongs(chart), chart) } ?: return ChartAnswer.Failed
        // Another server in use by the time it came: not this one's chart.
        if (session()?.id != session.id) return ChartAnswer.Failed
        val entries = list.entry.filter { it.song != null }
        val songs = rankTracks(entries, discovery.resolveInPlace(entries.map { it.song!! }))
        return ChartAnswer.Got(ChartList(chart, list.name, list.source, list.country, songs).also { lists[key] = now to it })
    }

    private suspend fun offers(session: Session): Boolean = offersIfKnown(session) ?: false

    // Whether the server has charts; null when it could not say.
    private suspend fun offersIfKnown(session: Session): Boolean? {
        if ("$OCTO_TOP_SONGS:$OCTO_TOP_SONGS_CHARTS" in session.extensions) return true
        if (!session.runsOcto) return false
        offered[session.sourceId]?.let { return it }
        val yes = session.client.supportsIfKnown(OCTO_TOP_SONGS, OCTO_TOP_SONGS_CHARTS) ?: return null
        offered[session.sourceId] = yes
        return yes
    }

    private fun serverKey(session: Session): String = session.id.ifEmpty { session.sourceId }

    private fun session(): Session? = (sessions.state.value as? SessionState.SignedIn)?.session

    private suspend fun <T> answerOf(call: suspend () -> T): T? =
        try {
            call()
        } catch (e: SubsonicException) {
            null
        }
}
