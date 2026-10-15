import Foundation
import Testing
@testable import OctoKit

private func json(_ text: String) -> Data { Data(text.utf8) }

private func release(_ tag: String, notes: String? = nil) -> ServerRelease {
    ServerRelease(tag: tag, name: tag, notes: notes, url: "https://github.com/winters27/octo/releases/tag/\(tag)")
}

private func status(running: String = "2026.10.11", newer: [String] = ["2026.10.13"],
                    helper: ServerUpdateHelper = ServerUpdateHelper(installed: true, version: "2", mode: "image"),
                    pending: Bool = false, pendingId: String? = nil, unanswered: String? = nil,
                    run: ServerUpdateRun? = nil, standing: String? = nil) -> ServerUpdateState {
    ServerUpdateState(enabled: true, repo: "winters27/octo", running: running,
                      latest: release(newer.first ?? running), newer: newer.map { release($0) },
                      updateAvailable: !newer.isEmpty, standing: standing ?? (newer.isEmpty ? "current" : "behind"),
                      helper: helper, reinstallCommand: "scripts/updater/install-updater.sh", pending: pending,
                      pendingId: pendingId, unanswered: unanswered, run: run)
}

private func answered(_ s: ServerUpdateState) -> ServerUpdateAnswer { .state(s) }

private func run(_ state: String, id: String = "r1", tag: String = "2026.10.13", error: String? = nil) -> ServerUpdateRun {
    ServerUpdateRun(id: id, tag: tag, state: state, error: error)
}

private func offer(_ track: ServerUpdateTrack) -> ServerUpdateOffer? {
    if case .available(let offer) = track.panel { return offer }
    return nil
}

private func steps(_ track: ServerUpdateTrack) -> [ServerUpdateStepLine]? {
    if case .updating(_, let steps) = track.panel { return steps }
    return nil
}

private extension ServerUpdateTrack {
    func startedHere(_ id: String? = "r1", _ tag: String = "2026.10.13") -> ServerUpdateTrack {
        beganStart().started(.started(id: id, tag: tag))
    }
}

