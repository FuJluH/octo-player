import Foundation
import Testing
@testable import OctoKit

/// Library health's fixes, planned from the songs and run through a stand-in for the server.
@Suite struct HealthFixesTests {
    private func song(_ id: String, _ title: String = "Teardrop", artist: String = "Massive Attack", album: String? = "Mezzanine",
                      albumId: String? = nil, suffix: String = "flac", bitDepth: Int? = 16, bitRate: Int? = 900, year: Int? = nil,
                      genre: String? = nil, track: Int? = nil, albumArtist: String? = nil, isrc: [String] = [],
                      seconds: Int = 330) -> ServerSong {
        ServerSong(id: id, title: title, album: album, albumId: albumId ?? "al-\(album ?? "")", artist: artist, track: track, year: year,
                   duration: seconds, coverArt: "mf-\(id)", suffix: suffix, bitRate: bitRate, samplingRate: 44_100, bitDepth: bitDepth,
                   displayAlbumArtist: albumArtist, genre: genre, albumArtists: albumArtist.map { [ArtistRef(name: $0)] } ?? [],
                   isrc: isrc)
    }

    private func group(_ songs: ServerSong...) throws -> DuplicateGroup<ServerSong> {
        let found = findDuplicates(songs, serverSongHealth)
        #expect(found.count == 1)
        return try #require(found.first)
    }

    private func fillMap(_ fills: [TagChange]) -> [String: String] {
        Dictionary(fills.map { ($0.tag, $0.value) }, uniquingKeysWith: { a, _ in a })
    }

    // MARK: Copies

