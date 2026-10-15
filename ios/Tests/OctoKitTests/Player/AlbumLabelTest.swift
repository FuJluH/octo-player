import Testing
@testable import OctoKit

@Suite struct AlbumLabelTest {
    @Test func anAlbumShowsItsName() {
        #expect(albumLabel("Collide With the Sky", "Bulls in the Bronx", 12) == "Collide With the Sky")
    }

    @Test func aOneSongReleaseIsASingle() {
        #expect(albumLabel("Late Night Drive", "Something Else", 1) == nil)
    }

    @Test func aReleaseNamedAfterTheSongIsASingle() {
        #expect(albumLabel("Blinding Lights", "Blinding Lights", 2) == nil)
        #expect(albumLabel("BLINDING LIGHTS", "Blinding Lights (feat. Someone)", 3) == nil)
        #expect(albumLabel("Blinding Lights - Single", "Blinding Lights", 2) == nil)
        #expect(albumLabel("Blinding Lights [Remixes] - EP", "Blinding Lights", 4) == nil)
    }

    @Test func punctuationAndAccentsDoNotMakeAnotherName() {
        #expect(albumLabel("Don’t Stop Me Now", "Dont Stop Me Now", 3) == nil)
        #expect(albumLabel("Déjà Vu - EP", "Deja Vu", 4) == nil)
        #expect(albumLabel("Déjà Vu", "Deja Vu Again", 4) == "Déjà Vu")
    }

    @Test func aSingleSuffixAlwaysHides() {
        #expect(albumLabel("Summer Songs - Single", "Other Title", 2) == nil)
    }

    @Test func aTitleTrackOnARealAlbumStillMatchesAndHides() {
        #expect(albumLabel("Nothing Was the Same", "Nothing Was the Same", 13) == nil)
    }

    @Test func noAlbumShowsNothing() {
        #expect(albumLabel(nil, "Song", 5) == nil)
        #expect(albumLabel("  ", "Song", 5) == nil)
    }
}
