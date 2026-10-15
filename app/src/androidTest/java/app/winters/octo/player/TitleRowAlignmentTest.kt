package app.winters.octo.player

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Text
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.getUnclippedBoundsInRoot
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import app.winters.octo.design.OctoType
import app.winters.octo.ui.common.fadingMarquee
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

// The full player's title row, laid out for real: the heart's and More's
// middles sit on the middle of the name's capitals whether the name fits,
// is too long and scrolls, or has no artist under it.
@RunWith(AndroidJUnit4::class)
class TitleRowAlignmentTest {
    @get:Rule
    val rule = createComposeRule()

    private val style = OctoType.title.copy(fontWeight = FontWeight.Bold)

    private fun capMiddleAndButtons(name: String, artist: String?, scroll: Boolean): Pair<Float, List<Float>> {
        var layout: TextLayoutResult? by mutableStateOf(null)
        var capPx = 0f
        rule.setContent {
            val capHeight = rememberCapHeightPx(style)
            val baseline = rememberBaselinePx(style)
            capPx = capHeight
            val density = LocalDensity.current
            val icons = TitleIcons(with(density) { capHeight.toDp() })
            Box(Modifier.width(360.dp)) {
                TitleWithButtons(
                    capHeight = capHeight,
                    titleBaseline = baseline,
                    icons = icons,
                    sideMargin = 24.dp,
                    title = {
                        Column {
                            Text(
                                name,
                                style = style,
                                maxLines = 1,
                                onTextLayout = { layout = it },
                                modifier = Modifier.testTag("name").fadingMarquee(name, scroll = scroll),
                            )
                            if (artist != null) Text(artist, style = OctoType.body, maxLines = 1)
                        }
                    },
                ) {
                    Box(Modifier.size(TitleButtonSize).testTag("heart"))
                    Box(Modifier.size(TitleButtonSize).testTag("more"))
                }
            }
        }
        // Long enough for a long name to be on its way through.
        rule.mainClock.advanceTimeBy(3_000)
        rule.waitForIdle()
        val density = rule.density.density
        val nameTop = rule.onNodeWithTag("name").getUnclippedBoundsInRoot().top.value * density
        val middle = nameTop + layout!!.firstBaseline - capPx / 2
        val buttons = listOf("heart", "more").map { tag ->
            val bounds = rule.onNodeWithTag(tag).getUnclippedBoundsInRoot()
            (bounds.top.value + bounds.bottom.value) / 2 * density
        }
        return middle to buttons
    }

    private fun assertOnCapitals(name: String, artist: String?, scroll: Boolean) {
        val (middle, buttons) = capMiddleAndButtons(name, artist, scroll)
        buttons.forEach { assertEquals("button middle against the capitals' middle", middle, it, 1.5f) }
    }

    @Test
    fun aNameThatFitsHasTheButtonsOnItsCapitals() = assertOnCapitals("Jungle", "Drake", scroll = true)

    @Test
    fun aScrollingNameHasTheButtonsOnItsCapitals() =
        assertOnCapitals("Let's Get Lost (feat. Devon Baldwin) [Bear//Face Remix]", "G-Eazy", scroll = true)

    @Test
    fun aStillLongNameHasTheButtonsOnItsCapitals() =
        assertOnCapitals("Let's Get Lost (feat. Devon Baldwin) [Bear//Face Remix]", "G-Eazy", scroll = false)

    @Test
    fun aNameWithNoArtistHasTheButtonsOnItsCapitals() = assertOnCapitals("Wednesday Night Interlude", null, scroll = true)
}
