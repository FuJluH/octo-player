package app.winters.octo.player

import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsModifier
import androidx.compose.ui.semantics.getOrNull
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ClosePlayerActionTest {
    @Test
    fun aScreenReaderFindsClosePlayerAndItClosesThePlayer() {
        var closed = 0
        val actions = closePlayerActions { closed++ }
        assertEquals(listOf("Close player"), actions.map { it.label })
        assertEquals(0, closed)
        // The action reports that it was handled, and closes the player once.
        assertTrue(actions.single().action())
        assertEquals(1, closed)
    }

    @Test
    fun theModifierPutsTheActionOnTheNodeItIsOn() {
        var closed = 0
        val actions = customActionsOf(Modifier.closesPlayer { closed++ })
        assertEquals(listOf("Close player"), actions.map { it.label })
        assertTrue(actions.single().action())
        assertEquals(1, closed)
    }

    // The custom actions a modifier chain gives its node.
    @Suppress("DEPRECATION")
    private fun customActionsOf(modifier: Modifier): List<CustomAccessibilityAction> =
        modifier.foldIn(emptyList()) { found, element ->
            val config = (element as? SemanticsModifier)?.semanticsConfiguration
            found + config?.getOrNull(SemanticsActions.CustomActions).orEmpty()
        }
}
