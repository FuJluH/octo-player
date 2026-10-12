import Foundation
import Testing
@testable import OctoKit

/// A clock that moves only when told, running what falls due in time order.
final class ManualClock: PlaybackClock {
    var time = 0
    private var waiting: [(at: Int, id: Int, block: () -> Void)] = []
    private var nextId = 0

    func now() -> Int { time }
    func wallNow() -> Int { time }

    func after(_ ms: Int, _ block: @escaping () -> Void) -> () -> Void {
        let id = nextId
        nextId += 1
        waiting.append((time + ms, id, block))
        return { [weak self] in self?.waiting.removeAll { $0.id == id } }
    }

    /// The wait most recently set, in ms from now, if any is left.
    var pendingMs: Int? { waiting.map { $0.at - time }.min() }

    func elapse(_ ms: Int) {
        let end = time + ms
        while let due = waiting.filter({ $0.at <= end }).min(by: { $0.at == $1.at ? $0.id < $1.id : $0.at < $1.at }) {
            waiting.removeAll { $0.id == due.id }
            time = due.at
            due.block()
        }
        time = end
    }
}

@Suite struct PlayTrackerTest {
    final class Fixture {
        let clock = ManualClock()
        var playing = true
        var records: [(String, Int)] = []
        var lengths: [Int] = []
        lazy var tracker = PlayTracker(started: { _ in }, record: { [unowned self] id, _, heard, length in
            if countsAsPlay(playedMs: heard, durationMs: length) {
                records.append((id, heard))
                lengths.append(length)
            }
        }, isPlaying: { [unowned self] in playing }, clock: clock)
    }

    @Test func aSongCountsTheMomentHalfIsHeardAndOnlyOnce() {
        let f = Fixture()
        f.tracker.moved("a", length: 200_000)
        #expect(f.clock.pendingMs == 100_000)
        f.clock.elapse(100_000)
        #expect(f.records.map(\.0) == ["a"] && f.records.map(\.1) == [100_000])
        f.clock.elapse(50_000)
        f.tracker.moved("b", length: 200_000)
        #expect(f.records.count == 1)
    }

    @Test func pausingCallsTheWaitOffAndPlayingResumesIt() {
        let f = Fixture()
        f.tracker.moved("a", length: 200_000)
        f.clock.elapse(30_000)
        f.playing = false
        f.tracker.playingChanged(false)
        #expect(f.clock.pendingMs == nil)
        f.playing = true
        f.tracker.playingChanged(true)
        #expect(f.clock.pendingMs == 70_000)
    }

    @Test func theMeasuredLengthReplacesTheListedOne() {
        let f = Fixture()
        f.tracker.moved("a", length: 296_000)
        #expect(f.clock.pendingMs == 148_000)
        f.tracker.lengthFound("b", length: 200_000)
        #expect(f.clock.pendingMs == 148_000)
        f.tracker.lengthFound("a", length: 291_000)
        #expect(f.clock.pendingMs == 145_500)
        f.clock.elapse(145_500)
        #expect(f.records.map(\.1) == [145_500])
        #expect(f.lengths == [291_000])
    }

    @Test func aSongSkippedEarlyNeverCounts() {
        let f = Fixture()
        f.tracker.moved("a", length: 200_000)
        f.clock.elapse(10_000)
        f.tracker.moved("b", length: 200_000)
        #expect(f.records.isEmpty)
    }
}

@Suite struct SleepTimerTest {
    /// Stands in for the player and remembers what the timer did to it.
    final class FakePlayer: SleepTarget {
        var fades: [Float] = []
        var sleepFade: Float = 1 { didSet { fades.append(sleepFade) } }
        var pauseAtEndOfSong = false
        var currentKey: String? = "q:0"
        var isBlending = false
        var entries: Set<String> = ["q:0", "q:1", "q:2", "q:3"]
        var paused = false
        weak var timer: SleepTimer?

        func hasEntry(_ key: String) -> Bool { entries.contains(key) }

        func moveTo(_ key: String, _ reason: SongChange) {
            currentKey = key
            timer?.songChanged(reason)
        }

        func pause() { paused = true }
    }

