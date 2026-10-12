import Foundation
import Testing
@testable import OctoKit

/// What the phone keeps for each server is kept per account: a switch to another server and back
/// loses none of it, and what was kept under a plain name becomes one server's. These are the key
/// rules the small stores follow, run over a plain dictionary of saved values.
@Suite struct AccountStoresTest {
    private let home = "home"

    @Test func anOlderVersionsKeyIsTheKeptServersId() {
        let url = "https://music.test/"
        #expect(accountOfServerKey("winters@\(url)") == serverAccountKey("winters", url))
        #expect(accountOfServerKey("me@mail.test@\(url)") == serverAccountKey("me@mail.test", url))
    }

    @Test func eachAccountsValuesHaveTheirOwnNames() {
        #expect(accountKey("pending_plays", "home") == "pending_plays@home")
        #expect(accountKey("pending_plays", "home") != accountKey("pending_plays", "work"))
        // An account id that holds an "@" keeps it whole.
        #expect(accountKey("synced_stars", "me@mail.test") == "synced_stars@me@mail.test")
    }

    @Test func playsWaitingForAServerStayWithItAcrossASwitch() {
        var saved: [String: String] = [:]
        saved[accountKey("pending_plays", "home")] = "1000 song-1"
        saved[accountKey("synced_stars", "home")] = "song-1"
        saved[accountKey("pending_plays", "work")] = "2000 song-9"
        #expect(saved[accountKey("pending_plays", "home")] == "1000 song-1")
        #expect(saved[accountKey("pending_plays", "work")] == "2000 song-9")
        #expect(saved[accountKey("synced_stars", "work")] == nil)
        // Forgetting one server leaves the other's.
        for key in accountKeys(saved.keys, of: "work") { saved[key] = nil }
        #expect(saved[accountKey("pending_plays", "work")] == nil)
        #expect(saved[accountKey("pending_plays", "home")] == "1000 song-1")
        #expect(saved[accountKey("synced_stars", "home")] == "song-1")
    }

    @Test func forgettingAnAccountTakesOnlyItsOwnValues() {
        let keys = ["recent@home", "recent@work", "recent@myhome", "recent", "server"]
        #expect(accountKeys(keys, of: "home") == ["recent@home"])
    }

    @Test func plainValuesBelongToTheirServer() {
        let plain = ["pending_plays": "1000 song-1", "synced_stars": "song-2"]
        let moved = movedToAccount(plain, existing: [], account: home)
        #expect(moved.write == ["pending_plays@home": "1000 song-1", "synced_stars@home": "song-2"])
        #expect(Set(moved.remove) == ["pending_plays", "synced_stars"])
    }

    @Test func favoriteStarsAreKeptPerServer() {
        // The account already has its own value: the plain one goes without overwriting it.
        let moved = movedToAccount(["synced_albums": "al-1"], existing: ["synced_albums@home"], account: home)
        #expect(moved.write.isEmpty)
        #expect(moved.remove == ["synced_albums"])
        // Another account's values are its own.
        let other = movedToAccount(["synced_albums": "al-1"], existing: ["synced_albums@work"], account: home)
        #expect(other.write == ["synced_albums@home": "al-1"])
    }
}
