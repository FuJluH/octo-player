import Foundation
import Testing
@testable import OctoKit

/// Fixtures shaped like an Octo server's answers.
enum FamilyFixtures {
    static let listener = #"{ "subsonic-response": { "status": "ok", "version": "1.16.1", "type": "octo", "openSubsonic": true, "family": { "me": { "username": "alex", "displayName": "Alex", "role": "Listener", "managed": true, "abilities": { "addToLibrary": "Request", "requestQuality": "Best", "autoApprove": false, "weeklyRequestLimit": 10, "streamCap": 192, "awayCap": 128, "away": true, "devicesAtOnce": 2, "downloadFiles": false, "offlineCopies": false, "share": false, "importPlaylists": true, "cleanOnly": false, "familyPlaylistsEdit": true, "manageFamily": false, "approveRequests": false, "storageLimitGb": 10, "instantFromFamily": true }, "requestsThisWeek": 3, "storageUsedBytes": 5400000000, "place": "Home", "deviceId": "d_7Qm2abc", "quality": { "home": "Original", "away": "Standard", "familyLimitKbps": 192, "familyAwayLimitKbps": 128 } } } } }"#
    static let owner = #"{ "subsonic-response": { "status": "ok", "version": "1.16.1", "type": "octo", "openSubsonic": true, "family": { "me": { "username": "jordan", "displayName": "Jordan", "role": "Owner", "managed": false, "abilities": { "addToLibrary": "Direct", "requestQuality": "Best", "autoApprove": true, "weeklyRequestLimit": 0, "streamCap": 0, "awayCap": 0, "away": true, "devicesAtOnce": 0, "downloadFiles": true, "offlineCopies": true, "share": true, "importPlaylists": true, "cleanOnly": false, "familyPlaylistsEdit": true, "manageFamily": true, "approveRequests": true, "storageLimitGb": 0, "instantFromFamily": true }, "requestsThisWeek": 0, "storageUsedBytes": 0, "place": "Away", "deviceId": null }, "manager": { "members": [ { "username": "alex", "displayName": "Alex", "role": "Listener", "suspended": false, "devices": 2, "playingNow": true, "pendingRequests": 1, "storageUsedBytes": 5400000000, "storageLimitGb": 10 }, { "username": "sam", "displayName": "Sam", "role": "Kid", "suspended": true, "devices": 0, "playingNow": false, "pendingRequests": 0, "storageUsedBytes": 0, "storageLimitGb": 5 } ], "pendingRequests": 1, "liveStreams": 3 } } } }"#
    static let future = #"{ "subsonic-response": { "status": "ok", "version": "1.16.1", "type": "octo", "openSubsonic": true, "family": { "me": { "username": "zoe", "displayName": "Zoe", "role": "Guest", "managed": true, "abilities": { "addToLibrary": "Borrow", "requestQuality": "Hires", "newAbility": true }, "place": "Moon", "deviceId": "d_1", "extra": { "a": 1 } } } } }"#
    static let requests = #"{ "subsonic-response": { "status": "ok", "version": "1.16.1", "type": "octo", "openSubsonic": true, "familyRequests": { "request": [ { "id": "r_9xK2", "username": "alex", "displayName": "Alex", "kind": "Song", "target": "ext-deezer-song-12345", "title": "Song", "artist": "Artist", "album": "Album", "coverArt": "ext-deezer-song-12345", "quality": "Flac", "state": "Pending", "created": "2026-10-20T18:00:00Z", "decided": null, "decidedBy": null, "note": "", "failure": null, "librarySongId": null, "outcome": null }, { "id": "r_2", "username": "alex", "displayName": "Alex", "kind": "Album", "target": "ext-deezer-song-12345", "title": "Album", "artist": "Artist", "album": "Album", "coverArt": null, "quality": "Best", "state": "Done", "created": "2026-10-20T18:00:00Z", "decided": "2026-10-20T18:05:00Z", "decidedBy": "jordan", "note": "", "failure": null, "librarySongId": "tr-77", "outcome": "AddedFromFamily" }, { "id": "r_3", "username": "alex", "displayName": "Alex", "kind": "Song", "target": "ext-deezer-song-12345", "title": "Song", "artist": "Artist", "album": "Album", "coverArt": "ext-deezer-song-12345", "quality": "Mp3", "state": "Declined", "created": "2026-10-20T18:00:00Z", "decided": "2026-10-21T09:00:00Z", "decidedBy": "jordan", "note": "We have the live one", "failure": null, "librarySongId": null, "outcome": null }, { "id": "r_4", "username": "alex", "displayName": "Alex", "kind": "Song", "target": "ext-deezer-song-12345", "title": "Song", "artist": "Artist", "album": "Album", "coverArt": "ext-deezer-song-12345", "quality": "Flac", "state": "Failed", "created": "2026-10-20T18:00:00Z", "decided": null, "decidedBy": null, "note": "", "failure": "No real FLAC copy found", "librarySongId": null, "outcome": null } ] } } }"#
    static let requestsEmpty = #"{ "subsonic-response": { "status": "ok", "version": "1.16.1", "type": "octo", "openSubsonic": true, "familyRequests": {} } }"#
    static let devices = #"{ "subsonic-response": { "status": "ok", "version": "1.16.1", "type": "octo", "openSubsonic": true, "familyDevices": { "device": [ { "id": "d_7Qm2abc", "username": "alex", "name": "Pixel 9", "app": "Octo 1.6 (Android)", "firstSeen": "2026-10-19T10:00:00Z", "lastSeen": "2026-10-20T18:00:00Z", "place": "Away", "playing": { "songId": "tr-9", "title": "Song", "artist": "Artist" }, "current": true, "quality": "App" }, { "id": "d_2", "username": "alex", "name": "Symfonium", "app": "Symfonium", "firstSeen": "2026-10-19T10:00:00Z", "lastSeen": "2026-10-19T11:00:00Z", "place": "Home", "playing": null, "current": false } ] } } }"#
    static let login = #"{ "subsonic-response": { "status": "ok", "version": "1.16.1", "type": "octo", "openSubsonic": true, "familyLogin": { "username": "alex", "servers": { "anywhere": "https://music.example.com", "home": "http://192.168.1.20:4533" }, "anywhereAvailable": true, "awayAllowed": false } } }"#
    static func request(_ state: String, outcome: String? = nil, id: String = "r_9xK2", note: String = "") -> String {
        #"{ "subsonic-response": { "status": "ok", "version": "1.16.1", "familyRequest": { "id": "\#(id)", "username": "alex", "kind": "Song", "target": "ext-deezer-song-12345", "title": "Song", "artist": "Artist", "quality": "Flac", "state": "\#(state)", "note": "\#(note)", "outcome": \#(outcome.map { "\"\($0)\"" } ?? "null") } } }"#
    }
    static let extensionsFamily = #"{ "subsonic-response": { "status": "ok", "version": "1.16.1", "type": "octo", "openSubsonic": true, "openSubsonicExtensions": [ { "name": "octoAcquisitions", "versions": [ 1, 2 ] }, { "name": "octoFamily", "versions": [ 1 ] } ] } }"#
    static let extensionsOcto = #"{"subsonic-response":{"status":"ok","version":"1.16.1","type":"octo","openSubsonic":true,"openSubsonicExtensions":[{"name":"songLyrics","versions":[1,2]},{"name":"octoAcquisitions","versions":[1]}]}}"#
    static let sharedSong = #"{ "subsonic-response": { "status": "failed", "version": "1.16.1", "error": { "code": 50, "message": "This song is in the shared library, so only the owner can remove it." } } }"#
    static let ok = #"{ "subsonic-response": { "status": "ok", "version": "1.16.1", "type": "octo", "openSubsonic": true } }"#
}

