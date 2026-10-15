import Foundation
import Testing
@testable import OctoKit

private func json(_ text: String) -> Data { Data(text.utf8) }

private func release(_ tag: String, notes: String? = nil) -> ServerRelease {
    ServerRelease(tag: tag, name: "Octo \(tag)", notes: notes, url: "https://github.com/winters27/octo/releases/tag/\(tag)")
}

private func behind(running: String = "2026.10.11", latest: String = "2026.10.13", newer: [String] = ["2026.10.13"],
                    helper: ServerUpdateHelper = ServerUpdateHelper(installed: true, version: "2", mode: "git"),
                    pending: Bool = false, run: ServerUpdateRun? = nil, reinstall: String? = "curl -fsSL x | sh") -> ServerUpdateState {
    ServerUpdateState(running: running, latest: release(latest), newer: newer.map { release($0) }, updateAvailable: true,
                      standing: "behind", helper: helper, reinstallCommand: reinstall, pending: pending, run: run)
}

@Suite struct ServerUpdateReadingTests {
    @Test func readsTheWholeAnswer() throws {
        let state = try ServerUpdateState.read(json("""
        {"enabled":true,"repo":"winters27/octo","running":"2026.10.11",
         "latest":{"tag":"2026.10.13","name":"2026.10.13","notes":"**New**","url":"https://github.com/winters27/octo/releases/tag/2026.10.13","publishedUtc":"2026-10-12T10:00:00Z"},
         "newer":[{"tag":"2026.10.13"},{"tag":"2026.10.12"}],
         "updateAvailable":true,"standing":"behind","checkedUtc":"2026-10-12T11:00:00Z","error":null,
         "helper":{"installed":true,"version":"2","mode":"image","dir":"/opt/octo","installedUtc":"2026-10-01T00:00:00Z","outdated":false},
         "reinstallCommand":"curl x | sh","pending":false,"pendingId":null,"unanswered":null,
         "run":{"id":"r1","tag":"2026.10.13","from":"2026.10.11","state":"fetching","step":"git fetch","error":null,
                "startedUtc":"2026-10-12T11:00:00Z","finishedUtc":null,"log":["one","two"]},
         "command":"octo-update","imageCommand":"docker pull"}
        """))
        #expect(state.running == "2026.10.11")
        #expect(state.latest?.tag == "2026.10.13")
        #expect(state.latest?.notes == "**New**")
        #expect(state.newer.map(\.tag) == ["2026.10.13", "2026.10.12"])
        #expect(state.updateAvailable)
        #expect(state.helper == ServerUpdateHelper(installed: true, version: "2", mode: "image", dir: "/opt/octo",
                                                   installedUtc: "2026-10-01T00:00:00Z", outdated: false))
        #expect(state.run?.state == "fetching")
        #expect(state.run?.log == ["one", "two"])
        #expect(state.runActive)
        #expect(!state.canUpdateNow)
    }

    @Test func aHelperNotInstalledAndNoReleaseReadAsNothing() throws {
        let state = try ServerUpdateState.read(json("""
        {"enabled":true,"running":"2026.10.13","latest":null,"newer":[],"updateAvailable":false,"standing":"current",
         "helper":{"installed":false},"pending":false,"run":null}
        """))
        #expect(state.latest == nil)
        #expect(state.helper == ServerUpdateHelper())
        #expect(state.run == nil)
        #expect(!state.runActive)
    }

    @Test func wrongOrMissingValuesAreTheDefault() throws {
        let state = try ServerUpdateState.read(json(#"{"updateAvailable":"yes","newer":[{"name":"no tag"},{"tag":"2026.10.13"}],"run":{"tag":"x"}}"#))
        #expect(!state.updateAvailable)
        #expect(state.newer.map(\.tag) == ["2026.10.13"])
        #expect(state.run == nil)
        #expect(state.running == "")
    }

    @Test func updateNowNeedsANewerReleaseAndAHelperThatIsCurrentAndIdle() {
        #expect(behind().canUpdateNow)
        #expect(!behind(helper: ServerUpdateHelper()).canUpdateNow)
        #expect(!behind(helper: ServerUpdateHelper(installed: true, outdated: true)).canUpdateNow)
        #expect(!behind(pending: true).canUpdateNow)
        #expect(!behind(run: ServerUpdateRun(tag: "2026.10.13", state: "building")).canUpdateNow)
        #expect(behind(run: ServerUpdateRun(tag: "2026.10.12", state: "failed")).canUpdateNow)
        var current = behind()
        current.updateAvailable = false
        #expect(!current.canUpdateNow)
    }
}

@Suite struct ServerUpdateAnswerTests {
    @Test func listenersOlderServersAndMissingPagesShowNothing() {
        #expect(ServerUpdateCalls.readAnswer(status: 401, data: Data()) == .refused)
        #expect(ServerUpdateCalls.readAnswer(status: 403, data: json(#"{"error":"admin only"}"#)) == .refused)
        #expect(ServerUpdateCalls.readAnswer(status: 404, data: Data()) == .refused)
    }

    @Test func noAnswerOrAnUnreadableOneIsMissed() {
        #expect(ServerUpdateCalls.readAnswer(status: nil, data: Data()) == .missed)
        #expect(ServerUpdateCalls.readAnswer(status: 502, data: Data()) == .missed)
        #expect(ServerUpdateCalls.readAnswer(status: 200, data: json("<html>")) == .missed)
    }

    @Test func aGoodAnswerIsRead() {
        guard case .state(let state) = ServerUpdateCalls.readAnswer(status: 200, data: json(#"{"running":"2026.10.13"}"#)) else {
            Issue.record("not read")
            return
        }
        #expect(state.running == "2026.10.13")
    }

    @Test func startingReadsTheIdAndShowsTheServersOwnWordsOnARefusal() {
        #expect(ServerUpdateCalls.startAnswer(status: 202, data: json(#"{"ok":true,"id":"u7","tag":"2026.10.13"}"#), tag: "2026.10.13")
                == .started(id: "u7", tag: "2026.10.13"))
        #expect(ServerUpdateCalls.startAnswer(status: 202, data: Data(), tag: "2026.10.13") == .started(id: nil, tag: "2026.10.13"))
        #expect(ServerUpdateCalls.startAnswer(status: 409, data: json(#"{"error":"An update is already running."}"#), tag: "x")
                == .refused("An update is already running."))
        #expect(ServerUpdateCalls.startAnswer(status: 409, data: Data(), tag: "x") == .refused("The server can't start an update right now."))
        #expect(ServerUpdateCalls.startAnswer(status: 500, data: Data(), tag: "x") == .failed)
        #expect(ServerUpdateCalls.startAnswer(status: nil, data: Data(), tag: "x") == .failed)
    }

    @Test func callsGoSignedToTheServerInUseOnly() throws {
        let client = SubsonicClient(baseURL: URL(string: "https://music.example.com")!,
                                    credentials: Credentials(username: "me", password: "pw", mode: .token),
                                    device: DeviceIdentity(id: "d1", name: "Phone"), appVersion: "1.0")
        let read = ServerUpdateCalls.stateRequest(client, seconds: 5)
        #expect(read.url?.host == "music.example.com")
        #expect(read.url?.path == "/api/admin/update")
        #expect(read.url?.query?.contains("u=me") == true)
        #expect(read.timeoutInterval == 5)
        #expect(read.httpMethod == "GET")

        let start = ServerUpdateCalls.startRequest(client, tag: "2026.10.13")
        #expect(start.httpMethod == "POST")
        #expect(start.url?.path == "/api/admin/update")
        #expect(start.value(forHTTPHeaderField: "X-Octo-Admin") == "1")
        let body = try JSONSerialization.jsonObject(with: start.httpBody ?? Data()) as? [String: String]
        #expect(body == ["tag": "2026.10.13"])
        #expect(ServerUpdateCalls.dashboard(client).absoluteString == "https://music.example.com/admin/")
    }
}

