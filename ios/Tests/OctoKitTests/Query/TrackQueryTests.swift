import Foundation
import Testing
@testable import OctoKit

@Suite struct TrackQueryTests {
    private let now: Int64 = 1_790_000_000_000
    private let day: Int64 = 86_400_000

    private func track(_ id: String, _ title: String, artist: String = "", genre: String = "", year: Int? = nil,
                       addedDaysAgo: Int64 = 1_000, mime: String? = "audio/mpeg", rating: Int = 0) -> LibraryTrack {
        LibraryTrack(id: id, sourceId: "device", nativeId: id, title: title, searchKey: title.lowercased(), sortKey: title.lowercased(),
                     artist: artist, artistId: "", album: "", albumId: "", year: year, durationMs: 200_000,
                     addedAt: (now - addedDaysAgo * day) / 1_000, mimeType: mime, genre: genre, rating: rating)
    }

    private var tracks: [LibraryTrack] {
        [track("1", "Airbag", artist: "Radiohead", genre: "Alternative", year: 1997, addedDaysAgo: 3, mime: "audio/flac", rating: 5),
         track("2", "Halo", artist: "Beyoncé", genre: "Pop", year: 2008, addedDaysAgo: 40),
         track("3", "Teardrop", artist: "Massive Attack", genre: "Electronic", year: 1998, mime: "audio/x-flac", rating: 3),
         track("4", "Untitled", mime: nil)]
    }

    /// Liked "3"; "1" played yesterday, "3" a year ago, "2" and "4" never.
    private var fields: LibraryTrackFields {
        LibraryTrackFields(liked: ["3"], listening: ["1": .init(plays: 4, lastPlayedAt: now - day),
                                                     "3": .init(plays: 1, lastPlayedAt: now - 365 * day)])
    }

    private func ids(_ query: LibraryQuery) -> [String] {
        filteredSongs(Sorted(items: tracks, order: SortList.songs.defaultOrder, headings: nil), query, fields: fields, now: now)
            .items.map(\.id)
    }

    @Test func thePhonesSongsAnswerTheSharedFilters() {
        #expect(ids(LibraryQuery([FilterPresets.addedThisWeek])) == ["1"])
        #expect(ids(LibraryQuery([FilterPresets.addedThisYear])) == ["1", "2"])
        #expect(ids(LibraryQuery([FilterPresets.neverPlayed])) == ["2", "4"])
        #expect(ids(LibraryQuery([FilterPresets.notPlayedLately])) == ["2", "3", "4"])
        #expect(ids(LibraryQuery([FilterPresets.favorites])) == ["3"])
        #expect(ids(LibraryQuery([FilterPresets.lossless])) == ["1", "3"])
        #expect(ids(LibraryQuery([FilterPresets.ratingAtLeast(3)])) == ["1", "3"])
        #expect(ids(LibraryQuery([FilterPresets.genre("electronic")])) == ["3"])
        #expect(ids(LibraryQuery([FilterPresets.decade(1990)])) == ["1", "3"])
        #expect(ids(LibraryQuery([QueryRule(.plays, .atLeast, number: 2)])) == ["1"])
        #expect(ids(LibraryQuery(text: "beyonce")) == ["2"])
        #expect(ids(LibraryQuery([FilterPresets.lossless], text: "attack")) == ["3"])
    }

    @Test func whatThePhoneDoesNotKeepMatchesNothing() {
        #expect(ids(LibraryQuery([QueryRule(.composer, .contains, text: "a")])) == [])
        #expect(ids(LibraryQuery([QueryRule(.bpm, .atLeast, number: 1)])) == [])
    }

    @Test func theHeadingsStayInStepWithTheSongsLeft() {
        let all = Sorted(items: tracks, order: SortList.songs.defaultOrder, headings: ["A", "H", "T", "U"])
        let shown = filteredSongs(all, LibraryQuery([FilterPresets.lossless]), fields: fields, now: now)
        #expect(shown.items.map(\.id) == ["1", "3"])
        #expect(shown.headings == ["A", "T"])
        #expect(shown.order == all.order)
    }

    @Test func noFiltersHandsBackTheSameList() {
        let all = Sorted(items: tracks, order: SortList.songs.defaultOrder, headings: nil)
        let shown = filteredSongs(all, LibraryQuery(text: "  "), fields: fields, now: now)
        #expect(shown.items.map(\.id) == all.items.map(\.id))
        #expect(shown.headings == nil)
    }

    @Test func theKindOfFileFromItsMimeType() {
        #expect(LibraryTrackFields.formatOf("audio/flac") == "flac")
        #expect(LibraryTrackFields.formatOf("audio/x-flac") == "flac")
        #expect(LibraryTrackFields.formatOf("audio/mpeg") == "mp3")
        #expect(LibraryTrackFields.formatOf("audio/mp4") == "m4a")
        #expect(LibraryTrackFields.formatOf("audio/x-wav") == "wav")
        #expect(LibraryTrackFields.formatOf("audio/ogg; codecs=opus") == "ogg")
        #expect(LibraryTrackFields.formatOf(nil) == nil)
        #expect(LibraryTrackFields.formatOf("nonsense") == nil)
        #expect(fields.lossless(track("x", "x", mime: "audio/wav")))
        #expect(!fields.lossless(track("x", "x", mime: "audio/mp4")))
    }

    @Test func theChoicesComeFromTheSongs() {
        #expect(genresIn(tracks, fields: LibraryTrackFields()) == ["Alternative", "Electronic", "Pop"])
        #expect(decadesIn(tracks, fields: LibraryTrackFields()) == [1990, 2000])
    }
}