/// The octoFamily extension's calls and answers, read from fixtures shaped like an Octo server's.
@Suite struct FamilyParsingTests {
    let server = FakeServer()
    var client: SubsonicClient { server.client(username: "alex", password: "secret") }

    @Test func theExtensionIsFoundWhenListed() async {
        server.enqueue(FamilyFixtures.extensionsFamily)
        #expect(await client.supportsIfKnown(octoFamily) == true)
        server.enqueue(FamilyFixtures.extensionsOcto)
        #expect(await client.supportsIfKnown(octoFamily) == false)
    }

    @Test func aListenerReadsTheirPlanWithoutTheManagerPart() async throws {
        server.enqueue(FamilyFixtures.listener)
        let family = try await client.family()
        let call = server.requests[0]
        #expect(call.path == "/rest/getFamily")
        #expect(call.query["u"] == "alex")
        let me = family.me
        #expect(me.username == "alex")
        #expect(me.displayName == "Alex")
        #expect(me.role == .listener)
        #expect(me.managed)
        #expect(me.requestsThisWeek == 3)
        #expect(me.storageUsedBytes == 5_400_000_000)
        #expect(me.place == .home)
        #expect(me.deviceId == "d_7Qm2abc")
        let can = me.abilities
        #expect(can.addToLibrary == .request)
        #expect(can.requestQuality == .best)
        #expect(!can.autoApprove)
        #expect(can.weeklyRequestLimit == 10)
        #expect(can.streamCap == 192)
        #expect(can.awayCap == 128)
        #expect(can.away)
        #expect(can.devicesAtOnce == 2)
        #expect(!can.downloadFiles)
        #expect(!can.offlineCopies)
        #expect(!can.share)
        #expect(can.importPlaylists)
        #expect(!can.cleanOnly)
        #expect(can.familyPlaylistsEdit)
        #expect(!can.manageFamily)
        #expect(!can.approveRequests)
        #expect(can.storageLimitGb == 10)
        #expect(can.instantFromFamily)
        #expect(family.manager == nil)
        #expect(me.quality == AccountQuality(home: .original, away: .standard, familyLimitKbps: 192, familyAwayLimitKbps: 128))
    }

