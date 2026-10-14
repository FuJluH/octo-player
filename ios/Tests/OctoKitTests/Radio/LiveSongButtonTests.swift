import Testing
@testable import OctoKit

@Suite struct LiveSongButtonTests {
    let petal = OnAir("Petal", "Ariana Grande")
    let inLibrary = HeartCandidate(id: "1", title: "Petal", artist: "Ariana Grande", inLibrary: true)
    let outside = HeartCandidate(id: "find:1", title: "Petal", artist: "Ariana Grande", inLibrary: false)

    func button(_ onAir: OnAir? = nil, match: HeartCandidate? = nil, looked: Bool = true, starred: Bool = false, now: Bool = false,
                adding: Bool = false) -> LiveSongButton {
        liveSongButton(onAir ?? petal, match: match, looked: looked, starred: starred, inLibrary: now, adding: adding)
    }

    @Test func aLibrarySongGetsTheHeart() {
        #expect(button(match: inLibrary) == .heart(starred: false))
        #expect(button(match: inLibrary, starred: true) == .heart(starred: true))
        #expect(liveSongButtonLabel(.heart(starred: false), petal) == "Heart Petal by Ariana Grande")
        #expect(liveSongButtonLabel(.heart(starred: true), petal) == "Remove heart from Petal by Ariana Grande")
    }

    @Test func anOutsideSongGetsThePlusUntilItIsInTheLibrary() {
        #expect(button(match: outside) == .add(adding: false))
        #expect(liveSongButtonLabel(.add(adding: false), petal) == "Add Petal by Ariana Grande to your library")
        // Starred, on its way.
        #expect(button(match: outside, adding: true) == .add(adding: true))
        #expect(button(match: outside, starred: true) == .add(adding: true))
        #expect(liveSongButtonLabel(.add(adding: true), petal) == "Adding Petal by Ariana Grande to your library")
        // Arrived: a filled heart.
        #expect(button(match: outside, starred: true, now: true) == .heart(starred: true))
    }

    @Test func noSongOctoIsSureOfGetsThePlusThatSearches() {
        #expect(button(match: nil, looked: true) == .search)
        #expect(liveSongButtonLabel(.search, petal) == "Search for Petal by Ariana Grande")
        // Still looking: the plus, not yet a search.
        #expect(button(match: nil, looked: false) == .add(adding: false))
    }

    @Test func aStationBreakGetsNoButton() {
        #expect(button(OnAir(tagline: "LA's #1 Hit Music Station"), match: inLibrary) == .none)
        #expect(button(.nothing) == .none)
        #expect(liveSongButtonLabel(.none, petal) == "")
        #expect(liveSongButtonLabel(.add(adding: false), OnAir("Interlude")) == "Add Interlude to your library")
    }
}
