import Foundation
import Testing
@testable import OctoKit

/// Outside song actions, offline copies, the request sheet, notices, the abilities in plain
/// words and joining with a code.
@Suite struct FamilyRulesTests {
    func member(add: AddToLibrary = .request, max: RequestQuality = .flac, limit: Int = 10, used: Int = 3, storageUsed: Int64 = 0,
                storageLimit: Int = 10, offline: Bool = false, role: FamilyRole = .listener, managed: Bool = true) -> FamilyMe {
        var me = FamilyMe()
        me.username = "alex"
        me.displayName = "Alex"
        me.roleName = role.rawValue
        me.managed = managed
        me.abilities.addToLibrary = add
        me.abilities.requestQuality = max
        me.abilities.weeklyRequestLimit = limit
        me.abilities.storageLimitGb = storageLimit
        me.abilities.offlineCopies = offline
        me.requestsThisWeek = used
        me.storageUsedBytes = storageUsed
        return me
    }

    @Test func outsideSongActionsFollowThePlan() {
        #expect(outsideActions(member(add: .request)) == OutsideActions(addLabel: "Save", offersRequest: true))
        #expect(outsideActions(member(add: .saveOnly)) == OutsideActions(addLabel: "Save", offersRequest: false))
        #expect(outsideActions(member(add: .direct)) == .usual)
        #expect(outsideActions(nil) == .usual)
    }

    @Test func onlyManagedMembersGetRemoveFromMyLibrary() {
        #expect(offersRemoveFromMyLibrary(member()))
        #expect(offersRemoveFromMyLibrary(member(role: .kid)))
        #expect(!offersRemoveFromMyLibrary(member(role: .owner, managed: false)))
        #expect(!offersRemoveFromMyLibrary(member(role: .unmanaged, managed: false)))
        #expect(!offersRemoveFromMyLibrary(nil))
        #expect(offersRemoveOn(personal: true, serverMarksPersonal: true))
        #expect(!offersRemoveOn(personal: false, serverMarksPersonal: true))
        #expect(offersRemoveOn(personal: false, serverMarksPersonal: false))
    }

    @Test func offlineCopiesFollowThePlan() {
        #expect(!offlineCopiesAllowed(member(offline: false)))
        #expect(offlineCopiesAllowed(member(offline: true)))
        #expect(offlineCopiesAllowed(nil))
        #expect(FamilyText.offlineCopiesOff == "Offline copies are off for this account")
    }

    @Test func theSheetHoldsBackQualitiesAboveThePlan() {
        let sheet = requestSheet(member(max: .flac))
        #expect(sheet.choices.map(\.quality) == [.best, .flac, .mp3])
        #expect(sheet.choices.map(\.enabled) == [false, true, true])
        #expect(sheet.choices[0].detail == "Not on your plan")
        #expect(sheet.initial == .flac)
        #expect(sheet.quotaLine == "7 of 10 requests left this week")
        #expect(!sheet.quotaUsed)
        #expect(sheet.storageLine == nil)
        #expect(sheet.approvalLine == "Waits for approval")
        let mp3 = requestSheet(member(max: .mp3))
        #expect(mp3.choices.map(\.enabled) == [false, false, true])
        #expect(mp3.initial == .mp3)
        #expect(requestSheet(member(max: .best)).initial == .best)
    }

    @Test func theSheetSaysWhenTheWeekOrTheLibraryIsFull() {
        let full = requestSheet(member(used: 10, storageUsed: 10_200_000_000, storageLimit: 10))
        #expect(full.quotaUsed)
        #expect(full.quotaLine == "You have used all 10 requests this week. Songs the family already has can still be added.")
        #expect(full.storageLine == "Your library is full (10.2 of 10 GB)")
        let open = requestSheet(member(limit: 0, storageUsed: 99_000_000_000, storageLimit: 0))
        #expect(open.quotaLine == nil)
        #expect(open.storageLine == nil)
    }

