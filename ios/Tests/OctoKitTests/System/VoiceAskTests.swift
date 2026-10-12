import Testing
@testable import OctoKit

/// What a spoken request plays.
@Suite struct VoiceAskTests {
    @Test func sayingNothingShufflesEverything() {
        #expect(voiceAsk(VoiceRequest()) == .search(""))
        #expect(voiceAsk(VoiceRequest(name: "  ", kind: .music)) == .search(""))
    }

    @Test func theNameSaidGoesToTheVoiceRules() {
        #expect(voiceAsk(VoiceRequest(name: "Nothing Was the Same", artist: "Drake", kind: .album)) == .search("Nothing Was the Same"))
        #expect(voiceAsk(VoiceRequest(name: " Drake ", kind: .artist)) == .search("Drake"))
        #expect(voiceAsk(VoiceRequest(name: "Hold On", kind: .song)) == .search("Hold On"))
    }

    @Test func withoutANameTheAlbumThenTheArtistThenTheGenre() {
        #expect(voiceAsk(VoiceRequest(artist: "Drake", album: "Take Care")) == .search("Take Care"))
        #expect(voiceAsk(VoiceRequest(artist: "Drake")) == .search("Drake"))
        #expect(voiceAsk(VoiceRequest(genres: ["Jazz"], kind: .genre)) == .search("Jazz"))
    }

    @Test func thisSongOrCarryingOnResumes() {
        #expect(voiceAsk(VoiceRequest(name: "Angel", current: true)) == .resume)
        #expect(voiceAsk(VoiceRequest(resume: true)) == .resume)
        // A name said wins over carrying on.
        #expect(voiceAsk(VoiceRequest(name: "Angel", resume: true)) == .search("Angel"))
    }

    @Test func theLikedSongsByAnyOfTheirNames() {
        #expect(voiceAsk(VoiceRequest(name: "my Liked songs", kind: .playlist)) == .liked)
        #expect(voiceAsk(VoiceRequest(name: "Liked Songs")) == .liked)
        #expect(voiceAsk(VoiceRequest(name: "my favorites", kind: .music)) == .liked)
        // An album that happens to share the words is still an album.
        #expect(voiceAsk(VoiceRequest(name: "Favorites", kind: .album)) == .search("Favorites"))
        #expect(namesLikedSongs("My  liked-songs"))
        #expect(!namesLikedSongs("Liked by you"))
    }

    @Test func aPlaylistByNameAndRadioFromAStation() {
        #expect(voiceAsk(VoiceRequest(name: "Road trip", kind: .playlist)) == .playlist("Road trip"))
        #expect(voiceAsk(VoiceRequest(name: "Drake", kind: .station)) == .radio("Drake"))
    }
}
