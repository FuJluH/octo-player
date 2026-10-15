import Foundation
import Testing
@testable import OctoKit

/// How a shared link's expiry is read, and how station and file ids trim what they carry.
@Suite struct ShareExpiryTimeTests {
    let now: Int64 = 1_790_416_800_000

    @Test func anInstantOrAnOffsetTimeIsRead() {
        let instant: ServerShare = decoded(#"{"id":"a","expires":"2026-09-29T10:00:00Z"}"#)
        #expect(shareExpiresAtMs(instant) == 1_790_676_000_000)
        let offset: ServerShare = decoded(#"{"id":"b","expires":"2026-09-29T12:00:00+02:00"}"#)
        #expect(shareExpiresAtMs(offset) == 1_790_676_000_000)
        let fraction: ServerShare = decoded(#"{"id":"c","expires":"2026-09-29T10:00:00.636933547Z"}"#)
        #expect(shareExpiresAtMs(fraction) == 1_790_676_000_636)
    }

    @Test func aTimeWithNoZoneNeverExpires() {
        let local: ServerShare = decoded(#"{"id":"a","expires":"2026-09-29T10:00:00","visitCount":0}"#)
        #expect(shareExpiresAtMs(local) == nil)
        #expect(shareDetails(local, nowMs: now) == "Never expires • No visits")
    }

    @Test func unreadableOrMissingNeverExpires() {
        let junk: ServerShare = decoded(#"{"id":"a","expires":"next week"}"#)
        #expect(shareExpiresAtMs(junk) == nil)
        let blank: ServerShare = decoded(#"{"id":"b","expires":""}"#)
        #expect(shareExpiresAtMs(blank) == nil)
        let none: ServerShare = decoded(#"{"id":"c"}"#)
        #expect(shareExpiresAtMs(none) == nil)
    }

    @Test func aStationIdTrimsNewlinesToo() {
        let id = radioId(streamUrl: "\n http://host/live \n", name: "\tFIP\n")
        #expect(id == radioId(streamUrl: "http://host/live", name: "FIP"))
        #expect(radioOf(id)?.stream == "http://host/live")
        #expect(radioOf(id)?.name == "FIP")
    }

    @Test func anOpenedFileIdTrimsNewlinesToo() {
        #expect(openedFileId("\nfile:///a.mp3\n", "Song\n", "\nBand") == openedFileId("file:///a.mp3", "Song", "Band"))
    }
}
