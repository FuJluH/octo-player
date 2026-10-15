import Foundation
import Testing
@testable import OctoKit

/// Songs for the health tests: by default tidy, every tag there, each its own track on its album.
final class HealthSongs {
    private var next = 0

    func song(
        _ title: String, _ artist: String = "Artist", seconds: Int = 200, album: String = "Album", albumId: String? = nil,
        suffix: String = "flac", bitDepth: Int? = 16, rate: Int? = 44_100, bitRate: Int? = 900, isrc: [String] = [],
        mbid: String? = nil, year: Int? = 2020, genre: String? = "Rock", track: Int?? = .none, albumArtist: String?? = .none,
        cover: String?? = .none, id: String? = nil
    ) -> ServerSong {
        next += 1
        let number = next
        let shownArtist: String? = albumArtist ?? artist
        let shownTrack: Int? = track ?? number
        let shownCover: String? = cover ?? "mf-\(number)"
        let shownId = id ?? "s\(number)"
        next += 1
        return ServerSong(
            id: shownId, title: title, album: album, albumId: albumId ?? "al-\(album)", artist: artist, track: shownTrack, year: year,
            duration: seconds, coverArt: shownCover, suffix: suffix, bitRate: bitRate, samplingRate: rate, bitDepth: bitDepth,
            displayAlbumArtist: shownArtist, genre: genre, albumArtists: shownArtist.map { [ArtistRef(name: $0)] } ?? [],
            musicBrainzId: mbid, isrc: isrc)
    }
}

func healthReport(_ songs: ServerSong...) -> HealthReport<ServerSong> { checkLibrary(songs, serverSongHealth) }

func ids(_ group: DuplicateGroup<ServerSong>) -> [String] { group.copies.map(\.id) }

@Suite struct LibraryHealthTests {
    let make = HealthSongs()

    // MARK: Duplicates

    @Test func twoCopiesOfOneSongAreASetWithTheLosslessOneFirst() {
        let mp3 = make.song("Holocene", "Bon Iver", seconds: 337, suffix: "mp3", bitDepth: nil, rate: 44_100, bitRate: 320, id: "mp3")
        let flac = make.song("Holocene", "Bon Iver", seconds: 336, id: "flac")
        let other = make.song("Towers", "Bon Iver", seconds: 188, id: "towers")
        let sets = healthReport(mp3, flac, other).duplicates
        #expect(sets.count == 1)
        #expect(ids(sets[0]) == ["flac", "mp3"])
        #expect(sets[0].basis == .titleAndLength)
        #expect(sets[0].bestReason == .sound)
    }

    @Test func lengthsMayDifferByThreeSecondsButNotFour() {
        let within = healthReport(make.song("Song", seconds: 200, id: "a"), make.song("Song", seconds: 203, id: "b"))
        let beyond = healthReport(make.song("Song", seconds: 200, id: "a"), make.song("Song", seconds: 204, id: "b"))
        #expect(within.duplicates.count == 1)
        #expect(beyond.duplicates.isEmpty)
    }

    @Test func anotherVersionIsNotACopy() {
        let found = healthReport(
            make.song("Song", seconds: 200, id: "studio"),
            make.song("Song (Live)", seconds: 201, id: "live"),
            make.song("Song - Acoustic", seconds: 200, id: "acoustic"),
            make.song("Song (Interlude)", seconds: 200, id: "interlude"),
            make.song("Song", "Someone Else", seconds: 200, id: "cover"))
        #expect(found.duplicates.isEmpty)
    }

    @Test func titlesThatNameDifferentVersionsAreNeverPaired() {
        let pairs = [
            ("Let's Get Lost [Bear//Face Remix]", "Let's Get Lost (Teklife Remix)"),
            ("Song (Remix)", "Song"),
            ("Song (Live)", "Song"),
            ("Song (Acoustic)", "Song"),
            ("Song (Sped Up)", "Song"),
            ("Song (Slowed)", "Song"),
            ("Song (Instrumental)", "Song"),
            ("Song (Radio Edit)", "Song (Album Version)"),
            ("Song (Demo)", "Song"),
            ("Song (Taylor's Version)", "Song"),
        ]
        for (one, other) in pairs {
            let found = healthReport(make.song(one, seconds: 200, id: "a"), make.song(other, seconds: 201, id: "b"))
            #expect(found.duplicates.isEmpty, "\(one) and \(other)")
        }
    }