    func timerWith(_ player: FakePlayer, _ clock: ManualClock) -> SleepTimer {
        let timer = SleepTimer(clock: clock)
        player.timer = timer
        timer.attach(player)
        return timer
    }

    @Test func countsDownThenPausesAndPutsTheVolumeBack() {
        let player = FakePlayer(), clock = ManualClock()
        let timer = timerWith(player, clock)
        timer.start(minutes: 1)
        #expect(timer.state == .counting(remainingMs: 60_000))
        clock.elapse(10_000)
        #expect(timer.state == .counting(remainingMs: 50_000))
        #expect(player.sleepFade == 1)
        #expect(!player.paused)
        clock.elapse(50_000)
        #expect(player.paused)
        #expect(timer.state == .off)
        #expect(Array(player.fades.suffix(2)) == [0, 1])
        #expect(player.sleepFade == 1)
    }

    @Test func fadesThroughThePlayerOverTheLastThirtySeconds() {
        let player = FakePlayer(), clock = ManualClock()
        let timer = timerWith(player, clock)
        timer.start(minutes: 1)
        clock.elapse(30_000)
        #expect(timer.state == .counting(remainingMs: 30_000))
        #expect(player.sleepFade == 1)
        clock.elapse(15_000)
        #expect(timer.state == .counting(remainingMs: 15_000))
        #expect(abs(player.sleepFade - 0.25) < 0.0001)
        clock.elapse(14_900)
        #expect(player.sleepFade < 0.0001)
        #expect(!player.paused)
    }

    @Test func cancellingMidFadeRestoresTheVolume() {
        let player = FakePlayer(), clock = ManualClock()
        let timer = timerWith(player, clock)
        timer.start(minutes: 1)
        clock.elapse(45_000)
        #expect(abs(player.sleepFade - 0.25) < 0.0001)
        timer.cancel()
        #expect(timer.state == .off)
        #expect(player.sleepFade == 1)
        clock.elapse(60_000)
        #expect(!player.paused)
        #expect(player.sleepFade == 1)
    }

    @Test func endOfSongIsClearedOnceThePlayerPausesThere() {
        let player = FakePlayer(), clock = ManualClock()
        let timer = timerWith(player, clock)
        timer.startEndOfSong()
        #expect(timer.state == .endOfSong)
        #expect(player.pauseAtEndOfSong)
        timer.playWhenReadyChanged(false, endOfSong: false)
        #expect(player.pauseAtEndOfSong)
        timer.playWhenReadyChanged(false, endOfSong: true)
        #expect(!player.pauseAtEndOfSong)
        #expect(timer.state == .off)
    }

    @Test func endOfSongIsClearedOnCancel() {
        let player = FakePlayer(), clock = ManualClock()
        let timer = timerWith(player, clock)
        timer.startEndOfSong()
        timer.cancel()
        #expect(!player.pauseAtEndOfSong)
        #expect(timer.state == .off)
    }

    @Test func aNewTimerReplacesTheOldOne() {
        let player = FakePlayer(), clock = ManualClock()
        let timer = timerWith(player, clock)
        timer.start(minutes: 1)
        clock.elapse(45_000)
        timer.start(minutes: 5)
        #expect(timer.state == .counting(remainingMs: 300_000))
        #expect(player.sleepFade == 1)
        clock.elapse(60_000)
        #expect(!player.paused)
        #expect(timer.state == .counting(remainingMs: 240_000))
        timer.startEndOfSong()
        #expect(player.pauseAtEndOfSong)
        clock.elapse(300_000)
        #expect(!player.paused)
        #expect(timer.state == .endOfSong)
        timer.start(minutes: 1)
        #expect(!player.pauseAtEndOfSong)
        #expect(timer.state == .counting(remainingMs: 60_000))
    }

    @Test func extendingAddsTimeAndLiftsTheFade() {
        let player = FakePlayer(), clock = ManualClock()
        let timer = timerWith(player, clock)
        timer.start(minutes: 1)
        clock.elapse(45_000)
        #expect(abs(player.sleepFade - 0.25) < 0.0001)
        timer.extend(minutes: 5)
        #expect(timer.state == .counting(remainingMs: 315_000))
        #expect(player.sleepFade == 1)
        clock.elapse(60_000)
        #expect(!player.paused)
    }

