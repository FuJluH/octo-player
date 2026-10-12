import Foundation
import Testing
@testable import OctoKit

private let favorites = LibraryQuery([FilterPresets.favorites], sort: QuerySort(by: "Title"))

private func track(_ id: String, _ mime: String = "audio/mpeg", added: Int64 = 0) -> LibraryTrack {
    LibraryTrack(id: id, sourceId: "device", nativeId: id, title: "Song \(id)", searchKey: id, sortKey: id, artist: "Artist",
                 artistId: "ar", album: "Album \(id)", albumId: "al\(id)", durationMs: 200_000, addedAt: added, mimeType: mime)
}

/// Live lists kept per account as stored values, read back after a restart, and the songs each
/// picks, following likes and plays.
@Suite struct LiveListStoreTests {
    @Test func listsAreKeptAndChangedPerAccount() {
        var store = LiveListMemoryStore(account: "one")
        #expect(store.lists == [])
        let made = store.save(LiveList.new(name: " Favorites ", query: favorites, now: 0, id: "f"), now: 1_000)
        #expect(made.name == "Favorites")
        #expect(made.created == 1_000)
        let copy = store.duplicate(made, now: 2_000)
        store.rename("f", to: "Hearts", now: 2_000)
        #expect(store.lists.map(\.name) == ["Hearts", "Favorites (copy)"])
        #expect(store.byId("f")?.changed == 2_000)
        #expect(store.byId("f")?.created == 1_000)

        // A blank name or the same name changes nothing.
        let before = store.values
        store.rename("f", to: "  ", now: 3_000)
        store.rename("f", to: " Hearts ", now: 3_000)
        store.rename("nope", to: "Other", now: 3_000)
        #expect(store.values == before)

        // Another account starts with none, and the first keeps its own.
        store.account = "two"
        #expect(store.lists == [])
        store.save(LiveList.new(name: "Theirs", query: favorites, now: 0, id: "t"), now: 2_500)
        store.account = "one"
        #expect(store.lists.map(\.id) == ["f", copy.id])

        store.remove("f")
        #expect(store.lists.map(\.id) == [copy.id])
        #expect(store.byId("f") == nil)
        // Read again, as after a restart.
        #expect(LiveListMemoryStore(account: "one", values: store.values).lists.map(\.name) == ["Favorites (copy)"])

        // A server taken off the list takes its lists with it.
        store.forget("two")
        store.account = "two"
        #expect(store.lists == [])
    }

    @Test func eachAccountsListsSitUnderTheirOwnKey() {
        var store = LiveListMemoryStore(account: "one")
        store.save(LiveList(id: "a", name: "A"), now: 5)
        #expect(Array(store.values.keys) == ["lists:one"])
        #expect(LiveListStoring.key("phone") == "lists:phone")
        #expect(decodeLiveLists(store.values["lists:one"]).map(\.id) == ["a"])
    }

    @Test func theAccountIsTheSignedInServersOrThePhonesOwn() {
        #expect(LiveListStoring.phoneAccount == "phone")
        let a = LiveListStoring.account(sessionId: nil, username: "winters", address: "https://music.example/")
        #expect(a == LiveListStoring.account(sessionId: "", username: "winters", address: "https://music.example/"))
        #expect(a != LiveListStoring.account(sessionId: nil, username: "guest", address: "https://music.example/"))
        #expect(a == liveListAccountKey(username: "winters", address: "https://music.example/"))
        // A session with its own id keeps its lists under that id.
        #expect(LiveListStoring.account(sessionId: "s1", username: "winters", address: "https://music.example/") == "s1")
    }

    @Test func aListsSongsFollowLikesAndPlays() {
        let tracks = [track("1", "audio/flac"), track("2"), track("3", "audio/flac")]
        func pick(_ query: LibraryQuery, liked: Set<String>, played: [PlayedTrack] = []) -> [String] {
            query.select(tracks, now: queryTestNow, fields: LibraryTrackFields(liked: liked, listening: libraryListening(played))).map(\.id)
        }
        let lossless = LibraryQuery([FilterPresets.favorites, FilterPresets.lossless])
        #expect(pick(lossless, liked: ["1"]) == ["1"])
        #expect(pick(lossless, liked: ["1", "2", "3"]) == ["1", "3"])

        let playedOften = LibraryQuery([FilterPresets.playedAtLeast(5)])
        #expect(pick(playedOften, liked: []) == [])
        #expect(pick(playedOften, liked: [], played: [PlayedTrack(track: track("2"), plays: 7, lastPlayedAt: queryTestNow)]) == ["2"])

        // The editor's preview follows its rules as they change.
        #expect(pick(LibraryQuery([FilterPresets.lossless]), liked: []) == ["1", "3"])
        #expect(pick(LibraryQuery([FilterPresets.lossless], text: "Song 3"), liked: []) == ["3"])
    }

    @Test func theLibrarysSongsReadTheirKindLengthAndDates() {
        let fields = LibraryTrackFields(liked: ["1"], listening: ["1": .init(plays: 3, lastPlayedAt: 9_000)])
        var song = track("1", "audio/x-flac; rate=44100", added: 1_700_000_000)
        song.genre = "Jazz"
        song.year = 1959
        #expect(fields.format(song) == "flac")
        #expect(fields.lossless(song))
        #expect(fields.addedAt(song) == 1_700_000_000_000)
        #expect(fields.lastPlayedAt(song) == 9_000)
        #expect(fields.plays(song) == 3)
        #expect(fields.favorite(song))
        #expect(fields.seconds(song) == 200)
        #expect(fields.genres(song) == ["Jazz"])
        #expect(fields.addedAt(track("2")) == nil)
        #expect(fields.lastPlayedAt(track("2")) == nil)
        #expect(fields.plays(track("2")) == 0)
        #expect(fields.composer(song) == nil && fields.albumArtist(song) == nil && fields.bpm(song) == nil)
        // An m4a from the phone is AAC unless its MIME type says Apple Lossless.
        #expect(!fields.lossless(track("4", "audio/mp4")))
        #expect(fields.lossless(track("5", "audio/alac")))
        #expect(LibraryQuery([FilterPresets.decade(1950)]).select([song], now: 0, fields: fields).count == 1)
    }

    @Test func aFilesKindComesFromItsMimeType() {
        let kinds: [String?: String?] = [
            "audio/flac": "flac", "audio/mpeg": "mp3", "audio/MP3": "mp3", "audio/mp4": "m4a", "audio/x-m4a": "m4a",
            "audio/aac-adts": "aac", "audio/vnd.wave": "wav", "audio/x-aif": "aiff", "audio/x-wavpack": "wv", "audio/ogg": "ogg",
            "audio/": nil, "flac": nil, nil: nil,
        ]
        for (mime, kind) in kinds { #expect(LibraryTrackFields.formatOf(mime) == kind, "\(mime ?? "nil")") }
    }
}