    @Test func aSongTaggedPlainlyOnAnAlbumOfAnotherVersionIsNotACopy() {
        let albums = [
            "Let's Get Lost Remixes",
            "Song (Remixes) - EP",
            "Song (Sped Up) - Single",
            "Slowed Down Hits",
            "Song (Acoustic)",
            "The Instrumentals",
            "Song (Radio Edit) - Single",
            "Club Hits (Extended Mixes)",
            "Song (Demo)",
        ]
        for album in albums {
            let found = healthReport(
                make.song("Song", seconds: 240, album: "Studio Album", id: "studio"),
                make.song("Song", seconds: 242, album: album, id: "other"))
            #expect(found.duplicates.isEmpty, "\(album)")
        }
    }

    @Test func albumsThatNameNoOtherVersionStillPairTheirCopies() {
        let albums = [
            "Studio Album (Deluxe Edition)",
            "Studio Album (Extended Edition)",
            "Studio Album (Remastered)",
            "Studio Album (Explicit)",
            "Mix Tape",
        ]
        for album in albums {
            let found = healthReport(
                make.song("Song", seconds: 240, album: "Studio Album", id: "studio"),
                make.song("Song", seconds: 241, album: album, id: "other"))
            #expect(found.duplicates.count == 1, "\(album)")
        }
    }

    @Test func copiesOnTwoAlbumsOfTheSameVersionArePaired() {
        let bothRemixes = healthReport(
            make.song("Song", seconds: 242, album: "Song Remixes", id: "ep"),
            make.song("Song", seconds: 242, album: "Song (Remixes)", id: "ep-again"))
        let versionInTheTitle = healthReport(
            make.song("Song (Remix)", seconds: 242, album: "Song (Remix) - Single", id: "single"),
            make.song("Song (Remix)", seconds: 242, album: "Best of 2014", id: "compilation"))
        #expect(bothRemixes.duplicates.count == 1)
        #expect(versionInTheTitle.duplicates.count == 1)
    }

    @Test func anArtistsOwnNameOnTheAlbumIsNoVersion() {
        let found = healthReport(
            make.song("Song", "The Remix Kids", seconds: 240, album: "Studio Album", id: "studio"),
            make.song("Song", "The Remix Kids", seconds: 241, album: "The Remix Kids", id: "self-titled"))
        #expect(found.duplicates.count == 1)
    }

    @Test func aRemasterGuestOrTrackNumberInTheTitleIsStillTheSameRecording() {
        let found = healthReport(
            make.song("Pain 1993", "Drake", seconds: 149, id: "plain"),
            make.song("Pain 1993 (featuring Playboi Carti)", "Drake", seconds: 149, id: "feat"),
            make.song("10 - Pain 1993 - Remastered 2021", "Drake", seconds: 150, id: "remaster"))
        #expect(found.duplicates.count == 1)
        #expect(found.duplicates.first?.copies.count == 3)
    }

    @Test func aSharedIsrcIsOneRecordingWhateverTheTitleSays() {
        let found = healthReport(
            make.song("紅蓮華", "LiSA", seconds: 240, isrc: ["JPU901901234"], id: "jp"),
            make.song("Gurenge", "LiSA", seconds: 241, isrc: ["JP-U90-19-01234"], id: "en"))
        #expect(found.duplicates.count == 1)
        #expect(found.duplicates.first?.basis == .tags)
    }

