import Foundation
import Testing
@testable import OctoKit

@Suite struct ServerPlaysTest {
    func local(_ id: String, _ plays: Int, _ at: Int64) -> PlayedTrack {
        PlayedTrack(track: listeningTrack(id), plays: plays, lastPlayedAt: at)
    }

    func server(_ id: String, _ plays: Int, _ at: Int64?, serverId: String? = nil) -> ServerPlayedTrack {
        ServerPlayedTrack(track: listeningTrack(id), serverId: serverId ?? "s\(id)", serverPlays: plays, serverLastPlayedAt: at)
    }

    func of(_ list: [PlayedTrack], _ id: String) throws -> PlayedTrack {
        let found = list.filter { $0.track.id == id }
        try #require(found.count == 1)
        return found[0]
    }

    @Test func countsAddUpAndTheLaterPlayWins() throws {
        let combined = withServerPlays([local("a", 3, 500)], [server("a", 4, 900)], [:])
        #expect(try of(combined, "a").plays == 7)
        #expect(try of(combined, "a").lastPlayedAt == 900)
    }

    @Test func aLaterPlayOnThePhoneWins() throws {
        let combined = withServerPlays([local("a", 1, 2_000)], [server("a", 1, 900)], [:])
        #expect(try of(combined, "a").lastPlayedAt == 2_000)
    }

    @Test func songsPlayedOnlyOnTheServerJoin() throws {
        let combined = withServerPlays([local("a", 1, 100)], [server("b", 5, 300)], [:])
        #expect(combined.map(\.track.id) == ["a", "b"])
        #expect(try of(combined, "b").plays == 5)
    }

    @Test func songsPlayedOnlyOnThePhoneStayAsTheyAre() {
        let combined = withServerPlays([local("a", 2, 100)], [], [:])
        #expect(combined == [local("a", 2, 100)])
    }

    @Test func octosOwnPlaysAreNotCountedTwice() throws {
        // Played twice on the phone and sent both; the server counts those two and three from
        // elsewhere.
        let sent = [String: SentPlays]().plusSent("sa", 1_000).plusSent("sa", 2_000)
        let combined = withServerPlays([local("a", 2, 2_000)], [server("a", 5, 2_000)], sent)
        #expect(try of(combined, "a").plays == 5)
    }

    @Test func aPlaySentAfterTheServerWasReadIsNotTakenOff() throws {
        // The server's record was read before the play at 3000 reached it.
        let sent = [String: SentPlays]().plusSent("sa", 1_000).plusSent("sa", 3_000)
        let combined = withServerPlays([local("a", 2, 3_000)], [server("a", 4, 1_000)], sent)
        // Two here, and three of the server's four are from elsewhere.
        #expect(try of(combined, "a").plays == 5)
    }

    @Test func serverTimesInWholeSecondsStillMatch() throws {
        let sent = [String: SentPlays]().plusSent("sa", 1_000_450)
        let combined = withServerPlays([local("a", 1, 1_000_450)], [server("a", 1, 1_000_000)], sent)
        #expect(try of(combined, "a").plays == 1)
    }

    @Test func aServerThatIgnoredOctosPlaysLosesNothing() throws {
        // Sent, but the server never counted it, so its last play stayed older.
        let sent = [String: SentPlays]().plusSent("sa", 5_000)
        let combined = withServerPlays([local("a", 1, 5_000)], [server("a", 3, 1_000)], sent)
        #expect(try of(combined, "a").plays == 4)
    }

    @Test func theServersCountNeverGoesBelowZero() throws {
        let sent = ["sa": SentPlays(folded: 9)]
        let combined = withServerPlays([local("a", 2, 100)], [server("a", 3, 100)], sent)
        #expect(try of(combined, "a").plays == 2)
    }

    @Test func aSongWhosePlaysAreAllOctosOwnAndGoneLocallyDropsOut() {
        let sent = ["sb": SentPlays(folded: 2)]
        let combined = withServerPlays([], [server("b", 2, 100)], sent)
        #expect(combined.isEmpty)
    }

    @Test func twoServerCopiesOfOneSongBothCount() throws {
        let combined = withServerPlays(
            [local("a", 1, 100)],
            [server("a", 2, 300, serverId: "sa1"), server("a", 3, 200, serverId: "sa2")],
            [:]
        )
        #expect(try of(combined, "a").plays == 6)
        #expect(try of(combined, "a").lastPlayedAt == 300)
    }

    @Test func aServerPlayWithoutATimeStillCounts() throws {
        let combined = withServerPlays([], [server("a", 2, nil)], [:])
        #expect(try of(combined, "a").plays == 2)
        #expect(try of(combined, "a").lastPlayedAt == 0)
    }

    @Test func foldingKeepsTheSameCountAndForgetsGoneSongs() {
        let sent = [String: SentPlays]()
            .plusSent("sa", 1_000).plusSent("sa", 3_000)
            .plusSent("gone", 1_000)
        let folded = sent.foldedInto(["sa": 2_000])
        #expect(folded == ["sa": SentPlays(folded: 1, recent: [3_000])])
        #expect(folded["sa"].heldBy(2_000) == sent["sa"].heldBy(2_000))
        // Once the server has the newer play too, it is counted as held.
        #expect(folded["sa"].heldBy(3_000) == 2)
    }

    @Test func aSongWithNoServerPlayTimeFoldsNothing() {
        let sent = [String: SentPlays]().plusSent("sa", 1_000)
        let lastPlayed: [String: Int64?] = ["sa": nil]
        #expect(sent.foldedInto(lastPlayed)["sa"] == SentPlays(folded: 0, recent: [1_000]))
    }

    @Test func sentPlaysRoundTrip() {
        let sent = [
            "sa": SentPlays(folded: 3, recent: [1_000, 2_000]),
            "sb": SentPlays(folded: 0, recent: [5]),
            "odd id with spaces": SentPlays(folded: 7, recent: []),
        ]
        #expect(decodeSent(encodeSent(sent)) == sent)
    }

    @Test func brokenSentLinesAreSkipped() {
        #expect(decodeSent(["", "x 1 sa", "2 1"]) == [:])
    }

    @Test func albumsTakeTheLaterLastPlay() {
        let combined = withServerAlbumPlays(
            [PlayedAlbum(album: listeningAlbum("x"), lastPlayedAt: 500), PlayedAlbum(album: listeningAlbum("y"), lastPlayedAt: 100)],
            [PlayedAlbum(album: listeningAlbum("x"), lastPlayedAt: 900), PlayedAlbum(album: listeningAlbum("z"), lastPlayedAt: 300)]
        )
        #expect(Dictionary(uniqueKeysWithValues: combined.map { ($0.album.id, $0.lastPlayedAt) }) == ["x": 900, "y": 100, "z": 300])
    }
}
