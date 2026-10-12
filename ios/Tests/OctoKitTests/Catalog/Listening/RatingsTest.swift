import Foundation
import Testing
@testable import OctoKit

@Suite struct RatingsTest {
    func copy(_ song: String, _ server: String, _ rating: Int = 0) -> RatingCopy {
        RatingCopy(trackId: song, serverId: server, rating: rating)
    }

    @Test func bothSidesAgreeingChangesNothing() {
        let plan = reconcileRatings([copy("t1", "s1", 4)], local: ["t1": 4], synced: ["s1": 4])
        #expect(plan == RatingPlan(synced: ["s1": 4]))
    }

    @Test func aRatingMadeOnThePhoneIsSent() {
        let plan = reconcileRatings([copy("t1", "s1", 2)], local: ["t1": 5], synced: ["s1": 2])
        #expect(plan.send == ["t1": RatingSend(serverIds: ["s1"], rating: 5)])
        #expect(plan.adopt.isEmpty)
        #expect(plan.synced == ["s1": 5])
    }

    @Test func aRatingClearedOnThePhoneIsClearedOnTheServer() {
        let plan = reconcileRatings([copy("t1", "s1", 3)], local: [:], synced: ["s1": 3])
        #expect(plan.send == ["t1": RatingSend(serverIds: ["s1"], rating: 0)])
        #expect(plan.synced.isEmpty)
    }

    @Test func aRatingMadeOnTheServerComesToThePhone() {
        let plan = reconcileRatings([copy("t1", "s1", 4)], local: ["t1": 2], synced: ["s1": 2])
        #expect(plan.send.isEmpty)
        #expect(plan.adopt == ["t1": 4])
        #expect(plan.synced == ["s1": 4])
    }

    @Test func aRatingClearedOnTheServerIsClearedOnThePhone() {
        let plan = reconcileRatings([copy("t1", "s1", 0)], local: ["t1": 3], synced: ["s1": 3])
        #expect(plan.adopt == ["t1": 0])
        #expect(plan.synced.isEmpty)
    }

    @Test func whenBothChangedThePhoneWins() {
        let plan = reconcileRatings([copy("t1", "s1", 1)], local: ["t1": 5], synced: ["s1": 3])
        #expect(plan.send == ["t1": RatingSend(serverIds: ["s1"], rating: 5)])
        #expect(plan.adopt.isEmpty)
    }

    @Test func beforeEverSyncingEachSideFillsTheOthersGaps() {
        let plan = reconcileRatings(
            [copy("t1", "s1", 0), copy("t2", "s2", 4), copy("t3", "s3", 0)],
            local: ["t1": 3],
            synced: [:]
        )
        #expect(plan.send == ["t1": RatingSend(serverIds: ["s1"], rating: 3)])
        #expect(plan.adopt == ["t2": 4])
        // Songs rated nowhere leave no record.
        #expect(plan.synced == ["s1": 3, "s2": 4])
    }

    @Test func everyServerCopyOfASongIsKeptTheSame() {
        let copies = [copy("t1", "b", 3), copy("t1", "a", 3)]
        // Rated 5 elsewhere on one copy only: the phone and the other copy follow.
        let plan = reconcileRatings([copy("t1", "b", 5), copy("t1", "a", 3)], local: ["t1": 3], synced: ["a": 3, "b": 3])
        #expect(plan.send == ["t1": RatingSend(serverIds: ["a", "b"], rating: 5)])
        #expect(plan.adopt == ["t1": 5])
        #expect(plan.synced == ["a": 5, "b": 5])
        #expect(reconcileRatings(copies, local: ["t1": 3], synced: ["a": 3, "b": 3]) == RatingPlan(synced: ["a": 3, "b": 3]))
    }

    @Test func aSongThatLostItsServerCopyKeepsItsRecord() {
        let plan = reconcileRatings([], local: ["t1": 4], synced: ["gone": 4])
        #expect(plan.synced == ["gone": 4])
    }

    @Test func aRatingThatFailedToSendIsTriedAgainNextTime() {
        let before = ["s1": 2]
        let plan = reconcileRatings([copy("t1", "s1", 2), copy("t2", "s2", 0)], local: ["t1": 5, "t2": 1], synced: before)
        let record = plan.settled(failed: ["t1", "t2"], before: before)
        // The old record stays, and a song never agreed on has none.
        #expect(record == ["s1": 2])
        let again = reconcileRatings([copy("t1", "s1", 2), copy("t2", "s2", 0)], local: ["t1": 5, "t2": 1], synced: record)
        #expect(Set(again.send.keys) == ["t1", "t2"])
    }

    @Test func theRecordSurvivesStorage() {
        let record = ["s1": 5, "a b": 1]
        #expect(decodeRatings(encodeRatings(record)) == record)
        #expect(decodeRatings(["x", "9 s1", "0 s2", "3 "]) == [:])
        #expect(encodeRatings(["s1": 0]).isEmpty)
    }

    @Test func ratingsStayInRange() {
        #expect(cleanRating(nil) == 0)
        #expect(cleanRating(-1) == 0)
        #expect(cleanRating(6) == 0)
        #expect(cleanRating(3) == 3)
    }
}