@Suite struct ServerUpdateTagTests {
    @Test func tagsOrderByTheirNumbers() {
        #expect(compareServerTags("2026.10.13", "2026.10.11") == 1)
        #expect(compareServerTags("2026.10.03", "2026.10.03.1") == -1)
        #expect(compareServerTags("v2026.10.13", "2026.10.13") == 0)
        #expect(compareServerTags("2026.10.13", "2026.9.30") == 1)
        #expect(compareServerTags("nightly", "2026.10.13") == nil)
    }

    @Test func laterHidesUntilANewerReleaseComesOut() {
        #expect(!laterHides(latest: "2026.10.13", dismissed: nil))
        #expect(laterHides(latest: "2026.10.13", dismissed: "2026.10.13"))
        #expect(!laterHides(latest: "2026.10.14", dismissed: "2026.10.13"))
        #expect(!laterHides(latest: "2026.10.13.1", dismissed: "2026.10.13"))
        #expect(laterHides(latest: "2026.10.12", dismissed: "2026.10.13"))
        #expect(laterHides(latest: "beta", dismissed: "beta"))
        #expect(!laterHides(latest: "beta-2", dismissed: "beta"))
    }
}

@Suite struct ServerUpdatePanelTests {
    let now: Int64 = 1_800_000_000_000

