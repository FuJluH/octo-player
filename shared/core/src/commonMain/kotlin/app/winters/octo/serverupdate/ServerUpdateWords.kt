package app.winters.octo.serverupdate

import app.winters.octo.markdown.Block
import app.winters.octo.markdown.Bullet
import app.winters.octo.markdown.Span
import app.winters.octo.markdown.parseMarkdown
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull

// The words both apps show on the server update panel.

fun headline(panel: UpdatePanel.Available): String = "Octo ${panel.latest.tag} is out."

// "Your server runs 2026.10.11.", and how far behind when more than one
// release came out since.
fun detail(panel: UpdatePanel.Available): String {
    val ahead = panel.newer.size
    return "Your server runs ${panel.running}." + if (ahead > 1) " That is $ahead releases ahead." else ""
}

// How to update when the app cannot do it itself, or null when it can.
fun wayWords(way: UpdateWay): String? = when (way) {
    UpdateWay.Now -> null
    UpdateWay.NoHelper -> "You can update it from Octo's dashboard."
    UpdateWay.HelperOutdated -> "The update helper on your server needs reinstalling before Octo can update from here. Run this on the server, or update from the dashboard:"
}

fun lastFailureWords(words: String): String = "The last try stopped: $words"

const val CONFIRM_TITLE = "Update your server?"

fun confirmDetail(tag: String): String = "Octo fetches $tag and restarts. Music from your server stops for a minute or two."

fun updatingTitle(tag: String): String = "Updating your server to $tag"

fun outcomeTitle(outcome: UpdateOutcome): String = when (outcome) {
    is UpdateOutcome.Done -> "Your server now runs ${outcome.tag}."
    is UpdateOutcome.Failed -> "The update to ${outcome.tag} did not finish."
    is UpdateOutcome.NotBack -> "Your server has not come back."
}

fun outcomeDetail(outcome: UpdateOutcome): String? = when (outcome) {
    is UpdateOutcome.Done -> null
    is UpdateOutcome.Failed -> outcome.words
    is UpdateOutcome.NotBack ->
        "Octo has not answered for ${RESTART_GRACE_MS / 60_000} minutes since it began restarting. Check the server, or open the dashboard once it answers."
}

// A release's title for the notes: its name when it has one beyond the tag.
fun releaseTitle(release: ServerRelease): String =
    release.name?.trim()?.takeIf { it.isNotEmpty() && it != release.tag } ?: "Octo ${release.tag}"

// Each newer release with its notes read into blocks, newest first. Links
// stay links only when they go to github.com; any other turns to plain words.
fun releaseNotes(releases: List<ServerRelease>): List<Pair<ServerRelease, List<Block>>> =
    releases.map { it to githubLinksOnly(parseMarkdown(it.notes.orEmpty())) }

internal fun githubLinksOnly(blocks: List<Block>): List<Block> = blocks.map { block ->
    when (block) {
        is Block.Heading -> block.copy(text = spans(block.text))
        is Block.Paragraph -> block.copy(text = spans(block.text))
        is Block.Bullets -> block.copy(items = block.items.map(::bullet))
        Block.Rule -> block
    }
}

private fun bullet(item: Bullet): Bullet = Bullet(spans(item.text), item.children.map(::bullet))

private fun spans(text: List<Span>): List<Span> = text.map { span ->
    if (span.link == null || isGitHub(span.link)) span else span.copy(link = null)
}

// Only https pages on github.com itself.
fun isGitHub(link: String): Boolean {
    val url = link.toHttpUrlOrNull() ?: return false
    return url.scheme == "https" && url.host == "github.com"
}