    @Test func theOwnerReadsTheWholeFamily() async throws {
        server.enqueue(FamilyFixtures.owner)
        let family = try await client.family()
        #expect(family.me.role == .owner)
        #expect(family.me.deviceId == nil)
        #expect(family.me.place == .away)
        let manager = try #require(family.manager)
        #expect(manager.pendingRequests == 1)
        #expect(manager.liveStreams == 3)
        #expect(manager.members.map(\.username) == ["alex", "sam"])
        #expect(manager.members[0].role == .listener)
        #expect(manager.members[0].devices == 2)
        #expect(manager.members[0].playingNow)
        #expect(manager.members[0].pendingRequests == 1)
        #expect(manager.members[0].storageUsedBytes == 5_400_000_000)
        #expect(manager.members[0].storageLimitGb == 10)
        #expect(manager.members[1].role == .kid)
        #expect(manager.members[1].suspended)
    }

    @Test func valuesFromANewerServerReadAsTheDefaults() async throws {
        server.enqueue(FamilyFixtures.future)
        let me = try await client.family().me
        #expect(me.username == "zoe")
        #expect(me.role == nil)
        #expect(me.roleName == "Guest")
        #expect(me.abilities.addToLibrary == .direct)
        #expect(me.abilities.requestQuality == .best)
        #expect(me.place == .home)
    }

    @Test func requestsAreReadWithEveryState() async throws {
        server.enqueue(FamilyFixtures.requests)
        let requests = try await client.familyRequests()
        let call = server.requests[0]
        #expect(call.path == "/rest/getFamilyRequests")
        #expect(call.query["all"] == nil)
        #expect(call.query["state"] == nil)
        #expect(requests.count == 4)
        let pending = requests[0]
        #expect(pending.id == "r_9xK2")
        #expect(pending.kind == .song)
        #expect(pending.target == "ext-deezer-song-12345")
        #expect(pending.coverArt == "ext-deezer-song-12345")
        #expect(pending.quality == .flac)
        #expect(pending.state == .pending)
        #expect(pending.created == "2026-10-20T18:00:00Z")
        #expect(pending.decided == nil)
        #expect(pending.outcome == nil)
        let done = requests[1]
        #expect(done.kind == .album)
        #expect(done.state == .done)
        #expect(done.outcome == .addedFromFamily)
        #expect(done.librarySongId == "tr-77")
        #expect(done.decidedBy == "jordan")
        #expect(done.coverArt == nil)
        #expect(requests[2].state == .declined)
        #expect(requests[2].note == "We have the live one")
        #expect(requests[2].quality == .mp3)
        #expect(requests[3].failure == "No real FLAC copy found")
    }

    @Test func aManagerAsksForEveryMembersPendingRequests() async throws {
        server.enqueue(FamilyFixtures.requestsEmpty)
        #expect(try await client.familyRequests(all: true, state: .pending).isEmpty)
        #expect(server.requests[0].query["all"] == "true")
        #expect(server.requests[0].query["state"] == "Pending")
    }