    func panel(_ state: ServerUpdateState?, dismissed: String? = nil) -> ServerUpdatePanel {
        var tracker = ServerUpdateTracker()
        if let state { tracker.read(state, nowMs: now) }
        return tracker.panel(dismissed: dismissed, nowMs: now)
    }

    @Test func nothingShowsWithoutANewerRelease() {
        #expect(panel(nil) == .hidden)
        var current = behind()
        current.updateAvailable = false
        #expect(panel(current) == .hidden)
        var noLatest = behind()
        noLatest.latest = nil
        #expect(panel(noLatest) == .hidden)
    }

    @Test func aNewerReleaseIsOfferedInPlainWords() {
        guard case .offer(let offer) = panel(behind()) else {
            Issue.record("no offer")
            return
        }
        #expect(offer.words == "Octo 2026.10.13 is out. Your server runs 2026.10.11.")
        #expect(offer.action == .updateNow)
        #expect(offer.confirmWords == "Octo fetches 2026.10.13 and restarts. Music from your server stops for a minute or two.")
        #expect(offer.notes.map(\.tag) == ["2026.10.13"])
        #expect(panel(behind()).badged)
    }

    @Test func severalReleasesAheadAreCounted() {
        guard case .offer(let offer) = panel(behind(newer: ["2026.10.13", "2026.10.12"])) else {
            Issue.record("no offer")
            return
        }
        #expect(offer.words == "Octo 2026.10.13 is out. Your server runs 2026.10.11. That is 2 releases ahead.")
        #expect(offer.notes.map(\.tag) == ["2026.10.13", "2026.10.12"])
    }

    @Test func withoutAHelperTheDashboardIsTheWay() {
        guard case .offer(let offer) = panel(behind(helper: ServerUpdateHelper())) else {
            Issue.record("no offer")
            return
        }
        #expect(offer.action == .noHelper)
    }

    @Test func anOutdatedHelperAsksForItsReinstall() {
        let old = ServerUpdateHelper(installed: true, version: "1", outdated: true)
        guard case .offer(let offer) = panel(behind(helper: old)) else {
            Issue.record("no offer")
            return
        }
        #expect(offer.action == .outdatedHelper("curl -fsSL x | sh"))
        guard case .offer(let blank) = panel(behind(helper: old, reinstall: "  ")) else {
            Issue.record("no offer")
            return
        }
        #expect(blank.action == .outdatedHelper(nil))
    }

