import Foundation
import Testing
@testable import ShareInbox

/// What "Share to Octo" leaves for the app, and the group the two share.
@Suite struct ShareInboxTests {
    func inbox() -> ShareInbox {
        ShareInbox(directory: FileManager.default.temporaryDirectory.appendingPathComponent("octo-inbox-" + UUID().uuidString))
    }

    @Test func aShareIsTakenOnce() throws {
        let inbox = inbox()
        defer { try? FileManager.default.removeItem(at: inbox.directory) }
        #expect(!inbox.waiting)
        #expect(inbox.take() == nil)
        try inbox.put(.text("Massive Attack - Angel\nMGMT - Kids", subject: "Road trip"))
        #expect(inbox.waiting)
        let taken = try #require(inbox.take())
        #expect(taken.drop == ShareDrop(kind: .text, text: "Massive Attack - Angel\nMGMT - Kids", name: "Road trip"))
        #expect(taken.bytes == nil)
        #expect(inbox.take() == nil)
        #expect(!inbox.waiting)
    }

    @Test func aFileKeepsItsBytesNameAndType() throws {
        let inbox = inbox()
        defer { try? FileManager.default.removeItem(at: inbox.directory) }
        let bytes = Data("Track name,Artist name\nAngel,Massive Attack\n".utf8)
        try inbox.put(.file(name: "Liked.csv", type: "text/csv"), bytes: bytes)
        let taken = try #require(inbox.take())
        #expect(taken.drop.kind == .file)
        #expect(taken.drop.name == "Liked.csv")
        #expect(taken.drop.type == "text/csv")
        #expect(taken.bytes == bytes)
    }

    @Test func aNewerShareReplacesOneWaiting() throws {
        let inbox = inbox()
        defer { try? FileManager.default.removeItem(at: inbox.directory) }
        try inbox.put(.file(name: "Old.csv", type: "text/csv"), bytes: Data("a,b\n".utf8))
        try inbox.put(.text("https://open.spotify.com/playlist/37i9", subject: nil))
        let taken = try #require(inbox.take())
        #expect(taken.drop.text == "https://open.spotify.com/playlist/37i9")
        #expect(taken.bytes == nil)
    }

    @Test func aFileIsReadUpToTheLimitAndNoFurther() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("octo-share-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        try Data(repeating: 65, count: 10).write(to: file)
        #expect(ShareInbox.read(file, limit: 10)?.bytes.count == 10)
        #expect(ShareInbox.read(file, limit: 10)?.tooBig == false)
        #expect(ShareInbox.read(file, limit: 9)?.tooBig == true)
        #expect(ShareInbox.read(file.appendingPathExtension("gone")) == nil)
    }

    @Test func theGroupFollowsHowTheBuildWasSigned() {
        #expect(OctoAppGroup.fromBundleID("XTL-1A2B3C4D.app.winters.octo") == "group.XTL-1A2B3C4D.app.winters.octo")
        #expect(OctoAppGroup.fromBundleID("XTL-1A2B3C4D.app.winters.octo.share") == "group.XTL-1A2B3C4D.app.winters.octo")
        #expect(OctoAppGroup.fromBundleID("app.winters.octo") == "group.app.winters.octo")
        #expect(OctoAppGroup.fromBundleID(nil) == "group.app.winters.octo")
    }

    @Test func theProfilesGroupWins() {
        func profile(_ groups: [String]) -> Data {
            let entitlements = groups.isEmpty ? "" : "<key>com.apple.security.application-groups</key><array>"
                + groups.map { "<string>\($0)</string>" }.joined() + "</array>"
            let plist = #"<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>Entitlements</key><dict>"#
                + entitlements + "</dict></dict></plist>"
            return Data([0x30, 0x82, 0x01]) + Data(plist.utf8) + Data([0x00, 0xA0])
        }
        let signed = profile(["group.XTL-9F00AA11.app.winters.octo"])
        #expect(OctoAppGroup.signed(profile: signed, bundleID: "app.winters.octo") == "group.XTL-9F00AA11.app.winters.octo")
        #expect(OctoAppGroup.signed(profile: profile([]), bundleID: "XTL-1A2B3C4D.app.winters.octo") == "group.XTL-1A2B3C4D.app.winters.octo")
        #expect(OctoAppGroup.signed(profile: Data("not a profile".utf8), bundleID: nil) == "group.app.winters.octo")
        #expect(OctoAppGroup.signed(profile: nil, bundleID: nil) == OctoAppGroup.name)
    }
}
