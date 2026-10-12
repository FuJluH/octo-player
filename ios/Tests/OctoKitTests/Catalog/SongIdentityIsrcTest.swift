import Foundation
import Testing
@testable import OctoKit

// ISRCs read one way everywhere, the same as on the server: one spelling for a valid code,
// nothing for anything else, and a shared code as one recording.
@Suite struct SongIdentityIsrcTest {
    @Test func anIsrcHasOneSpellingOrIsAbsent() {
        let cases: [(String?, String?)] = [
            ("USRC17607839", "USRC17607839"),
            ("us-rc1-76-07839", "USRC17607839"),
            (" US RC1 76 07839 ", "USRC17607839"),
            ("US.RC1.76.07839", "USRC17607839"),
            ("ＵＳＲＣ１７６０７８３９", "USRC17607839"),
            ("GBAHT1600302", "GBAHT1600302"),
            ("USRC1760783", nil),
            ("USRC176078390", nil),
            ("1SRC17607839", nil),
            ("USRC1760783X", nil),
            ("US_RC17607839", nil),
            ("ISRC: USRC17607839", nil),
            ("", nil),
            (nil, nil),
        ]
        for (value, expected) in cases {
            #expect(SongIdentity.normalizeIsrc(value) == expected, "'\(value ?? "null")'")
        }
    }

    @Test func sharingAnIsrcNeedsAValidCodeOnBothSides() {
        #expect(SongIdentity.sharesIsrc(["USRC17607839"], ["us-rc1-76-07839"]))
        #expect(SongIdentity.sharesIsrc(["GBAHT1600302", "USRC17607839"], ["USRC17607839"]))
        #expect(!SongIdentity.sharesIsrc(["USRC17607839"], ["GBAHT1600302"]))
        #expect(!SongIdentity.sharesIsrc(["USRC17607839"], []))
        #expect(!SongIdentity.sharesIsrc(nil, ["USRC17607839"]))
        #expect(!SongIdentity.sharesIsrc(["junk"], ["junk"]))
    }

    @Test func oneIsrcIsTheSameRecordingAtFullConfidence() {
        let match = SongIdentity.same(
            SongRef(title: "紅蓮華", artist: "LiSA", isrcs: ["JPU901901234"]),
            SongRef(title: "Gurenge", artist: "LiSA", isrcs: ["JP-U90-19-01234"])
        )

        #expect(match.verdict == .same)
        #expect(match.confidence == 1.0)
        #expect(match.reason == "same ISRC")
    }

    @Test func differentIsrcsFallBackToTheTextUnchanged() {
        let withCodes = SongIdentity.same(
            SongRef(title: "Song (Remastered 2011)", artist: "Artist", seconds: 200.0, isrcs: ["GBAAA0100001"]),
            SongRef(title: "Song", artist: "Artist", seconds: 201.0, isrcs: ["GBAAA1100002"])
        )
        let without = SongIdentity.same(
            SongRef(title: "Song (Remastered 2011)", artist: "Artist", seconds: 200.0),
            SongRef(title: "Song", artist: "Artist", seconds: 201.0)
        )

        #expect(without == withCodes)
    }
}