@Suite struct ServerUpdateReadingTests {
    @Test func readsAFullAnswer() throws {
        let state = try ServerUpdateState.read(json("""
        {"enabled":true,"repo":"winters27/octo","running":"2026.10.11",
         "latest":{"tag":"2026.10.13","name":"2026.10.13","notes":"## Fixes\\n- One","url":"https://github.com/winters27/octo/releases/tag/2026.10.13","publishedUtc":"2026-10-13T02:00:00Z"},
         "newer":[{"tag":"2026.10.13","name":"2026.10.13","notes":"n","url":"u","publishedUtc":null},{"tag":"2026.10.12","name":null,"notes":null,"url":null,"publishedUtc":null}],
         "updateAvailable":true,"standing":"behind","checkedUtc":"2026-10-13T03:00:00Z","error":null,
         "helper":{"installed":true,"version":"2","mode":"image","dir":"/opt/octo","installedUtc":"2026-10-01T00:00:00Z","outdated":false},
         "reinstallCommand":"scripts/updater/install-updater.sh","pending":false,"pendingId":null,"unanswered":null,
         "run":{"id":"r1","tag":"2026.10.11","from":"2026.10.10","state":"done","step":null,"error":null,"startedUtc":"x","finishedUtc":"y","log":["one"]},
         "command":"git fetch --tags","imageCommand":"docker compose pull","somethingNew":42}
        """))
        #expect(state.running == "2026.10.11")
        #expect(state.latest?.tag == "2026.10.13")
        #expect(state.newer.map(\.tag) == ["2026.10.13", "2026.10.12"])
        #expect(state.updateAvailable)
        #expect(state.helper == ServerUpdateHelper(installed: true, version: "2", mode: "image", dir: "/opt/octo",
                                                   installedUtc: "2026-10-01T00:00:00Z", outdated: false))
        #expect(state.run?.state == ServerRunState.done)
        #expect(state.run?.log == ["one"])
        #expect(!state.busy)
        #expect(state.canUpdate)
    }

    @Test func readsTheShortestAnswer() throws {
        let state = try ServerUpdateState.read(json("""
        {"enabled":false,"repo":"winters27/octo","running":"2026.10.11","latest":null,"newer":[],"updateAvailable":false,"standing":"unknown","checkedUtc":null,"error":null,"helper":{"installed":false},"reinstallCommand":"r","pending":false,"pendingId":null,"unanswered":null,"run":null,"command":"c","imageCommand":"i"}
        """))
        #expect(state.latest == nil)
        #expect(!state.helper.installed)
        #expect(!state.canUpdate)
    }

    @Test func wrongOrMissingValuesAreTheDefault() throws {
        let state = try ServerUpdateState.read(json(#"{"updateAvailable":"yes","newer":[{"name":"no tag"},{"tag":"2026.10.13"}],"run":{"tag":"x"}}"#))
        #expect(!state.updateAvailable)
        #expect(state.newer.map(\.tag) == ["2026.10.13"])
        #expect(state.run == nil)
        #expect(state.running == "")
    }

    @Test func somethingElseIsNotAnAnswer() {
        #expect(throws: (any Error).self) { try ServerUpdateState.read(json("<html>Bad gateway</html>")) }
        #expect(throws: (any Error).self) { try ServerUpdateState.read(Data()) }
    }

    @Test func updateNowIsOnlyPossibleWhenNothingStandsInTheWay() {
        #expect(status().canUpdate)
        #expect(!status(helper: ServerUpdateHelper(installed: false)).canUpdate)
        #expect(!status(helper: ServerUpdateHelper(installed: true, outdated: true)).canUpdate)
        #expect(!status(pending: true).canUpdate)
        #expect(!status(run: run(ServerRunState.fetching, id: "r")).canUpdate)
        #expect(status(run: run(ServerRunState.done, id: "r", tag: "2026.10.12")).canUpdate)
        #expect(!status(newer: []).canUpdate)
    }
}

@Suite struct ServerUpdateTagTests {
    @Test func ordersDatedTags() {
        #expect(compareReleaseTags("2026.10.13", "2026.10.11") > 0)
        #expect(compareReleaseTags("2026.10.03.1", "2026.10.03") > 0)
        #expect(compareReleaseTags("2026.10.03", "2026.10.03.1") < 0)
        #expect(compareReleaseTags("2026.9.30", "2026.10.01") < 0)
        #expect(compareReleaseTags("2026.10.13", "2026.10.13") == 0)
        #expect(compareReleaseTags("v2026.10.13", "2026.10.13") == 0)
    }

    @Test func wordsCompareAsWords() {
        #expect(compareReleaseTags("2026.10.13-beta", "2026.10.13-rc") < 0)
        #expect(compareReleaseTags("nightly", "nightly") == 0)
    }
}

@Suite struct ServerUpdateTrackTests {
    @Test func aNewerReleaseShowsThePanelWithUpdateNow() throws {
        let shown = try #require(offer(ServerUpdateTrack().read(answered(status()), nowMs: 0)))
        #expect(shown.latest.tag == "2026.10.13")
        #expect(shown.way == .now)
        #expect(ServerUpdateWords.headline(shown) == "Octo 2026.10.13 is out.")
        #expect(ServerUpdateWords.detail(shown) == "Your server runs 2026.10.11.")
        #expect(ServerUpdateWords.way(shown.way) == nil)
    }

    @Test func severalReleasesSayHowFarAhead() throws {
        let shown = try #require(offer(ServerUpdateTrack().read(answered(status(newer: ["2026.10.13", "2026.10.12", "2026.10.11.1"])), nowMs: 0)))
        #expect(ServerUpdateWords.detail(shown) == "Your server runs 2026.10.11. That is 3 releases ahead.")
        #expect(shown.newer.count == 3)
    }

    @Test func upToDateShowsNoPanelButAFactsLine() {
        let track = ServerUpdateTrack().read(answered(status(running: "2026.10.13", newer: [])), nowMs: 0)
        #expect(track.panel == .hidden)
        #expect(!track.showsDot)
        #expect(track.upToDateLine == "Octo 2026.10.13, up to date")
    }

    @Test func anUnknownStandingSaysNothingAboutBeingUpToDate() {
        let track = ServerUpdateTrack().read(answered(status(running: "2026.10.13", newer: [], standing: "unknown")), nowMs: 0)
        #expect(track.upToDateLine == nil)
    }

    @Test func noHelperOffersTheDashboard() throws {
        let shown = try #require(offer(ServerUpdateTrack().read(answered(status(helper: ServerUpdateHelper(installed: false))), nowMs: 0)))
        #expect(shown.way == .noHelper)
        #expect(ServerUpdateWords.way(.noHelper) == "You can update it from Octo's dashboard.")
    }

    @Test func anOutdatedHelperAsksForItToBeReinstalled() throws {
        let helper = ServerUpdateHelper(installed: true, version: "1", outdated: true)
        let shown = try #require(offer(ServerUpdateTrack().read(answered(status(helper: helper)), nowMs: 0)))
        #expect(shown.way == .helperOutdated)
        #expect(shown.reinstallCommand == "scripts/updater/install-updater.sh")
        #expect(ServerUpdateWords.way(.helperOutdated)?.hasSuffix("Run this on the server, or update from the dashboard:") == true)
    }

    @Test func aServerThatDoesNotOfferItShowsNothing() {
        let shown = ServerUpdateTrack().read(answered(status()), nowMs: 0)
        let track = shown.read(.refused, nowMs: 1)
        #expect(track.panel == .hidden)
        #expect(!track.showsDot)
        #expect(ServerUpdateTrack().read(.refused, nowMs: 0).panel == .hidden)
    }

    @Test func noAnswerOutsideAnUpdateKeepsWhatWasKnown() {
        let shown = ServerUpdateTrack().read(answered(status()), nowMs: 0)
        #expect(shown.read(.missed, nowMs: 1) == shown)
        #expect(ServerUpdateTrack().read(.missed, nowMs: 0).panel == .hidden)
    }

    @Test func laterHidesTheNewsUntilANewerRelease() {
        let dismissed = ServerUpdateTrack().read(answered(status()), nowMs: 0).later()
        #expect(dismissed.dismissed == "2026.10.13")
        #expect(dismissed.panel == .hidden)
        #expect(!dismissed.showsDot)
        // The same release asked about again stays put away.
        #expect(dismissed.read(answered(status()), nowMs: 1).panel == .hidden)
        // A newer one brings it back.
        let newer = dismissed.read(answered(status(newer: ["2026.10.13.1", "2026.10.13"])), nowMs: 2)
        #expect(offer(newer) != nil)
        #expect(newer.showsDot)
    }

    @Test func laterNeverHidesAnUpdateUnderWay() {
        let track = ServerUpdateTrack(dismissed: "2026.10.13").read(answered(status(run: run(ServerRunState.fetching))), nowMs: 0)
        #expect(steps(track) != nil)
    }

    @Test func aStartedUpdateWalksThroughItsSteps() throws {
        let start = ServerUpdateTrack().read(answered(status()), nowMs: 0).startedHere()
        #expect(start.nextReadMs == ServerUpdateTiming.activeReadMs)
        func states(_ t: ServerUpdateTrack) -> [ServerUpdateStepState]? { steps(t)?.map(\.state) }

        #expect(states(start) == [.now, .waiting, .waiting, .waiting])
        let pending = start.read(answered(status(pending: true, pendingId: "r1")), nowMs: 1)
        #expect(states(pending) == [.now, .waiting, .waiting, .waiting])
        let fetching = pending.read(answered(status(run: run(ServerRunState.fetching))), nowMs: 2)
        #expect(states(fetching) == [.done, .now, .waiting, .waiting])
        let pulling = fetching.read(answered(status(run: run(ServerRunState.building))), nowMs: 3)
        #expect(try #require(steps(pulling))[2].words == "Pulling the new Octo")
        let restarting = pulling.read(answered(status(run: run(ServerRunState.restarting))), nowMs: 4)
        #expect(states(restarting) == [.done, .done, .done, .now])
        #expect(steps(restarting)?.map(\.words) == ["Handed to the update helper", "Fetching the release", "Pulling the new Octo", "Restarting Octo"])
    }

    @Test func aHelperThatBuildsSaysSo() throws {
        let track = ServerUpdateTrack().read(answered(status(helper: ServerUpdateHelper(installed: true, mode: "build"))), nowMs: 0).startedHere()
        #expect(try #require(steps(track))[2].words == "Building the new Octo")
    }

    @Test func theUpdateIsDoneWhenTheServerRunsTheNewRelease() {
        let going = ServerUpdateTrack().read(answered(status()), nowMs: 0).startedHere()
            .read(answered(status(run: run(ServerRunState.restarting))), nowMs: 1)
        // The new release answers, its run still saying "restarting".
        let done = going.read(answered(status(running: "2026.10.13", newer: [], run: run(ServerRunState.restarting))), nowMs: 2)
        #expect(done.panel == .finished(.done(tag: "2026.10.13")))
        #expect(ServerUpdateWords.outcomeTitle(.done(tag: "2026.10.13")) == "Your server now runs 2026.10.13.")
        #expect(ServerUpdateWords.outcomeDetail(.done(tag: "2026.10.13")) == nil)
        #expect(done.watch == nil)
        #expect(done.nextReadMs == ServerUpdateTiming.idleReadMs)
        #expect(!done.showsDot)
        // Closing it leaves nothing: the server is up to date.
        #expect(done.closeOutcome().panel == .hidden)
    }

    @Test func theUpdateIsDoneWhenItsRunSaysSo() {
        let going = ServerUpdateTrack().read(answered(status()), nowMs: 0).startedHere()
        let done = going.read(answered(status(run: run(ServerRunState.done))), nowMs: 1)
        #expect(done.panel == .finished(.done(tag: "2026.10.13")))
    }

    @Test func aFailedRunSaysWhyInTheServersWords() throws {
        let going = ServerUpdateTrack().read(answered(status()), nowMs: 0).startedHere()
        let failed = going.read(answered(status(run: run(ServerRunState.failed, error: "docker compose pull failed: no space left"))), nowMs: 1)
        #expect(failed.panel == .finished(.failed(tag: "2026.10.13", words: "docker compose pull failed: no space left")))
        #expect(failed.showsDot)
        #expect(ServerUpdateWords.outcomeTitle(.failed(tag: "2026.10.13", words: "x")) == "The update to 2026.10.13 did not finish.")
        // Once read, the release is offered again, with the reason.
        let again = try #require(offer(failed.closeOutcome()))
        #expect(again.lastFailure == "docker compose pull failed: no space left")
        #expect(ServerUpdateWords.lastFailure(again.lastFailure ?? "") == "The last try stopped: docker compose pull failed: no space left")
    }

    @Test func aFailedRunWithoutWordsSaysItStopped() {
        let going = ServerUpdateTrack().read(answered(status()), nowMs: 0).startedHere()
        let failed = going.read(answered(status(run: run(ServerRunState.failed, error: "  "))), nowMs: 1)
        #expect(failed.outcome == .failed(tag: "2026.10.13", words: "The update stopped before it finished."))
    }

    @Test func aRequestTheHelperNeverPickedUpFails() {
        let going = ServerUpdateTrack().read(answered(status()), nowMs: 0).startedHere()
            .read(answered(status(pending: true, pendingId: "r1")), nowMs: 1)
        let silent = going.read(answered(status(unanswered: "r1")), nowMs: 2)
        #expect(silent.outcome == .failed(tag: "2026.10.13", words: ServerUpdateWords.helperSilent))
    }

    @Test func aRunThatVanishesOnTheOldReleaseFails() {
        let going = ServerUpdateTrack().read(answered(status()), nowMs: 0).startedHere()
        let gone = going.read(answered(status()), nowMs: 1)
        #expect(gone.outcome == .failed(tag: "2026.10.13",
                                        words: "The update stopped before it finished. Your server still runs 2026.10.11."))
    }

    @Test func silenceDuringAnUpdateReadsAsRestartingForFifteenMinutes() throws {
        let grace = ServerUpdateTiming.restartGraceMs
        let going = ServerUpdateTrack().read(answered(status()), nowMs: 0).startedHere()
            .read(answered(status(run: run(ServerRunState.building))), nowMs: 1_000)
        let quiet = going.read(.missed, nowMs: 10_000)
        let last = try #require(steps(quiet)?.last)
        #expect(last.state == .now)
        #expect(last.words == "Restarting Octo")
        // A refusal while it restarts (a proxy, an old page) is silence too.
        let stillQuiet = quiet.read(.refused, nowMs: 10_000 + grace - 1)
        #expect(steps(stillQuiet) != nil)
        let notBack = stillQuiet.read(.missed, nowMs: 10_000 + grace)
        #expect(notBack.panel == .finished(.notBack(tag: "2026.10.13")))
        #expect(notBack.showsDot)
        #expect(ServerUpdateWords.outcomeTitle(.notBack(tag: "x")) == "Your server has not come back.")
        #expect(ServerUpdateWords.outcomeDetail(.notBack(tag: "x"))
                == "Octo has not answered for 15 minutes since it began restarting. Check the server, or open the dashboard once it answers.")
    }

    @Test func anAnswerResetsTheQuietClock() {
        let grace = ServerUpdateTiming.restartGraceMs
        let going = ServerUpdateTrack().read(answered(status()), nowMs: 0).startedHere()
        let quiet = going.read(.missed, nowMs: 0)
        let back = quiet.read(answered(status(run: run(ServerRunState.restarting))), nowMs: grace - 10)
        let quietAgain = back.read(.missed, nowMs: grace)
        #expect(steps(quietAgain) != nil)
    }

    @Test func anUpdateStartedElsewhereIsFollowedButItsEndIsNotAnnounced() {
        let track = ServerUpdateTrack().read(answered(status(pending: true, pendingId: "d1")), nowMs: 0)
        guard case .updating(let tag, _) = track.panel else {
            Issue.record("not followed")
            return
        }
        #expect(tag == "2026.10.13")
        let done = track.read(answered(status(running: "2026.10.13", newer: [])), nowMs: 1)
        #expect(done.panel == .hidden)
    }

    @Test func anotherReleasesRunUnderWayIsTheOneFollowed() {
        let going = ServerUpdateTrack().read(answered(status()), nowMs: 0).startedHere()
        let other = going.read(answered(status(run: run(ServerRunState.fetching, id: "d2", tag: "2026.10.13.1"))), nowMs: 1)
        #expect(other.watch?.tag == "2026.10.13.1")
        #expect(other.watch?.byThisApp == false)
    }

    @Test func aRefusalShowsTheServersWords() throws {
        let refused = ServerUpdateTrack().read(answered(status()), nowMs: 0).beganStart()
            .started(.refused("An update is already under way."))
        let shown = try #require(offer(refused))
        #expect(shown.problem == "An update is already under way.")
        #expect(!shown.starting)
    }

    @Test func startingShowsOnTheOffer() throws {
        let starting = ServerUpdateTrack().read(answered(status()), nowMs: 0).beganStart()
        #expect(try #require(offer(starting)).starting)
        #expect(starting.nextReadMs == ServerUpdateTiming.activeReadMs)
    }

    @Test func anOldFinishedRunIsNotFollowed() {
        let track = ServerUpdateTrack().read(answered(status(run: run(ServerRunState.done, id: "old", tag: "2026.10.11"))), nowMs: 0)
        #expect(track.watch == nil)
        #expect(offer(track) != nil)
    }

    @Test func askingIsRareUnlessAnUpdateIsUnderWay() {
        #expect(ServerUpdateTrack().nextReadMs == 3 * 60 * 60 * 1_000)
        #expect(ServerUpdateTiming.activeReadMs == 2_000)
        #expect(ServerUpdateTiming.callSeconds == 5)
    }

    @Test func theQuestionBeforeUpdating() {
        #expect(ServerUpdateWords.confirmTitle == "Update your server?")
        #expect(ServerUpdateWords.confirmDetail("2026.10.13") == "Octo fetches 2026.10.13 and restarts. Music from your server stops for a minute or two.")
        #expect(ServerUpdateWords.updatingTitle("2026.10.13") == "Updating your server to 2026.10.13")
    }
}

