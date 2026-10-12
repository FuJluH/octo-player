import Foundation
import Testing
@testable import OctoKit

/// Every common way files write each tag, as a tag reader hands them over: its own names for FLAC,
/// MP3 and MP4, and the raw frame and atom names older files and other writers leave behind.
@Suite struct TagFormsTest {
    /// A tag map from name and value pairs, a repeated name gathering its values in order.
    private func tags(_ pairs: (String, String)...) -> FileTags {
        parseTags(groupInOrder(pairs, by: { $0.0 }).map { ($0.0, $0.1.map { $0.1 }) })
    }

    private func near(_ value: Float?, _ expected: Float) throws -> Bool {
        abs(try #require(value) - expected) <= 0.001
    }

    let recording = "b1a9c0e9-d987-4042-ae91-78d6a3267d69"
    let release = "3f0a4f44-1f1b-4b3c-9c62-7a7d7e2c1a10"
    let group = "7c3218d7-75e0-4e8c-971f-f097b6c308c5"
    let artistA = "056e4f3e-d505-4dad-8ec1-d04f521cbb56"
    let artistB = "a8e8e3c4-9f0b-4d8e-9a1f-6b5b0d6f2e77"

    @Test func aFlacFileAsItsCommentsName() throws {
        let t = tags(
            ("TITLE", "Get Lucky"),
            ("ARTIST", "Daft Punk feat. Pharrell Williams"),
            ("ARTISTS", "Daft Punk"),
            ("ARTISTS", "Pharrell Williams"),
            ("ALBUMARTIST", "Daft Punk"),
            ("ALBUM", "Random Access Memories"),
            ("DATE", "2013-05-17"),
            ("ORIGINALDATE", "2013-05-17"),
            ("TRACKNUMBER", "8"),
            ("TRACKTOTAL", "13"),
            ("DISCNUMBER", "1"),
            ("DISCTOTAL", "1"),
            ("GENRE", "Disco"),
            ("GENRE", "Funk"),
            ("COMPOSER", "Thomas Bangalter"),
            ("COMPOSER", "Pharrell Williams"),
            ("BPM", "116"),
            ("MUSICBRAINZ_TRACKID", recording),
            ("MUSICBRAINZ_ALBUMID", release),
            ("MUSICBRAINZ_RELEASEGROUPID", group),
            ("MUSICBRAINZ_ARTISTID", artistA),
            ("MUSICBRAINZ_ARTISTID", artistB),
            ("REPLAYGAIN_TRACK_GAIN", "-9.12 dB"),
            ("REPLAYGAIN_TRACK_PEAK", "0.988251"),
            ("REPLAYGAIN_ALBUM_GAIN", "-8.40 dB"),
            ("REPLAYGAIN_ALBUM_PEAK", "1.000000")
        )
        #expect(t.title == "Get Lucky")
        #expect(t.artist == "Daft Punk feat. Pharrell Williams")
        #expect(t.artists == ["Daft Punk", "Pharrell Williams"])
        #expect(t.albumArtist == "Daft Punk")
        #expect(t.year == 2013)
        #expect(t.originalYear == 2013)
        #expect(t.trackNo == 8)
        #expect(t.discNo == 1)
        #expect(t.genres == ["Disco", "Funk"])
        #expect(t.composer == "Thomas Bangalter, Pharrell Williams")
        #expect(t.bpm == 116)
        #expect(t.mbRecordingId == recording)
        #expect(t.mbAlbumId == release)
        #expect(t.mbReleaseGroupId == group)
        #expect(t.mbArtistIds == [artistA, artistB])
        #expect(try near(t.trackGain, -9.12))
        #expect(try near(t.trackPeak, 0.988))
        #expect(try near(t.albumGain, -8.4))
        #expect(try near(t.albumPeak, 1))
    }

    @Test func anMp3AsTheTagLibraryTranslatesIt() {
        let t = tags(
            ("TITLE", "Song"),
            ("ARTIST", "Artist"),
            ("ALBUMARTIST", "Band"),
            ("DATE", "2017-06-16"),
            ("ORIGINALDATE", "1977"),
            ("TRACKNUMBER", "3/12"),
            ("DISCNUMBER", "2/2"),
            ("COMPILATION", "1"),
            ("GENRE", "Rock"),
            ("ARTISTSORT", "Artist, The"),
            ("ALBUMSORT", "Album, An"),
            ("TITLESORT", "Song, A"),
            ("COMMENT", "Bought on vinyl"),
            ("MUSICBRAINZ_TRACKID", recording),
            ("MUSICBRAINZ_ALBUMID", release)
        )
        #expect(t.year == 2017)
        #expect(t.originalYear == 1977)
        #expect(t.trackNo == 3)
        #expect(t.discNo == 2)
        #expect(t.compilation)
        #expect(t.sortTitle == "Song, A")
        #expect(t.sortAlbum == "Album, An")
        // Artist sort only files the album when there is no album-artist tag.
        #expect(t.sortAlbumArtist == nil)
        #expect(t.comment == "Bought on vinyl")
        #expect(t.mbRecordingId == recording)
    }

    @Test func rawId3FrameNamesAndUserTextFrames() throws {
        let t = tags(
            ("TIT2", "Frame Title"),
            ("TPE1", "Frame Artist"),
            ("TPE2", "Frame Band"),
            ("TALB", "Frame Album"),
            ("TYER", "1999"),
            ("TORY", "1985"),
            ("TRCK", "07/10"),
            ("TPOS", "1/1"),
            ("TCON", "(17)"),
            ("TCMP", "1"),
            ("TBPM", "98"),
            ("TCOM", "Writer"),
            ("TSOP", "Artist, Frame"),
            ("TSST", "Side A"),
            ("TXXX:MusicBrainz Album Id", release),
            ("MUSICBRAINZ RELEASE GROUP ID", group),
            ("TXXX:MusicBrainz Artist Id", "\(artistA)/\(artistB)"),
            ("UFID:http://musicbrainz.org", recording),
            ("TXXX:REPLAYGAIN_TRACK_GAIN", "+1.5 dB")
        )
        #expect(t.title == "Frame Title")
        #expect(t.artist == "Frame Artist")
        #expect(t.albumArtist == "Frame Band")
        #expect(t.album == "Frame Album")
        #expect(t.year == 1999)
        #expect(t.originalYear == 1985)
        #expect(t.trackNo == 7)
        #expect(t.discNo == 1)
        #expect(t.genres == ["Rock"])
        #expect(t.compilation)
        #expect(t.bpm == 98)
        #expect(t.composer == "Writer")
        #expect(t.discTitle == "Side A")
        #expect(t.mbAlbumId == release)
        #expect(t.mbReleaseGroupId == group)
        #expect(t.mbArtistIds == [artistA, artistB])
        #expect(t.mbRecordingId == recording)
        #expect(try near(t.trackGain, 1.5))
        // A band tag means the artist sort does not file the album.
        #expect(t.sortAlbumArtist == nil)
    }

    @Test func anMp4AsTheTagLibraryTranslatesIt() throws {
        let t = tags(
            ("TITLE", "Track"),
            ("DATE", "2017-06-16T07:00:00Z"),
            ("TRACKNUMBER", "3/12"),
            ("DISCNUMBER", "1/2"),
            ("ALBUMARTIST", "Band"),
            ("COMPILATION", "1"),
            ("BPM", "120"),
            ("ALBUMARTISTSORT", "Band, The"),
            ("----:com.apple.iTunes:MusicBrainz Track Id", recording),
            ("----:com.apple.iTunes:replaygain_album_gain", "-7.00 dB"),
            ("ITUNESADVISORY", "1")
        )
        #expect(t.year == 2017)
        #expect(t.trackNo == 3)
        #expect(t.discNo == 1)
        #expect(t.compilation)
        #expect(t.bpm == 120)
        #expect(t.sortAlbumArtist == "Band, The")
        #expect(t.mbRecordingId == recording)
        #expect(try near(t.albumGain, -7))
        #expect(t.explicit == true)
    }

    @Test func rawMp4AtomNames() {
        let t = tags(
            ("©nam", "Atom Title"),
            ("©ART", "Atom Artist"),
            ("aART", "Atom Band"),
            ("©alb", "Atom Album"),
            ("©day", "2020"),
            ("trkn", "4/9"),
            ("disk", "2/3"),
            ("©gen", "Jazz"),
            ("cpil", "1"),
            ("tmpo", "90"),
            ("©wrt", "Atom Writer"),
            ("soaa", "Band, Atom"),
            ("rtng", "2")
        )
        #expect(t.title == "Atom Title")
        #expect(t.artist == "Atom Artist")
        #expect(t.albumArtist == "Atom Band")
        #expect(t.album == "Atom Album")
        #expect(t.year == 2020)
        #expect(t.trackNo == 4)
        #expect(t.discNo == 2)
        #expect(t.genres == ["Jazz"])
        #expect(t.compilation)
        #expect(t.bpm == 90)
        #expect(t.composer == "Atom Writer")
        #expect(t.sortAlbumArtist == "Band, Atom")
        #expect(t.explicit == false)
    }

    @Test func everyWayOfWritingAYear() {
        let years: [(String, Int)] = [
            ("2017", 2017),
            ("2017-06-16", 2017),
            ("2017-06", 2017),
            ("20170616", 2017),
            ("2017/06/16", 2017),
            (" 2017 ", 2017),
            ("(2017)", 2017),
            ("2017-06-16T10:00:00Z", 2017),
            ("2017-06-16 10:00:00", 2017),
            ("\u{FEFF}2017", 2017),
            ("16/06/2017", 2017),
            ("June 16, 2017", 2017),
            ("c. 1965", 1965),
        ]
        for (text, year) in years { #expect(yearOf(text) == year, "\(text)") }
        for text in ["", "  ", "0000", "17", "unknown", "0"] { #expect(yearOf(text) == nil, "\(text)") }
        #expect(yearOf(nil) == nil)
    }

    @Test func theYearTagsInOrder() {
        #expect(tags(("YEAR", "2001")).year == 2001)
        #expect(tags(("RELEASEDATE", "2002-01-01")).year == 2002)
        #expect(tags(("TDRC", "2003")).year == 2003)
        #expect(tags(("ORIGINALYEAR", "1970"), ("DATE", "2003")).originalYear == 1970)
        #expect(tags(("TDOR", "1971-02")).originalYear == 1971)
    }

    @Test func anOriginalYearAfterTheEditionIsAMistake() {
        let t = tags(("DATE", "1990"), ("ORIGINALDATE", "2005"))
        #expect(t.year == 1990)
        #expect(t.originalYear == nil)
        // With no edition year, the original alone is kept.
        #expect(tags(("ORIGINALDATE", "1977")).originalYear == 1977)
    }

    @Test func everyWayOfWritingAPlace() {
        #expect(position("3") == Position(number: 3, total: nil))
        #expect(position("03") == Position(number: 3, total: nil))
        #expect(position("3/12") == Position(number: 3, total: 12))
        #expect(position(" 3 / 12 ") == Position(number: 3, total: 12))
        #expect(position("3 of 12") == Position(number: 3, total: 12))
        #expect(position("(3)") == Position(number: 3, total: nil))
        #expect(position("0/12") == Position(number: nil, total: 12))
        #expect(position("A1") == Position(number: nil, total: nil))
        #expect(position("") == Position(number: nil, total: nil))
        #expect(position(nil) == Position(number: nil, total: nil))
    }

    @Test func aTotalIsNeverTakenForTheNumber() {
        let t = tags(("TRACKTOTAL", "12"), ("TOTALDISCS", "2"))
        #expect(t.trackNo == nil)
        #expect(t.discNo == nil)
        #expect(tags(("TRACK", "5"), ("TOTALTRACKS", "10")).trackNo == 5)
        #expect(tags(("DISC", "2")).discNo == 2)
    }

    @Test func oldGenreNumbers() {
        #expect(parseGenres(["17"]) == ["Rock"])
        #expect(parseGenres(["(17)"]) == ["Rock"])
        #expect(parseGenres(["(17)(13)"]) == ["Rock", "Pop"])
        #expect(parseGenres(["(17)Rock and Roll"]) == ["Rock and Roll"])
        #expect(parseGenres(["(RX)"]) == ["Remix"])
        #expect(parseGenres(["0; 191"]) == ["Blues", "Psybient"])
        // Numbers past the list, and names with digits, stay as written.
        #expect(parseGenres(["1990s", "2step", "999"]) == ["1990s", "2step", "999"])
    }

    @Test func genresJoinedByNullsOrSeparators() {
        #expect(tags(("GENRE", "Rock\u{0}Pop"), ("GENRE", "Soul")).genres == ["Rock", "Pop", "Soul"])
        #expect(tags(("GENRE", "House, Techno")).genres == ["House", "Techno"])
    }

    @Test func keysInAnyCaseAndSpellingAreOneTag() {
        #expect(tags(("album artist", "X")).albumArtist == "X")
        #expect(tags(("Album_Artist", "X")).albumArtist == "X")
        #expect(tags(("\u{FEFF}TITLE", "X")).title == "X")
        #expect(tags(("musicbrainz_trackid", recording.uppercased())).mbRecordingId == recording)
    }

    @Test func valuesLoseByteOrderMarksSpacesAndNulls() {
        let t = tags(("TITLE", "\u{FEFF}  Title \u{0}"), ("ARTIST", "   "), ("ARTIST", "Real"))
        #expect(t.title == "Title")
        #expect(t.artist == "Real")
        #expect(tags(("TITLE", "First\u{0}Second")).title == "First")
    }

    @Test func compilationForms() {
        #expect(tags(("COMPILATION", "true")).compilation)
        #expect(tags(("TCMP", "yes")).compilation)
        #expect(!tags(("COMPILATION", "0")).compilation)
    }

    @Test func tempoForms() {
        #expect(bpmOf("128") == 128)
        #expect(bpmOf("128.6") == 129)
        #expect(bpmOf("128 BPM") == 128)
        #expect(bpmOf("0") == nil)
        #expect(bpmOf("fast") == nil)
    }

    @Test func explicitForms() {
        #expect(explicitOf("4") == true)
        #expect(explicitOf("Explicit") == true)
        #expect(explicitOf("clean") == false)
        #expect(explicitOf("0") == nil)
    }

    @Test func musicBrainzIdsHoweverTheyAreJoined() {
        #expect(musicIds(["\(artistA); \(artistB)"]) == [artistA, artistB])
        #expect(musicIds([" \(artistA.uppercased()) ", artistA]) == [artistA])
        #expect(musicIds(["not an id", ""]) == [])
    }

    @Test func r128GainIsUsedWhenThereIsNoOther() throws {
        let t = tags(("R128_TRACK_GAIN", "-512"))
        #expect(try near(t.trackGain, 3))
    }

    @Test func theOnlyTagsSomeFilesHave() {
        // Most files of a plain library: title, artist and album, nothing else.
        let t = tags(("TITLE", "T"), ("ARTIST", "A"), ("ALBUM", "B"))
        #expect(t == FileTags(title: "T", artist: "A", album: "B", artists: ["A"]))
    }

    @Test func aTempoTooLargeForANumberIsNotOne() {
        #expect(bpmOf("99999999999999999999999") == nil)
        #expect(bpmOf("99999999999999999999999.5") == nil)
    }
}
