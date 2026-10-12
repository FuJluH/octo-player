import Foundation
import Testing
@testable import OctoKit

@Suite struct PlayerVersionTests {
    private func v(_ text: String) -> PlayerVersion { PlayerVersion.parse(text)! }

    @Test func versionsOrderByTheirNumbers() {
        #expect(v("1.2.0") > v("1.1.9"))
        #expect(v("1.10.0") > v("1.9.0"))
        #expect(v("2.0.0") > v("1.99.99"))
        #expect(v("1.0.324") > v("1.0.99"))
        #expect(v("1.2.3") == v("1.2.3"))
    }

    @Test func anEarlyVersionComesBeforeItsRelease() {
        #expect(v("1.3.0-beta.1") < v("1.3.0"))
        #expect(v("1.3.0-beta.1") > v("1.2.9"))
        #expect(v("1.3.0-beta.2") > v("1.3.0-beta.1"))
        #expect(v("1.3.0-beta.10") > v("1.3.0-beta.9"))
        #expect(v("1.3.0-rc.1") > v("1.3.0-beta.5"))
        #expect(v("1.3.0-1") < v("1.3.0-alpha"))
        #expect(v("1.3.0-beta") < v("1.3.0-beta.1"))
        #expect(v("1.3.0-beta.1").isEarly)
        #expect(v("1.7.0-beta.2").description == "1.7.0-beta.2")
    }

    @Test func whatIsNotAVersionIsNil() {
        for text in ["Development build", "1.2", "1.2.3.4", "0.2.0.189-debug", "01.2.3", "v1.2.3", "1.2.3-", "1.2.3-be..ta"] {
            #expect(PlayerVersion.parse(text) == nil, "\(text)")
        }
        #expect(PlayerVersion.parse(nil) == nil)
        #expect(PlayerVersion.parse("0.1.0") == PlayerVersion(0, 1, 0))
    }

    @Test func onlyThisAppsOwnTagsNameAVersion() {
        #expect(versionOfTag("desktop-v1.2.3", .desktop) == v("1.2.3"))
        #expect(versionOfTag("android-v0.2.0", .android) == v("0.2.0"))
        #expect(versionOfTag("ios-v0.2.0", .ios) == v("0.2.0"))
        #expect(versionOfTag("android-v0.2.0", .ios) == nil)
        #expect(versionOfTag("ios-v1.2.3", .android) == nil)
        for tag in ["2026.09.23", "2026.09.23.1", "v1.2.3", "v2026.09.23", "1.2.3"] {
            for app in PlayerApp.allCases { #expect(versionOfTag(tag, app) == nil, "\(tag)") }
        }
    }

    @Test func playerTagsNeverMatchTheServersImageTags() {
        for tag in ["desktop-v1.2.3", "android-v0.2.0", "ios-v1.3.0-beta.1", "ios-v10.0.0"] {
            #expect(!tag.hasPrefix("v"))
            #expect(!(tag.prefix(4).allSatisfy(\.isNumber) && tag.dropFirst(4).hasPrefix(".")))
            #expect(PlayerApp.allCases.contains { versionOfTag(tag, $0) != nil })
        }
    }

    private let releases = [
        GitHubRelease(tag: "2026.09.23"), GitHubRelease(tag: "2026.12.31"), GitHubRelease(tag: "v9.9.9"),
        GitHubRelease(tag: "ios-v1.1.0"), GitHubRelease(tag: "ios-v1.2.0"), GitHubRelease(tag: "ios-v1.4.0", draft: true),
        GitHubRelease(tag: "ios-v1.3.0-beta.1", prerelease: true), GitHubRelease(tag: "android-v5.0.0"),
    ]

    @Test func theNewestFinalReleaseOfThisAppIsOffered() {
        #expect(newestUpdate(releases, app: .ios, running: v("1.0.324"), early: false)?.release.tag == "ios-v1.2.0")
    }

    @Test func draftsAndEarlyVersionsWaitUnlessAskedFor() {
        #expect(newestUpdate(releases, app: .ios, running: v("1.2.0"), early: true)?.release.tag == "ios-v1.3.0-beta.1")
        #expect(newestUpdate(releases, app: .ios, running: v("1.2.0"), early: false) == nil)
        #expect(newestUpdate([GitHubRelease(tag: "ios-v1.5.0-rc.1")], app: .ios, running: v("1.2.0"), early: false) == nil)
        #expect(newestUpdate([GitHubRelease(tag: "ios-v1.5.0", prerelease: true)], app: .ios, running: v("1.2.0"), early: false) == nil)
    }

    @Test func anEarlyVersionIsOfferedItsRelease() {
        let list = [GitHubRelease(tag: "ios-v1.3.0"), GitHubRelease(tag: "ios-v1.3.0-beta.1", prerelease: true)]
        #expect(newestUpdate(list, app: .ios, running: v("1.3.0-beta.1"), early: false)?.release.tag == "ios-v1.3.0")
    }

    @Test func nothingNewerIsNothing() {
        #expect(newestUpdate(releases, app: .ios, running: v("1.2.0"), early: false) == nil)
        #expect(newestUpdate(releases, app: .android, running: v("5.0.0"), early: true) == nil)
        #expect(newestUpdate(releases, app: .android, running: v("0.2.0"), early: false)?.release.tag == "android-v5.0.0")
    }

    @Test func githubsListIsRead() {
        let text = #"[{"tag_name":"ios-v1.2.0","name":"Octo 1.2.0","draft":false,"prerelease":false,"body":"Notes","extra":1,"html_url":"https://github.com/winters27/octo/releases/tag/ios-v1.2.0","assets":[{"name":"update.json","size":512,"browser_download_url":"https://example.com/update.json","id":7}]}]"#
        let list = parseReleases(Data(text.utf8))
        #expect(list?.first?.tag == "ios-v1.2.0")
        #expect(list?.first?.assets.first?.size == 512)
        #expect(list?.first?.page == "https://github.com/winters27/octo/releases/tag/ios-v1.2.0")
        #expect(parseReleases(Data("<html>portal</html>".utf8)) == nil)
    }
}

@Suite struct UpdateManifestTests {
    let key = Data(repeating: 7, count: 32)
    let signature = Data(repeating: 1, count: 64).base64EncodedString()