    @Test func laterHidesThePanelAndBadgeForThatReleaseOnly() {
        #expect(panel(behind(), dismissed: "2026.10.13") == .hidden)
        #expect(!panel(behind(), dismissed: "2026.10.13").badged)
        if case .offer = panel(behind(latest: "2026.10.14", newer: ["2026.10.14", "2026.10.13"]), dismissed: "2026.10.13") {
        } else {
            Issue.record("a newer release than the one put off should show")
        }
    }

    @Test func anUpdateUnderWayShowsItsStepEvenAfterLater() {
        let state = behind(run: ServerUpdateRun(id: "r1", tag: "2026.10.13", state: "building"))
        #expect(panel(state, dismissed: "2026.10.13") == .running(tag: "2026.10.13", step: .pulling))
        #expect(panel(behind(pending: true)) == .running(tag: "2026.10.13", step: .handed))
        let unfollowed = ServerUpdateTracker(state: behind(run: ServerUpdateRun(tag: "2026.10.13", state: "restarting")))
        #expect(unfollowed.panel(dismissed: nil, nowMs: now) == .running(tag: "2026.10.13", step: .restarting))
    }

    @Test func stepsFollowTheRunsState() {
        #expect(ServerUpdateStep(runState: "accepted") == .handed)
        #expect(ServerUpdateStep(runState: "fetching") == .fetching)
        #expect(ServerUpdateStep(runState: "building") == .pulling)
        #expect(ServerUpdateStep(runState: "restarting") == .restarting)
        #expect(ServerUpdateStep(runState: "done") == nil)
        #expect(ServerUpdateStep.allCases.map(\.words) ==
                ["Handed to the update helper", "Fetching the release", "Pulling the new Octo", "Restarting Octo"])
    }

    @Test func releaseNotesKeepOnlyGitHubLinks() {
        let blocks = serverReleaseNotes("""
        See [the release](https://github.com/winters27/octo/releases) and [elsewhere](https://evil.example.com/x).

        - [plain](http://github.com/x)
        """)
        guard case .paragraph(let spans) = blocks.first, case .bullets(let items) = blocks.last else {
            Issue.record("unexpected blocks \(blocks)")
            return
        }
        #expect(spans.first { $0.text == "the release" }?.link == "https://github.com/winters27/octo/releases")
        #expect(spans.first { $0.text == "elsewhere" }?.link == nil)
        #expect(items.first?.text.first?.link == nil)
        #expect(isGitHubLink("https://www.github.com/a"))
        #expect(!isGitHubLink("https://github.com.evil.example/a"))
        #expect(!isGitHubLink(nil))
    }
}

@Suite struct ServerUpdateFollowTests {
    let start: Int64 = 1_800_000_000_000

    func started() -> ServerUpdateTracker {
        var tracker = ServerUpdateTracker()
        tracker.read(behind(), nowMs: start)
        tracker.started(tag: "2026.10.13", id: "u7", nowMs: start)
        return tracker
    }

    @Test func handedOverItIsFollowedQuickly() {
        let tracker = started()
        #expect(tracker.following)
        #expect(tracker.nextPollMs(nowMs: start) == ServerUpdateTiming.runPollMs)
        #expect(tracker.panel(dismissed: nil, nowMs: start) == .running(tag: "2026.10.13", step: .handed))
    }

    @Test func eachStepShowsAsTheRunMoves() {
        var tracker = started()
        tracker.read(behind(pending: true), nowMs: start + 2_000)
        #expect(tracker.panel(dismissed: nil, nowMs: start + 2_000) == .running(tag: "2026.10.13", step: .handed))
        for (state, step) in [("fetching", ServerUpdateStep.fetching), ("building", .pulling), ("restarting", .restarting)] {
            tracker.read(behind(run: ServerUpdateRun(id: "u7", tag: "2026.10.13", state: state)), nowMs: start + 4_000)
            #expect(tracker.panel(dismissed: nil, nowMs: start + 4_000) == .running(tag: "2026.10.13", step: step))
        }
    }

