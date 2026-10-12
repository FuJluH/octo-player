import Foundation
import Testing
@testable import OctoKit

@Suite struct DownloadRulesTest {
    let source = "server:music.example"

    func copy(_ nativeId: String, of trackId: String, mime: String? = "audio/mpeg", bitrate: Int? = nil, sampleRate: Int? = nil,
              bitDepth: Int? = nil, size: Int64? = nil, durationMs: Int64 = 200_000) -> SourceTrack {
        SourceTrack(id: "\(source):\(nativeId)", sourceId: source, nativeId: nativeId, title: "Title \(nativeId)", searchKey: "",
                    sortKey: "", artist: "Artist", artistId: "", album: "", albumId: "", durationMs: durationMs, addedAt: 0,
                    mimeType: mime, sizeBytes: size, bitrate: bitrate, sampleRate: sampleRate, bitDepth: bitDepth, mergedId: trackId)
    }

    func row(_ trackId: String, source: String = "server:music.example", state: DownloadStatus = .done, reason: String) -> KeptDownload {
        KeptDownload(trackId: trackId, sourceId: source, serverId: "s-\(trackId)", path: "/music/\(trackId).flac", sizeBytes: 100,
                     format: "audio/flac", state: state, progress: state == .done ? 1 : 0.4, addedAt: 1, reason: reason,
                     title: "", artist: "")
    }

    @Test func aBrokenDownloadTriesThreeTimesFiveSecondsApart() {
        #expect(downloadAfterFailure(noConnection: false, serverRefused: false, tried: 1) == .retry(afterMs: 5_000))
        #expect(downloadAfterFailure(noConnection: false, serverRefused: false, tried: 2) == .retry(afterMs: 5_000))
        #expect(downloadAfterFailure(noConnection: false, serverRefused: false, tried: 3) == .fail)
    }

    @Test func withNoConnectionADownloadWaitsHoweverOftenItBroke() {
        #expect(downloadAfterFailure(noConnection: true, serverRefused: false, tried: 7) == .waitForConnection)
        #expect(downloadAfterFailure(noConnection: true, serverRefused: true, tried: 1) == .waitForConnection)
    }

    @Test func aServerThatSaidNoFailsAtOnce() {
        #expect(downloadAfterFailure(noConnection: false, serverRefused: true, tried: 1) == .fail)
    }

    @Test func progressIsHeldShortOfDoneAndWrittenEveryHalfSecond() {
        #expect(downloadProgress(written: 50, length: 100) == 0.5)
        #expect(downloadProgress(written: 100, length: 100) == 0.99)
        #expect(downloadProgress(written: 10, length: 0) == nil)
        #expect(downloadProgressDue(nowMs: 1_000_000, lastMs: 0))
        #expect(!downloadProgressDue(nowMs: 1_000_499, lastMs: 1_000_000))
        #expect(downloadProgressDue(nowMs: 1_000_500, lastMs: 1_000_000))
        #expect(downloadUndoKeepMs == 10_000)
    }

    @Test func downloadsWaitForWifiWhenAskedTo() {
        #expect(!downloadMayRunNow(signedIn: true, wifiOnly: true, onWifi: false, online: true))
        #expect(downloadMayRunNow(signedIn: true, wifiOnly: false, onWifi: false, online: true))
        #expect(!downloadMayRunNow(signedIn: false, wifiOnly: false, onWifi: true, online: true))
        #expect(downloadLeftWifi(wifiOnly: true, onWifi: false))
        #expect(!downloadLeftWifi(wifiOnly: false, onWifi: false))
    }

    @Test func aRemovedDownloadComesBackAsItWasOrWaitsAgain() {
        let done = row("a", reason: "manual")
        #expect(restoredDownload(done, fileBack: true) == done)
        let lost = restoredDownload(done, fileBack: false)
        #expect(lost.state == .queued && lost.progress == 0 && lost.path.isEmpty && lost.sizeBytes == 0)
        let failed = row("b", state: .failed, reason: "manual")
        #expect(restoredDownload(failed, fileBack: false) == failed)
        #expect(restoredDownload(row("c", state: .downloading, reason: "manual"), fileBack: false).state == .queued)
    }

