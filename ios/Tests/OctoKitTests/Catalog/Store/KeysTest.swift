import Foundation
import Testing
@testable import OctoKit

@Suite struct KeysTest {
    @Test func accentsAndCaseAreIgnored() {
        #expect(searchKey("Beyoncé") == "beyonce")
        #expect(searchKey(" Mötley Crüe ") == "motley crue")
    }

    @Test func leadingArticleIsDroppedForSorting() {
        #expect(sortKey("The Beatles") == "beatles")
        #expect(sortKey("A Tribe Called Quest") == "tribe called quest")
        // A name that is only an article, or merely starts with the letters, stays whole.
        #expect(sortKey("The") == "the")
        #expect(sortKey("Theory") == "theory")
    }

    @Test func naturalKeysOrderNumbersByValue() {
        let names = ["Album 10", "Album 2", "The Album 1", "Album 007", "album 2b"]
        let sorted = names.enumerated().sorted { a, b in
            let ka = naturalSortKey(a.element), kb = naturalSortKey(b.element)
            return ka != kb ? ka < kb : a.offset < b.offset
        }.map(\.element)
        #expect(sorted == ["The Album 1", "Album 2", "album 2b", "Album 007", "Album 10"])
    }
}