    @Test func theBestCopyIsKeptTheOthersGoAndItsBlankTagsAreFilledFromThem() throws {
        let flac = song("flac")
        let mp3 = song("mp3", suffix: "mp3", bitDepth: nil, bitRate: 320, year: 1998, genre: "Trip Hop", track: 3,
                       albumArtist: "Massive Attack", isrc: ["GBAAA9800003"])
        let fix = duplicateFix(try group(mp3, flac), serverSongHealth)
        #expect(fix.keep.id == "flac")
        #expect(fix.remove.map(\.id) == ["mp3"])
        #expect(fix.why == "Keeps the FLAC, 16-bit, 44.1 kHz copy, because it sounds best.")
        #expect(fillMap(fix.fills) == [SongTag.albumArtist: "Massive Attack", SongTag.track: "3", SongTag.year: "1998",
                                       SongTag.genre: "Trip Hop", SongTag.isrc: "GBAAA9800003"])
        #expect(fix.fills.allSatisfy { $0.from == "mp3" && $0.now == nil })
        #expect(fix.note == nil)
        let steps = fix.steps(serverSongHealth)
        // The tags first, while the copy they come from is still there.
        if case .retag(let id, _, _) = steps[0] { #expect(id == "flac") } else { Issue.record("first step is not a retag") }
        #expect(steps[1] == .remove(id: "mp3", title: "Teardrop", copy: true))
        // Only that copy is unwanted, so the server is told.
        #expect(steps[1].with.map { "\($0.0)=\($0.1)" } == ["copy=true"])
        #expect(FixStep.remove(id: "mp3", title: "Teardrop").with.isEmpty)
    }

    @Test func aTrackNumberIsNotTakenFromACopyOnAnotherAlbumButTheGenreIs() throws {
        let keep = song("keep")
        let single = song("single", album: "Teardrop (Single)", suffix: "mp3", bitDepth: nil, bitRate: 320, year: 1998, genre: "Trip Hop",
                          track: 1)
        let fix = duplicateFix(try group(single, keep), serverSongHealth)
        #expect(fillMap(fix.fills) == [SongTag.genre: "Trip Hop"])
        #expect(fix.note == "Teardrop (MP3, 320 kbps) is on Teardrop (Single), so that album will no longer have this song.")
    }

    @Test func aCopyWithNoAlbumTakesAWholeAlbumFromOneCopy() throws {
        let loose = song("loose", album: nil, albumId: "")
        let tagged = song("tagged", suffix: "mp3", bitDepth: nil, bitRate: 320, track: 3, albumArtist: "Massive Attack")
        let fix = duplicateFix(try group(tagged, loose), serverSongHealth)
        #expect(fix.keep.id == "loose")
        #expect(fillMap(fix.fills) == [SongTag.album: "Mezzanine", SongTag.albumArtist: "Massive Attack", SongTag.track: "3"])
    }

    @Test func aPersonCanKeepAnotherCopyAndTagsTheCopiesSayDifferentlyAreForThemToPick() throws {
        let flac = song("flac", year: 1998)
        let mp3 = song("mp3", suffix: "mp3", bitDepth: nil, bitRate: 320, year: 1997)
        let fix = duplicateFix(try group(mp3, flac), serverSongHealth, keep: mp3)
        #expect(fix.keep.id == "mp3")
        #expect(fix.remove.map(\.id) == ["flac"])
        #expect(fix.why == "You picked this copy (MP3, 320 kbps) to keep.")
        #expect(fix.differs.count == 1)
        #expect(fix.differs.first?.tag == SongTag.year)
        #expect(fix.differs.first?.value(of: "mp3") == "1997")
        #expect(fix.differs.first?.value(of: "flac") == "1998")
        #expect(fix.fills.isEmpty)
    }

    // MARK: Albums

    @Test func aSplitAlbumMovesTheSmallerPartsOntoTheLargest() throws {
        let songs = [
            song("a1", "Angel", album: "Mezzanine", albumId: "big", year: 1998, albumArtist: "Massive Attack"),
            song("a2", "Risingson", album: "Mezzanine", albumId: "big", year: 1998, albumArtist: "Massive Attack"),
            song("b1", "Teardrop", album: "Mezzanine ", albumId: "small", year: 1998, albumArtist: "Massive Attack"),
        ]
        let split = try #require(findSplitAlbums(songs, serverSongHealth).first)
        let join = albumJoin(split)
        #expect(join.moving.map(\.id) == ["b1"])
        #expect(join.steps(serverSongHealth) == [.joinAlbum(id: "b1", title: "Teardrop", like: join.lead.id)])
        #expect(join.lead.id == "a1" || join.lead.id == "a2")
        #expect(join.words == "Moves 1 song onto Mezzanine, the part with 2 songs.")
    }

    // MARK: Missing tags

    @Test func aYearTheRestOfTheAlbumAgreesOnIsFilledInButNotWhenItDisagrees() {
        let all = [
            song("a1", "One", year: 1998), song("a2", "Two", year: 1998), song("a3", "Three", year: nil),
            song("b1", "Four", album: "Other", year: 2001), song("b2", "Five", album: "Other", year: 2003),
            song("b3", "Six", album: "Other", year: nil),
        ]
        let missing = all.filter { $0.year == nil }
        let fills = fillsFromAlbum(missing, all: all, tag: .year, serverSongHealth)
        #expect(fills.map { "\($0.0.id)=\($0.1.value)" } == ["a3=1998"])
    }

    @Test func anAlbumArtistComesFromTheArtistWhenEverySongIsByOne() {
        let all = [song("a1", "One"), song("a2", "Two")]
        let fills = fillsFromAlbum(all, all: all, tag: .albumArtist, serverSongHealth)
        #expect(fills.map(\.1.value) == ["Massive Attack", "Massive Attack"])
        #expect(fills.first?.1.tag == SongTag.albumArtist)
    }

    // MARK: Lookups

    @Test func aLookupPicksBlanksAndOverwritesOnlyWhenSureNeverTheSongsName() {
        var lookup = SongLookup(
            state: "found",
            current: ["title": "teardrop", "year": nil, "genre": "Electronic", "track": "3"],
            suggested: ["title": "Teardrop", "year": "1998", "genre": "Trip Hop", "track": "3"],
            confidence: "Strong", source: "Fingerprint")
        let picked = Dictionary(lookup.changes().map { ($0.0.tag, $0.1) }, uniquingKeysWith: { a, _ in a })
        #expect(picked == ["title": false, "year": true, "genre": true])
        lookup.confidence = "Low"
        let doubtful = Dictionary(lookup.changes().map { ($0.0.tag, $0.1) }, uniquingKeysWith: { a, _ in a })
        #expect(doubtful == ["title": false, "year": true, "genre": false])
        lookup.confidence = "Strong"
        #expect(lookup.origin == "A sure match from the song's fingerprint.")
    }

    // MARK: Running

    @Test @MainActor func aRunSaysWhatWasDoneWhatWasNotAndHowToPutItBack() async {
        let steps: [FixStep] = [
            .retag(id: "flac", title: "Teardrop", tags: ["year": "1998"]),
            .remove(id: "mp3", title: "Teardrop"),
            .remove(id: "ogg", title: "Teardrop"),
            .addCover(id: "c", title: "Angel"),
        ]
        var seen: [(Int, Int)] = []
        let outcome = await runFix(steps, send: { step in
            switch step.id {
            case "ogg": FileActionResult(id: step.id, action: step.action, state: "failed",
                                         detail: "Could not work out which file this is, so nothing was touched.")
            case "c": FileActionResult(id: step.id, action: step.action, state: "skipped",
                                       detail: "The song has a picture of its own already, so it was left alone.")
            default: FileActionResult(id: step.id, action: step.action, state: "applied")
            }
        }, progress: { done, total in seen.append((done, total)) })
        #expect(outcome.removed == ["mp3"])
        #expect(outcome.undo == [.restore(id: "mp3", title: "Teardrop"), .undo(id: "flac", title: "Teardrop")])
        #expect(outcome.unchanged.map(\.id) == ["c"])
        #expect(outcome.summary()
            == "Removed 1 song, changed the tags of 1 song. Teardrop: Could not work out which file this is, so nothing was touched.")
        #expect(seen.first.map { "\($0.0)/\($0.1)" } == "0/4")
        #expect(seen.last.map { "\($0.0)/\($0.1)" } == "4/4")
    }

    @Test @MainActor func aRehearsalSaysNothingChangedAndAStopEndsBetweenSteps() async {
        let rehearsed = await runFix([.remove(id: "a", title: "A")], send: {
            FileActionResult(id: $0.id, action: $0.action, state: "rehearsed")
        })
        #expect(rehearsed.rehearsed)
        #expect(rehearsed.done.isEmpty)
        #expect(rehearsed.summary().contains("dry run"))

        var asked = 0
        let stopped = await runFix([.remove(id: "a", title: "A"), .remove(id: "b", title: "B")], send: {
            asked += 1
            return FileActionResult(id: $0.id, action: $0.action, state: "applied")
        }, stop: { asked >= 1 })
        #expect(asked == 1)
        #expect(stopped.stopped)
        #expect(!stopped.summary().isEmpty)
    }

    @Test @MainActor func puttingBackAReplacedCopySaysTheServersWordsAndUndoSwapsAgain() async {
        let replaced = TrashedSong(id: "nd-1", title: "Holocene", kind: "replaced", was: "FLAC 16-bit 44.1 kHz", now: "MP3 320")
        #expect(replaced.replaced)
        #expect(!TrashedSong(id: "x", title: "X").replaced)
        #expect(replacedText(was: replaced.was, now: replaced.now) == "Replaced: was FLAC 16-bit 44.1 kHz, now MP3 320")
        #expect(replacedText(was: nil, now: " ") == "Replaced by another copy")
        let step = replaced.restoreStep
        #expect(step == .restore(id: "nd-1", title: "Holocene", replaced: true))
        #expect(step.undoStep == step)

        var sent: [String] = []
        let back = await runFix([step], send: {
            sent.append("\($0.action):\($0.id)")
            return FileActionResult(id: $0.id, action: $0.action, state: "applied",
                                    detail: "Put back your old copy. The one that replaced it is in Recently removed.")
        })
        #expect(sent == ["restore:nd-1"])
        #expect(back.summary() == "Put back your old copy. The one that replaced it is in Recently removed.")

        let notKept = await runFix([step], send: {
            FileActionResult(id: $0.id, action: $0.action, state: "skipped",
                             detail: "Your old copy was not kept on this server, so there is nothing to put back.")
        })
        #expect(notKept.summary() == "Your old copy was not kept on this server, so there is nothing to put back.")

        // A plain removed song still reads as before.
        let plain = await runFix([.restore(id: "x", title: "X")], send: {
            FileActionResult(id: $0.id, action: $0.action, state: "applied", detail: "Put back.")
        })
        #expect(plain.summary() == "Put back 1 song.")
    }

    @Test func theFixWordsHaveNoDashes() throws {
        let set = try group(song("a"), song("b", suffix: "mp3", bitDepth: nil, bitRate: 128))
        let words = [
            keepWhy(set, song("a"), serverSongHealth),
            TagChange(SongTag.year, now: "1997", value: "1998").words,
            SongLookup(confidence: "Medium", source: "Database", release: "'Mezzanine' 1998").origin,
        ] + SongTag.all.map(fixTagName)
        for line in words { #expect(!line.contains("\u{2014}") && !line.contains("\u{2013}") && !line.contains(" - "), "\(line)") }
    }

    @Test func deletingSaysWhereTheFileGoesAndForHowLong() {
        #expect(deleteTitle(1) == "Delete this song from disk?")
        #expect(deleteTitle(3) == "Delete 3 songs from disk?")
        let body = deleteBody("Teardrop", keepDays: 30)
        #expect(body.contains("for 30 days"))
        #expect(deleteBody("Teardrop", keepDays: 0).contains("until someone clears it"))
        let day: Int64 = 86_400_000
        #expect(goneText(goneAtMillis: 13 * day - 1, nowMillis: 0) == "Deleted for good in 12 days")
        #expect(goneText(goneAtMillis: day + 5, nowMillis: 0) == "Deleted for good tomorrow")
        #expect(goneText(goneAtMillis: nil, nowMillis: 0) == "Kept until someone clears the trash")
        let lines = [body, deletedLine(2, title: nil)] + HealthCheck.allCases.flatMap { [$0.fixAllLabel(2), $0.fixMeaning] }
        for line in lines { #expect(!line.contains("\u{2014}") && !line.contains("\u{2013}") && !line.contains(" - "), "\(line)") }
    }
}
