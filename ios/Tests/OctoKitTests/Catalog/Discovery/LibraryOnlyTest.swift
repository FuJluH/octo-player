import Foundation
import Testing
@testable import OctoKit

@Suite struct LibraryOnlyTest {
    @Test func onlyLibrarySongsStayInTheirOrder() {
        let songs = ["a", "find:b", "c", "find:d"]
        #expect(librarySongsOnly(songs, hide: true) { $0.hasPrefix("find:") } == ["a", "c"])
        #expect(librarySongsOnly(songs, hide: false) { $0.hasPrefix("find:") } == songs)
    }

    @Test func theWordsHaveNoDashes() {
        for words in [libraryOnlySetting, libraryOnlyHelp, onlyMySongs] {
            #expect(!words.unicodeScalars.contains { $0.value == 0x2014 || $0.value == 0x2013 })
        }
    }
}