    private func manifest(product: String = "ios", tag: String = "ios-v1.2.0", version: String = "1.2.0",
                          sha: String = String(repeating: "a", count: 64), name: String = "Octo.ipa") -> Data {
        Data(#"{"format":1,"product":"\#(product)","version":"\#(version)","tag":"\#(tag)","notes":"Better","assets":[{"name":"\#(name)","sha256":"\#(sha)","size":10,"os":"ios","kind":"ipa"}]}"#.utf8)
    }

    private func check(_ bytes: Data, signature: String? = nil, keys: [Data]? = nil, good: Bool = true) throws -> UpdateManifest {
        try UpdateFiles.verifiedManifest(bytes, signature: signature ?? self.signature, keys: keys ?? [key], app: .ios, tag: "ios-v1.2.0") { _, _, _ in good }
    }

    @Test func aSignedManifestForThisReleaseReads() throws {
        let read = try check(manifest())
        #expect(read.notes == "Better")
        #expect(read.assets.first?.kind == "ipa")
    }

    @Test func anythingElseIsRefused() {
        #expect(throws: UpdateRefused("the signature does not match")) { try check(manifest(), good: false) }
        #expect(throws: UpdateRefused("this build has no key to check updates with")) { try check(manifest(), keys: []) }
        #expect(throws: UpdateRefused("the signature is not readable")) { try check(manifest(), signature: "%%%") }
        #expect(throws: UpdateRefused("the manifest is for another app")) { try check(manifest(product: "android")) }
        #expect(throws: UpdateRefused("the manifest is for another release")) { try check(manifest(tag: "ios-v1.1.0")) }
        #expect(throws: UpdateRefused("the manifest names another version")) { try check(manifest(version: "1.2.1")) }
        #expect(throws: UpdateRefused("the manifest lists a file badly")) { try check(manifest(sha: "xyz")) }
        #expect(throws: UpdateRefused("the manifest lists a file badly")) { try check(manifest(name: "../Octo.ipa")) }
        #expect(throws: UpdateRefused("the manifest is not readable")) { try check(Data("not json".utf8)) }
    }

    @Test func theShippedKeyIsReadAndBadKeysAreRefused() throws {
        #expect(UpdateFiles.trustedKeys.count == 1)
        #expect(UpdateFiles.trustedKeys.first?.count == 32)
        #expect(try UpdateFiles.parseKeys("# only a comment\n\n").isEmpty)
        #expect(throws: UpdateRefused.self) { try UpdateFiles.parseKeys("bm90IGEga2V5") }
    }

    @Test func checksWaitSixHoursOrAsLongAsGitHubAsks() {
        #expect(UpdateTiming.nextWait(now: 0, retryAt: nil) == 21_600_000)
        #expect(UpdateTiming.nextWait(now: 0, retryAt: 30_000_000) == 30_000_000)
        #expect(UpdateTiming.firstCheckDelayMs == 90_000)
    }

    @Test func githubsAnswersAreMadeSenseOf() {
        let list = Data(#"[{"tag_name":"ios-v1.0.0"}]"#.utf8)
        #expect(ReleaseFeedAnswer.of(status: 200, headers: ["ETag": "abc"], body: list, cached: nil, nowMs: 0)
            == .releases([GitHubRelease(tag: "ios-v1.0.0")], keep: ("abc", list)))
        #expect(ReleaseFeedAnswer.of(status: 304, headers: [:], body: Data(), cached: list, nowMs: 0)
            == .releases([GitHubRelease(tag: "ios-v1.0.0")], keep: nil))
        #expect(ReleaseFeedAnswer.of(status: 429, headers: ["Retry-After": "60"], body: Data(), cached: nil, nowMs: 1_000)
            == .wait(reason: "GitHub asked Octo to wait", retryAt: 61_000))
        #expect(ReleaseFeedAnswer.of(status: 403, headers: ["X-RateLimit-Remaining": "0", "X-RateLimit-Reset": "99"], body: Data(), cached: nil, nowMs: 0)
            == .wait(reason: "GitHub asked Octo to wait", retryAt: 99_000))
        #expect(ReleaseFeedAnswer.of(status: 500, headers: [:], body: Data(), cached: nil, nowMs: 0) == .wait(reason: "GitHub answered 500", retryAt: nil))
        #expect(ReleaseFeedAnswer.of(status: 200, headers: [:], body: Data("<html>".utf8), cached: nil, nowMs: 0)
            == .wait(reason: "GitHub's answer was not readable", retryAt: nil))
        #expect(ReleaseFeedAnswer.of(status: nil, headers: [:], body: Data(), cached: nil, nowMs: 0) == .wait(reason: "GitHub could not be reached", retryAt: nil))
        #expect(releasesURL().absoluteString == "https://api.github.com/repos/winters27/octo/releases?per_page=100")
    }
}
