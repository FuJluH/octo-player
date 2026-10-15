import Foundation
import Testing
@testable import OctoKit

@Suite struct AnimatedArtBackupTests {
    @Test func theSettingTravelsInABackup() {
        var backup = Backup()
        var player = PlayerPrefs()
        player.animatedArt = .fullScreen
        backup.player = player
        let text = BackupFile.encode(backup)
        #expect(text.contains("\"animatedArt\": \"full_screen\""))
        guard case .read(let read) = BackupFile.decode(text) else {
            Issue.record("not read")
            return
        }
        #expect(read.player?.animatedArt == .fullScreen)
    }

    @Test func aBackupWithoutItKeepsTheDefault() {
        guard case .read(let read) = BackupFile.decode(#"{"player": {"crossfade": true}}"#) else {
            Issue.record("not read")
            return
        }
        #expect(read.player?.animatedArt == .square)
        guard case .read(let unknown) = BackupFile.decode(#"{"player": {"animatedArt": "spinning"}}"#) else {
            Issue.record("not read")
            return
        }
        #expect(unknown.player?.animatedArt == .square)
    }
}
