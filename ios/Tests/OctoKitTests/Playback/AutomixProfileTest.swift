import Foundation
import Testing
@testable import OctoKit

/// A song's transition profile as Octo sends it (transition-profile.json, the server's own
/// output for the song below), what the player reads from it, and the plan it makes: the one a
/// scout of the same song would make.
@Suite struct AutomixProfileTest {
    /// 75 s at 120 BPM: a quiet 4 s intro, a kick on every bar and a click on every beat, then a
    /// 15 s fade from 60 s. The server's fixture song.
    let song = SyntheticSong(rate: 22_050, channels: 1, lengthMs: 75_000, layers: [
        SongLayer("tone", 0, 4_000, hz: 300, db: -40),
        SongLayer("tone", 4_000, 60_000, hz: 300, db: -22),
        SongLayer("tone", 60_000, 75_000, hz: 300, db: -22, endDb: -70),
        SongLayer("pulse", 4_000, 60_000, hz: 60, db: -6, bpm: 120, firstMs: 4_000, every: 4, decayMs: 80),
        SongLayer("pulse", 4_000, 60_000, hz: 2_000, db: -16, bpm: 120, firstMs: 4_000, every: 1, decayMs: 10),
    ])

    func fixture() -> TransitionProfileAnswer {
        var answer = try! TransitionProfileAnswer.parse(transitionProfileJSON)
        answer.id = "nd-1"
        answer.ready = true
        return answer
    }

    @Test func theServersProfileReadsWhole() throws {
        let profile = try #require(TransitionProfile.of(fixture()))
        #expect(profile.durationMs == 75_000)
        #expect(profile.head.startMs == 0)
        #expect(profile.head.hopMs == 100)
        #expect(profile.head.levels.count == 300)
        #expect(profile.tail.startMs == 15_000)
        #expect(profile.tail.levels.count == 600)
        #expect(abs(profile.tempoPrior! - 120) < 0.5)
        let intro = profile.head.features.introEndMs!
        #expect((3_400...4_300).contains(intro), "intro end \(intro)")
        #expect(profile.tail.levels[200] > -30, "\(profile.tail.levels[200])")
        #expect(profile.tail.levels[590] < -50, "\(profile.tail.levels[590])")
    }

    @Test func theFeaturesAreTheOnesTheAppFindsInTheSameSong() throws {
        let profile = try #require(TransitionProfile.of(fixture()))
        let whole = song.envelope(0, 75_000)
        let body = try #require(bodyLevelOf(whole))
        let scouted = song.tail().withBodyLevel(body).features
        let served = profile.tail.features
        #expect(abs(body - profile.bodyDb!) <= 0.01)
        for (name, mine, theirs) in [("sound start", scouted.soundStartMs, served.soundStartMs),
                                     ("sound end", scouted.soundEndMs, served.soundEndMs),
                                     ("outro", scouted.outroStartMs, served.outroStartMs)] {
            #expect(abs(mine! - theirs!) <= 100, "\(name): scouted \(mine!), served \(theirs!)")
        }
        let head = song.head().features
        #expect(abs(head.introEndMs! - profile.head.features.introEndMs!) <= 20)
        #expect(abs(head.tempo!.bpm - profile.head.features.tempo!.bpm) < 0.1)
    }

    @Test func aProfilePlansTheBlendAScoutWould() throws {
        let profile = try #require(TransitionProfile.of(fixture()))
        let whole = song.envelope(0, 75_000)
        let current = FadeSong(albumId: nil, albumOrder: nil, durationMs: 75_000)
        let next = FadeSong(albumId: nil, albumOrder: nil, durationMs: 75_000)
        let settings = AutomixSettings(maxOverlapMs: 8_000)
        let heardTempo = analyzeHead(whole).features.tempo
        let heard = TransitionContext(bodyLevelDb: bodyLevelOf(whole), tempoPrior: heardTempo?.confident == true ? heardTempo?.bpm : nil)
        let scouted = planTransition(current: current, next: next, tail: song.tail(), head: song.head(), settings: settings, context: heard)
        let served = planTransition(current: current, next: next, tail: profile.tailAnalysis(), head: profile.headAnalysis(),
                                    settings: settings, context: TransitionContext(tempoPrior: profile.tempoPrior))
        #expect(scouted.kind == served.kind, "\(served) / \(scouted)")
        #expect(abs(scouted.startMs - served.startMs) <= 300, "\(served) / \(scouted)")
        #expect(abs(scouted.overlapMs - served.overlapMs) <= 300, "\(served) / \(scouted)")
        #expect(abs(scouted.entryMs - served.entryMs) <= 20, "\(served) / \(scouted)")
        #expect(scouted.barLocked == served.barLocked)
    }

    @Test func aProfileThePlayerCannotReadIsNone() {
        let ready = fixture()
        var notReady = ready
        notReady.ready = false
        #expect(TransitionProfile.of(notReady) == nil)
        var newer = ready
        newer.version = profileVersion + 1
        #expect(TransitionProfile.of(newer) == nil)
        var noTail = ready
        noTail.tail = nil
        #expect(TransitionProfile.of(noTail) == nil)
        var badLevels = ready
        badLevels.head!.levels = "not base64!"
        #expect(TransitionProfile.of(badLevels) == nil)
        var noHop = ready
        noHop.head!.hopMs = 0
        #expect(TransitionProfile.of(noHop) == nil)
    }

    @Test func levelsComeInHalfDecibelSteps() {
        #expect(levelOfCode(0) == silentDb)
        #expect(levelOfCode(171) == -14.5)
        #expect(levelOfCode(255) == 27.5)
    }

    @Test func aProfileIsAskedForOnceAndANotReadyAnswerRestsAMinute() async throws {
        final class State: @unchecked Sendable {
            var clock = 0
            var asked: [String] = []
        }
        let state = State()
        let answers = ["ready": fixture(), "later": TransitionProfileAnswer(id: "later", ready: false, version: 1)]
        let profiles = TransitionProfiles(fetch: { id in
            state.asked.append(id)
            guard let answer = answers[id] else { throw URLError(.cannotConnectToHost) }
            return answer
        }, now: { state.clock })

        let first = try #require(await profiles.profile("ready"))
        #expect(await profiles.profile("ready") === first)
        #expect(profiles.cached("ready") === first)
        #expect(await profiles.profile("later") == nil)
        #expect(await profiles.profile("later") == nil)
        #expect(await profiles.profile("broken") == nil)
        #expect(state.asked == ["ready", "later", "broken"])

        state.clock += profileRetryMs
        #expect(await profiles.profile("later") == nil)
        #expect(state.asked == ["ready", "later", "broken", "later"])

        profiles.clear()
        #expect(profiles.cached("ready") == nil)
    }
}
