package app.winters.octo.desktop.pages

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLinkStyles
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.withLink
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import app.winters.octo.design.DesktopType
import app.winters.octo.design.OctoColors
import app.winters.octo.design.SeparatorColor
import app.winters.octo.design.Space
import app.winters.octo.markdown.Block
import app.winters.octo.markdown.Span

private val LinkStyle = TextLinkStyles(SpanStyle(color = OctoColors.TextPrimary, textDecoration = TextDecoration.Underline))

private val CodeStyle = SpanStyle(fontFamily = FontFamily.Monospace, background = Color.White.copy(alpha = 0.08f))

// A page of markdown, like a release's notes, in the window's type: headings
// in white, the body in the quieter ink with bold words lit, soft dots for
// bullets and hairlines for rules. A click on a link opens it in the browser.
@Composable
internal fun MarkdownView(blocks: List<Block>, open: (String) -> Unit, modifier: Modifier = Modifier) {
    Column(modifier) {
        blocks.forEachIndexed { index, block ->
            val first = index == 0
            when (block) {
                is Block.Heading -> {
                    val style = if (block.level <= 2) DesktopType.emphasis else DesktopType.meta.copy(fontWeight = FontWeight.SemiBold)
                    Line(
                        block.text,
                        style.copy(color = if (block.level <= 2) OctoColors.TextPrimary else OctoColors.TextSecondary),
                        open,
                        Modifier.padding(top = if (first) Space.None else Space.Xl, bottom = Space.S).semantics { heading() },
                    )
                }
                is Block.Paragraph -> Line(block.text, Body, open, Modifier.padding(top = if (first) Space.None else Space.M))
                is Block.Bullets -> Column(Modifier.padding(top = if (first) Space.None else Space.S), verticalArrangement = Arrangement.spacedBy(Space.S)) {
                    block.items.forEach { item ->
                        Bullet(item.text, open, dot = 5.dp, OctoColors.TextMuted)
                        if (item.children.isNotEmpty()) {
                            Column(Modifier.padding(start = Space.Xl), verticalArrangement = Arrangement.spacedBy(Space.Xs)) {
                                item.children.forEach { child -> Bullet(child.text, open, dot = 4.dp, OctoColors.TextMuted.copy(alpha = 0.35f)) }
                            }
                        }
                    }
                }
                Block.Rule -> Box(Modifier.padding(vertical = Space.L).fillMaxWidth().height(1.dp).background(SeparatorColor))
            }
        }
    }
}

private val Body = DesktopType.body.copy(color = OctoColors.TextSecondary)

@Composable
private fun Bullet(text: List<Span>, open: (String) -> Unit, dot: Dp, color: Color) {
    Row(Modifier.fillMaxWidth()) {
        Box(Modifier.padding(top = 8.dp, end = Space.L).size(dot).background(color, CircleShape))
        Line(text, Body, open, Modifier.weight(1f))
    }
}

@Composable
private fun Line(text: List<Span>, style: TextStyle, open: (String) -> Unit, modifier: Modifier = Modifier) {
    BasicText(annotated(text, open), modifier, style = style)
}

// The runs as styled text: bold lit white, italic slanted, code in a fixed
// face on a faint patch, and links underlined.
private fun annotated(spans: List<Span>, open: (String) -> Unit): AnnotatedString = buildAnnotatedString {
    spans.forEach { span ->
        val look = SpanStyle(
            color = if (span.bold || span.link != null) OctoColors.TextPrimary else Color.Unspecified,
            fontWeight = if (span.bold) FontWeight.SemiBold else null,
            fontStyle = if (span.italic) FontStyle.Italic else null,
        ).let { if (span.code) it.merge(CodeStyle) else it }
        val link = span.link
        if (link != null) {
            withLink(LinkAnnotation.Clickable(link, LinkStyle) { open(link) }) { withStyle(look) { append(span.text) } }
        } else {
            withStyle(look) { append(span.text) }
        }
    }
}
