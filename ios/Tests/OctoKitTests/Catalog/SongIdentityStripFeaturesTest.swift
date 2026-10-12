import Foundation
import Testing
@testable import OctoKit

// A title without its guest credits, the same as on the server: the credit goes, and a version
// written beside it stays, whether it shares the credit's bracket, follows it, or comes before it
// after a dash.
@Suite struct SongIdentityStripFeaturesTest {
    @Test func aGuestCreditInsideAVersionTagKeepsTheVersion() {
        let cases = [
            ("Get Lucky (Radio Edit - feat. Pharrell Williams and Nile Rodgers)", "Get Lucky (Radio Edit)"),
            ("Get Lucky [Radio Edit - feat. Pharrell Williams and Nile Rodgers]", "Get Lucky [Radio Edit]"),
            ("Get Lucky (Radio Edit, feat. Pharrell Williams & Nile Rodgers)", "Get Lucky (Radio Edit)"),
            ("Get Lucky (Radio Edit – feat. Pharrell Williams)", "Get Lucky (Radio Edit)"),
            ("Get Lucky (Radio Edit / ft. Pharrell Williams)", "Get Lucky (Radio Edit)"),
            ("Get Lucky (Radio Edit featuring Pharrell Williams)", "Get Lucky (Radio Edit)"),
            ("Get Lucky - Radio Edit - feat. Pharrell Williams and Nile Rodgers", "Get Lucky - Radio Edit"),
            ("Get Lucky (feat. Pharrell Williams and Nile Rodgers) - Radio Edit", "Get Lucky - Radio Edit"),
            ("Get Lucky feat. Pharrell Williams and Nile Rodgers (Radio Edit)", "Get Lucky (Radio Edit)"),
        ]
        for (title, expected) in cases {
            #expect(SongIdentity.stripFeatures(title) == expected, "\(title)")
        }
    }

    @Test func aCreditAloneGoesAndEverythingElseStays() {
        let cases = [
            ("Get Lucky (feat. Pharrell Williams)", "Get Lucky"),
            ("Get Lucky feat. Pharrell Williams", "Get Lucky"),
            ("Get Lucky (Live)", "Get Lucky (Live)"),
            ("Get Lucky (Daft Punk Remix) [feat. Pharrell Williams]", "Get Lucky (Daft Punk Remix)"),
            ("Get Lucky", "Get Lucky"),
            ("", ""),
        ]
        for (title, expected) in cases {
            #expect(SongIdentity.stripFeatures(title) == expected, "\(title)")
        }
    }
}