    @Test func doneWhenTheRunSaysSo() {
        var tracker = started()
        let finished = tracker.read(behind(run: ServerUpdateRun(id: "u7", tag: "2026.10.13", state: "done")), nowMs: start + 60_000)
        #expect(finished)
        #expect(tracker.panel(dismissed: nil, nowMs: start + 60_000) == .done(tag: "2026.10.13"))
        #expect(!tracker.following)
        #expect(tracker.nextPollMs(nowMs: start + 60_000) == ServerUpdateTiming.idlePollMs)
        #expect(!tracker.panel(dismissed: nil, nowMs: start + 60_000).badged)
    }

    @Test func doneWhenTheServerRunsTheNewReleaseEvenWithoutARun() {
        var tracker = started()
        var now = ServerUpdateState(running: "2026.10.13", latest: release("2026.10.13"), updateAvailable: false, standing: "current")
        now.run = nil
        #expect(tracker.read(now, nowMs: start + 90_000))
        #expect(tracker.panel(dismissed: nil, nowMs: start + 90_000) == .done(tag: "2026.10.13"))
    }

    @Test func aFailureShowsTheServersWords() {
        var tracker = started()
        tracker.read(behind(run: ServerUpdateRun(id: "u7", tag: "2026.10.13", state: "failed", error: "git fetch failed: no route")),
                     nowMs: start + 30_000)
        #expect(tracker.panel(dismissed: nil, nowMs: start + 30_000) == .failed(tag: "2026.10.13", words: "git fetch failed: no route"))
        var blank = started()
        blank.read(behind(run: ServerUpdateRun(id: "u7", tag: "2026.10.13", state: "failed", error: " ")), nowMs: start + 30_000)
        #expect(blank.panel(dismissed: nil, nowMs: start + 30_000) == .failed(tag: "2026.10.13", words: "The update did not finish."))
    }

    @Test func anEarlierFailedRunIsNotTakenForThisOne() {
        var tracker = started()
        tracker.read(behind(pending: true, run: ServerUpdateRun(id: "old", tag: "2026.10.13", state: "failed", error: "old")),
                     nowMs: start + 2_000)
        #expect(tracker.panel(dismissed: nil, nowMs: start + 2_000) == .running(tag: "2026.10.13", step: .handed))
    }

    @Test func missedCallsReadAsRestartingForFifteenMinutesThenNotBack() {
        var tracker = started()
        tracker.read(behind(run: ServerUpdateRun(id: "u7", tag: "2026.10.13", state: "building")), nowMs: start + 2_000)
        let firstMiss = start + 4_000
        tracker.missed(refused: false, nowMs: firstMiss)
        #expect(tracker.panel(dismissed: nil, nowMs: firstMiss) == .running(tag: "2026.10.13", step: .restarting))
        tracker.missed(refused: true, nowMs: firstMiss + 60_000)
        #expect(tracker.panel(dismissed: nil, nowMs: firstMiss + 60_000) == .running(tag: "2026.10.13", step: .restarting))
        let late = firstMiss + ServerUpdateTiming.notBackAfterMs - 1
        #expect(tracker.panel(dismissed: nil, nowMs: late) == .running(tag: "2026.10.13", step: .restarting))
        #expect(tracker.nextPollMs(nowMs: late) == ServerUpdateTiming.runPollMs)
        let gone = firstMiss + ServerUpdateTiming.notBackAfterMs
        #expect(tracker.panel(dismissed: nil, nowMs: gone) == .notBack(tag: "2026.10.13"))
        #expect(tracker.nextPollMs(nowMs: gone) == ServerUpdateTiming.notBackPollMs)
        #expect(tracker.panel(dismissed: nil, nowMs: gone).badged)
    }

    @Test func anAnswerAfterMissedCallsStartsTheClockAgain() {
        var tracker = started()
        tracker.missed(refused: false, nowMs: start + 2_000)
        tracker.read(behind(run: ServerUpdateRun(id: "u7", tag: "2026.10.13", state: "restarting")), nowMs: start + 600_000)
        tracker.missed(refused: false, nowMs: start + 602_000)
        #expect(tracker.panel(dismissed: nil, nowMs: start + 602_000 + 14 * 60_000) == .running(tag: "2026.10.13", step: .restarting))
    }