@Suite struct ServerUpdateCallTests {
    @Test func listenersOlderServersAndMissingPagesShowNothing() {
        #expect(ServerUpdateCalls.readAnswer(status: 401, data: Data()) == .refused)
        #expect(ServerUpdateCalls.readAnswer(status: 403, data: json(#"{"error":"admin only"}"#)) == .refused)
        #expect(ServerUpdateCalls.readAnswer(status: 404, data: Data()) == .refused)
    }

    @Test func aGatewayErrorOrAPageIsNoAnswer() {
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

    @Test func startingReadsTheIdAndARefusalCarriesTheServersWords() {
        #expect(ServerUpdateCalls.startAnswer(status: 202, data: json(#"{"ok":true,"id":"r1","tag":"2026.10.13"}"#), tag: "2026.10.13")
                == .started(id: "r1", tag: "2026.10.13"))
        #expect(ServerUpdateCalls.startAnswer(status: 202, data: Data(), tag: "2026.10.13") == .started(id: nil, tag: "2026.10.13"))
        #expect(ServerUpdateCalls.startAnswer(status: 409, data: json(#"{"error":"An update is already under way."}"#), tag: "x")
                == .refused("An update is already under way."))
        #expect(ServerUpdateCalls.startAnswer(status: 409, data: Data(), tag: "x") == .refused("Octo would not start the update just now."))
        for code in [401, 403, 404] {
            #expect(ServerUpdateCalls.startAnswer(status: code, data: Data(), tag: "x") == .refused("Only a Navidrome admin can update the server."))
        }
        #expect(ServerUpdateCalls.startAnswer(status: 500, data: json(#"{"error":"Disk full."}"#), tag: "x") == .refused("Disk full."))
        #expect(ServerUpdateCalls.startAnswer(status: 500, data: Data(), tag: "x") == .refused("Octo did not answer. Try again in a moment."))
        #expect(ServerUpdateCalls.startAnswer(status: nil, data: Data(), tag: "x") == .refused("Octo did not answer. Try again in a moment."))
    }

    @Test func callsGoSignedToTheServersOwnAddress() throws {
        let client = SubsonicClient(baseURL: URL(string: "https://music.example.com/navidrome")!,
                                    credentials: Credentials(username: "me", password: "pw", mode: .token),
                                    device: DeviceIdentity(id: "d1", name: "Phone"), appVersion: "1.0")
        let read = ServerUpdateCalls.stateRequest(client)
        #expect(read.url?.host == "music.example.com")
        #expect(read.url?.path == "/api/admin/update")
        #expect(read.url?.query?.contains("u=me") == true)
        #expect(read.timeoutInterval == ServerUpdateTiming.callSeconds)
        #expect(read.httpMethod == "GET")
        #expect(read.value(forHTTPHeaderField: "X-Octo-Admin") == nil)

        let start = ServerUpdateCalls.startRequest(client, tag: "2026.10.13")
        #expect(start.httpMethod == "POST")
        #expect(start.url?.path == "/api/admin/update")
        #expect(start.value(forHTTPHeaderField: "X-Octo-Admin") == "1")
        let body = try JSONSerialization.jsonObject(with: start.httpBody ?? Data()) as? [String: String]
        #expect(body == ["tag": "2026.10.13"])
        #expect(ServerUpdateCalls.dashboard(client).absoluteString == "https://music.example.com/admin/")
    }
}

