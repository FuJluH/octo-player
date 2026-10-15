package app.winters.octo.server

import app.winters.octo.subsonic.SubsonicException
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

// Which refusals mark a server station as one that cannot be changed.
class StationRefusalTest {
    @Test
    fun onlyTheReadOnlyAnswerMarksAStationReadOnly() {
        assertTrue(refusedAsReadOnly(SubsonicException.NotFound("Octo's generated playlists are read-only")))
        // An account that may not change stations leaves the station as it is.
        assertFalse(refusedAsReadOnly(SubsonicException.Server(50, "User not authorized")))
    }
}
