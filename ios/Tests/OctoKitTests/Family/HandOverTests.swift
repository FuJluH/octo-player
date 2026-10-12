import Foundation
import Testing
@testable import OctoKit

/// A clock the tests move by hand, read from any thread.
final class HandOverClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Int64
    init(_ now: Int64) { value = now }
    var now: Int64 {
        get { lock.withLock { value } }
        set { lock.withLock { value = newValue } }
    }
}

/// Signing in on another device of one's own: the sealed box, the signed-in device's side
/// (renewing, asking, nothing sent before Allow) and the new device's side (the key never
/// leaves it).
@MainActor
@Suite struct HandOverTests {
    let start = epochMs("2026-10-20T18:00:00Z")!
    let signIn = HandOverSignIn(username: "alex", secret: "secret", mode: "Token", server: "https://music.example.com",
                                home: "http://192.168.1.20:4533", displayName: "Alex")

    @Test func theCipherMatchesItsPublishedExamples() throws {
        func hex(_ text: String) -> [UInt8] {
            stride(from: 0, to: text.count, by: 2).map { i in
                UInt8(text[text.index(text.startIndex, offsetBy: i)..<text.index(text.startIndex, offsetBy: i + 2)], radix: 16)!
            }
        }
        func text(_ bytes: [UInt8]) -> String { bytes.map { String(format: "%02x", $0) }.joined() }
        // RFC 8439 2.5.2.
        #expect(text(Poly1305.tag(message: Array("Cryptographic Forum Research Group".utf8),
                                  key: hex("85d6be7857556d337f4452fe42d506a80103808afb0db2fd4abff6af4149f51b")))
            == "a8061dc1305136c6c22b8baf0c0127a9")
        // XChaCha draft 2.2.1, HChaCha20.
        #expect(text(ChaCha20.hChaCha(key: hex("000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"),
                                      nonce: hex("000000090000004a0000000031415927")))
            == "82413b4227b27bfed30e42508a877d73a0f9e4d58a74a853c12ec41326d3ecdc")
        // XChaCha draft A.3.1, XChaCha20-Poly1305.
        let plain = Array("Ladies and Gentlemen of the class of '99: If I could offer you only one tip for the future, sunscreen would be it.".utf8)
        let sealed = try XChaCha20Poly1305.seal(plain, key: hex("808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9f"),
                                                nonce: hex("404142434445464748494a4b4c4d4e4f5051525354555657"), aad: hex("50515253c0c1c2c3c4c5c6c7"))
        #expect(text(Array(sealed.suffix(16))) == "c0875924c1c7987947deafd8780acf49")
        #expect(text(Array(sealed.prefix(16))) == "bd6d179d3e83d43b9576579493c0e939")
        let opened = try XChaCha20Poly1305.open(sealed, key: hex("808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9f"),
                                                nonce: hex("404142434445464748494a4b4c4d4e4f5051525354555657"), aad: hex("50515253c0c1c2c3c4c5c6c7"))
        #expect(opened == plain)
    }

    @Test func aSealedSignInOpensWithItsKey() throws {
        let key = HandOverBox.newKey()
        #expect(key.count == 43)
        let box = try HandOverBox.seal(signIn, key: key)
        #expect(!box.contains("secret"))
        #expect(try HandOverBox.open(box, key: key) == signIn)
        #expect(try box != HandOverBox.seal(signIn, key: key))
        #expect(!signIn.description.contains("secret"))
    }

    @Test func aWrongKeyFailsCleanly() throws {
        let box = try HandOverBox.seal(signIn, key: HandOverBox.newKey())
        #expect(throws: HandOverError(message: "This sign-in could not be opened here. Make a new QR code on your other device.")) {
            _ = try HandOverBox.open(box, key: HandOverBox.newKey())
        }
        let key = HandOverBox.newKey()
        let sealed = try HandOverBox.seal(signIn, key: key)
        let changed = String(sealed.dropLast(2)) + (sealed.hasSuffix("AA") ? "BB" : "AA")
        for bad in [changed, "not a box", ""] {
            #expect(throws: HandOverError.self) { _ = try HandOverBox.open(bad, key: key) }
        }
        #expect(throws: HandOverError(message: "This sign-in link is not complete. Scan the QR code again.")) {
            _ = try HandOverBox.open(sealed, key: "c2hvcnQ")
        }
        #expect(throws: HandOverError(message: "The sign-in from your other device is damaged.")) {
            _ = try HandOverBox.open("not a box", key: key)
        }
    }

    func answerStarts(_ fake: FamilyFake, _ clock: HandOverClock) {
        fake.answer("startFamilySignIn") { _ in
            let n = fake.called("startFamilySignIn").count
            let expires = ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: Double(clock.now + 120_000) / 1_000))
            return #""familySignIn":{"token":"tok_\#(n)","expires":"\#(expires)","links":{"anywhere":"https://music.example.com/family/signin","home":"http://192.168.1.20:4533/family/signin"},"servers":{"anywhere":"https://music.example.com","home":"http://192.168.1.20:4533"},"anywhereAvailable":true}"#
        }
    }

    func pending(_ fake: FamilyFake, _ device: String?) {
        fake.answer("getFamilySignInPending") { _ in device.map { #""familySignInPending":\#($0)"# } ?? "" }
    }

    func source(_ fake: FamilyFake, _ clock: HandOverClock) -> HandOverSource {
        let client = fake.client()
        return HandOverSource(client: { client }, displayName: { "Alex" }, mainAddress: { URL(string: "https://music.example.com") },
                              clock: { clock.now }, tickMs: 10, askEveryMs: 20)
    }

    @Test func theSignedInDeviceSendsNothingBeforeAllow() async throws {
        let fake = FamilyFake()
        let clock = HandOverClock(start)
        answerStarts(fake, clock)
        pending(fake, nil)
        fake.answer("decideFamilySignIn") { _ in #""familySignInDecided":{"state":"Allowed"}"# }
        fake.answer("putFamilySignInBox") { _ in "" }
        let source = source(fake, clock)
        source.open()
        #expect(await until("code") { source.sheet?.start != nil })
        let sheet = try #require(source.sheet)
        #expect(sheet.start?.token == "tok_1")
        let link = try #require(sheet.options(awayAllowed: true, username: "alex")?.linkFor(.anywhere))
        #expect(link.hasPrefix("https://music.example.com/family/signin#t=tok_1&k="))
        #expect(link.hasSuffix("&s=https%3A%2F%2Fmusic.example.com&h=http%3A%2F%2F192.168.1.20%3A4533&u=alex"))
        let atHome = try #require(sheet.options(awayAllowed: true)?.linkFor(.home))
        #expect(atHome.hasPrefix("http://192.168.1.20:4533/family/signin#t=tok_1&k="))
        #expect(atHome.contains("&s=http%3A%2F%2F192.168.1.20%3A4533"))
        if case .handOver(let parsed)? = parseFamilyLink(link) { #expect(parsed.key == sheet.key) } else { Issue.record("not a hand-over") }

        pending(fake, #"{"id":"r_1","deviceName":"Pixel 9","platform":"Android"}"#)
        #expect(await until("asking") { source.sheet?.asking != nil })
        #expect(askingTitle(try #require(source.sheet?.asking)) == "Sign in on Pixel 9?")
        await settle()
        #expect(fake.called("decideFamilySignIn").isEmpty)
        #expect(fake.called("putFamilySignInBox").isEmpty)

        source.allow()
        #expect(await until("sent") { source.sheet?.done != nil })
        #expect(source.sheet?.done == "Sent to Pixel 9. It's signing in now.")
        let decide = try #require(fake.called("decideFamilySignIn").first)
        #expect(decide.query["allow"] == "true")
        let boxCall = try #require(fake.called("putFamilySignInBox").first)
        let order = fake.calls.map(\.endpoint)
        #expect(order.firstIndex(of: "decideFamilySignIn")! < order.firstIndex(of: "putFamilySignInBox")!)
        let field = boxCall.text.components(separatedBy: "&").first { $0.hasPrefix("box=") } ?? ""
        let box = String(field.dropFirst(4)).removingPercentEncoding ?? ""
        #expect(try HandOverBox.open(box, key: sheet.key) == signIn)
        for call in fake.calls {
            #expect(!call.url.absoluteString.contains(sheet.key))
            #expect(!call.text.contains(sheet.key))
            #expect(!call.text.contains("secret"))
        }
    }

    @Test func denyingTellsTheServerAndShowsAFreshCode() async throws {
        let fake = FamilyFake()
        let clock = HandOverClock(start)
        answerStarts(fake, clock)
        pending(fake, #"{"id":"r_1","deviceName":"Someone's laptop","platform":"Windows"}"#)
        fake.answer("decideFamilySignIn") { _ in #""familySignInDecided":{"state":"Allowed"}"# }
        let source = source(fake, clock)
        source.open()
        #expect(await until("asking") { source.sheet?.asking != nil })
        let first = try #require(source.sheet?.key)
        pending(fake, nil)
        source.deny()
        #expect(await until("fresh code") { source.sheet?.start?.token == "tok_2" && source.sheet?.loading == false })
        #expect(fake.called("decideFamilySignIn").first?.query["allow"] == "false")
        #expect(fake.called("putFamilySignInBox").isEmpty)
        #expect(source.sheet?.key != first)
        #expect(source.sheet?.asking == nil)
        #expect(source.sheet?.renewed == 1)
    }

    @Test func theCodeRenewsBeforeItExpiresPausesWhenHiddenAndStopsAfterTenMinutes() async throws {
        let fake = FamilyFake()
        let clock = HandOverClock(start)
        answerStarts(fake, clock)
        pending(fake, nil)
        let source = source(fake, clock)
        source.open()
        #expect(await until("code") { source.sheet?.start != nil })
        let firstKey = try #require(source.sheet?.key)
        let expires = try #require(expiresAtMs(source.sheet?.start?.expires))

        source.sheetOnScreen(false)
        await settle()
        clock.now = expires + 10_000
        await settle()
        #expect(fake.called("startFamilySignIn").count == 1)
        source.sheetOnScreen(true)
        #expect(await until("renewed on return") { source.sheet?.renewed == 1 })
        #expect(source.sheet?.key != firstKey)

        while clock.now - start < HandOverText.forMs {
            let renewals = source.sheet?.renewed ?? 0
            clock.now = (expiresAtMs(source.sheet?.start?.expires) ?? clock.now) - 1_000
            _ = await until("renewal") { source.sheet?.renewed == renewals + 1 || source.sheet?.stale == true }
            if source.sheet?.stale == true { break }
        }
        clock.now = (expiresAtMs(source.sheet?.start?.expires) ?? clock.now) - 1_000
        #expect(await until("asks instead") { source.sheet?.stale == true })
        let made = fake.called("startFamilySignIn").count
        await settle()
        #expect(fake.called("startFamilySignIn").count == made)
        source.newCode()
        #expect(await until("new code") { source.sheet?.stale == false && fake.called("startFamilySignIn").count == made + 1 })
    }

    @Test func theNewDeviceNeverSendsTheKey() async throws {
        let fake = FamilyFake()
        let link = FamilyHandOverLink(base: fake.url.absoluteString, token: "tok_9", key: HandOverBox.newKey(), server: "https://music.example.com",
                                      home: "http://192.168.1.20:4533")
        let box = try HandOverBox.seal(signIn, key: link.key)
        fake.answer("redeemFamilySignIn") { _ in #""familySignInRedeemed":{"id":"r_1"}"# }
        fake.answer("getFamilySignInRedeem") { _ in
            fake.called("getFamilySignInRedeem").count < 2 ? #""familySignInRedeem":{"state":"Waiting"}"#
                : #""familySignInRedeem":{"state":"Allowed","box":"\#(box)"}"#
        }
        let steps = StepLog()
        let result = await receiveHandOver(link, session: FakeServer.session, deviceName: "Pixel 9", platform: .android,
                                           step: { await steps.add($0) }, pollMs: 10)
        #expect(result == .received(signIn))
        #expect(await steps.all == [handOverWaiting, handOverAllowed])
        let redeem = try #require(fake.called("redeemFamilySignIn").first)
        #expect(redeem.query["token"] == "tok_9")
        #expect(redeem.query["deviceName"] == "Pixel 9")
        #expect(redeem.query["platform"] == "Android")
        for call in fake.calls {
            #expect(!call.url.absoluteString.contains(link.key))
            #expect(!call.url.absoluteString.contains("#"))
            #expect(!call.text.contains(link.key))
        }
    }

    @Test func aDeniedOrExpiredHandOverSaysSo() async {
        let fake = FamilyFake()
        let link = FamilyHandOverLink(base: fake.url.absoluteString, token: "tok_9", key: HandOverBox.newKey(), server: "https://music.example.com")
        fake.answer("redeemFamilySignIn") { _ in #""familySignInRedeemed":{"id":"r_1"}"# }
        fake.answer("getFamilySignInRedeem") { _ in #""familySignInRedeem":{"state":"Denied"}"# }
        #expect(await receiveHandOver(link, session: FakeServer.session, deviceName: "Pixel 9", platform: .android, pollMs: 10) == .refused(handOverDenied))
        fake.answer("getFamilySignInRedeem") { _ in #""familySignInRedeem":{"state":"Expired"}"# }
        #expect(await receiveHandOver(link, session: FakeServer.session, deviceName: "Pixel 9", platform: .android, pollMs: 10) == .refused(handOverExpired))
        fake.answer("getFamilySignInRedeem") { _ in #""familySignInRedeem":{"state":"Waiting"}"# }
        #expect(await receiveHandOver(link, session: FakeServer.session, deviceName: "Pixel 9", platform: .android, pollMs: 10, waitMs: 50)
            == .refused(handOverExpired))
        fake.fail("redeemFamilySignIn", 40, "That sign-in code has been used or has expired.")
        #expect(await receiveHandOver(link, session: FakeServer.session, deviceName: "Pixel 9", platform: .android, pollMs: 10) == .refused(handOverExpired))
        let gone = FakeServer()
        gone.close()
        let unreachable = FamilyHandOverLink(base: gone.base.absoluteString, token: "t", key: "k", server: "https://x")
        #expect(await receiveHandOver(unreachable, session: FakeServer.session, deviceName: "P", platform: .iOS) == .refused(handOverUnreachable))
        #expect(await receiveHandOver(FamilyHandOverLink(base: "not an address", token: "t", key: "k", server: "x"), session: FakeServer.session,
                                      deviceName: "P", platform: .iOS) == .refused("This sign-in link has no server in it. Scan the QR code again."))
    }

    @Test func aBoxSealedWithAnotherKeyIsRefused() async throws {
        let fake = FamilyFake()
        let link = FamilyHandOverLink(base: fake.url.absoluteString, token: "tok_9", key: HandOverBox.newKey(), server: "https://music.example.com")
        let other = try HandOverBox.seal(signIn, key: HandOverBox.newKey())
        fake.answer("redeemFamilySignIn") { _ in #""familySignInRedeemed":{"id":"r_1"}"# }
        fake.answer("getFamilySignInRedeem") { _ in #""familySignInRedeem":{"state":"Allowed","box":"\#(other)"}"# }
        #expect(await receiveHandOver(link, session: FakeServer.session, deviceName: "Pixel 9", platform: .android, pollMs: 10)
            == .refused("This sign-in could not be opened here. Make a new QR code on your other device."))
    }
}

actor StepLog {
    private(set) var all: [String] = []
    func add(_ step: String) { all.append(step) }
}

/// The Family view's state, against a pretend server with Family on.
@MainActor
@Suite struct FamilyModelTests {
    final class Flags: @unchecked Sendable {
        var supported = true
        var answered: [FamilyRequest] = []
    }

    func model(_ fake: FamilyFake, _ flags: Flags = Flags()) -> FamilyModel {
        let client = fake.client()
        return FamilyModel(client: { client }, supported: { flags.supported }, answered: { flags.answered.append($0) }, pollMs: 60_000)
    }

    @Test func aListenerSeesTheirPlanRequestsDevicesAndSaved() async throws {
        let fake = FamilyFake()
        fake.answer("getFamilyRequests") { _ in #""familyRequests":{"request":[\#(FamilyFake.request("r1")),\#(FamilyFake.request("r2", state: "Done", outcome: "AlreadyShared"))]}"# }
        fake.answer("getFamilyDevices") { _ in #""familyDevices":{"device":[{"id":"d_1","username":"alex","name":"Pixel 9","kind":"OctoApp","app":"Octo 1.6 (Android)","place":"Away","playing":null,"current":true}]}"# }
        fake.answer("getStarred2") { _ in #""starred2":{"song":[{"id":"ext-deezer-song-1","title":"Found","isExternal":true},{"id":"tr-1","title":"Mine"}],"album":[{"id":"ext-deezer-album-2","name":"Found album","isExternal":true}]}"# }
        let model = model(fake)
        await model.refresh()
        #expect(planTitle(try #require(model.me)) == "Alex, Listener")
        #expect(!model.manages)
        #expect(model.sections() == [.plan, .saved, .requests, .devices])
        #expect(model.requests.map(\.id) == ["r1", "r2"])
        #expect(requestStateLine(model.requests[1]) == "Already in the family library")
        #expect(model.devices.first?.name == "Pixel 9")
        #expect(model.saved.songs.map(\.id) == ["ext-deezer-song-1"])
        #expect(model.saved.albums.map(\.id) == ["ext-deezer-album-2"])
        #expect(!fake.called("getFamilyRequests").contains { $0.query["all"] == "true" })
    }

    @Test func aManagerAlsoSeesMembersAndTheInbox() async throws {
        let fake = FamilyFake()
        fake.answer("getFamily") { _ in
            #""family":{"me":\#(FamilyFake.me(role: "Owner", addToLibrary: "Direct", approveRequests: true, manageFamily: true, managed: false)),"manager":{"members":[{"username":"alex","displayName":"Alex","role":"Listener","suspended":false,"devices":2,"playingNow":true,"pendingRequests":1,"storageUsedBytes":5400000000,"storageLimitGb":10}],"pendingRequests":1,"liveStreams":1}}"#
        }
        fake.answer("getFamilyRequests") { call in
            call.query["all"] == "true" ? #""familyRequests":{"request":[\#(FamilyFake.request("r9"))]}"# : #""familyRequests":{}"#
        }
        let model = model(fake)
        await model.refresh()
        #expect(model.manages)
        #expect(model.sections() == FamilySection.allCases.filter { $0 != .login })
        #expect(memberLine(try #require(model.info?.manager?.members.first)) == "Listener · 2 devices · Playing now · 1 request waiting")
        #expect(model.inbox.map(\.id) == ["r9"])
        #expect(fake.called("getFamilyRequests").first { $0.query["all"] == "true" }?.query["state"] == "Pending")

        fake.answer("decideFamilyRequest") { _ in #""familyRequest":\#(FamilyFake.request("r9", state: "Approved"))"# }
        model.approve("r9", note: "Enjoy")
        #expect(await until("approved") { model.said == "Approved Song · Artist" })
        #expect(fake.called("decideFamilyRequest").first?.query["approve"] == "true")
        #expect(fake.called("decideFamilyRequest").first?.query["note"] == "Enjoy")
        model.decline("r9")
        #expect(await until("declined") { fake.called("decideFamilyRequest").count == 2 })
        #expect(fake.called("decideFamilyRequest")[1].query["approve"] == "false")
    }

    @Test func aRequestTheFamilyAlreadyHasComesBackDone() async {
        let fake = FamilyFake()
        fake.answer("requestCopy") { _ in #""familyRequest":\#(FamilyFake.request("r5", state: "Done", outcome: "AddedFromFamily"))"# }
        let flags = Flags()
        let model = model(fake, flags)
        let made = await model.request("ext-deezer-song-5", quality: .flac)
        #expect(made?.outcome == .addedFromFamily)
        #expect(model.said == "Added from the family library")
        #expect(fake.called("requestCopy").first?.query["quality"] == "Flac")
        #expect(flags.answered.map(\.id) == ["r5"])
        #expect(model.requests.first?.id == "r5")
    }

    @Test func aRefusedRequestSaysWhyInTheServersWords() async {
        let fake = FamilyFake()
        fake.fail("requestCopy", 50, "You have used all 10 requests this week.")
        let model = model(fake)
        #expect(await model.request("ext-deezer-song-5", quality: .best) == nil)
        #expect(model.said == "You have used all 10 requests this week.")
        #expect(!model.working)
    }

    @Test func cancellingAndRemovingADeviceFromTheList() async {
        let fake = FamilyFake()
        fake.answer("cancelFamilyRequest") { _ in #""familyRequest":\#(FamilyFake.request("r1", state: "Cancelled"))"# }
        let model = model(fake)
        model.cancel("r1")
        #expect(await until("cancelled") { model.said == "Request cancelled" })
        fake.answer("forgetFamilyDevice") { _ in "" }
        model.forget(device: FamilyDevice(id: "d_2", name: "Symfonium"))
        #expect(await until("removed") { model.said == "Symfonium is off the list" })
        #expect(fake.called("forgetFamilyDevice").first?.query["id"] == "d_2")
        model.forget(device: FamilyDevice(id: "d_3", name: " "))
        #expect(await until("removed blank") { model.said == "The device is off the list" })
    }

    @Test func theLoginIsReadForTheYourLoginCard() async {
        let fake = FamilyFake()
        fake.answer("getFamilyLogin") { _ in #""familyLogin":{"username":"alex","servers":{"anywhere":"https://music.example.com","home":"http://192.168.1.20:4533"},"anywhereAvailable":true,"awayAllowed":true}"# }
        let model = model(fake)
        await model.refresh()
        #expect(model.login?.username == "alex")
        #expect(model.sections().first == .login)
        model.forget()
        #expect(model.login == nil)
    }

    @Test func removingASharedSongShowsTheServersReason() async {
        let fake = FamilyFake()
        fake.fail("removeFromMyLibrary", 50, "This song is in the shared library.")
        let model = model(fake)
        model.removeFromMyLibrary("tr-1", title: "Song")
        #expect(await until("refused") { model.said == "This song is in the shared library." })
        fake.answer("removeFromMyLibrary") { _ in "" }
        model.removeFromMyLibrary("tr-2", title: "Other song")
        #expect(await until("removed") { model.said == "Removed Other song from your library" })
    }

    @Test func aManagerAddsAMemberAndSeesTheirInviteAsAQrCode() async {
        let fake = FamilyFake()
        fake.raw("members") { _ in #"{"member":{"username":"sam","displayName":"Sam","role":"Kid"},"inviteLink":"https://music.example.com/family/join#invite=t9"}"# }
        fake.raw("sam") { _ in #"{"username":"sam"}"# }
        let model = model(fake)
        model.addMember(username: "sam", displayName: "Sam", preset: .kid)
        #expect(await until("invite shown") { model.invite != nil })
        #expect(model.invite?.title == "Invite Sam")
        #expect(model.invite?.url == "https://music.example.com/family/join#invite=t9")
        #expect(await until("said") { model.said == "Added Sam" })
        let call = fake.called("members").first
        #expect(call?.query["u"] == "alex")
        #expect(call?.query["p"] == nil)
        model.closeInvite()
        #expect(model.invite == nil)
    }

    @Test func aMemberKeptHomeGetsOnlyTheHomeLinkOnReset() async {
        let fake = FamilyFake()
        fake.raw("members") { _ in #"{"member":{"username":"sam","displayName":"Sam"},"inviteLink":"https://x/family/join#invite=t","links":{"anywhere":"https://x/family/join#invite=t","home":"http://h/family/join#invite=t"}}"# }
        fake.raw("sam") { _ in #"{"username":"sam"}"# }
        fake.raw("reset") { _ in #"{"inviteLink":"https://x/family/join#invite=r","links":{"anywhere":"https://x/family/join#invite=r","home":"http://h/family/join#invite=r"}}"# }
        let model = model(fake)
        model.addMember(username: "sam", displayName: "Sam", preset: .member, away: false)
        #expect(await until("invite") { model.invite != nil })
        #expect(model.invite?.awayAllowed == false)
        #expect(model.invite?.options.choosable == false)
        model.closeInvite()
        model.resetPassword(FamilyMember(username: "sam", displayName: "Sam"))
        #expect(await until("reset") { model.invite?.reset == true })
        #expect(model.invite?.awayAllowed == false)
        #expect(model.invite?.options.linkFor(.anywhere) == "http://h/family/join#invite=r")
    }

    @Test func aManagerResetsAPasswordAndGetsANewSignInLink() async {
        let fake = FamilyFake()
        fake.raw("reset") { _ in #"{"inviteLink":"https://music.example.com/family/join#invite=r1","expires":"2026-10-27T18:00:00Z"}"# }
        let model = model(fake)
        model.resetPassword(FamilyMember(username: "sam", displayName: "Sam"))
        #expect(await until("link shown") { model.invite != nil })
        #expect(model.invite?.title == "New sign-in link for Sam")
        #expect(model.invite?.url == "https://music.example.com/family/join#invite=r1")
        #expect(await until("said") { model.said == "Sam's password no longer works" })
        model.sendNewLink()
        #expect(await until("second link") { fake.called("reset").count == 2 })
        #expect(fake.called("invite").isEmpty)
    }

    @Test func aFailedNewLinkSaysSoInTheSheet() async {
        let fake = FamilyFake()
        fake.raw("members") { _ in #"{"member":{"username":"sam","displayName":"Sam"},"inviteLink":"https://x/family/join#invite=t"}"# }
        fake.raw("sam") { _ in #"{"username":"sam"}"# }
        fake.raw("invite") { _ in nil }
        let model = model(fake)
        model.addMember(username: "sam", displayName: "", preset: .member)
        #expect(await until("invite") { model.invite != nil })
        model.sendNewLink()
        #expect(await until("failed") { model.invite?.error == "Couldn't make a new link. Try again." && model.invite?.loading == false })
    }

    @Test func withoutTheExtensionNothingIsAsked() async {
        let fake = FamilyFake()
        let flags = Flags()
        flags.supported = false
        let model = model(fake, flags)
        await model.refresh()
        #expect(model.info == nil)
        #expect(await model.plan() == nil)
        #expect(fake.calls.isEmpty)
    }

    @Test func thePlanIsReadOnceForTheRestOfTheApp() async {
        let fake = FamilyFake()
        let model = model(fake)
        #expect(await model.plan() != nil)
        _ = await model.plan()
        #expect(fake.called("getFamily").count == 1)
        model.forget()
        #expect(model.info == nil)
    }

    @Test func aServerOutOfReachSaysSo() async {
        let fake = FamilyFake()
        fake.close()
        let model = model(fake)
        await model.refresh()
        #expect(model.problem == "Octo can't reach the server right now.")
    }

    @Test func theSheetLinesFollowTheAnswer() {
        #expect(requestAnswerLine(FamilyRequest(state: .pending)) == "Requested. You'll hear when it's decided")
        #expect(requestAnswerLine(FamilyRequest(state: .done, outcome: .alreadyShared)) == "Already in the family library")
        #expect(requestAnswerLine(FamilyRequest(state: .done, outcome: .downloaded)) == "Downloaded")
        #expect(requestAnswerLine(FamilyRequest(state: .approved)) == "Approved. Getting it now")
    }
}