    @Test func aSharedMusicBrainzRecordingIsOneRecording() {
        let found = healthReport(
            make.song("Teardrop", "Massive Attack", seconds: 330, mbid: "F200A9A9-0000-0000-0000-000000000001", id: "a"),
            make.song("Tear Drop (Album Version)", "Massive Attack", seconds: 331, mbid: "f200a9a9-0000-0000-0000-000000000001", id: "b"))
        #expect(found.duplicates.count == 1)
        #expect(found.duplicates.first?.basis == .tags)
    }

    @Test func oneIsrcOnAWholeAlbumOfDifferentLengthsIsATaggingMistakeNotACopy() {
        let code = ["USRC17607839"]
        let found = healthReport(
            make.song("One", seconds: 180, isrc: code, id: "1"),
            make.song("Two", seconds: 240, isrc: code, id: "2"),
            make.song("Three", seconds: 305, isrc: code, id: "3"))
        #expect(found.duplicates.isEmpty)
    }

    @Test func differentIsrcsStillFallBackToTheTitleAndLength() {
        let found = healthReport(
            make.song("Song", seconds: 200, isrc: ["GBAAA0100001"], id: "a"),
            make.song("Song (Remastered 2011)", seconds: 201, isrc: ["GBAAA1100002"], id: "b"))
        #expect(found.duplicates.count == 1)
        #expect(found.duplicates.first?.basis == .titleAndLength)
    }

    @Test func copiesChainIntoOneSet() {
        let found = healthReport(
            make.song("Song", seconds: 200, id: "a"), make.song("Song", seconds: 203, id: "b"), make.song("Song", seconds: 206, id: "c"))
        #expect(found.duplicates.count == 1)
        #expect(found.duplicates.first?.copies.count == 3)
    }

    @Test func theBestCopyHasMoreBitsThenAHigherRate() {
        let found = healthReport(
            make.song("Song", bitDepth: 16, rate: 44_100, bitRate: 1650, id: "cd"),
            make.song("Song", bitDepth: 24, rate: 48_000, bitRate: 1500, id: "hires48"),
            make.song("Song", bitDepth: 24, rate: 96_000, bitRate: 2800, id: "hires96"),
            make.song("Song", suffix: "mp3", bitDepth: nil, rate: 44_100, bitRate: 320, id: "mp3"))
        #expect(found.duplicates.first.map(ids) == ["hires96", "hires48", "cd", "mp3"])
    }

    @Test func theBitRateSettlesLossyCopies() {
        let found = healthReport(
            make.song("Song", suffix: "mp3", bitDepth: nil, bitRate: 192, id: "low"),
            make.song("Song", suffix: "mp3", bitDepth: nil, bitRate: 320, id: "high"))
        #expect(found.duplicates.first.map(ids) == ["high", "low"])
        #expect(found.duplicates.first?.bestReason == .sound)
    }

    @Test func copiesThatSoundAlikeKeepTheOneWithFullerTags() {
        let found = healthReport(make.song("Song", year: nil, genre: nil, id: "bare"), make.song("Song", id: "tagged"))
        #expect(found.duplicates.first.map(ids) == ["tagged", "bare"])
        #expect(found.duplicates.first?.bestReason == .tags)
    }

    @Test func identicalCopiesSayNothingSetsThemApart() {
        let found = healthReport(make.song("Song", id: "b"), make.song("Song", id: "a"))
        #expect(found.duplicates.first.map(ids) == ["a", "b"])
        #expect(found.duplicates.first?.bestReason == BestReason.none)
    }

    @Test func copiesInTwoPlacesAreNotDuplicates() {
        var phone = serverSongHealth
        phone.place = { $0.id.hasPrefix("p") ? "phone" : "server" }
        let found = checkLibrary([make.song("Song", id: "p1"), make.song("Song", id: "s1")], phone)
        #expect(found.duplicates.isEmpty)
    }

    // MARK: Split albums

