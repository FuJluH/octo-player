package app.winters.octo.catalog

import org.junit.Assert.assertEquals
import org.junit.Test

// What an album's name and a title say of a song's version.
class VersionVariantTest {
    @Test
    fun anAlbumNamesTheVersionsOfItsPlainlyNamedSongs() {
        assertEquals(setOf("remix"), VersionVariant.inFolder("Let's Get Lost Remixes", "G-Eazy"))
        assertEquals(setOf("radio edit"), VersionVariant.inFolder("Too Close (Radio Edit) - Single", "Alex Clare"))
        assertEquals(setOf("sped up"), VersionVariant.inFolder("Speed Up Hits", null))
        assertEquals(setOf("dj mix"), VersionVariant.inFolder("Summer Sessions (Mixed by Someone)", null))
    }

    @Test
    fun anEditionOrAGenericBracketIsNoVersion() {
        assertEquals(emptySet<String>(), VersionVariant.inFolder("Album (Extended Edition)", null))
        assertEquals(emptySet<String>(), VersionVariant.inFolder("Album (Japanese Version)", null))
        assertEquals(emptySet<String>(), VersionVariant.inFolder("Album (Deluxe Edition)", null))
        assertEquals(setOf("extended"), VersionVariant.inFolder("Club Hits (Extended Mixes)", null))
    }

    @Test
    fun theArtistsOwnNameIsNeverAVersion() {
        assertEquals(emptySet<String>(), VersionVariant.inFolder("The Remix Kids", "The Remix Kids"))
        assertEquals("  Greatest Hits", VersionVariant.withoutArtist("Slowed Greatest Hits", "slowed"))
        // A name inside a longer word stays.
        assertEquals("Slowedtown", VersionVariant.withoutArtist("Slowedtown", "Slowed"))
    }

    @Test
    fun aTitleAsksForItsBracketedAndItsBareVersions() {
        assertEquals(setOf("remix"), VersionVariant.requested("Let's Get Lost [Bear//Face Remix]", null))
        assertEquals(setOf("sped up"), VersionVariant.requested("Song sped up", null))
        assertEquals(emptySet<String>(), VersionVariant.requested("Let's Get Lost (feat. Devon Baldwin)", null))
        assertEquals(emptySet<String>(), VersionVariant.requested("Extended Play", null))
    }
}