    @Test func onlyTheServerInUsesDownloadsAreHeld() {
        let rows = [row("a", reason: "manual"), row("a", source: "server:other", reason: "liked"),
                    row("b", reason: "liked,playlist:gym")]
        #expect(downloadsHeld(rows, serverInUse: source) == ["a": ["manual"], "b": ["liked", "playlist:gym"]])
        #expect(downloadsHeld(rows, serverInUse: nil).isEmpty)
    }

    @Test func aDownloadByHandAddsNewSongsAndMarksHeldOnes() {
        let plan = planManualDownloads(held: ["a": ["liked"]], trackIds: ["a", "b", "b"])
        #expect(plan.add == ["b": ["manual"]])
        #expect(plan.change == ["a": ["liked", "manual"]])
        #expect(reasonsAfterManualRemoval(["manual"]).isEmpty)
        #expect(reasonsAfterManualRemoval(["manual", "liked"]) == ["liked"])
    }

    @Test func doneSongsAreTheFinishedOnes() {
        let rows = [row("a", reason: "manual"), row("b", state: .queued, reason: "manual")]
        #expect(downloadedTrackIds(rows) == ["a"])
        #expect(downloadKey("server:x", "tr-1") == "server:x|tr-1")
    }

    @Test func theBestCopyIsLosslessThenRateThenBitsThenBitrate() {
        let mp3 = copy("1", of: "t", mime: "audio/mpeg", bitrate: 320)
        let flac = copy("2", of: "t", mime: "audio/flac", sampleRate: 44_100, bitDepth: 16)
        let hiRes = copy("3", of: "t", mime: "audio/flac", sampleRate: 96_000, bitDepth: 24)
        #expect(downloadBestCopy([mp3, flac, hiRes])?.nativeId == "3")
        #expect(downloadBestCopy([mp3, flac])?.nativeId == "2")
        // Equal copies keep the first.
        #expect(downloadBestCopy([copy("4", of: "t"), copy("5", of: "t")])?.nativeId == "4")
        #expect(downloadBestCopy([]) == nil)
        // Kilobits from the server, or worked out from size and length.
        #expect(downloadBitrate(copy("6", of: "t", bitrate: 256)) == 256_000)
        #expect(downloadBitrate(copy("7", of: "t", size: 5_000_000, durationMs: 200_000)) == 200_000)
        #expect(downloadBestCopy([copy("8", of: "t", bitrate: 128), copy("9", of: "t", bitrate: 320)])?.nativeId == "9")
    }

    @Test func newDownloadsComeFromTheBestCopyOfSongsThatCanDownload() throws {
        let copies = [copy("1", of: "a", bitrate: 128), copy("2", of: "a", mime: "audio/flac"), copy("3", of: "c")]
        let made = newDownloads(wanted: ["a": ["liked", "manual"], "b": ["manual"], "c": ["manual"]], downloadable: ["a", "b"],
                                copies: copies, now: 42)
        #expect(made.kept.map(\.serverId) == ["2"])
        let first = try #require(made.kept.first)
        #expect(first.reason == "liked,manual")
        #expect(first.state == .queued && first.addedAt == 42 && first.title == "Title 2")
        let refused = newDownloads(wanted: ["a": ["manual"]], downloadable: ["a"], copies: copies, now: 42, refusedSource: source)
        #expect(refused.kept.isEmpty && refused.refused.count == 1)
    }

    @Test func aSmallerDownloadIsAnMp3OnlyWhenThatSavesRoom() {
        #expect(downloadMaxKbps(mimeType: "audio/flac", bitrate: 900, quality: .original) == nil)
        #expect(downloadMaxKbps(mimeType: "audio/flac", bitrate: 900, quality: .mp3(kbps: 192)) == 192)
        #expect(downloadMaxKbps(mimeType: "audio/mpeg", bitrate: 128_000, quality: .mp3(kbps: 192)) == nil)
        #expect(downloadMaxKbps(mimeType: "audio/mpeg", bitrate: 320_000, quality: .mp3(kbps: 192)) == 192)
        #expect(downloadFormat(serverMimeType: "audio/flac", maxKbps: nil) == "audio/flac")
        #expect(downloadFormat(serverMimeType: "audio/flac", maxKbps: 192) == "audio/mpeg")
    }
}
