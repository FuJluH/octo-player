import Foundation
import Testing
@testable import OctoKit

@Suite struct LibraryWordsTests {
    @Test func lengthsAndCounts() {
        #expect(asClock(187) == "3:07")
        #expect(asClock(3_765) == "1:02:45")
        #expect(asLength(2_880) == "48 min")
        #expect(asLength(4_320) == "1 hr 12 min")
        #expect(asLength(29) == "0 min")
        #expect(songsCount(1) == "1 song")
        #expect(songsCount(1_234) == "1234 songs")
        #expect(albumsCount(2) == "2 albums")
        #expect(countText(1_234, "song", "songs") == "1,234 songs")
        #expect(countText(1, "day", "days") == "1 day")
        #expect(filteredCount(shown: 120, all: 2_835) == "120 of 2,835 songs")
        #expect(filteredCount(shown: 0, all: 1) == "0 of 1 song")
        #expect(grouped(1_234_567) == "1,234,567")
    }

    @Test func anUnknownLengthShowsNothingRatherThanZero() {
        #expect(rowLength(0) == nil)
        #expect(rowLength(-1) == nil)
        #expect(rowLength(999) == nil)
        #expect(rowLength(225_000) == "3:45")
        #expect(rowLength(7_400) == "0:07")
        #expect(rowLength(723_000) == "12:03")
        #expect(rowLength(3_723_000) == "1:02:03")
        for seconds in [1, 59, 60, 599, 600, 3_599] {
            #expect((rowLength(Int64(seconds) * 1_000) ?? "").count <= lengthSlotSample.count)
        }
    }

    @Test func aFindWhoseAlbumIsItsOwnTitleNamesOnlyTheArtist() {
        #expect(songSubtitle(title: "Night Song", artist: "Singer", album: "Night Song", find: true) == "Singer")
        #expect(songSubtitle(title: "Night Song", artist: "Singer", album: " night song ", find: true) == "Singer")
        #expect(songSubtitle(title: "Night Song", artist: "Singer", album: "First Album", find: true) == "Singer • First Album")
        #expect(songSubtitle(title: "Night Song", artist: "Singer", album: "Night Song", find: false) == "Singer • Night Song")
        #expect(songSubtitle(title: "Night Song", artist: "Singer", album: "", find: true) == "Singer")
    }

    @Test func theSortArrowAndTheTitleFit() {
        #expect(sortArrowTurn(descending: false) == 0)
        #expect(sortArrowTurn(descending: true) == 180)
        #expect(titleFitsBeside(titleWidth: 400, buttonsWidth: 500, width: 1080))
        #expect(titleFitsBeside(titleWidth: 580, buttonsWidth: 500, width: 1080))
        #expect(!titleFitsBeside(titleWidth: 581, buttonsWidth: 500, width: 1080))
        #expect(!titleFitsBeside(titleWidth: 300, buttonsWidth: 900, width: 1080))
    }

    @Test func serverErrorsInPlainWords() {
        #expect(userMessage(URLError(.cannotConnectToHost)) == "Couldn't reach the server. Check the address, and that you're on the right network.")
        #expect(userMessage(OctoError.http(503)) == "The server isn't answering right now. It may be restarting, so try again in a moment.")
        #expect(userMessage(OctoError.notSubsonic) == "That address answered, but not like a music server. Check the port.")
        #expect(userMessage(OctoError.wrongCredentials("x")) == "Wrong username or password.")
        #expect(userMessage(OctoError.notFound("x")) == "That isn't on the server any more.")
        #expect(userMessage(OctoError.server(code: 0, message: "Nope")) == "The server said: Nope")
        #expect(accessButtonLabel(deniedForever: true) == "Open settings")
        #expect(accessButtonLabel(deniedForever: false) == "Allow access")
    }

