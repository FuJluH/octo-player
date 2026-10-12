import Foundation
import Testing
@testable import OctoKit

@Suite struct SortQueriesTests {
    private let scopes: [SongScope] = [.all, .genre("Rock"), .liked]

    private let songKeys: Set<String> = [
        "t.sortKey", "COALESCE(ar.sortKey, LOWER(t.artist))", "COALESCE(al.sortKey, LOWER(t.album))",
        "t.id", "t.albumId", "t.albumOrder", "t.addedAt", "t.year IS NULL", "t.year", "t.durationMs",
        "t.rating = 0", "t.rating", "EXISTS(SELECT 1 FROM liked_track lk WHERE lk.trackId = t.id)",
        "(SELECT lk.likedAt FROM liked_track lk WHERE lk.trackId = t.id) IS NULL",
        "(SELECT lk.likedAt FROM liked_track lk WHERE lk.trackId = t.id)",
    ]
    private let albumKeys: Set<String> = [
        "a.sortKey", "COALESCE(ar.sortKey, LOWER(a.artist))", "a.id", "a.year IS NULL", "a.year", "a.addedAt", "a.songCount", "a.durationMs",
    ]
    private let artistKeys: Set<String> = [
        "r.sortKey", "r.id", "r.songCount", "r.albumCount", "(SELECT MAX(t.addedAt) FROM track t WHERE t.artistId = r.id)",
    ]

    /// The ORDER BY's keys, split at the commas outside brackets.
    private func keysOf(_ sql: String) -> [String] {
        let order = orderOf(sql)
        var keys: [String] = []
        var depth = 0
        var current = ""
        for char in order {
            switch char {
            case "(": depth += 1
            case ")": depth -= 1
            default: break
            }
            if char == ",", depth == 0 {
                keys.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(char)
            }
        }
        keys.append(current.trimmingCharacters(in: .whitespaces))
        return keys.map { $0.hasSuffix(" DESC") ? String($0.dropLast(5)) : $0 }
    }

    private func orderOf(_ sql: String) -> String {
        guard let range = sql.range(of: " ORDER BY ") else { return sql }
        return String(sql[range.upperBound...])
    }

    @Test func songOrdersUseOnlyKnownPieces() {
        for sort in SongSort.allCases {
            for scope in scopes {
                for descending in [false, true] {
                    let keys = keysOf(songQuery(sort, descending: descending, scope: scope).sql)
                    #expect(keys.allSatisfy(songKeys.contains), "\(sort) \(scope): \(keys)")
                    #expect(keys.last == "t.id")
                }
            }
        }
    }

    @Test func albumAndArtistOrdersUseOnlyKnownPieces() {
        for sort in AlbumSort.allCases {
            for descending in [false, true] {
                for artistId in [nil, "device:artist:x"] {
                    let keys = keysOf(albumQuery(sort, descending: descending, artistId: artistId).sql)
                    #expect(keys.allSatisfy(albumKeys.contains), "\(sort): \(keys)")
                    #expect(keys.last == "a.id")
                }
            }
        }
        for sort in ArtistSort.allCases {
            for descending in [false, true] {
                let keys = keysOf(artistQuery(sort, descending: descending).sql)
                #expect(keys.allSatisfy(artistKeys.contains), "\(sort): \(keys)")
                #expect(keys.last == "r.id")
            }
        }
    }

    @Test func namesAreBoundNeverWrittenIn() {
        let name = "Rock'; DROP TABLE track; --"
        let query = songQuery(.title, descending: false, scope: .genre(name))
        #expect(!query.sql.contains("DROP"))
        #expect(query.sql.contains("WHERE t.genre = ? COLLATE NOCASE"))
        #expect(query.args == [name])

        let artist = "device:artist:it's"
        let albums = albumQuery(.year, descending: true, artistId: artist)
        #expect(!albums.sql.contains("it's"))
        #expect(albums.sql.contains("WHERE a.artistId = ?"))
        #expect(albums.args == [artist])

        #expect(songQuery(.title, descending: false, scope: .all).args.isEmpty)
        #expect(albumQuery(.title, descending: false).args.isEmpty)
    }

