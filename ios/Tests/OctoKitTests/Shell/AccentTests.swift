import Foundation
import Testing
@testable import OctoKit

@Suite struct AccentTests {
    @Test func theChoicesAreTheOtherAppsOwnInTheirOrder() {
        #expect(AccentChoice.allCases.map(\.label) == ["Octo", "Sky", "Iris", "Lilac", "Rose", "Coral", "Amber", "Lime", "Mint", "From the album art"])
        #expect(AccentChoice.allCases.map(\.storedName) == ["Octo", "Sky", "Iris", "Lilac", "Rose", "Coral", "Amber", "Lime", "Mint", "FromArt"])
        #expect(AccentChoice.fixed.map { $0.argb! } == [0xFF97_B1B9, 0xFF73_BAEA, 0xFFA3_A9F6, 0xFFC7_9DE6, 0xFFE4_96B4, 0xFFEF_9687,
                                                        0xFFDA_A75D, 0xFFA0_BE66, 0xFF6F_C5A1])
        #expect(AccentChoice.fromArt.argb == nil)
        #expect(PlayerPrefs().accent == .octo)
        #expect(octoAccentArgb == OctoPalette.accent.hex | 0xFF00_0000)
    }

    @Test func everyFixedAccentReadsOnThePageAndTheRaisedSurface() {
        for choice in AccentChoice.fixed {
            #expect(accentReads(choice.argb!), "\(choice.label)")
            // White words on the filled button made from it.
            let fill = mix(RGBA(argb: choice.argb!), .black, 0.45)
            #expect(contrastRatio(0xFFFF_FFFF, fill.hex | 0xFF00_0000) >= 4.5, "\(choice.label)")
        }
    }

    @Test func theAlbumArtGivesItsHueAtTheAccentsLightness() {
        let red: UInt32 = 0xFFD0_2020
        let accent = accentFromArt(red)!
        #expect(accentReads(accent))
        #expect(hueDistance(toLch(accent).h, toLch(red).h) < 8)
        #expect(abs(toLch(accent).l - 0.76) < 0.1)
        // A dark blue cover still reads.
        #expect(accentReads(accentFromArt(0xFF10_1860)!))
    }

    @Test func aGrayCoverOrNoneKeepsOctosOwn() {
        #expect(accentFromArt(0xFF80_8080) == nil)
        #expect(accentArgb(.fromArt, art: 0xFF80_8080) == octoAccentArgb)
        #expect(accentArgb(.fromArt, art: nil) == octoAccentArgb)
        #expect(accentArgb(.coral, art: 0xFF10_1860) == 0xFFEF_9687)
    }

    @Test func eachChoiceSaysWhatItColors() {
        #expect(AccentChoice.octo.help == "Octo's own blue gray for selections, sliders, switches and buttons.")
        #expect(AccentChoice.rose.help == "Selections, sliders, switches and buttons in rose.")
        #expect(AccentChoice.fromArt.help.hasPrefix("Follows the playing song's cover."))
    }

    @Test func theGlassStaysApplesOwnUntilItIsAskedToTakeTheAccent() {
        #expect(PlayerPrefs().glassTint == false)
        #expect(glassFilm(accent: RGBA(argb: 0xFFEF_9687), tinted: false) == OctoPalette.glazeFilm)
        let tinted = glassFilm(accent: RGBA(argb: 0xFFEF_9687), tinted: true)
        #expect(tinted != OctoPalette.glazeFilm)
        #expect(tinted.red > tinted.blue)
        #expect(GlassTintWords.helper(.octo) == GlassTintWords.same)
        #expect(GlassTintWords.helper(.mint) == GlassTintWords.help)
    }

    @Test func theAccentAndTheGlassAreBackedUp() {
        for accent in AccentChoice.allCases {
            var backup = Backup()
            var player = PlayerPrefs()
            player.accent = accent
            player.glassTint = true
            backup.player = player
            guard case .read(let read) = BackupFile.decode(BackupFile.encode(backup)) else { Issue.record("not read"); return }
            #expect(read.player?.accent == accent)
            #expect(read.player?.glassTint == true)
        }
        var backup = Backup()
        var player = PlayerPrefs()
        player.accent = .fromArt
        backup.player = player
        let text = BackupFile.encode(backup)
        #expect(text.contains("\"accent\": \"FromArt\""))
        // One this app does not know, from a newer Octo, reads as Octo's own.
        guard case .read(let newer) = BackupFile.decode(text.replacingOccurrences(of: "\"FromArt\"", with: "\"Chartreuse\"")) else {
            Issue.record("not read"); return
        }
        #expect(newer.player?.accent == .octo)
        // A backup from before accents leaves Octo's own.
        guard case .read(let old) = BackupFile.decode(#"{"kind": "octo-settings", "version": 1, "player": {}}"#) else {
            Issue.record("not read"); return
        }
        #expect(old.player?.accent == .octo)
        #expect(old.player?.glassTint == false)
    }
}