    @Test func deletingFromDiskAsksAndSays() {
        #expect(deleteNames(["Teardrop"]) == "Teardrop")
        #expect(deleteNames(["a", "b", "c"]) == "3 songs")
        #expect(deleteTitle(1) == "Delete this song from disk?")
        #expect(deleteTitle(1_200) == "Delete 1,200 songs from disk?")
        #expect(deleteBody("Teardrop", keepDays: 30) == "This takes Teardrop off the server's disk and out of your library. The server keeps the file in its trash for 30 days, so you can put it back from Library health. Octo will not download it again by itself.")
        #expect(deleteBody("3 songs", keepDays: 1).contains("in its trash for 1 day,"))
        #expect(deleteBody("3 songs", keepDays: 0).contains("in its trash until someone clears it,"))
        #expect(deletedLine(1, title: "Teardrop") == "Deleted Teardrop from disk.")
        #expect(deletedLine(4, title: nil) == "Deleted 4 songs from disk.")
    }

    @Test func theTrashSaysHowLongIsLeft() {
        let now: Int64 = 1_000_000_000_000
        #expect(goneText(goneAtMillis: nil, nowMillis: now) == "Kept until someone clears the trash")
        #expect(goneText(goneAtMillis: now + 3_600_000, nowMillis: now) == "Deleted for good today")
        #expect(goneText(goneAtMillis: now + 86_400_000, nowMillis: now) == "Deleted for good tomorrow")
        #expect(goneText(goneAtMillis: now + 5 * 86_400_000, nowMillis: now) == "Deleted for good in 5 days")
        #expect(goneText(goneAtMillis: now - 5 * 86_400_000, nowMillis: now) == "Deleted for good today")
        #expect(goneAtMillis("2026-10-11T00:00:00Z") == 1_791_676_800_000)
        #expect(goneAtMillis("") == nil)
        #expect(keepsFor(1) == "The server keeps a song deleted from disk for 1 day, then deletes it for good.")
        #expect(keepsFor(0) == "The server keeps a song deleted from disk until someone clears its trash.")
        #expect(replacedText(was: "FLAC", now: "MP3 320") == "Replaced: was FLAC, now MP3 320")
        #expect(replacedText(was: nil, now: " ") == "Replaced by another copy")
        #expect(replacedSpoken(was: "FLAC", now: "MP3") == "Replaced by another copy. Yours was FLAC, now MP3")
    }

    @Test func anAlbumsGenreAndAverage() {
        #expect(albumGenre(["Rock", "pop", "Pop", "rock", ""]) == "Rock")
        #expect(albumGenre(["", " "]) == nil)
        #expect(albumGenre(["jazz", "Soul", "SOUL"]) == "Soul")
        #expect(averageRating([0, 4, 5, 4]) == 13.0 / 3)
        #expect(averageRating([0, 0]) == nil)
        #expect(starsText(13.0 / 3) == "4.3")
        #expect(starsText(4.0) == "4")
        #expect(starsText(3.96) == "4")
        #expect(averageRatingSpoken(1) == "Songs rated 1 star on average")
        #expect(averageRatingSpoken(4.25) == "Songs rated 4.3 stars on average")
        #expect(albumDownloadLabel(songs: 3, held: 2, done: 0) == "Download album")
        #expect(albumDownloadLabel(songs: 3, held: 3, done: 1) == "Downloading")
        #expect(albumDownloadLabel(songs: 3, held: 3, done: 3) == "Downloaded")
        #expect(albumLibraryNote(inLibrary: 3, songs: 10) == "3 of 10 in your library")
        #expect(albumLibraryNote(inLibrary: 10, songs: 10) == nil)
        #expect(addMissingLabel(missing: 1) == "Add the missing song")
        #expect(addMissingLabel(missing: 4) == "Add the 4 missing songs")
    }

    @Test func theFavoritesPageOpensWhereThereIsSomething() {
        #expect(firstSegment(songs: 1, albums: 3, artists: 0) == .songs)
        #expect(firstSegment(songs: 0, albums: 3, artists: 2) == .albums)
        #expect(firstSegment(songs: 0, albums: 0, artists: 2) == .artists)
        #expect(firstSegment(songs: 0, albums: 0, artists: 0) == .songs)
    }

