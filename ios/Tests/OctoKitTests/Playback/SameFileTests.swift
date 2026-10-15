import Testing
@testable import OctoKit

/// Which phone song an opened file is, when the names match.
@Suite struct SameFileTests {
    @Test func theSameNameAndLengthIsTheSameSong() {
        let candidates = [
            NamedCandidate(id: 1, durationMs: 200_000, sizeBytes: 5_000),
            NamedCandidate(id: 2, durationMs: 180_900, sizeBytes: 4_000),
        ]
        #expect(pickSameFile(candidates, durationMs: 180_000, sizeBytes: nil) == 2)
        // Too far apart to be the same recording.
        #expect(pickSameFile(candidates, durationMs: 150_000, sizeBytes: nil) == nil)
    }

    @Test func theSameSizeSettlesATie() {
        let candidates = [
            NamedCandidate(id: 1, durationMs: 180_000, sizeBytes: 5_000),
            NamedCandidate(id: 2, durationMs: 180_000, sizeBytes: 4_000),
        ]
        #expect(pickSameFile(candidates, durationMs: 180_200, sizeBytes: 4_000) == 2)
        #expect(pickSameFile(candidates, durationMs: 180_200, sizeBytes: nil) == 1)
    }

    @Test func withNoLengthOnlyTheSameSizeCounts() {
        let candidates = [NamedCandidate(id: 3, durationMs: nil, sizeBytes: 9_000)]
        #expect(pickSameFile(candidates, durationMs: 100_000, sizeBytes: 9_000) == 3)
        #expect(pickSameFile(candidates, durationMs: 100_000, sizeBytes: 8_000) == nil)
        #expect(pickSameFile(candidates, durationMs: nil, sizeBytes: nil) == nil)
    }

    @Test func theEdgeOfTheLengthGapStillFits() {
        let candidates = [NamedCandidate(id: 4, durationMs: 181_500, sizeBytes: nil)]
        #expect(pickSameFile(candidates, durationMs: 180_000, sizeBytes: nil) == 4)
        #expect(pickSameFile(candidates, durationMs: 179_999, sizeBytes: nil) == nil)
    }

    @Test func phoneSongsAreFiledByName() {
        let fallback = FileTags()
        let files = [
            DeviceFile(id: 1, uri: "file:///a/Song.mp3", fileName: "Song.mp3", folder: "a/", modifiedAt: 0, sizeBytes: 4_000,
                       durationMs: 180_000, addedAtSeconds: 0, mimeType: nil, fallback: fallback),
            DeviceFile(id: 2, uri: "file:///b/Song.mp3", fileName: "Song.mp3", folder: "b/", modifiedAt: 0, sizeBytes: 0,
                       durationMs: 0, addedAtSeconds: 0, mimeType: nil, fallback: fallback),
            DeviceFile(id: 3, uri: "file:///b/Other.mp3", fileName: "Other.mp3", folder: "b/", modifiedAt: 0, sizeBytes: 1,
                       durationMs: 1, addedAtSeconds: 0, mimeType: nil, fallback: fallback),
        ]
        let named = namedCandidates(files)
        #expect(named["Song.mp3"] == [NamedCandidate(id: 1, durationMs: 180_000, sizeBytes: 4_000),
                                      NamedCandidate(id: 2, durationMs: nil, sizeBytes: nil)])
        #expect(named["Other.mp3"]?.count == 1)
        #expect(named["Missing.mp3"] == nil)
    }
}