    @Test func anAlbumUnderTwoIdsIsSplitAndSaysWhatDiffers() {
        let found = healthReport(
            make.song("One", "SueCo", album: "It Was Fun While It Lasted", albumId: "a", track: 1, albumArtist: "SueCo"),
            make.song("Two", "SueCo", album: "It Was Fun While It Lasted", albumId: "a", track: 2, albumArtist: "SueCo"),
            make.song("Three", "Sueco", album: "It Was Fun While It Lasted", albumId: "b", track: 3, albumArtist: "Sueco")).splitAlbums
        #expect(found.count == 1)
        #expect(found.first?.parts.map(\.albumId) == ["a", "b"])
        #expect(found.first?.artist == "SueCo")
        #expect(found.first?.differences == [AlbumDifferenceValues(kind: .albumArtist, values: ["SueCo", "Sueco"])])
    }

    @Test func aMissingYearSplitsAnAlbumAndIsNamed() {
        let found = healthReport(
            make.song("One", album: "Currents", albumId: "a", year: 2015),
            make.song("Two", album: "Currents", albumId: "b", year: nil)).splitAlbums
        #expect(found.count == 1)
        #expect(found.first?.differences.map(\.kind) == [.year])
        #expect(found.first?.differences.first?.values == ["2015", ""])
        #expect(found.first?.differences.first?.words == "The year differs: 2015, none.")
    }

