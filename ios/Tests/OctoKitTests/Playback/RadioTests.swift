import Foundation
import Testing
@testable import OctoKit

@Suite struct RadioMixTest {
    let now = 1_800_000_000_000
    let day = 86_400_000

    func song(_ id: String, _ artist: String, genre: String = "Rock", year: Int? = 1995, album: String?? = .none, rating: Int = 0,
              lastPlayedAt: Int? = nil, title: String? = nil, ms: Int = 200_000, liked: Bool = false) -> RadioSong {
        let albumName: String? = switch album {
        case .none: "al-\(id)"
        case .some(let value): value
        }
        return RadioSong(id: id, title: title ?? id, artists: [artist], album: albumName, genres: [genre], year: year, durationMs: ms,
                         liked: liked, rating: rating, lastPlayedAt: lastPlayedAt)
    }

    func mix(_ seeds: [RadioSong], _ library: [RadioSong], _ count: Int, seed: Int32 = 1, suggested: [RadioSong] = [],
             before: [RadioSong] = [], tuning: RadioTuning = RadioTuning()) -> [String] {
        var random = OctoRandom(seed: seed)
        return radioMix(RadioInput(seeds: seeds, library: library, suggested: suggested, before: before, now: now, tuning: tuning),
                        count: count, random: &random).map(\.id)
    }

    func mixSongs(_ input: RadioInput, _ count: Int, _ seed: Int32) -> [RadioSong] {
        var random = OctoRandom(seed: seed)
        return radioMix(input, count: count, random: &random)
    }

    @Test func aSongMustShareAGenreWithTheSeeds() {
        let seed = song("seed", "A")
        #expect(mix([seed], [seed, song("rock", "B"), song("jazz", "A", genre: "Jazz")], 5) == ["rock"])
    }

    @Test func theRightEraBeatsAFavoriteFromAnotherEra() {
        let seed = song("seed", "A", year: 1995)
        let near = (1...10).map { song("near\($0)", "N\($0)", year: 1994 + $0 % 3) }
        let far = (1...6).map { song("far\($0)", "F\($0)", year: 2014 + $0, liked: true) }
        for tuning in [RadioTuning(), RadioTuning(favorites: true)] {
            for run in 0..<50 {
                let picks = mix([seed], [seed] + near + far, 3, seed: Int32(run), tuning: tuning)
                #expect(picks.allSatisfy { $0.hasPrefix("near") }, "\(tuning) \(picks)")
            }
        }
    }

    @Test func songsHeardLatelyComeOnlyWhenNothingElseIs() {
        let seed = song("seed", "A")
        let heard = song("heard", "A", lastPlayedAt: now - 2 * day, liked: true)
        let fresh = song("fresh", "B", year: 2015, lastPlayedAt: now - 20 * day)
        let library = [seed, fresh, heard]
        for run in 0..<20 {
            #expect(mix([seed], library, 1, seed: Int32(run)) == ["fresh"])
            #expect(mix([seed], library, 2, seed: Int32(run)) == ["fresh", "heard"])
        }
    }

