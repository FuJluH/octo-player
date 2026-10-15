import Foundation
import Testing
@testable import OctoKit

/// What an album's name and a title say of a song's version.
@Suite struct VersionVariantTest {
    @Test func anAlbumNamesTheVersionsOfItsPlainlyNamedSongs() {
        #expect(VersionVariant.inFolder("Let's Get Lost Remixes", "G-Eazy") == ["remix"])
        #expect(VersionVariant.inFolder("Too Close (Radio Edit) - Single", "Alex Clare") == ["radio edit"])
        #expect(VersionVariant.inFolder("Speed Up Hits", nil) == ["sped up"])
        #expect(VersionVariant.inFolder("Summer Sessions (Mixed by Someone)", nil) == ["dj mix"])
    }

    @Test func anEditionOrAGenericBracketIsNoVersion() {
        #expect(VersionVariant.inFolder("Album (Extended Edition)", nil).isEmpty)
        #expect(VersionVariant.inFolder("Album (Japanese Version)", nil).isEmpty)
        #expect(VersionVariant.inFolder("Album (Deluxe Edition)", nil).isEmpty)
        #expect(VersionVariant.inFolder("Club Hits (Extended Mixes)", nil) == ["extended"])
    }

    @Test func theArtistsOwnNameIsNeverAVersion() {
        #expect(VersionVariant.inFolder("The Remix Kids", "The Remix Kids").isEmpty)
        #expect(VersionVariant.withoutArtist("Slowed Greatest Hits", "slowed") == "  Greatest Hits")
        // A name inside a longer word stays.
        #expect(VersionVariant.withoutArtist("Slowedtown", "Slowed") == "Slowedtown")
    }

    @Test func aTitleAsksForItsBracketedAndItsBareVersions() {
        #expect(VersionVariant.requested("Let's Get Lost [Bear//Face Remix]", nil) == ["remix"])
        #expect(VersionVariant.requested("Song sped up", nil) == ["sped up"])
        #expect(VersionVariant.requested("Let's Get Lost (feat. Devon Baldwin)", nil).isEmpty)
        #expect(VersionVariant.requested("Extended Play", nil).isEmpty)
    }
}