    @Test func downloadsSayWhereTheyAre() {
        #expect(sizeLabel(850 * 1024) == "850 KB")
        #expect(sizeLabel(1) == "1 KB")
        #expect(sizeLabel(13 * 1024 * 1024) == "13.0 MB")
        #expect(sizeLabel(3 * (1 << 30) + (1 << 29)) == "3.5 GB")
        #expect(downloadDetail(.queued, progress: 0, sizeBytes: 0, reasons: [], playlistNames: [:]) == "Waiting")
        #expect(downloadDetail(.downloading, progress: 0.426, sizeBytes: 0, reasons: [], playlistNames: [:]) == "Downloading, 43%")
        #expect(downloadDetail(.failed, progress: 0, sizeBytes: 0, reasons: [], playlistNames: [:]) == "Could not download. Tap to try again")
        #expect(downloadDetail(.done, progress: 1, sizeBytes: 2 * 1024 * 1024, reasons: ["manual"], playlistNames: [:]) == "2.0 MB")
        #expect(downloadDetail(.done, progress: 1, sizeBytes: 1024, reasons: ["liked"], playlistNames: [:]) == "1 KB · Kept with Liked songs")
        #expect(keptBy(["playlist:p1"], playlistNames: ["p1": "Road trip"]) == "Kept with Road trip")
        #expect(keptBy(["playlist:gone"], playlistNames: [:]) == "Kept with a playlist")
        #expect(keptSummary(serverOnly: 0, done: 0) == "Every song is already on this phone")
        #expect(keptSummary(serverOnly: 5, done: 5) == "All 5 downloaded")
        #expect(keptSummary(serverOnly: 5, done: 2) == "2 of 5 downloaded")
    }

    @Test func playlistLinesAndNotes() {
        #expect(playlistsLead(importNote: false) == [.newPlaylist, .newLiveList, .importFile])
        #expect(playlistsLead(importNote: true) == [.newPlaylist, .newLiveList, .importFile, .importNote])
        #expect(phoneOnlyNote(1) == "1 song is only on this phone and is not in the server's copy")
        #expect(phoneOnlyNote(3) == "3 songs are only on this phone and are not in the server's copy")
        #expect(holdingsByPlaylist([("p", "a"), ("p", "b"), ("q", "a")]) == ["p": ["a", "b"], "q": ["a"]])
    }

    @Test func findingABetterCopy() {
        #expect(findHigherQualityLabel(9) == "Find higher quality for 9 songs")
        #expect(findHigherQualityAsk(1) == "Look for a higher quality copy of 1 song?")
        #expect(findHigherQualityAsk(3, source: " Lidarr ") == "Look for a higher quality copy of 3 songs on Lidarr?")
    }
}

@Suite struct SongInfoTests {
    private let utc = TimeZone(identifier: "UTC")!
    private let us = Locale(identifier: "en_US_POSIX")

    private func lines(_ facts: SongInfoFacts) -> [String: String] {
        Dictionary(infoLines(facts, zone: utc, locale: us).map { ($0.label, $0.value) }, uniquingKeysWith: { a, _ in a })
    }

    @Test func aPhoneFileSaysEverythingItKnows() {
        var facts = SongInfoFacts(title: "Hold On", artist: "Mira", album: "Long Way")
        facts.albumArtist = "Various Artists"
        facts.year = 2021
        facts.genre = "Soul"
        facts.trackNo = 3
        facts.discNo = 2
        facts.durationMs = 245_000
        facts.mimeType = "audio/flac"
        facts.bitrate = 1_021_400
        facts.sampleRate = 44_100
        facts.bitDepth = 24
        facts.sizeBytes = 31_400_000
        facts.source = .phone(path: "Music/Mira/Long Way/03 Hold On.flac")
        facts.addedAtSeconds = 1_700_000_000
        facts.plays = 1_234
        facts.lastPlayedAt = 1_750_000_000_000
        facts.rating = 4
        facts.trackGain = -6.2
        facts.trackPeak = 0.98765
        facts.albumGain = 1.5
        let shown = lines(facts)
        #expect(shown["Album artist"] == "Various Artists")
        #expect(shown["Track"] == "3")
        #expect(shown["Disc"] == "2")
        #expect(shown["Length"] == "4:05")
        #expect(shown["Format"] == "FLAC, lossless")
        #expect(shown["File type"] == "audio/flac")
        #expect(shown["Bitrate"] == "1021 kbps")
        #expect(shown["Sample rate"] == "44.1 kHz")
        #expect(shown["Bit depth"] == "24-bit")
        #expect(shown["File size"] == "31.4 MB")
        #expect(shown["Source"] == "This phone")
        #expect(shown["Path"] == "Music/Mira/Long Way/03 Hold On.flac")
        #expect(shown["Added"] == "14 Nov 2023")
        #expect(shown["Plays"] == "1,234")
        #expect(shown["Last played"] == "15 Jun 2025")
        #expect(shown["Rating"] == "4 stars")
        #expect(shown["Track gain"] == "-6.20 dB")
        #expect(shown["Track peak"] == "0.988")
        #expect(shown["Album gain"] == "+1.50 dB")
        #expect(infoLines(facts, zone: utc, locale: us).filter(\.copyable).map(\.label) == ["Path"])
    }

