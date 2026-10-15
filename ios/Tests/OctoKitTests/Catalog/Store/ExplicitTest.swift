import Foundation
import Testing
@testable import OctoKit

@Suite struct ExplicitTest {
    @Test func onlyExplicitIsMarked() {
        #expect(isExplicit("explicit"))
        #expect(isExplicit(" Explicit "))
        #expect(!isExplicit("clean"))
        #expect(!isExplicit(""))
        #expect(!isExplicit(nil))
    }

    @Test func aSongReadsItsOwnStatus() {
        var explicit = Song(id: "1", title: "Dracula")
        explicit.explicitStatus = "explicit"
        var clean = Song(id: "2", title: "Dracula")
        clean.explicitStatus = "clean"
        #expect(explicit.isExplicit)
        #expect(!clean.isExplicit)
        #expect(!Song(id: "3", title: "Dracula").isExplicit)
    }
}