    @Test func requestsNameTheirQualityAndKindWhenGiven() async throws {
        server.enqueue(FamilyFixtures.request("Done", outcome: "AlreadyShared"))
        let request = try await client.requestCopy("ext-deezer-song-12345", quality: .flac)
        let call = server.requests[0]
        #expect(call.path == "/rest/requestCopy")
        #expect(call.query["id"] == "ext-deezer-song-12345")
        #expect(call.query["quality"] == "Flac")
        #expect(call.query["kind"] == nil)
        #expect(request.state == .done)
        #expect(request.outcome == .alreadyShared)
        server.enqueue(FamilyFixtures.request("Pending"))
        _ = try await client.requestCopy("tr-1", quality: .mp3, kind: .upgrade)
        #expect(server.requests[1].query["quality"] == "Mp3")
        #expect(server.requests[1].query["kind"] == "Upgrade")
    }

    @Test func aFamilyPlaylistIsMade() async throws {
        server.enqueue(#"{ "subsonic-response": { "status": "ok", "version": "1.16.1", "type": "octo", "openSubsonic": true, "playlist": { "id": "of_road", "name": "Road trip", "songCount": 0, "duration": 0, "owner": "alex", "public": true, "created": "2026-10-20T18:00:00Z", "changed": "2026-10-20T18:00:00Z" } } }"#)
        let made = try await client.createFamilyPlaylist(name: " Road trip ", approveAdditions: true)
        #expect(server.requests[0].path == "/rest/createFamilyPlaylist")
        #expect(server.requests[0].query["name"] == "Road trip")
        #expect(server.requests[0].query["approveAdditions"] == "true")
        #expect(made.id == "of_road")
        #expect(made.name == "Road trip")
    }

    @Test func cancelAndDecideAnswerTheRequest() async throws {
        server.enqueue(FamilyFixtures.request("Cancelled"))
        #expect(try await client.cancelFamilyRequest("r_9xK2").state == .cancelled)
        #expect(server.requests[0].query["id"] == "r_9xK2")
        server.enqueue(FamilyFixtures.request("Approved"))
        #expect(try await client.decideFamilyRequest("r_9xK2", approve: true, note: " Enjoy ").state == .approved)
        #expect(server.requests[1].path == "/rest/decideFamilyRequest")
        #expect(server.requests[1].query["approve"] == "true")
        #expect(server.requests[1].query["note"] == "Enjoy")
        server.enqueue(FamilyFixtures.request("Declined"))
        _ = try await client.decideFamilyRequest("r_9xK2", approve: false, note: "  ")
        #expect(server.requests[2].query["approve"] == "false")
        #expect(server.requests[2].query["note"] == nil)
    }

    @Test func devicesAreReadWithWhatTheyPlay() async throws {
        server.enqueue(FamilyFixtures.devices)
        let devices = try await client.familyDevices(all: true)
        #expect(server.requests[0].query["all"] == "true")
        #expect(devices.count == 2)
        let phone = devices[0]
        #expect(phone.name == "Pixel 9")
        #expect(phone.firstSeen == "2026-10-19T10:00:00Z")
        #expect(phone.app == "Octo 1.6 (Android)")
        #expect(phone.place == .away)
        #expect(phone.playing?.title == "Song")
        #expect(phone.current)
        #expect(phone.quality == .app)
        #expect(devices[1].quality == .account)
        #expect(devices[1].app == "Symfonium")
        #expect(devices[1].playing == nil)
        #expect(!devices[1].current)
    }

    @Test func removingADeviceAndASongSendTheirIds() async throws {
        server.enqueue(FamilyFixtures.ok)
        try await client.forgetFamilyDevice("d_2")
        #expect(server.requests[0].path == "/rest/forgetFamilyDevice")
        #expect(server.requests[0].query["id"] == "d_2")
        server.enqueue(FamilyFixtures.ok)
        try await client.removeFromMyLibrary("tr-5")
        #expect(server.requests[1].query["id"] == "tr-5")
        server.enqueue(FamilyFixtures.sharedSong)
        do {
            try await client.removeFromMyLibrary("tr-6")
            Issue.record("A shared song cannot be removed")
        } catch let error as SubsonicError {
            #expect(error.code == 50)
            #expect(error.message.contains("shared library"))
        }
    }

    @Test func theLoginIsReadWithBothAddresses() async throws {
        server.enqueue(FamilyFixtures.login)
        let login = try await client.familyLogin()
        #expect(server.requests[0].path == "/rest/getFamilyLogin")
        #expect(login.username == "alex")
        #expect(login.servers.anywhere == "https://music.example.com")
        #expect(login.servers.home == "http://192.168.1.20:4533")
        #expect(login.anywhereAvailable)
        #expect(!login.awayAllowed)
    }

    @Test func changingTheFamilyPasswordSendsBothInTheBody() async throws {
        server.enqueue(FamilyFixtures.ok)
        try await client.changeFamilyPassword(current: "secret", next: "a new long one")
        let change = server.requests[0]
        #expect(change.method == "POST")
        #expect(change.path == "/rest/changeFamilyPassword")
        #expect(change.text.contains("current=secret"))
        #expect(change.text.contains("next=a%20new%20long%20one"))
        #expect(change.query["next"] == nil)
    }

    @Test func aHandOverIsStartedAndDecidedByOctoFamilyCalls() async throws {
        server.ok(#""familySignIn":{"token":"tok_9","expires":"2026-10-20T18:02:00Z","links":{"anywhere":"https://music.example.com/family/signin","home":"http://192.168.1.20:4533/family/signin"},"servers":{"anywhere":"https://music.example.com","home":"http://192.168.1.20:4533"},"anywhereAvailable":true}"#)
        let start = try await client.startFamilySignIn()
        #expect(start.token == "tok_9")
        #expect(start.links.anywhere == "https://music.example.com/family/signin")
        #expect(start.servers.home == "http://192.168.1.20:4533")
        #expect(!start.description.contains("tok_9"))
        #expect(server.requests[0].path == "/rest/startFamilySignIn")
        #expect(server.requests[0].query["u"] == "alex")

        server.ok(#""familySignInPending":null"#)
        #expect(try await client.familySignInPending(token: "tok_9") == nil)
        #expect(server.requests[1].query["token"] == "tok_9")
        server.ok()
        #expect(try await client.familySignInPending(token: "tok_9") == nil)
        server.ok(#""familySignInPending":{"id":"r_1","deviceName":"Pixel 9","platform":"Android"}"#)
        #expect(try await client.familySignInPending(token: "tok_9") == FamilySignInPending(id: "r_1", deviceName: "Pixel 9", platform: "Android"))

        server.ok(#""familySignInDecided":{"state":"Allowed"}"#)
        try await client.decideFamilySignIn(token: "tok_9", allow: true)
        #expect(server.requests[4].path == "/rest/decideFamilySignIn")
        #expect(server.requests[4].query["allow"] == "true")

        server.ok()
        try await client.putFamilySignInBox(token: "tok_9", box: "c2VhbGVk")
        let box = server.requests[5]
        #expect(box.method == "POST")
        #expect(box.path == "/rest/putFamilySignInBox")
        #expect(box.query["box"] == nil)
        #expect(box.text.contains("box=c2VhbGVk"))
    }

    @Test func theNewDeviceRedeemsAndWaitsWithNoSignIn() async throws {
        server.ok(#""familySignInRedeemed":{"id":"r_1"}"#)
        server.ok(#""familySignInRedeem":{"state":"Waiting"}"#)
        server.ok(#""familySignInRedeem":{"state":"Allowed","box":"c2VhbGVk"}"#)
        #expect(try await FamilyOpenCalls.redeem(server: server.base, session: FakeServer.session, token: "tok_9", deviceName: " Pixel 9 ", platform: .android) == "r_1")
        let redeem = server.requests[0]
        #expect(redeem.path == "/rest/redeemFamilySignIn")
        #expect(redeem.query["token"] == "tok_9")
        #expect(redeem.query["deviceName"] == "Pixel 9")
        #expect(redeem.query["platform"] == "Android")
        #expect(redeem.query["u"] == nil)
        #expect(redeem.query["t"] == nil)
        #expect(redeem.query["p"] == nil)
        #expect(try await FamilyOpenCalls.status(server: server.base, session: FakeServer.session, id: "r_1").state == .waiting)
        let allowed = try await FamilyOpenCalls.status(server: server.base, session: FakeServer.session, id: "r_1")
        #expect(allowed.state == .allowed)
        #expect(allowed.box == "c2VhbGVk")
        #expect(!allowed.description.contains("c2VhbGVk"))
        #expect(server.requests[2].path == "/rest/getFamilySignInRedeem")
    }

    @Test func aWrongTokenIsRefusedInPlainWords() async {
        server.error(40, "That sign-in code has been used or has expired.")
        await #expect(throws: SubsonicError.wrongCredentials("That sign-in code has been used or has expired.")) {
            _ = try await FamilyOpenCalls.redeem(server: server.base, session: FakeServer.session, token: "old", deviceName: "Pixel 9", platform: .android)
        }
    }

    @Test func aServerBehindAPathKeepsItInEveryCall() async throws {
        server.ok(#""familySignInRedeemed":{"id":"r_1"}"#)
        _ = try await FamilyOpenCalls.redeem(server: server.base.appendingPathComponent("octo"), session: FakeServer.session, token: "tok",
                                             deviceName: "Phone", platform: .android)
        #expect(server.requests[0].path == "/octo/rest/redeemFamilySignIn")
        server.enqueue(#"{"inviteLink":"x"}"#)
        _ = try await FamilyWeb(server: URL(string: server.base.absoluteString + "/octo/")!, session: FakeServer.session).resetMember(username: "sam")
        #expect(server.requests[1].path == "/octo/api/family/members/sam/reset")
    }

    @Test func qualityLimitsCompareLowestFirst() {
        #expect(RequestQuality.mp3.allowedUnder(.flac))
        #expect(RequestQuality.flac.allowedUnder(.flac))
        #expect(!RequestQuality.best.allowedUnder(.flac))
        #expect(!RequestQuality.flac.allowedUnder(.mp3))
        #expect(RequestQuality.best.allowedUnder(.best))
    }
}

/// The family page's calls: an invite accepted, a manager's member and link, and plain words on errors.
@Suite struct FamilyWebTests {
    let server = FakeServer()
    var web: FamilyWeb { FamilyWeb(server: server.base, session: FakeServer.session) }

    @Test func anInviteIsAcceptedWithTheChosenPassword() async throws {
        server.enqueue(#"{"username":"alex"}"#)
        #expect(try await web.join(token: "tok_1", password: "a long password", displayName: " Alex ") == "alex")
        let joined = server.requests[0]
        #expect(joined.method == "POST")
        #expect(joined.path == "/api/family/join")
        #expect(joined.headers["X-Octo-Family"] == "1")
        #expect(joined.headers["Accept"] == "application/json")
        let body = try JSONSerialization.jsonObject(with: joined.body) as? [String: String]
        #expect(body == ["token": "tok_1", "password": "a long password", "displayName": "Alex"])
    }

    @Test func aManagerAddsAMemberAndGetsTheirLink() async throws {
        server.enqueue(#"{"member":{"username":"sam","displayName":"Sam","role":"Kid"},"inviteLink":"https://music.example.com/family/join#invite=t9","links":{"anywhere":null,"home":"http://192.168.1.20:4533/family/join#invite=t9"},"anywhereAvailable":false}"#)
        server.enqueue(#"{"username":"sam","displayName":"Sam","role":"Kid"}"#)
        let added = try await web.addMember(username: "sam", displayName: "Sam", preset: .kid, away: false)
        #expect(added.member.roleName == "Kid")
        #expect(added.inviteLink == "https://music.example.com/family/join#invite=t9")
        #expect(!added.anywhereAvailable)
        #expect(added.links?.anywhere == nil)
        #expect(added.links?.home == "http://192.168.1.20:4533/family/join#invite=t9")
        #expect(server.requests[0].text.contains(#""preset":"Kid""#))
        let edit = server.requests[1]
        #expect(edit.method == "PUT")
        #expect(edit.path == "/api/family/members/sam")
        #expect(edit.text == #"{"edits":{"away":false}}"#)

        server.enqueue(#"{"inviteLink":"https://music.example.com/family/join#invite=r1","links":{"anywhere":"https://music.example.com/family/join#invite=r1","home":null},"inviteDays":7,"expires":"2026-10-27T18:00:00Z","anywhereAvailable":true,"awayAllowed":false,"homeOnly":false,"publicUrl":"https://music.example.com"}"#)
        let reset = try await web.resetMember(username: "sam smith")
        #expect(reset.inviteLink == "https://music.example.com/family/join#invite=r1")
        #expect(reset.expires == "2026-10-27T18:00:00Z")
        #expect(reset.inviteDays == 7)
        #expect(!reset.awayAllowed)
        #expect(reset.publicUrl == "https://music.example.com")
        #expect(server.requests[2].method == "POST")
        #expect(server.requests[2].url.absoluteString.hasSuffix("/api/family/members/sam%20smith/reset"))

        server.enqueue(#"{"inviteLink":"https://music.example.com/family/join#invite=t10","homeOnly":true}"#)
        let fresh = try await web.newInvite(username: "sam smith")
        #expect(fresh.homeOnly)
        #expect(server.requests[3].url.absoluteString.hasSuffix("/api/family/members/sam%20smith/invite"))
    }

    @Test func errorsSayWhatHappened() async {
        server.enqueue(status: 410, #"{"message":"That invite has been used."}"#)
        await #expect(throws: SubsonicError.notFound("That invite has been used.")) {
            _ = try await web.join(token: "tok", password: "password1", displayName: "Alex")
        }
        server.enqueue(status: 401, "")
        await #expect(throws: SubsonicError.wrongCredentials("The server did not take this sign-in for that.")) {
            _ = try await web.resetMember(username: "sam")
        }
        server.enqueue(status: 404, "")
        await #expect(throws: SubsonicError.notSubsonic("This server has no family page. Update Octo on the server.", status: 404)) {
            _ = try await web.newInvite(username: "sam")
        }
        server.enqueue(status: 500, "")
        await #expect(throws: SubsonicError.server(code: 500, message: "The server said no (HTTP 500).")) {
            _ = try await web.newInvite(username: "sam")
        }
    }

    @Test func anAppsCallsCarryItsSubsonicSignInAndNoPassword() async throws {
        server.enqueue(#"{"member":{"username":"sam"},"inviteLink":"https://music.example.com/family/join#invite=t9"}"#)
        server.enqueue(#"{"username":"sam"}"#)
        _ = try await server.client(username: "winters", password: "pw").familyWeb().addMember(username: "sam", displayName: "Sam", preset: .kid)
        let call = server.requests[0]
        #expect(call.path == "/api/family/members")
        #expect(call.query["u"] == "winters")
        #expect(!(call.query["t"] ?? "").isEmpty)
        #expect(!(call.query["s"] ?? "").isEmpty)
        #expect(call.query["v"] == "1.16.1")
        #expect(call.query["c"] == "Octo")
        #expect(call.query["p"] == nil)
        #expect(!call.url.absoluteString.contains("pw"))
    }

    @Test func thePagesCookiesAreKeptForTheNextCall() async throws {
        server.route { request in
            if request.endpoint == "join" {
                return FakeServer.Reply(status: 200, body: Data(#"{"username":"alex"}"#.utf8),
                                        headers: ["Content-Type": "application/json", "Set-Cookie": "octo_family=s1; Path=/; HttpOnly"])
            }
            return FakeServer.Reply(status: 200, body: Data(#"{"inviteLink":"x"}"#.utf8))
        }
        let web = self.web
        _ = try await web.join(token: "t", password: "password1", displayName: "Alex")
        _ = try await web.newInvite(username: "alex")
        #expect(server.requests[1].headers["Cookie"] == "octo_family=s1")
    }
}

@Suite struct FamilyLinkTests {
    @Test func aSignInLinkFillsInTheServerAndUsername() {
        let link = parseFamilyLink(" octo://signin?server=https%3A%2F%2Fmusic.example.com%2Fnd&home=http%3A%2F%2F192.168.1.20%3A4533&username=alex%20smith ")
        #expect(link == .prefill(FamilySignInPrefill(server: "https://music.example.com/nd", username: "alex smith", home: "http://192.168.1.20:4533")))
        #expect(link.flatMap { parseFamilyLink(familyAppLink($0)) } == link)
        #expect(parseFamilyLink("octo://signin?server=https%3A%2F%2Fmusic.example.com") == .prefill(FamilySignInPrefill(server: "https://music.example.com")))
        #expect(parseFamilyLink("octo://signin?username=alex") == nil)
        #expect(parseFamilyLink("octo://album/al-1") == nil)
    }

    @Test func aHandOverLinkIsReadInBothFormsAndKeepsItsKey() {
        let web = familySignInUrl(base: "https://music.example.com/nd/", token: "tok_1", key: "K-ey_0", server: "https://music.example.com/nd",
                                  home: "http://192.168.1.20:4533", username: "alex")
        #expect(web == "https://music.example.com/nd/family/signin#t=tok_1&k=K-ey_0&s=https%3A%2F%2Fmusic.example.com%2Fnd&h=http%3A%2F%2F192.168.1.20%3A4533&u=alex")
        let link = FamilyHandOverLink(base: "https://music.example.com/nd", token: "tok_1", key: "K-ey_0", server: "https://music.example.com/nd",
                                      home: "http://192.168.1.20:4533", username: "alex")
        #expect(parseFamilyLink(web) == .handOver(link))
        let own = familyAppLink(.handOver(link))
        #expect(own == "octo://handover?" + web.split(separator: "#", maxSplits: 1)[1])
        #expect(parseFamilyLink(own) == .handOver(link))
        #expect(!link.description.contains("tok_1"))
        #expect(!link.description.contains("K-ey"))
        #expect(parseFamilyLink("octo://handover?t=tok_9&k=a_b-c&s=https%3A%2F%2Fmusic.example.com&h=http%3A%2F%2F192.168.1.20%3A4533")
            == .handOver(FamilyHandOverLink(base: "https://music.example.com", token: "tok_9", key: "a_b-c", server: "https://music.example.com",
                                            home: "http://192.168.1.20:4533")))
        #expect(parseFamilyLink("intent://handover?t=tok_9&k=a_b-c&s=https%3A%2F%2Fmusic.example.com&u=alex#Intent;scheme=octo;package=app.winters.octo;S.browser_fallback_url=https%3A%2F%2Fmusic.example.com%2Ffamily%2Fsignin%26back%3D1;end")
            == .handOver(FamilyHandOverLink(base: "https://music.example.com", token: "tok_9", key: "a_b-c", server: "https://music.example.com",
                                            username: "alex")))
        #expect(parseFamilyLink("octo://handover?t=tok_9&s=https%3A%2F%2Fmusic.example.com") == nil)
        #expect(parseFamilyLink("octo://handover?k=a&s=https%3A%2F%2Fmusic.example.com") == nil)
        #expect(parseFamilyLink("octo://handover?t=tok_9&k=a") == nil)
        #expect(parseFamilyLink("https://music.example.com/family/signin#t=tok_1") == nil)
        #expect(parseFamilyLink("https://music.example.com/family/signin") == nil)
        #expect(parseFamilyLink("https://music.example.com/family/other#t=1&k=2") == nil)
    }

    @Test func aWebHandOverWithoutAServerUsesItsOwnAddress() {
        #expect(parseFamilyLink("https://Music.Example.com/octo/family/signin#t=a&k=b")
            == .handOver(FamilyHandOverLink(base: "https://music.example.com/octo", token: "a", key: "b", server: "https://music.example.com/octo")))
    }

    @Test func anInviteLinkIsReadInBothForms() {
        let invite = FamilyInviteLink(server: "https://music.example.com", token: "tok_ABC-123")
        #expect(parseFamilyLink("https://music.example.com/family/join#invite=tok_ABC-123") == .invite(invite))
        #expect(parseFamilyLink("octo://join?server=https%3A%2F%2Fmusic.example.com&invite=tok_ABC-123") == .invite(invite))
        #expect(familyInviteUrl(server: "https://music.example.com", token: "tok_ABC-123") == "https://music.example.com/family/join#invite=tok_ABC-123")
        #expect(parseFamilyLink(familyAppLink(.invite(invite))) == .invite(invite))
        #expect(!invite.description.contains("tok_"))
        #expect(parseFamilyLink("https://music.example.com/family/join#invite=tok_ABC-123")?.isInvite == true)
    }

    @Test func anInvitesHomeAddressIsReadInBothFormsAndThePathIsKept() {
        let invite = FamilyInviteLink(server: "https://example.com/octo", token: "tok_1", home: "http://music.lan")
        #expect(parseFamilyLink("https://example.com/octo/family/join#invite=tok_1&home=http%3A%2F%2Fmusic.lan") == .invite(invite))
        #expect(parseFamilyLink("octo://join?server=https%3A%2F%2Fexample.com%2Focto&invite=tok_1&home=http%3A%2F%2Fmusic.lan") == .invite(invite))
        #expect(parseFamilyLink(familyInviteUrl(server: "https://example.com/octo", token: "tok_1", home: "http://music.lan")) == .invite(invite))
        #expect(parseFamilyLink("https://example.com/family/join#invite=t")?.home == nil)
        #expect(parseFamilyLink("https://example.com/family/join#invite=t&home=")?.home == nil)
        #expect(parseFamilyLink("https://example.com/family/join#invite=t&home=%3A%2F%2F")?.home == nil)
    }

    @Test func encodingIsRFC3986() {
        #expect(encodeComponent("a b/c~d_e.f-g") == "a%20b%2Fc~d_e.f-g")
        #expect(encodeComponent("ö") == "%C3%B6")
        #expect(decodeComponent("a+b%20c") == "a b c")
        #expect(decodeComponent("100%") == "100%")
    }
}
