import Foundation
import Testing
@testable import OctoKit

/// The account's audio quality choices and the family's limits on them.
@Suite struct AudioQualityTest {
    @Test func originalComesFirstAndIsTheDefault() {
        #expect(AccountStreamQuality.allCases.first == .original)
        #expect(AccountQualityWords.options(limitKbps: 0).first?.quality == .original)
        #expect(AccountQuality().home == .original)
        #expect(AccountQuality().away == .original)
        #expect(AccountStreamQuality.original.line == "As the file is, FLAC stays FLAC")
        #expect(AccountQualityWords.originalLabel == "Original (as the file is, FLAC stays FLAC)")
    }

    @Test func withoutALimitEveryChoiceCanBePicked() {
        let options = AccountQualityWords.options(limitKbps: 0)
        #expect(options.allSatisfy { $0.enabled })
        #expect(options.first?.blocked == nil)
        #expect(options.first?.line == "As the file is, FLAC stays FLAC")
    }

    @Test func aCappedMemberSeesOriginalOffAndWhy() {
        let options = AccountQualityWords.options(limitKbps: 192)
        let original = options[0]
        #expect(original.quality == .original)
        #expect(!original.enabled)
        #expect(original.blocked == "Your family plan streams up to 192 kbps")
        #expect(original.line == "Your family plan streams up to 192 kbps")
        // The bitrates stay pickable; one above the limit plays at it.
        #expect(options.dropFirst().allSatisfy { $0.enabled })
        #expect(options.first { $0.quality == .high }?.limited == true)
        #expect(options.first { $0.quality == .standard }?.limited == false)
        #expect(AccountQualityWords.originalBlocked(by: 96) == "Your family plan streams up to 96 kbps")
        #expect(AccountQualityWords.originalBlocked(by: 0) == nil)
    }

    @Test func audioQualityChoicesShowTheFamilysLimit() {
        let free = AccountQuality()
        #expect(free.limitLines.isEmpty)
        #expect(!AccountQualityWords.options(limitKbps: free.homeLimit).contains { $0.limited })
        let limited = AccountQuality(home: .original, away: .standard, familyLimitKbps: 0, familyAwayLimitKbps: 160)
        #expect(limited.limitLines == ["Your family plan limits away listening to 160 kbps"])
        #expect(limited.awayLimit == 160)
        #expect(limited.homeLimit == 0)
        // Original and High are held to 160 away; Standard and Data saver are not.
        #expect(AccountQualityWords.options(limitKbps: limited.awayLimit).map(\.limited) == [true, true, false, false])
        #expect(AccountQualityWords.options(limitKbps: 0).map(\.name) == ["Original", "High", "Standard", "Data saver"])
        // A home limit is the away limit too, unless away is lower.
        let both = AccountQuality(familyLimitKbps: 256, familyAwayLimitKbps: 96)
        #expect(both.limitLines == ["Your family plan limits listening to 256 kbps", "Your family plan limits away listening to 96 kbps"])
        #expect(both.awayLimit == 96)
        #expect(AccountQuality(familyLimitKbps: 256).awayLimit == 256)
    }

    @Test func removeFromMyLibraryGoesOnlyOnMarkedSongsWhenTheServerMarks() {
        // A server that marks: only the member's own songs.
        #expect(offersRemoveOn(personal: true, serverMarksPersonal: true))
        #expect(!offersRemoveOn(personal: false, serverMarksPersonal: true))
        // A server that marks none: every library song, and its refusal says why.
        #expect(offersRemoveOn(personal: false, serverMarksPersonal: false))
    }
}

/// "Library songs only" leaves out songs found online, everywhere.
@Suite struct LibraryOnlyTest {
    @Test func onlyLibrarySongsStayInTheirOrder() {
        let songs = ["a", "find:b", "c", "find:d"]
        #expect(librarySongsOnly(songs, hide: true) { $0.hasPrefix("find:") } == ["a", "c"])
        #expect(librarySongsOnly(songs, hide: false) { $0.hasPrefix("find:") } == songs)
    }

    @Test func theLibraryOnlyWordsHaveNoDashes() {
        for words in [LibraryOnlyWords.setting, LibraryOnlyWords.help, LibraryOnlyWords.onlyMySongs] {
            #expect(!words.unicodeScalars.contains { $0.value == 0x2014 || $0.value == 0x2013 })
        }
    }
}