    @Test func onlyTheChosenKeyFlips() {
        #expect(orderOf(songQuery(.recentlyAdded, descending: true, scope: .all).sql) == "t.addedAt DESC, t.albumId, t.albumOrder, t.sortKey, t.id")
        #expect(orderOf(songQuery(.recentlyAdded, descending: false, scope: .all).sql) == "t.addedAt, t.albumId, t.albumOrder, t.sortKey, t.id")
    }

    @Test func artistOrderGoesAlbumThenAlbumOrderThenTitle() {
        #expect(orderOf(songQuery(.artist, descending: true, scope: .all).sql)
            == "COALESCE(ar.sortKey, LOWER(t.artist)) DESC, COALESCE(al.sortKey, LOWER(t.album)), t.albumId, t.albumOrder, t.sortKey, t.id")
        #expect(orderOf(songQuery(.album, descending: false, scope: .all).sql)
            == "COALESCE(al.sortKey, LOWER(t.album)), COALESCE(ar.sortKey, LOWER(t.artist)), t.albumId, t.albumOrder, t.sortKey, t.id")
    }

    @Test func missingYearsAndRatingsGoLastEitherWay() {
        for descending in [false, true] {
            #expect(orderOf(songQuery(.year, descending: descending, scope: .all).sql).hasPrefix("t.year IS NULL, t.year"))
            #expect(orderOf(songQuery(.rating, descending: descending, scope: .all).sql).hasPrefix("t.rating = 0, t.rating"))
            #expect(orderOf(albumQuery(.year, descending: descending).sql).hasPrefix("a.year IS NULL, a.year"))
        }
        #expect(orderOf(songQuery(.rating, descending: false, scope: .all).sql)
            .contains("EXISTS(SELECT 1 FROM liked_track lk WHERE lk.trackId = t.id) DESC"))
    }

    @Test func playOrdersStartFromNameOrder() {
        let byTitle = orderOf(songQuery(.title, descending: false, scope: .all).sql)
        #expect(orderOf(songQuery(.mostPlayed, descending: false, scope: .all).sql) == byTitle)
        #expect(orderOf(songQuery(.recentlyPlayed, descending: false, scope: .all).sql) == byTitle)
    }

    @Test func headingsOnlyForNameOrders() {
        #expect(songQuery(.title, descending: false, scope: .all).sql.hasPrefix("SELECT t.*, t.sortKey AS heading"))
        #expect(songQuery(.length, descending: false, scope: .all).sql.hasPrefix("SELECT t.*, NULL AS heading"))
        #expect(artistQuery(.name, descending: false).sql.hasPrefix("SELECT r.*, r.sortKey AS heading"))
        #expect(albumQuery(.songCount, descending: false).sql.hasPrefix("SELECT a.*, NULL AS heading"))
    }

    @Test func onlyQueriesThatReadLikesWatchThem() {
        #expect(!songQuery(.title, descending: false, scope: .all).readsLikes)
        #expect(!songQuery(.recentlyAdded, descending: true, scope: .genre("Pop")).readsLikes)
        #expect(songQuery(.title, descending: false, scope: .liked).readsLikes)
        #expect(songQuery(.rating, descending: true, scope: .all).readsLikes)
        #expect(songQuery(.liked, descending: true, scope: .all).readsLikes)
        #expect(songQuery(.dateLiked, descending: true, scope: .liked).readsLikes)
    }

    @Test func likedScopeJoinsTheLikes() {
        let sql = songQuery(.dateLiked, descending: true, scope: .liked).sql
        #expect(sql.contains("FROM liked_track l JOIN track t ON t.id = l.trackId"))
        #expect(orderOf(sql).hasPrefix(
            "(SELECT lk.likedAt FROM liked_track lk WHERE lk.trackId = t.id) IS NULL, "
                + "(SELECT lk.likedAt FROM liked_track lk WHERE lk.trackId = t.id) DESC"))
    }
}