    @Test func theTagsAndServerDetailsShowWhenKnown() {
        var facts = SongInfoFacts(title: "Get Lucky", artist: "Daft Punk", album: "RAM")
        facts.year = 2013
        facts.originalYear = 1979
        facts.genre = "Disco"
        facts.genres = ["Disco", "Funk"]
        facts.composer = "Thomas Bangalter"
        facts.bpm = 116
        facts.comment = "Single edit"
        facts.explicit = false
        facts.discNo = 2
        facts.discTitle = "Night Two"
        facts.mbRecordingId = "rec"
        facts.mbAlbumId = "rel"
        facts.mbReleaseGroupId = "grp"
        facts.mbArtistIds = ["a1", "a2"]
        let shown = lines(facts)
        #expect(shown["Original year"] == "1979")
        #expect(shown["Genres"] == "Disco, Funk")
        #expect(shown["Lyrics"] == "Clean")
        #expect(shown["Disc"] == "2 · Night Two")
        #expect(shown["Artist MBIDs"] == "a1\na2")
        #expect(infoLines(facts, zone: utc, locale: us).filter(\.copyable).map(\.label)
            == ["Recording MBID", "Release MBID", "Release group MBID", "Artist MBIDs"])
    }

    @Test func whatIsNotKnownIsLeftOut() {
        let facts = SongInfoFacts(title: "Untitled", artist: "", album: "")
        #expect(infoLines(facts, zone: utc, locale: us).map(\.label) == ["Title", "Source", "Plays"])
        #expect(lines(facts)["Source"] == "Found online")
    }

    @Test func aRadioSongSaysWhichSourceSuggestedItRightAfterWhereItIs() {
        var facts = SongInfoFacts(title: "Roads", artist: "Portishead", album: "Dummy")
        facts.suggestedBy = "Sounds alike"
        let keys = infoLines(facts, zone: utc, locale: us).map(\.label)
        #expect(keys.firstIndex(of: "Suggested by") == keys.firstIndex(of: "Source").map { $0 + 1 })
    }

    @Test func aServerSongNamesTheServer() {
        var facts = SongInfoFacts(title: "t", artist: "a", album: "b")
        facts.source = .server(name: "Octo", downloadedTo: "/data/octo/t.mp3")
        #expect(lines(facts)["Source"] == "Octo")
        #expect(lines(facts)["Downloaded to"] == "/data/octo/t.mp3")
        facts.source = .server(name: nil, downloadedTo: nil)
        #expect(lines(facts)["Source"] == "Your server")
    }

    @Test func theFormatComesFromTheFileType() {
        #expect(formatName("audio/mpeg") == "MP3")
        #expect(formatName("audio/mp4") == "AAC")
        #expect(formatName("audio/alac") == "ALAC, lossless")
        #expect(formatName("application/octet-stream") == nil)
        #expect(formatName(nil) == nil)
        #expect(bitrateText(320_000) == "320 kbps")
        #expect(sampleRateText(48_000) == "48 kHz")
        #expect(sizeText(850_000) == "850 KB")
        #expect(sizeText(2_340_000_000) == "2.34 GB")
    }
}
