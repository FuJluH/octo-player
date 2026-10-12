import Foundation
import Testing
@testable import OctoKit

@Suite struct DownloadUndoTest {
    @Test func aFinishedDownloadWhoseFileWasKeptCanComeBack() {
        #expect(canRestore([(.done, true)]))
    }

    @Test func aFinishedDownloadWhoseFileIsGoneCannot() {
        #expect(!canRestore([(.done, false)]))
        #expect(!canRestore([(.done, true), (.done, false)]))
    }

    @Test func unfinishedDownloadsOnlyNeedToWaitAgain() {
        #expect(canRestore([(.queued, false), (.downloading, false), (.failed, false)]))
    }

    @Test func nothingRemovedHasNothingToBringBack() {
        #expect(!canRestore([]))
    }
}