    @Test func sizesAndCountsReadPlainly() {
        #expect(storageLine(usedBytes: 5_400_000_000, limitGb: 10) == "5.4 of 10 GB used")
        #expect(storageLine(usedBytes: 5_400_000_000, limitGb: 0) == "5.4 GB used")
        #expect(storageLine(usedBytes: 40_000_000, limitGb: 10) == "40 MB of 10 GB used")
        #expect(storageLine(usedBytes: 0, limitGb: 5) == "0 of 5 GB used")
        #expect(storageLine(usedBytes: 120_400_000_000, limitGb: 0) == "120 GB used")
        #expect(abs((storageShare(usedBytes: 5_400_000_000, limitGb: 10) ?? 0) - 0.54) < 0.001)
        #expect(storageShare(usedBytes: 50_000_000_000, limitGb: 10) == 1)
        #expect(storageShare(usedBytes: 5, limitGb: 0) == nil)
        #expect(weeklyLine(used: 3, limit: 10) == "3 of 10 requests used this week")
        #expect(weeklyLine(used: 1, limit: 0) == "1 request this week")
    }

    @Test func thePlanReadsInPlainWords() {
        var can = member().abilities
        can.streamCap = 192
        can.awayCap = 128
        can.devicesAtOnce = 2
        let lines = abilityLines(can).map(\.text)
        #expect(lines[0] == "Songs you add are saved. Request a copy to keep one in your library")
        for expected in ["Copies in FLAC or MP3", "Your requests wait for approval", "10 requests a week", "Room for 10 GB in your library",
                         "Your family plan limits listening to 192 kbps", "Your family plan limits away listening to 128 kbps",
                         "Plays on 2 devices at once", "Offline copies are off"] {
            #expect(lines.contains(expected), "\(expected)")
        }
        for line in lines { #expect(!line.contains("\u{2014}") && !line.contains("\u{2013}")) }

        var ownerCan = FamilyAbilities()
        ownerCan.manageFamily = true
        ownerCan.approveRequests = true
        let owner = abilityLines(ownerCan).map(\.text)
        #expect(owner[0] == "Songs you add go straight into your library")
        #expect(!owner.contains { $0.contains("kbps") || $0.contains("quality") })
        #expect(owner.contains("Manages the family"))
        #expect(!owner.contains { $0.contains("requests a week") })

        var same = FamilyAbilities()
        same.streamCap = 192
        let sameAway = abilityLines(same).map(\.text)
        #expect(sameAway.contains("Listens away from home too"))
        #expect(!sameAway.contains { $0.contains("away listening") })
        var higher = FamilyAbilities()
        higher.streamCap = 128
        higher.awayCap = 192
        #expect(!abilityLines(higher).contains { $0.text.contains("away listening") })
        var awayOnly = FamilyAbilities()
        awayOnly.awayCap = 128
        #expect(abilityLines(awayOnly).contains { $0.text == "Your family plan limits away listening to 128 kbps" })
        var home = FamilyAbilities()
        home.away = false
        #expect(abilityLines(home).first { $0.text.hasPrefix("Listening away") } == AbilityLine("Listening away from home is off", on: false))
    }

    @Test func aRoleFromANewerServerShowsItsOwnName() {
        #expect(roleLabel(name: "Listener") == "Listener")
        #expect(roleLabel(name: "CoAdmin") == "Co-admin")
        #expect(roleLabel(name: "Guest") == "Guest")
        #expect(roleLabel(name: "FamilyGuest") == "Family Guest")
        #expect(roleLabel(name: "") == "Member")
        var zoe = FamilyMe()
        zoe.username = "zoe"
        zoe.displayName = "Zoe"
        zoe.roleName = "Guest"
        #expect(planTitle(zoe) == "Zoe, Guest")
    }

    @Test func anInviteNeedsANameAndAPasswordTwice() {
        #expect(inviteProblem(displayName: "Alex", password: "short", again: "short") == "Choose a password of at least 8 characters")
        #expect(inviteProblem(displayName: "Alex", password: "long enough", again: "long enougH") == "The two passwords are not the same")
        #expect(inviteProblem(displayName: " ", password: "long enough", again: "long enough") == "Type your name")
        let long = String(repeating: "x", count: 1025)
        #expect(inviteProblem(displayName: "Alex", password: long, again: long) == "That password is too long")
        #expect(inviteProblem(displayName: "Alex", password: "long enough", again: "long enough") == nil)
    }

    @Test func anInviteSignsUpWithTheChosenPassword() async {
        let fake = FamilyFake()
        fake.raw("join") { _ in #"{"username":"alex"}"# }
        let joined = await joinWithInvite(address: fake.url, token: "tok_1", displayName: "Alex", password: "long enough", session: FakeServer.session)
        #expect(joined == .signedUp(username: "alex", password: "long enough", at: fake.url))
        #expect(!joined.description.contains("long enough"))
        let body = fake.called("join").first?.text ?? ""
        #expect(body.contains(#""token":"tok_1""#))
        #expect(body.contains(#""password":"long enough""#))
        #expect(fake.calls.count == 1)
    }

    @Test func aUsedInviteSaysSo() async {
        let fake = FamilyFake()
        fake.raw("join") { _ in nil }
        let refused = await joinWithInvite(address: fake.url, token: "tok_1", displayName: "Alex", password: "long enough", session: FakeServer.session)
        #expect(refused == .failed("The server did not take this sign-in for that.", unreachable: false))
        fake.server.route { _ in FakeServer.Reply(status: 410, body: Data()) }
        #expect(await joinWithInvite(address: fake.url, token: "t", displayName: "A", password: "long enough", session: FakeServer.session)
            == .failed("That invite has been used or has expired. Ask for a new one.", unreachable: false))
        fake.server.route { _ in FakeServer.Reply(status: 404, body: Data(#"{"message":"nope"}"#.utf8)) }
        #expect(await joinWithInvite(address: fake.url, token: "t", displayName: "A", password: "long enough", session: FakeServer.session)
            == .failed("That server has no family sign-up. Check the address, or update Octo on the server.", unreachable: false))
        fake.server.route { _ in FakeServer.Reply(status: 200, body: Data(#"{"username":" "}"#.utf8)) }
        #expect(await joinWithInvite(address: fake.url, token: "t", displayName: "A", password: "long enough", session: FakeServer.session)
            == .failed("The server did not answer with a username. Ask for a new invite.", unreachable: false))
    }

    @Test func signingUpFallsBackToTheHomeAddressWhenTheOutsideOneCantBeReached() async {
        let home = FamilyFake()
        home.raw("join") { _ in #"{"username":"alex"}"# }
        let outside = FakeServer()
        outside.close()
        let joined = await joinWithInvite(address: outside.base, token: "tok_1", displayName: "Alex", password: "long enough",
                                          session: FakeServer.session, home: home.url)
        #expect(joined == .signedUp(username: "alex", password: "long enough", at: home.url))
        #expect(home.called("join").count == 1)
        let alone = await joinWithInvite(address: outside.base, token: "tok_1", displayName: "Alex", password: "long enough", session: FakeServer.session)
        #expect(alone == .failed("Octo can't reach that address. Check it and try again.", unreachable: true))
    }

    @Test func passwordStrengthReadsPlainly() {
        #expect(passwordStrength("") == nil)
        #expect(passwordStrength("abc") == "Too short: at least 8 characters")
        #expect(passwordStrength("abcdefgh") == "Weak: make it longer, or mix in numbers and symbols")
        #expect(passwordStrength("abcdefgh12!") == "Good. Longer is stronger.")
        #expect(passwordStrength("correct horse battery") == "Strong")
    }

    @Test func requestsAndDevicesReadPlainly() {
        let done = FamilyRequest(title: "Song", artist: "Artist", state: .done, quality: .flac, outcome: .downloaded)
        #expect(requestStateLine(done) == "Downloaded")
        var other = done
        other.outcome = .addedFromFamily
        #expect(requestStateLine(other) == "Added from the family library")
        other.outcome = .alreadyShared
        #expect(requestStateLine(other) == "Already in the family library")
        other.state = .failed
        other.failure = "No real FLAC copy found"
        #expect(requestStateLine(other) == "Failed: No real FLAC copy found")
        #expect(requestKindLine(done) == "Song · FLAC")
        #expect(requestTitle(done) == "Song · Artist")
        #expect(requestTitle(FamilyRequest(target: "ext-1")) == "ext-1")
        let phone = FamilyDevice(name: "Pixel 9", app: "Octo 1.6 (Android)", place: .away, playing: FamilyDevicePlaying(title: "Song", artist: "Artist"))
        #expect(deviceLine(phone) == "Octo 1.6 (Android) · Away · Playing Song by Artist")
        #expect(deviceLine(FamilyDevice()) == "A music app · Home")
        var alex = FamilyMember(username: "alex", displayName: "Alex", roleName: "Listener")
        alex.devices = 2
        alex.playingNow = true
        alex.pendingRequests = 1
        #expect(memberLine(alex) == "Listener · 2 devices · Playing now · 1 request waiting")
    }

    @Test func eachDecisionIsToldOnce() {
        let pending = FamilyRequest(id: "r1", title: "Song", artist: "Artist", state: .pending)
        var old = pending
        old.id = "r0"
        old.state = .done
        let (first, afterFirst) = familyNotices(NoticeMemory(), mine: [pending, old], waiting: nil)
        #expect(first.isEmpty)
        var approved = pending
        approved.state = .approved
        let (second, afterSecond) = familyNotices(afterFirst, mine: [approved], waiting: nil)
        #expect(second == [FamilyNotice(key: "r1", title: "Approved", text: "Song · Artist is on its way to your library.")])
        #expect(familyNotices(afterSecond, mine: [approved], waiting: nil).0.isEmpty)
        var added = approved
        added.state = .done
        added.outcome = .addedFromFamily
        let (third, afterThird) = familyNotices(afterSecond, mine: [added], waiting: nil)
        #expect(third.first?.title == "Added")
        #expect(third.first?.text == "Song · Artist. Added from the family library.")
        let declined = FamilyRequest(id: "r2", title: "Other", state: .declined, note: "We have the live one")
        #expect(familyNotices(afterThird, mine: [declined], waiting: nil).0 == [FamilyNotice(key: "r2", title: "Declined", text: "Other. \"We have the live one\"")])
        let shown = FamilyRequest(id: "r3", title: "Shown", state: .done, outcome: .alreadyShared)
        #expect(familyNotices(afterThird.alreadyTold(shown), mine: [shown], waiting: nil).0.isEmpty)
        let failed = FamilyRequest(id: "r4", title: "Gone", state: .failed)
        #expect(familyNotices(afterThird, mine: [failed], waiting: nil).0.first?.text == "Gone. Ask for it again later.")
    }

    @Test func managersAreToldHowManyWait() {
        let (first, after) = familyNotices(NoticeMemory(), mine: [], waiting: 2)
        #expect(first == [FamilyNotice(key: waitingNoticeKey, title: "2 requests waiting", text: "Open Family to approve or decline.")])
        #expect(familyNotices(after, mine: [], waiting: 2).0.isEmpty)
        let (fewer, afterFewer) = familyNotices(after, mine: [], waiting: 1)
        #expect(fewer.isEmpty)
        #expect(familyNotices(afterFewer, mine: [], waiting: 2).0.first?.title == "2 requests waiting")
        #expect(familyNotices(NoticeMemory(), mine: [], waiting: 1).0.first?.title == "1 request waiting")
    }

    @Test func theNoticeMemoryReadsBackAsKept() throws {
        let memory = NoticeMemory(told: ["r1": "Approved"], waitingTold: 2, started: true)
        let text = try JSONEncoder().encode(memory)
        #expect(try JSONDecoder().decode(NoticeMemory.self, from: text) == memory)
        #expect(try JSONDecoder().decode(NoticeMemory.self, from: Data("{}".utf8)) == NoticeMemory())
    }
}

/// Which link the sheets show, how links and addresses read, the countdown, and the steps for each app.
@Suite struct FamilyPopupsTests {
    let anywhere = "https://example.com/octo/family/join#invite=t9"
    let home = "http://192.168.1.20:4533/family/join#invite=t9"

    @Test func anywhereIsTheDefaultWhenTheServerHasIt() {
        let options = LinkOptions(anywhere: anywhere, home: home)
        #expect(options.choosable)
        #expect(options.defaultReach == .anywhere)
        #expect(options.linkFor(.anywhere) == anywhere)
        #expect(options.linkFor(.home) == home)
    }

    @Test func withoutAnOutsideAddressHomeIsTheDefaultAndAnywhereIsUnavailable() {
        let options = LinkOptions(anywhere: nil, home: home, anywhereAvailable: false)
        #expect(options.choosable)
        #expect(options.defaultReach == .home)
        #expect(options.linkFor(.anywhere) == nil)
        #expect(dashboardStatusPage("https://music.example.com/") == "https://music.example.com/admin/#status")
    }

    @Test func someoneKeptHomeOnlyGetsTheHomeLink() {
        let options = LinkOptions(anywhere: anywhere, home: home, awayAllowed: false)
        #expect(!options.choosable)
        #expect(options.defaultReach == .home)
        #expect(options.linkFor(.anywhere) == home)
    }

    @Test func anInvitesOneLinkStaysTheOnlyChoice() {
        let one = inviteLinkOptions(url: anywhere, choices: nil, anywhereAvailable: true, homeOnly: false)
        #expect(!one.choosable)
        #expect(one.linkFor(one.defaultReach) == anywhere)
        let homeOnly = inviteLinkOptions(url: home, choices: nil, anywhereAvailable: false, homeOnly: true)
        #expect(homeOnly.linkFor(homeOnly.defaultReach) == home)
        let both = inviteLinkOptions(url: anywhere, choices: FamilyLinkChoices(anywhere: anywhere, home: home), anywhereAvailable: true, homeOnly: false)
        #expect(both.linkFor(.home) == home)
    }

    @Test func aLinkShowsWhereItGoesAndItsServer() {
        #expect(shownLink(anywhere) == "example.com/octo/family/join…#invite=t9")
        #expect(shownLink("https://music.example.com/family/signin#t=tok_1&k=key&s=x") == "music.example.com/family/signin…#t=tok_1")
        #expect(shownLink("https://music.example.com/family/join") == "music.example.com/family/join")
        #expect(shownLink("https://music.example.com/family/join#invite=winters", max: 34) == "music.example.com…#invite=winters")
        #expect(linkServer(anywhere) == "https://example.com/octo")
        #expect(linkServer("https://example.com/octo/family/signin#t=1") == "https://example.com/octo")
        #expect(linkServer(home) == "http://192.168.1.20:4533")
        #expect(shownServer("https://example.com/octo/") == "example.com/octo")
        #expect(middleEllipsized("abcdefghij", max: 5) == "ab…ij")
    }

    @Test func theChoicesSayWhichAddressTheyUse() {
        let options = LinkOptions(anywhere: anywhere, home: home)
        #expect(reachLine(.anywhere, options) == "Uses https://example.com")
        #expect(reachLine(.home, options) == "Uses your home network (192.168.1.20:4533)")
        #expect(reachLine(.anywhere, LinkOptions(anywhere: nil, home: home, anywhereAvailable: false)) == nil)
        #expect(reachQuestion(own: true) == "Where will you use it?")
        #expect(reachQuestion(own: false) == "Where will they use it?")
    }

    @Test func theInviteSheetIsTitledForWhatItIs() {
        #expect(InviteSheet(name: "Sam", username: "sam", url: anywhere).title == "Invite Sam")
        #expect(InviteSheet(name: "Sam", username: "sam", url: anywhere, reset: true).title == "New sign-in link for Sam")
        #expect(inviteNext("Sam") == "Sam picks a password, then signs in on any app.")
        #expect(inviteCaption("Sam") == "Sam scans this with their phone")
    }

    @Test func theCountdownRunsToTheEnd() {
        let expires = "2026-10-20T18:02:00Z"
        #expect(secondsLeft(expires, nowMs: epochMs(expires)! - 102_000) == 102)
        #expect(secondsLeft(expires, nowMs: epochMs(expires)! + 5_000) == 0)
        #expect(secondsLeft(nil, nowMs: 0) == nil)
        #expect(countdownLine(102) == "Works once · expires in 1:42")
        #expect(countdownLine(nil) == "Works once")
        #expect(!countdownWarns(30))
        #expect(countdownWarns(29))
        #expect(countdownLine(0) == "Works once · getting a new code")
        #expect(countdownAnnouncement(31) == nil)
        #expect(countdownAnnouncement(30) == "Thirty seconds left")
        #expect(countdownAnnouncement(0) == "This code expired. Getting a new one.")
    }

    @Test func everyAppHasTwoOrThreeStepsWithTheServerAndUsername() {
        let steps = loginSteps(server: "https://music.example.com", username: "alex")
        #expect(steps.map(\.app) == ["Octo", "Symfonium", "Feishin", "Amperfy", "Substreamer", "Tempo"])
        for app in steps {
            #expect((2...3).contains(app.steps.count))
            #expect(app.steps.contains { $0.contains("https://music.example.com") })
            #expect(!app.steps.contains { $0.contains("app password") })
        }
    }
}
