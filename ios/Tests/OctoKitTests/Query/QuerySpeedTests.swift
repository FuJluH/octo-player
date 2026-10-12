import Foundation
import Testing
@testable import OctoKit

/// A small seeded generator, so the library is the same on every run.
private struct SeededNumbers {
    private var state: UInt64

    init(_ seed: UInt64) { state = seed }

    mutating func next(_ below: Int64) -> Int64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Int64(z % UInt64(below))
    }
}

private func library(_ count: Int) -> [QueryTestSong] {
    var random = SeededNumbers(7)
    let genres = ["Rock", "Electronic", "Jazz", "Hip-Hop", "Classical", "Pop", "Ambient", "Folk"]
    return (0..<count).map { i in
        let album = i / 10
        let artist = album / 8
        return QueryTestSong(
            "s\(i)",
            "Song \(random.next(100_000)) of the \(i % 7 == 0 ? "Café" : "night")",
            album: "Album \(album)",
            albumId: "a\(album)",
            artist: "Artist \(artist)",
            year: 1960 + Int(random.next(66)),
            duration: 120 + Int(random.next(400)),
            suffix: i % 3 == 0 ? "flac" : "mp3",
            genre: genres[artist % genres.count],
            created: queryTestTime(queryTestNow - random.next(3_000 * 86_400_000)),
            played: i % 4 == 0 ? nil : queryTestTime(queryTestNow - random.next(900 * 86_400_000)),
            playCount: random.next(40),
            userRating: Int(random.next(6)),
            starred: i % 11 == 0 ? "2026-01-01T00:00:00Z" : nil
        )
    }
}

/// How long filtering a big library takes. The bound is loose on purpose, a guard against
/// something quadratic rather than a benchmark; the numbers are printed for the record.
@Suite struct QuerySpeedTests {
    @Test func tenThousandSongsFilterQuickly() {
        let songs = library(10_000)
        let fields = QueryTestFields()
        let queries: [(String, LibraryQuery)] = [
            ("words", LibraryQuery(text: "cafe artist 12")),
            ("genre and rating", LibraryQuery([FilterPresets.genre("Electronic"), FilterPresets.ratingAtLeast(4)])),
            ("added this year", LibraryQuery([FilterPresets.addedThisYear])),
            ("not played lately, lossless", LibraryQuery([FilterPresets.notPlayedLately, FilterPresets.lossless], text: "night")),
            ("most played", LibraryQuery(sort: QuerySort(.mostPlayed, descending: true), limit: 50)),
            ("by artist", LibraryQuery(sort: QuerySort(.artist, descending: false))),
        ]
        for (name, query) in queries {
            var found = 0
            var best = Duration.seconds(1_000)
            // The best of three, so a busy machine skews it less.
            for _ in 0..<3 {
                let clock = ContinuousClock()
                let took = clock.measure { found = query.select(songs, now: queryTestNow, fields: fields).count }
                best = min(best, took)
            }
            let ms = best.components.seconds * 1_000 + best.components.attoseconds / 1_000_000_000_000_000
            print("Filter over 10k songs, \(name): \(ms) ms, \(found) found")
            #expect(ms < 2_000, "\(name) took \(ms) ms")
            #expect(found > 0, "\(name) found nothing")
        }
    }
}
