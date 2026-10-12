import Foundation
import Testing
@testable import OctoKit

@Suite struct ServerSwitchWordsTest {
    @Test func theSwitchNoticeSaysWhenMusicStopped() {
        #expect(serverSwitchNotice(to: "Work", from: nil, stoppedMusic: true) == nil)
        #expect(serverSwitchNotice(to: "Work", from: "Home", stoppedMusic: false) == "Now on Work.")
        #expect(serverSwitchNotice(to: "Work", from: "Home", stoppedMusic: true)
            == "Now on Work. The music from Home stopped, and its queue is kept for when you come back.")
    }

    @Test func aFailedSwitchSaysWhy() {
        #expect(serverSwitchFailedWords("Home", why: "The server is out of reach.")
            == "Couldn't switch to Home. The server is out of reach.")
        #expect(serverSwitchPasswordRefusedWords("Home") == "Home didn't take the saved password. It may have been changed.")
    }
}