    @Test func aServerThatComesBackLateStillFinishes() {
        var tracker = started()
        tracker.missed(refused: false, nowMs: start + 2_000)
        #expect(tracker.panel(dismissed: nil, nowMs: start + 20 * 60_000) == .notBack(tag: "2026.10.13"))
        let back = ServerUpdateState(running: "2026.10.13", latest: release("2026.10.13"), standing: "current")
        #expect(tracker.read(back, nowMs: start + 21 * 60_000))
        #expect(tracker.panel(dismissed: nil, nowMs: start + 21 * 60_000) == .done(tag: "2026.10.13"))
    }

    @Test func aRunThatVanishesWhileTheOldReleaseStillRunsFailed() {
        var tracker = started()
        tracker.read(behind(run: ServerUpdateRun(id: "u7", tag: "2026.10.13", state: "fetching")), nowMs: start + 2_000)
        var stopped = behind()
        stopped.unanswered = "The update helper did not answer."
        tracker.read(stopped, nowMs: start + 4_000)
        #expect(tracker.panel(dismissed: nil, nowMs: start + 4_000) == .failed(tag: "2026.10.13", words: "The update helper did not answer."))
    }

    @Test func aRunNotListedYetRightAfterHandingOverIsWaitedFor() {
        var tracker = started()
        tracker.read(behind(), nowMs: start + 2_000)
        #expect(tracker.panel(dismissed: nil, nowMs: start + 2_000) == .running(tag: "2026.10.13", step: .handed))
        tracker.read(behind(), nowMs: start + ServerUpdateTiming.settleMs)
        #expect(tracker.panel(dismissed: nil, nowMs: start + ServerUpdateTiming.settleMs) == .failed(tag: "2026.10.13", words: "The update did not finish."))
    }

    @Test func refusedReadsHideThePanelWhenNothingIsFollowed() {
        var tracker = ServerUpdateTracker()
        tracker.read(behind(), nowMs: start)
        tracker.missed(refused: false, nowMs: start + 1)
        #expect(tracker.panel(dismissed: nil, nowMs: start + 1) != .hidden)
        tracker.missed(refused: true, nowMs: start + 2)
        #expect(tracker.panel(dismissed: nil, nowMs: start + 2) == .hidden)
    }

    @Test func anUpdateStartedElsewhereIsFollowedToo() {
        var tracker = ServerUpdateTracker()
        tracker.read(behind(run: ServerUpdateRun(id: "dash", tag: "2026.10.13", state: "fetching")), nowMs: start)
        #expect(tracker.following)
        #expect(tracker.watch?.id == "dash")
        tracker.read(behind(run: ServerUpdateRun(id: "dash", tag: "2026.10.13", state: "done")), nowMs: start + 2_000)
        #expect(tracker.panel(dismissed: nil, nowMs: start + 2_000) == .done(tag: "2026.10.13"))
    }

    @Test func closingTheResultLeavesWhatTheServerSays() {
        var tracker = started()
        tracker.read(ServerUpdateState(running: "2026.10.13", latest: release("2026.10.13"), standing: "current"), nowMs: start + 60_000)
        tracker.closeResult(nowMs: start + 60_000)
        #expect(tracker.watch == nil)
        #expect(tracker.panel(dismissed: nil, nowMs: start + 60_000) == .hidden)
    }

    @Test func anUpdateUnderWayCannotBeClosed() {
        var tracker = started()
        tracker.closeResult(nowMs: start + 1_000)
        #expect(tracker.following)
        tracker.missed(refused: false, nowMs: start + 2_000)
        tracker.closeResult(nowMs: start + 2_000 + ServerUpdateTiming.notBackAfterMs)
        #expect(tracker.watch == nil)
    }
}