@Suite struct ServerUpdateNotesTests {
    @Test func notesKeepOnlyGitHubLinks() {
        let blocks = serverReleaseNotes("See [the issue](https://github.com/winters27/octo/issues/9) and [elsewhere](https://example.com/x).\n\n- [plain http](http://github.com/a)")
        guard case .paragraph(let spans) = blocks.first, case .bullets(let items) = blocks.last else {
            Issue.record("unexpected blocks \(blocks)")
            return
        }
        #expect(spans.first { $0.text == "the issue" }?.link == "https://github.com/winters27/octo/issues/9")
        #expect(spans.first { $0.text == "elsewhere" }?.link == nil)
        #expect(items.first?.text.allSatisfy { $0.link == nil } == true)
    }

    @Test func aReleaseIsTitledByItsNameOrTag() {
        #expect(ServerUpdateWords.releaseTitle(ServerRelease(tag: "2026.10.13", name: "2026.10.13")) == "Octo 2026.10.13")
        #expect(ServerUpdateWords.releaseTitle(ServerRelease(tag: "2026.10.13")) == "Octo 2026.10.13")
        #expect(ServerUpdateWords.releaseTitle(ServerRelease(tag: "2026.10.13", name: "Faster radio")) == "Faster radio")
    }

    @Test func onlyGitHubCounts() {
        #expect(isGitHubLink("https://github.com/winters27/octo"))
        #expect(!isGitHubLink("https://github.com.evil.example/x"))
        #expect(!isGitHubLink("https://gist.github.com/x"))
        #expect(!isGitHubLink("http://github.com/x"))
        #expect(!isGitHubLink("javascript:alert(1)"))
        #expect(!isGitHubLink(nil))
    }
}