    @Test func aStraySpaceIsNamedSinceItCannotBeSeen() throws {
        let found = try #require(healthReport(
            make.song("One", "Disturbed", album: "The Sickness ", albumId: "a"),
            make.song("Two", "Disturbed", album: "The Sickness", albumId: "b")).splitAlbums.first)
        #expect(found.heading == "The Sickness by Disturbed, shown as 2 albums")
        #expect(found.summary == "The album title has a stray space on some songs.")
    }

    @Test func twoAlbumsOfOneNameFromDifferentYearsAreTwoAlbums() {
        let found = healthReport(
            make.song("My Name Is Jonas", "Weezer", album: "Weezer", albumId: "blue", year: 1994),
            make.song("Hash Pipe", "Weezer", album: "Weezer", albumId: "green", year: 2001))
        #expect(found.splitAlbums.isEmpty)
    }

    @Test func albumsOfOneNameByDifferentArtistsAreNotSplit() {
        let found = healthReport(
            make.song("A", "One", album: "Greatest Hits", albumId: "x"), make.song("B", "Two", album: "Greatest Hits", albumId: "y"))
        #expect(found.splitAlbums.isEmpty)
    }

    @Test func whenNothingVisibleDiffersTheReportSaysSomethingElseDoes() {
        let found = healthReport(make.song("One", album: "Album", albumId: "a"), make.song("Two", album: "Album", albumId: "b")).splitAlbums
        #expect(found.first?.differences.map(\.kind) == [.other])
    }

    // MARK: Missing tags

    @Test func eachMissingTagListsItsSongs() {
        let found = healthReport(
            make.song("Tidy", albumId: "x"),
            make.song("No genre", albumId: "x", genre: nil),
            make.song("No year", albumId: "x", year: 0),
            make.song("No track", albumId: "x", track: .some(nil)),
            make.song("No album artist", albumId: "x", albumArtist: .some(nil)),
            make.song("No cover", albumId: "x", cover: .some(nil)))
        #expect(found.missing[.genre]?.map(\.title) == ["No genre"])
        #expect(found.missing[.year]?.map(\.title) == ["No year"])
        #expect(found.missing[.trackNumber]?.map(\.title) == ["No track"])
        #expect(found.missing[.albumArtist]?.map(\.title) == ["No album artist"])
        #expect(found.missing[.cover]?.map(\.title) == ["No cover"])
        #expect(found.count(.noGenre) == 1)
    }

    @Test func aSingleNeedsNoTrackNumberOrAlbumArtist() {
        let found = healthReport(make.song("Single", albumId: "one", track: .some(nil), albumArtist: .some(nil)))
        #expect(found.missing[.trackNumber] == nil)
        #expect(found.missing[.albumArtist] == nil)
    }

    @Test func aTagTheAppNeverKeepsIsNeverMissing() {
        var phone = serverSongHealth
        phone.seen = [.genre]
        let found = checkLibrary([make.song("Song", year: nil, genre: nil, cover: .some(nil))], phone)
        #expect(Set(found.missing.keys) == [.genre])
    }

    @Test func songsMissingATagComeByArtistThenAlbumOrder() {
        let found = healthReport(
            make.song("B2", "Beta", album: "B", albumId: "b", genre: nil, track: 2),
            make.song("A1", "Alpha", album: "A", albumId: "a", genre: nil, track: 1),
            make.song("B1", "Beta", album: "B", albumId: "b", genre: nil, track: 1))
        #expect(found.songs(.noGenre).map(\.title) == ["A1", "B1", "B2"])
    }

    // MARK: The report

    @Test func aSongWithNoLengthIsFound() {
        let found = healthReport(make.song("Broken", seconds: 0), make.song("Fine", seconds: 180))
        #expect(found.noLength.map(\.title) == ["Broken"])
    }

    @Test func aTidyLibraryIsClean() {
        let found = healthReport(make.song("One", albumId: "a"), make.song("Two", seconds: 180, albumId: "a"))
        #expect(found.clean)
        #expect(found.overview == "Checked 2 songs.")
    }

    @Test func findingsComeInTheirOrderWithCounts() {
        let found = healthReport(make.song("Song", genre: nil, id: "a"), make.song("Song", genre: nil, id: "b"), make.song("Other", seconds: 0))
        #expect(found.findings == [.duplicates, .noLength, .noGenre])
        #expect(found.count(.duplicates) == 1)
        #expect(found.overview == "Checked 3 songs. 3 things could be better.")
    }

    @Test func removedSongsLeaveTheReport() {
        let found = healthReport(make.song("Song", genre: nil, id: "a"), make.song("Song", genre: nil, id: "b"))
        let after = found.without(["b"], fields: serverSongHealth)
        #expect(after.duplicates.isEmpty)
        #expect(after.songs(.noGenre).map(\.id) == ["a"])
    }

    // MARK: Words

    @Test func aSetOfCopiesSaysWhichToKeep() throws {
        let found = try #require(healthReport(
            make.song("Song", "Artist", bitDepth: 24, rate: 96_000, id: "a"),
            make.song("Song", "Artist", suffix: "mp3", bitDepth: nil, bitRate: 320, id: "b")).duplicates.first)
        #expect(found.heading(serverSongHealth) == "Song by Artist")
        #expect(found.summary(serverSongHealth) == "2 copies. Same title, artist and length. Keep the first, FLAC, 24-bit, 96 kHz.")
    }

    @Test func qualityReadsTheWayPeopleSayIt() {
        #expect(qualityText(format: "flac", lossless: true, bitDepth: 16, sampleRate: 44_100, bitRate: 900) == "FLAC, 16-bit, 44.1 kHz")
        #expect(qualityText(format: "mp3", lossless: false, bitDepth: nil, sampleRate: 44_100, bitRate: 320) == "MP3, 320 kbps")
        #expect(qualityText(format: nil, lossless: false, bitDepth: nil, sampleRate: nil, bitRate: nil) == "unknown quality")
    }

    @Test func countsReadNaturally() {
        #expect(HealthCheck.noGenre.countLabel(1) == "1 song")
        #expect(HealthCheck.noGenre.countLabel(2256) == "2,256 songs")
        #expect(HealthCheck.duplicates.countLabel(64) == "64 songs with more than one copy")
    }

    @Test func noWordsUseADash() {
        let differences: [AlbumDifference] = [.title, .albumArtist, .year, .other]
        let words = HealthCheck.allCases.flatMap { [$0.title, $0.meaning, $0.advice] }
            + differences.map { AlbumDifferenceValues(kind: $0, values: ["a", "b"]).words }
            + [DuplicateBasis.tags, .titleAndLength].map(\.words)
            + [BestReason.sound, .tags, .none].map { $0.words("FLAC") } + [healthAllClear]
        for word in words { #expect(!word.contains("\u{2014}") && !word.contains("\u{2013}"), "\(word)") }
    }
}