    @Test func aOneStarSongNeverPlays() {
        let seed = song("seed", "A")
        let library = [seed, song("bad", "B", rating: 1), song("ok", "C")]
        for run in 0..<50 { #expect(!mix([seed], library, 5, seed: Int32(run)).contains("bad")) }
    }

    @Test func fillerNeverPlays() {
        let seed = song("seed", "A")
        #expect(mix([seed], [seed, song("skit", "B", title: "Skit", ms: 40_000), song("ok", "C")], 5) == ["ok"])
    }

    @Test func anArtistWaitsItsTurn() {
        let seed = song("seed", "A")
        let library = [seed] + (1...5).map { song("a\($0)", "A") } + ["B", "C", "D", "E"].map { song("x\($0)", $0) }
        for run in 0..<50 {
            let picks = mixSongs(RadioInput(seeds: [seed], library: library, now: now), 5, Int32(run))
            #expect(Set(picks.map(\.artists)).count == 5)
        }
    }

    @Test func twoArtistsTakeTurns() {
        let seed = song("seed", "A")
        let library = [seed, song("a1", "A"), song("a2", "A"), song("b1", "B")]
        for run in 0..<20 {
            #expect(mixSongs(RadioInput(seeds: [seed], library: library, now: now), 3, Int32(run)).map { $0.artists[0] } == ["A", "B", "A"])
        }
    }

    @Test func aSmallLibraryStillFillsTheCount() {
        let seed = song("seed", "A")
        let library = [seed, song("a1", "A", album: "one"), song("a2", "A", album: "one"), song("a3", "A", album: "one")]
        #expect(mix([seed], library, 3).count == 3)
    }

    @Test func theServersSuggestionsCountWithoutAGenre() {
        let seed = song("seed", "A", genre: "")
        let suggested = [song("s1", "B", genre: ""), song("s2", "C", genre: "")]
        #expect(Set(mix([seed], [seed], 5, suggested: suggested)) == ["s1", "s2"])
    }

    var seedSong: RadioSong { song("seed", "A") }
    var plenty: [RadioSong] { [seedSong] + (1...60).map { song("lib\($0)", "L\($0)") } }
    var found: [RadioSong] { (1...60).map { song("new\($0)", "S\($0)", genre: "", year: nil) } }

    func kinds(_ tuning: RadioTuning = RadioTuning(), runs: Int = 200, count: Int = 30) -> [String] {
        let seed = seedSong, library = plenty, suggested = found
        return (0..<runs).map { run in
            mix([seed], library, count, seed: Int32(run), suggested: suggested, tuning: tuning).map { $0.hasPrefix("new") ? "O" : "L" }.joined()
        }
    }

    func share(_ radios: [String], _ count: Int = 30) -> Double {
        Double(radios.reduce(0) { $0 + $1.filter { $0 == "O" }.count }) / Double(count * radios.count)
    }

    @Test func outsideSongsLandAtRandomNotEveryThirdSong() {
        let openings = kinds().map { String($0.prefix(9)) }
        #expect(Set(openings).count >= 20, "\(Set(openings).count)")
        #expect(openings.filter { $0 == "LLOLLOLLO" }.count < 10)
    }

    @Test func theShareHoldsAcrossRadios() {
        let radios = kinds()
        #expect(radios.allSatisfy { $0.count == 30 })
        #expect(radios.allSatisfy { (8...13).contains($0.filter { $0 == "O" }.count) }, "\(radios)")
        #expect((0.33...0.37).contains(share(radios)), "\(share(radios))")
    }

    @Test func neverThreeOutsideSongsInARow() { #expect(!kinds().contains { $0.contains("OOO") }) }

    @Test func mostlyNewNeverPlaysThreeLibrarySongsInARow() {
        let radios = kinds(RadioTuning(discovery: .mostlyNew))
        #expect(!radios.contains { $0.contains("LLL") })
        #expect((0.82...0.88).contains(share(radios)), "\(share(radios))")
    }

    @Test func eachDiscoveryLevelKeepsItsShare() {
        for level in [RadioDiscovery.aLittle, .lots] {
            let radios = kinds(RadioTuning(discovery: level), runs: 100)
            #expect(((level.share - 0.03)...(level.share + 0.03)).contains(share(radios)), "\(level) \(share(radios))")
        }
    }

    @Test func onlyMyLibraryNeverPlaysAnOutsideSong() {
        let library = [seedSong, song("a", "B"), song("b", "C"), song("c", "D")]
        let picks = mix([seedSong], library, 10, suggested: found, tuning: RadioTuning(discovery: .libraryOnly))
        #expect(Set(picks) == ["a", "b", "c"])
        #expect(picks.count == 3)
    }

    @Test func aShareTheOutsideSongsCannotReachEndsWithoutABlockOfLibrarySongs() {
        let few = Array(found.prefix(35)), seed = seedSong, library = plenty
        let radios = (0..<200).map { run in
            mix([seed], library, 50, seed: Int32(run), suggested: few, tuning: RadioTuning(discovery: .mostlyNew))
                .map { $0.hasPrefix("new") ? "O" : "L" }.joined()
        }
        #expect(!radios.contains { $0.contains("LLL") }, "\(radios.filter { $0.contains("LLL") })")
        #expect(radios.allSatisfy { $0.filter { $0 == "O" }.count >= 33 })
    }

    @Test func pacedShareFollowsWhatThereIs() {
        #expect(abs(pacedShare(0.35, outside: 60, library: 60, slots: 30) - 0.35) < 1e-9)
        #expect(abs(pacedShare(0.85, outside: 35, library: 400, slots: 50) - 0.7) < 1e-9)
        #expect(abs(pacedShare(0.35, outside: 100, library: 10, slots: 50) - 0.8) < 1e-9)
        #expect(abs(pacedShare(0.85, outside: 5, library: 15, slots: 50) - 0.25) < 1e-9)
        #expect(abs(pacedShare(0.35, outside: 0, library: 0, slots: 50) - 0.35) < 1e-9)
    }

    @Test func theRunCapHoldsWhereverADrawLands() {
        for adventure in [RadioAdventure.focused, .balanced, .wander] {
            let balanced = kinds(RadioTuning(adventure: adventure), runs: 300)
            #expect(!balanced.contains { $0.contains("OOO") }, "\(adventure)")
            let lots = kinds(RadioTuning(discovery: .lots, adventure: adventure), runs: 300)
            #expect(!lots.contains { $0.contains("LLL") }, "\(adventure)")
        }
    }

    @Test func theRunCarriesOnFromTheSongsBefore() {
        let before = [song("x1", "X1", genre: "", year: nil), song("x2", "X2", genre: "", year: nil)]
        let seed = seedSong, library = plenty, suggested = found
        for run in 0..<200 {
            let first = mix([seed], library, 1, seed: Int32(run), suggested: suggested, before: before)[0]
            #expect(first.hasPrefix("lib"), "\(first)")
        }
        for run in 0..<200 {
            let first = mixSongs(RadioInput(seeds: [seed], library: library, suggested: suggested, now: now, beforeOutside: [false, true, true]),
                                 1, Int32(run))[0].id
            #expect(first.hasPrefix("lib"), "\(first)")
        }
        #expect(runOf([false, true, true]) == 2)
        #expect(runOf([true, false]) == -1)
        #expect(runOf([]) == 0)
    }

    @Test func tightVarietyStillSpacesOtherVersionsOfASong() {
        let seed = song("seed", "Z")
        let library = [seed] + (1...12).flatMap { t in (1...4).map { v in song("t\(t)-\(v)", "Artist \(t)-\(v)", title: "Title \(t)") } }
        for run in 0..<100 {
            let titles = mixSongs(RadioInput(seeds: [seed], library: library, now: now, tuning: RadioTuning(variety: .tight)), 20, Int32(run))
                .map(\.title)
            let close = titles.indices.contains { i in (1...8).contains { d in i + d < titles.count && titles[i] == titles[i + d] } }
            #expect(!close, "\(titles)")
        }
    }

    @Test func focusedStillDrawsFromMoreThanAHandful() {
        let seed = song("seed", "Z")
        let library = [seed] + (1...300).map { song("s\($0)", "S\($0)") }
        var picked = Set<String>()
        for run in 0..<100 {
            for s in mixSongs(RadioInput(seeds: [seed], library: library, now: now, tuning: RadioTuning(adventure: .focused)), 10, Int32(run)) {
                picked.insert(s.id)
            }
        }
        #expect(picked.count > 30, "\(picked.count)")
    }

    @Test func outsideDueFollowsItsRules() {
        var random = OctoRandom(seed: 1)
        #expect(!outsideDue(0.0, picked: 5, outside: 0, run: 0, random: &random))
        #expect(outsideDue(1.0, picked: 5, outside: 5, run: 3, random: &random))
        #expect(outsideDue(0.35, picked: 4, outside: 0, run: -4, random: &random))
        #expect(!outsideDue(0.35, picked: 2, outside: 2, run: 2, random: &random))
        #expect(!outsideDue(0.35, picked: 5, outside: 2, run: 2, random: &random))
        #expect(outsideDue(0.85, picked: 5, outside: 5, run: -2, random: &random))
    }

    @Test func focusedStaysCloserThanWander() {
        let seed = song("seed", "A", year: 1995)
        let library = [seed] + (0..<40).map { song("y\($0)", "Y\($0)", year: 1995 + $0) }
        func distance(_ adventure: RadioAdventure) -> Double {
            (0..<200).reduce(0.0) { sum, run in
                sum + mixSongs(RadioInput(seeds: [seed], library: library, now: now, tuning: RadioTuning(adventure: adventure)), 5, Int32(run))
                    .reduce(0.0) { $0 + Double($1.year! - 1995) }
            } / 1000.0
        }
        let focused = distance(.focused), balanced = distance(.balanced), wander = distance(.wander)
        #expect(focused < balanced && balanced < wander, "\(focused) \(balanced) \(wander)")
    }

    @Test func tightVarietyLetsAnArtistBackSooner() {
        let seed = song("seed", "Z")
        let library = [seed] + (1...6).flatMap { a in (1...8).map { song("a\(a)-\($0)", "Artist \(a)") } }
        func closeRepeats(_ variety: RadioVariety) -> Int {
            (0..<100).filter { run in
                let artists = mixSongs(RadioInput(seeds: [seed], library: library, now: now, tuning: RadioTuning(variety: variety)), 12, Int32(run))
                    .map { $0.artists[0] }
                return artists.indices.contains { i in (1...3).contains { d in i + d < artists.count && artists[i] == artists[i + d] } }
            }.count
        }
        #expect(closeRepeats(.tight) > 0)
        #expect(closeRepeats(.normal) == 0)
    }

    @Test func favoritesMoreOftenPlaysMoreFavorites() {
        let seed = song("seed", "A", year: 1995)
        let rest = (1...15).map { song("r\($0)", "R\($0)", year: 1995) }
        let liked = (1...15).map { song("f\($0)", "F\($0)", year: 1999, liked: true) }
        let library = [seed] + rest + liked
        func favorites(_ on: Bool) -> Double {
            (0..<200).reduce(0.0) { sum, run in
                sum + Double(mixSongs(RadioInput(seeds: [seed], library: library, now: now, tuning: RadioTuning(favorites: on)), 10, Int32(run))
                    .filter(\.liked).count)
            } / 200.0
        }
        let off = favorites(false), on = favorites(true)
        #expect(on >= off + 1.0, "\(off) \(on)")
    }

    @Test func theFirstSeedAndExcludedSongsAreNeverPicked() {
        let seed = song("seed", "A")
        let library = [seed, song("x", "B"), song("y", "C")]
        #expect(mixSongs(RadioInput(seeds: [seed], library: library, exclude: ["x"], now: now), 5, 3).map(\.id) == ["y"])
    }

    @Test func theSameDrawGivesTheSameMix() {
        let seed = song("seed", "A")
        let library = [seed] + (1...30).map { song("s\($0)", "Artist \($0 % 7)", year: 1990 + $0 % 10) }
        #expect(mix([seed], library, 10, seed: 9) == mix([seed], library, 10, seed: 9))
    }

    @Test func spacingGrowsWithTheLibrary() {
        #expect(radioSpacing(0) == 8)
        #expect(radioSpacing(60_000) == 16)
        #expect(radioSpacing(1_000_000) == 30)
    }

    @Test func theDrawIsTheOtherAppsDraw() {
        var random = OctoRandom(seed: 42)
        let first = (0..<3).map { _ in random.nextInt() }
        var again = OctoRandom(seed: 42)
        #expect((0..<3).map { _ in again.nextInt() } == first)
        var bounded = OctoRandom(seed: 7)
        for _ in 0..<1000 {
            let n = bounded.nextInt(10)
            #expect((0..<10).contains(n))
            let d = bounded.nextDouble()
            #expect(d >= 0 && d < 1)
        }
    }

    @Test func tuningAsksForMoreSuggestionsWhenMostAreToComeFromOutside() {
        #expect(RadioTuning().suggestions == 50)
        #expect(RadioTuning(discovery: .lots).suggestions == 100)
        #expect(RadioTuning().discovery == .balanced && RadioTuning().adventure == .balanced && RadioTuning().variety == .normal)
        #expect(!RadioTuning().favorites)
    }
}

@Suite struct RadioFilterTest {
    @Test func tooShortOrTooLongIsLeftOut() {
        #expect(isRadioFiller("Song", durationMs: 30_000))
        #expect(isRadioFiller("Song", durationMs: 50 * 60_000))
        #expect(!isRadioFiller("Song", durationMs: 200_000))
        #expect(!isRadioFiller("Song", durationMs: 0))
    }

    @Test func shortIntrosSkitsAndInterludesAreLeftOut() {
        #expect(isRadioFiller("Intro", durationMs: 60_000))
        #expect(isRadioFiller("Interlude No. 2", durationMs: 90_000))
        #expect(isRadioFiller("Skit (Live)", durationMs: 50_000))
        #expect(!isRadioFiller("Intro", durationMs: 5 * 60_000))
        #expect(!isRadioFiller("Introducing the Band", durationMs: 180_000))
        #expect(!isRadioFiller("Intro", durationMs: 0))
        #expect(!isRadioFiller("Skité", durationMs: 60_000))
        #expect(isRadioFiller("Café Intro", durationMs: 60_000))
    }

    @Test func talkIsLeftOut() {
        #expect(isRadioFiller("Interview with the Band", durationMs: 600_000))
        #expect(isRadioFiller("Song", durationMs: 600_000, genres: ["Podcast"]))
    }
}

@Suite struct LibraryRadioTest {
    private func track(_ id: String, artist: String = "Artist", genre: String = "Rock", rating: Int = 0) -> LibraryTrack {
        LibraryTrack(id: id, sourceId: "device", nativeId: id, title: "Title \(id)", searchKey: id, sortKey: id, artist: artist,
                     artistId: "ar-\(id)", album: "Album", albumId: "al-1", year: 1995, durationMs: 200_000, addedAt: 0,
                     genre: genre, rating: rating)
    }

    @Test func aPhoneSongCarriesWhatTheRadioWeighs() {
        let song = track("t1", rating: 1)
        let radio = radioSong(song, liked: ["t1"], played: PlayedTrack(track: song, plays: 7, lastPlayedAt: 1_000))
        #expect(radio.artists == ["Artist"])
        #expect(radio.album == "al-1")
        #expect(radio.genres == ["Rock"])
        #expect(radio.year == 1995)
        #expect(radio.durationMs == 200_000)
        #expect(radio.liked)
        #expect(radio.rating == 1)
        #expect(radio.plays == 7)
        #expect(radio.lastPlayedAt == 1_000)
    }

    @Test func aPhoneSongWithNoNameOrGenreStillHasAnArtist() {
        let radio = radioSong(track("t2", artist: "", genre: ""), liked: [], played: nil)
        #expect(radio.artists == ["ar-t2"])
        #expect(radio.genres.isEmpty)
        #expect(!radio.liked)
        #expect(radio.plays == 0)
        #expect(radio.lastPlayedAt == nil)
    }

    @Test func aServerSongTakesItsListsAndListening() {
        var song = ServerSong(id: "s1")
        song.title = "Song"
        song.artists = [ArtistRef(id: "a1", name: "One"), ArtistRef(id: "a2", name: " ")]
        song.artist = "Ignored"
        song.genres = ["Jazz", "Soul"]
        song.genre = "Ignored"
        song.displayComposer = "Ann; Bo / Cy,"
        song.playCount = 4
        song.played = "2026-01-01T00:00:00Z"
        song.userRating = 3
        song.duration = 180
        let radio = radioSong(song)
        #expect(radio.artists == ["One"])
        #expect(radio.genres == ["Jazz", "Soul"])
        #expect(radio.composers == ["Ann", "Bo", "Cy"])
        #expect(radio.plays == 4)
        #expect(radio.lastPlayedAt == serverTime("2026-01-01T00:00:00Z"))
        #expect(radio.rating == 3)
        #expect(radioSong(song, rating: 5).rating == 5)
        // Three minutes exactly is a length the server only guessed.
        #expect(radio.durationMs == 0)
        var bare = ServerSong(id: "s2")
        bare.artistId = "ar-2"
        bare.genre = " Rock "
        let plain = radioSong(bare)
        #expect(plain.artists == ["ar-2"])
        #expect(plain.genres == ["Rock"])
        #expect(plain.album == nil)
    }

    @Test func aServerSongCarriesWhatTheRadioWeighs() {
        var song = Song(id: "t1", title: "Title t1", artist: "Artist", albumId: "al-1", duration: 200)
        song.genre = "Rock"
        song.year = 1995
        song.starred = "2026-01-01T00:00:00Z"
        let radio = radioSong(song, rating: 1, plays: 7, lastPlayedAt: 1_000)
        #expect(radio.artists == ["Artist"])
        #expect(radio.album == "al-1")
        #expect(radio.genres == ["Rock"])
        #expect(radio.year == 1995)
        #expect(radio.durationMs == 200_000)
        #expect(radio.liked)
        #expect(radio.rating == 1)
        #expect(radio.plays == 7)
        #expect(radio.lastPlayedAt == 1_000)
    }

    @Test func aSongWithNoNameOrGenreStillHasAnArtist() {
        var song = Song(id: "t2", title: "Title t2", artist: "", duration: 200)
        song.artistId = "ar-t2"
        song.genre = ""
        let radio = radioSong(song)
        #expect(radio.artists == ["ar-t2"])
        #expect(radio.genres.isEmpty)
        #expect(!radio.liked)
        #expect(radio.plays == 0)
        #expect(radio.lastPlayedAt == nil)
    }
}