    @Test func extendingDoesNothingWithoutACountdown() {
        let player = FakePlayer(), clock = ManualClock()
        let timer = timerWith(player, clock)
        timer.extend(minutes: 10)
        #expect(timer.state == .off)
        timer.startEndOfSong()
        timer.extend(minutes: 10)
        #expect(timer.state == .endOfSong)
    }

    @Test func countsSongsAsTheyEndAndStopsAfterTheLast() {
        let player = FakePlayer(), clock = ManualClock()
        let timer = timerWith(player, clock)
        timer.startAfterSongs(3)
        #expect(timer.state == .songs(left: 3))
        #expect(!player.pauseAtEndOfSong)
        player.moveTo("q:1", .seek)
        #expect(timer.state == .songs(left: 3))
        player.moveTo("q:2", .auto)
        #expect(timer.state == .songs(left: 2))
        player.isBlending = true
        player.moveTo("q:3", .playlistChanged)
        player.isBlending = false
        #expect(timer.state == .endOfSong)
        #expect(player.pauseAtEndOfSong)
        timer.playWhenReadyChanged(false, endOfSong: true)
        #expect(timer.state == .off)
        #expect(!player.pauseAtEndOfSong)
    }

    @Test func aNewQueueIsNotASongEnding() {
        let player = FakePlayer(), clock = ManualClock()
        let timer = timerWith(player, clock)
        timer.startAfterSongs(2)
        player.moveTo("q:1", .playlistChanged)
        #expect(timer.state == .songs(left: 2))
    }

    @Test func oneSongIsTheEndOfThisSong() {
        let timer = timerWith(FakePlayer(), ManualClock())
        timer.startAfterSongs(1)
        #expect(timer.state == .endOfSong)
    }

    @Test func stopsAfterAChosenSongOnceItPlays() {
        let player = FakePlayer(), clock = ManualClock()
        let timer = timerWith(player, clock)
        timer.startAfter(key: "q:2", title: "Song two")
        #expect(timer.state == .afterSong(key: "q:2", title: "Song two"))
        #expect(!player.pauseAtEndOfSong)
        player.moveTo("q:1", .auto)
        #expect(!player.pauseAtEndOfSong)
        timer.playWhenReadyChanged(false, endOfSong: true)
        #expect(timer.state == .afterSong(key: "q:2", title: "Song two"))
        player.moveTo("q:2", .seek)
        #expect(player.pauseAtEndOfSong)
        timer.playWhenReadyChanged(false, endOfSong: true)
        #expect(timer.state == .off)
        #expect(!player.pauseAtEndOfSong)
    }

    @Test func choosingTheSongOnNowIsTheEndOfThisSong() {
        let timer = timerWith(FakePlayer(), ManualClock())
        timer.startAfter(key: "q:0", title: "Song zero")
        #expect(timer.state == .endOfSong)
    }

    @Test func takingTheChosenSongOutOfTheQueueTurnsTheTimerOff() {
        let player = FakePlayer(), clock = ManualClock()
        let timer = timerWith(player, clock)
        timer.startAfter(key: "q:3", title: "Song three")
        player.entries.remove("q:3")
        timer.queueChanged()
        #expect(timer.state == .off)
    }

    @Test func detachingStopsTheTimerAndLetsGoOfThePlayer() {
        let player = FakePlayer(), clock = ManualClock()
        let timer = timerWith(player, clock)
        timer.start(minutes: 1)
        clock.elapse(45_000)
        timer.detach()
        #expect(timer.state == .off)
        #expect(player.sleepFade == 1)
        clock.elapse(60_000)
        #expect(!player.paused)
    }
}

@Suite struct HeadsetResumeTest {
    let both = ResumePrefs(resumeWired: true, resumeBluetooth: true)
    let now = 100 * 60_000

    func decide(_ kind: HeadsetKind = .bluetooth, prefs: ResumePrefs? = nil, playing: Bool = false, hasQueue: Bool = true,
                lostOutputAt: Int?? = .some(nil)) -> Bool {
        let lost: Int? = switch lostOutputAt {
        case .some(.some(let at)): at
        case .some(.none): now - 60_000
        case .none: nil
        }
        return shouldResumeOnConnect(kind, prefs: prefs ?? both, playing: playing, hasQueue: hasQueue, lostOutputAt: lost, now: now)
    }

