import Foundation
import Testing
@testable import OctoKit

@Suite struct TagParsingTest {
    /// A tag map with one entry per key, a repeated key keeping its first place and its last values.
    private func tags(_ pairs: (String, [String])...) -> FileTags {
        var order: [String] = []
        var byKey: [String: [String]] = [:]
        for (key, values) in pairs {
            if byKey[key] == nil { order.append(key) }
            byKey[key] = values
        }
        return parseTags(order.map { ($0, byKey[$0] ?? []) })
    }

    @Test func trackAndDiscAcceptSlashForm() {
        let t = tags(("TRACKNUMBER", ["3/12"]), ("DISCNUMBER", ["02"]))
        #expect(t.trackNo == 3)
        #expect(t.discNo == 2)
    }

    @Test func zeroTrackIsNotSet() {
        #expect(tags(("TRACKNUMBER", ["0"])).trackNo == nil)
    }

    @Test func theEditionAndOriginalYearsAreKeptApart() {
        let t = tags(("DATE", ["2014-03-01"]), ("ORIGINALDATE", ["1994"]))
        #expect(t.year == 2014)
        #expect(t.originalYear == 1994)
        #expect(tags(("DATE", ["20150904"])).year == 2015)
    }

    @Test func multipleArtistValuesAreKept() {
        let t = tags(("ARTIST", ["Kavinsky", "Angèle"]))
        #expect(t.artist == "Kavinsky, Angèle")
        #expect(t.artists == ["Kavinsky", "Angèle"])
    }

    @Test func artistsTagGivesTheCreditsAndArtistStaysAsWritten() {
        let t = tags(("ARTIST", ["A feat. B"]), ("ARTISTS", ["A", "B"]))
        #expect(t.artist == "A feat. B")
        #expect(t.artists == ["A", "B"])
        // With only ARTISTS, the credits make the name.
        #expect(tags(("ARTISTS", ["A", "B"])).artist == "A, B")
    }

    @Test func keysAreCaseInsensitiveAndBlanksIgnored() {
        let t = tags(("albumartist", ["  "]), ("Album Artist", ["Kavinsky"]))
        #expect(t.albumArtist == "Kavinsky")
    }

    @Test func compilationFlag() {
        #expect(tags(("COMPILATION", ["1"])).compilation)
        #expect(!tags().compilation)
    }

    @Test func genreValuesAreKeptInOrder() {
        #expect(tags(("GENRE", ["Synthwave", " Electronic "])).genres == ["Synthwave", "Electronic"])
        #expect(tags().genres == [])
    }

    @Test func oneGenreValueSplitsOnSemicolonSlashAndComma() {
        #expect(parseGenres(["Rock; Pop/Indie , Folk"]) == ["Rock", "Pop", "Indie", "Folk"])
        #expect(parseGenres(["Rock\u{0}Pop"]) == ["Rock", "Pop"])
    }

    @Test func ampersandNeverSplitsAGenre() {
        #expect(parseGenres(["R&B; Drum & Bass"]) == ["R&B", "Drum & Bass"])
    }

    @Test func namesWrittenWithASeparatorStayWhole() {
        #expect(parseGenres(["Singer/Songwriter; Folk"]) == ["Singer/Songwriter", "Folk"])
        #expect(parseGenres(["hip-hop/rap"]) == ["hip-hop/rap"])
        #expect(parseGenres(["Folk, World, & Country, Pop"]) == ["Folk, World, & Country", "Pop"])
        #expect(parseGenres(["Rock / R&B/Soul"]) == ["Rock", "R&B/Soul"])
    }

    @Test func keptNamesAreOnlyWholePieces() {
        #expect(parseGenres(["Pop/Soulful House"]) == ["Pop", "Soulful House"])
        #expect(parseGenres(["Hip-Hop/Rapcore"]) == ["Hip-Hop", "Rapcore"])
    }

    @Test func genresAreTidiedAndDeduplicated() {
        #expect(parseGenres(["  Deep   House ;; deep house", ";", ""]) == ["Deep House"])
    }

    @Test func genreSpellingsShareAKey() {
        let hipHop = ["Hip Hop", "Hip-Hop", "hiphop", "Hip-Hop/Rap", "Rap", "Rap & Hip-Hop"]
        #expect(Set(hipHop.map(genreKey)) == ["hiphop"])
        #expect(Set(["R&B", "RnB", "Rhythm and Blues", "R&B/Soul"].map(genreKey)) == ["randb"])
        #expect(genreKey("Alternative & Indie") == genreKey("Alternatif et Indé"))
        #expect(genreKey("Electronic") == genreKey("Electronica"))
        #expect(genreKey("Electronic") == genreKey("Électronique"))
    }

    @Test func differentGenresKeepDifferentKeys() {
        let keys = ["Rock", "Pop", "Soul", "Country", "Metal", "Hip Hop", "R&B"].map(genreKey)
        #expect(keys.count == Set(keys).count)
    }
}
