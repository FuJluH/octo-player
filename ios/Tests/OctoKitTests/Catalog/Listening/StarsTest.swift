import Foundation
import Testing
@testable import OctoKit

@Suite struct StarsTest {
    /// Library songs a, b, c, d, each with one server copy: "sa" and so on.
    let copies = ["a", "b", "c", "d"].map { ServerCopy(trackId: $0, serverId: "s\($0)") }

    func plan(liked: Set<String>, starred: Set<String>, synced: Set<String>, from: [ServerCopy]? = nil) -> StarPlan {
        reconcileStars(from ?? copies, liked: liked, starred: starred, synced: synced)
    }

    @Test func agreeingSidesNeedNothing() {
        let p = plan(liked: ["a"], starred: ["sa"], synced: ["sa"])
        #expect(p == StarPlan(synced: ["sa"]))
    }

    @Test func aLikeOnThePhoneStarsTheServerCopy() {
        let p = plan(liked: ["a"], starred: [], synced: [])
        #expect(p.star == ["sa"])
        #expect(p.synced == ["sa"])
        #expect(p.like.isEmpty && p.unlike.isEmpty && p.unstar.isEmpty)
    }

    @Test func aStarOnTheServerBecomesALike() {
        let p = plan(liked: [], starred: ["sb"], synced: [])
        #expect(p.like == ["b"])
        #expect(p.synced == ["sb"])
        #expect(p.star.isEmpty && p.unstar.isEmpty && p.unlike.isEmpty)
    }

    @Test func anUnlikeOnThePhoneUnstarsTheServerCopy() {
        let p = plan(liked: [], starred: ["sa"], synced: ["sa"])
        #expect(p.unstar == ["sa"])
        #expect(p.synced.isEmpty)
        #expect(p.like.isEmpty)
    }

    @Test func anUnstarOnTheServerUnlikesOnThePhone() {
        let p = plan(liked: ["a"], starred: [], synced: ["sa"])
        #expect(p.unlike == ["a"])
        #expect(p.synced.isEmpty)
        #expect(p.star.isEmpty)
    }

    @Test func addedOnBothSidesIsSimplyAgreed() {
        let p = plan(liked: ["c"], starred: ["sc"], synced: [])
        #expect(p == StarPlan(synced: ["sc"]))
    }

    @Test func removedOnBothSidesIsForgotten() {
        let p = plan(liked: [], starred: [], synced: ["sc"])
        #expect(p == StarPlan())
    }

    @Test func likesMadeOfflineArePushedAtTheNextSync() {
        // Liked b and d without a connection; the server still has a starred.
        let p = plan(liked: ["a", "b", "d"], starred: ["sa"], synced: ["sa"])
        #expect(p.star == ["sb", "sd"])
        #expect(p.synced == ["sa", "sb", "sd"])
    }

    @Test func unlikesMadeOfflineWinOverTheServersOldStar() {
        let p = plan(liked: ["a"], starred: ["sa", "sb"], synced: ["sa", "sb"])
        #expect(p.unstar == ["sb"])
        #expect(p.synced == ["sa"])
        #expect(p.like.isEmpty)
    }

    @Test func changesOnBothSidesAtOnceAllLand() {
        let p = plan(liked: ["a", "c"], starred: ["sb", "sd"], synced: ["sb", "sc"])
        // a liked here, b unliked here, c unstarred there, d starred there.
        #expect(p.star == ["sa"])
        #expect(p.unstar == ["sb"])
        #expect(p.like == ["d"])
        #expect(p.unlike == ["c"])
        #expect(p.synced == ["sa", "sd"])
    }

    @Test func aSongThatLostItsServerCopyIsLeftAlone() {
        // The server no longer has d. Its like stays, nothing is sent, and its record is kept in
        // case the copy comes back.
        let p = plan(liked: ["d"], starred: [], synced: ["sd"], from: Array(copies.prefix(3)))
        #expect(p == StarPlan(synced: ["sd"]))
    }

    @Test func aReturningCopyPicksUpWhereItLeftOff() {
        // d came back while unliked on the phone: the phone's removal wins.
        let p = plan(liked: [], starred: ["sd"], synced: ["sd"])
        #expect(p.unstar == ["sd"])
    }

    @Test func aLibrarySongWithTwoServerCopiesStarsBoth() {
        let two = [ServerCopy(trackId: "a", serverId: "sa1"), ServerCopy(trackId: "a", serverId: "sa2")]
        let p = plan(liked: ["a"], starred: [], synced: [], from: two)
        #expect(p.star == ["sa1", "sa2"])
    }

    @Test func oneStarredCopyIsEnoughForALike() {
        let two = [ServerCopy(trackId: "a", serverId: "sa1"), ServerCopy(trackId: "a", serverId: "sa2")]
        let p = plan(liked: [], starred: ["sa2"], synced: [], from: two)
        #expect(p.like == ["a"])
        #expect(p.synced == ["sa2"])
    }

    @Test func songsOnlyOnThePhoneAreNotInvolved() {
        let p = plan(liked: ["phone-only"], starred: [], synced: [])
        #expect(p == StarPlan())
    }

    @Test func aStarThatFailedIsTriedAgain() {
        let first = plan(liked: ["a"], starred: [], synced: [])
        let record = first.settled(starFailed: ["sa"], unstarFailed: [])
        #expect(record.isEmpty)
        #expect(plan(liked: ["a"], starred: [], synced: record).star == ["sa"])
    }

    @Test func anUnstarThatFailedIsTriedAgain() {
        let first = plan(liked: [], starred: ["sa"], synced: ["sa"])
        let record = first.settled(starFailed: [], unstarFailed: ["sa"])
        #expect(record == ["sa"])
        #expect(plan(liked: [], starred: ["sa"], synced: record).unstar == ["sa"])
    }

    @Test func serverTimesParse() {
        #expect(parseServerTime("2026-09-25T01:44:59.636933547Z") == 1_790_300_699_636)
        #expect(parseServerTime("yesterday") == nil)
        #expect(parseServerTime(nil) == nil)
    }
}