    @Test func resumesWhenTheOutputWentAwayRecently() {
        #expect(decide())
        #expect(decide(.wired))
        #expect(decide(lostOutputAt: now - resumeWindowMs))
    }

    @Test func notAfterHalfAnHour() { #expect(!decide(lostOutputAt: now - resumeWindowMs - 1)) }

    @Test func notWhenPausedSomeOtherWay() { #expect(!decide(lostOutputAt: .none)) }

    @Test func eachKindHasItsOwnSwitch() {
        #expect(!decide(.wired, prefs: ResumePrefs(resumeBluetooth: true)))
        #expect(!decide(.bluetooth, prefs: ResumePrefs(resumeWired: true)))
        #expect(decide(.wired, prefs: ResumePrefs(resumeWired: true)))
    }

    @Test func offByDefault() {
        #expect(!decide(prefs: ResumePrefs()))
        #expect(!decide(.wired, prefs: ResumePrefs()))
    }

    @Test func alwaysPlayIgnoresWhyItPaused() {
        var always = both
        always.resumeAlways = true
        #expect(decide(prefs: always, lostOutputAt: .none))
        #expect(decide(prefs: always, lostOutputAt: now - 5 * resumeWindowMs))
        #expect(!decide(prefs: ResumePrefs(resumeAlways: true), lostOutputAt: .none))
    }

    @Test func nothingWhenAlreadyPlayingOrNothingQueued() {
        #expect(!decide(playing: true))
        #expect(!decide(hasQueue: false))
        var always = both
        always.resumeAlways = true
        #expect(!decide(prefs: always, hasQueue: false))
    }

    @Test func aClockGoingBackDoesNotCount() { #expect(!decide(lostOutputAt: now + 1_000)) }

    @Test func devicesAreSortedIntoKinds() {
        #expect(headsetKind(portType: "Headphones") == .wired)
        #expect(headsetKind(portType: "USBAudio") == .wired)
        #expect(headsetKind(portType: "BluetoothA2DPOutput") == .bluetooth)
        #expect(headsetKind(portType: "BluetoothLE") == .bluetooth)
        #expect(headsetKind(portType: "Speaker") == nil)
        #expect(headsetKind(portType: "BluetoothHFP") == nil)
    }

    @Test func theWayBackFollowsTheSettingOnlyWhenCastingEndsByItself() {
        // Picking the phone carries on as things were.
        #expect(playsOnReturn(wasPlaying: true, chosen: true, keepPlaying: false))
        #expect(!playsOnReturn(wasPlaying: false, chosen: true, keepPlaying: true))
        // The device went away: paused, unless the setting says carry on.
        #expect(!playsOnReturn(wasPlaying: true, chosen: false, keepPlaying: false))
        #expect(playsOnReturn(wasPlaying: true, chosen: false, keepPlaying: true))
        #expect(!playsOnReturn(wasPlaying: false, chosen: false, keepPlaying: true))
    }
}

@Suite struct AutoplayTest {
    @Test func itIsTimeOnlyNearTheEndOfTheLastSongWithRepeatOff() {
        #expect(autoplayDue(true, repeatMode: .off, hasNext: false, remainingMs: 15_000, leadMs: 20_000))
        #expect(!autoplayDue(true, repeatMode: .off, hasNext: false, remainingMs: 90_000, leadMs: 20_000))
        #expect(!autoplayDue(true, repeatMode: .off, hasNext: true, remainingMs: 15_000, leadMs: 20_000))
        #expect(!autoplayDue(true, repeatMode: .all, hasNext: false, remainingMs: 15_000, leadMs: 20_000))
        #expect(!autoplayDue(true, repeatMode: .one, hasNext: false, remainingMs: 15_000, leadMs: 20_000))
        #expect(!autoplayDue(false, repeatMode: .off, hasNext: false, remainingMs: 0, leadMs: 20_000))
    }

    @Test func theLeadCoversALongBlendThatStartsEarly() {
        #expect(autoplayLead(crossfadeMs: 0) == 20_000)
        #expect(autoplayLead(crossfadeMs: 8_000) == 8_000 + 45_000 + 15_000)
    }
}
