import Foundation
import OctoKit

/// How often to check on the song: rarely while the end is far off, and every frame or so near
/// it and during the blend.
private let farCheckMs = 1_000
private let nearCheckMs = 40

/// The planner needs the end of the playing song and the start of the next once the song has
/// played this long.
private let scoutAfterMs = 1_000

/// The song's body level from what has been heard counts once this much has been heard.
private let levelHeardMs = 20_000

/// A tempo-matched song eases back to its own speed in steps this small.
private let rateStep = 0.0025

/// Runs the transition between two decks. While a song plays it reads the end of it and the
/// start of the next song, and plans where and how they meet (`planTransition`). Each comes from
/// the server's transition profile of the song when the server has one, else from scouting it.
/// Ahead of the blend it loads the spare deck with the next song, parked where the next song's
/// silent run-up starts. A little before the blend the spare plays, silent, and is lined up with
/// the playing song by its position. At the blend the player hands over to the spare, while the
/// old deck plays on until the plan ends it. Volume and filters are run by each deck's own sound
/// processor, on that deck's song time, once armed with the plan; this only arms them. Anything
/// the listener does mid-blend (skip, seek, pause, editing the queue) ends the blend at once.
@MainActor
final class Crossfader {
    private unowned let player: PlaybackEngine
    private(set) var spare: Deck
    private let scout: Scout?
    private let profiles: ServerProfiles?
    private let lengths: RealLengths

    /// How transitions are planned; a longest blend of 0 turns them off.
    var settings = AutomixSettings(maxOverlapMs: 0) {
        didSet {
            if oldValue != settings { interrupt() }
        }
    }

    /// The longest blend, or 0 when crossfade is off.
    var fadeMs: Int { settings.maxOverlapMs }

    private var check: DispatchWorkItem?

    /// The queue entry the spare is loaded with, if it is loaded, and the plan it was loaded for.
    private var loadedFor: String?
    private var loadedPlan: TransitionPlan?

    /// The last next song that was not ready in time, so it is said once.
    private var notReadyFor: String?

    /// The plan for the coming transition, and what it was made from.
    private var plan: TransitionPlan?
    private var planKey: PlanKey?

    /// The silence gate the playing song was armed with, for an early fade.
    private var outgoingGate: Double?

    /// The silent run-up: lining the spare up with the playing song.
    private var aligner: Aligner?
    private var alignment: Aligner.Step?

    /// During the blend: the deck playing out the old song, and the plan.
    private(set) var outgoing: Deck?
    private var blending: TransitionPlan?

    /// A tempo-matched song easing back to its own speed.
    private var easing: Easing?

    /// The scouted end of the playing song and start of the next.
    private var tail: Scouted?
    private var head: Scouted?
    private var reading: Reading?

    /// Where the song was at the last check, to see it jump.
    private var lastPosition = -1
    private var lastCheckAt = 0

    private final class Scouted {
        let entryId: String
        var job: Scout.Job?
        var done = false
        var analysis: SectionAnalysis?
        /// The server's profile of the song, when the analysis came from it.
        var profile: TransitionProfile?

        init(_ entryId: String) { self.entryId = entryId }
    }

    private final class Reading {
        let entryId: String
        var job: Scout.Job?
        var done = false
        var value: TapReading?

        init(_ entryId: String) { self.entryId = entryId }
    }

    private final class Easing {
        let deck: Deck
        let plan: TransitionPlan
        let enteredAt: Int
        var rate: Float
        let after: Pace

        init(deck: Deck, plan: TransitionPlan, enteredAt: Int, rate: Float, after: Pace) {
            self.deck = deck
            self.plan = plan
            self.enteredAt = enteredAt
            self.rate = rate
            self.after = after
        }
    }

    /// Everything a plan depends on besides the clock. A change means a new plan.
    private struct PlanKey: Equatable {
        var current: String?
        var next: String?
        var currentMs: Int
        var nextMs: Int
        var settings: AutomixSettings
        var repeatOne: Bool
        var stopAtEnd: Bool
        var speed: Float
        var skipSilence: Bool
        var tail: Bool
        var head: Bool
        var reading: Bool
    }

    init(player: PlaybackEngine, spare: Deck, scout: Scout?, profiles: ServerProfiles?, lengths: RealLengths) {
        self.player = player
        self.spare = spare
        self.scout = scout
        self.profiles = profiles
        self.lengths = lengths
    }

    private var nowMs: Int { Int(ProcessInfo.processInfo.systemUptime * 1000) }

    // MARK: What the player tells it

    func isPlayingChanged(_ isPlaying: Bool) {
        if isPlaying {
            schedule(0)
        } else {
            let deck = player.deck
            if outgoing != nil && isRebuffering(playWhenReady: deck.playWhenReady, state: deck.state, suppression: .none) {
                // The incoming song is waiting for its sound: the blend goes on once it has it,
                // each deck on its own song time.
                schedule(nearCheckMs)
                return
            }
            // A pause, a call or unplugged headphones: no half-finished blend.
            finishFade()
            dropRunUp()
            cancelCheck()
        }
    }

    /// The song changed some other way, so what the spare holds is stale.
    func songChanged() {
        if outgoing == nil {
            dropPlan()
            unloadSpare()
        }
    }

    /// Called before anything that changes what plays or where.
    func interrupt() {
        finishFade()
        stopEasing()
        dropPlan()
        unloadSpare()
        schedule(0)
    }

    func release() {
        cancelCheck()
        finishFade()
        tail?.job?.cancel()
        head?.job?.cancel()
        reading?.job?.cancel()
        scout?.release()
        spare.clear()
    }

    /// Whether a crossfade is under way.
    var isBlending: Bool { outgoing != nil }

    // MARK: The check

    private func step() {
        easeRate()
        if outgoing != nil {
            blendStep()
            return
        }
        let deck = player.deck
        if !deck.isPlaying {
            lastPosition = -1
            // Briefly not playing while it loads after a seek: keep watching. Truly paused: stop
            // until playing starts again.
            if deck.playWhenReady { schedule(nearCheckMs) }
            return
        }
        let queue = player.queue
        // A live station has no end to fade out of, and is never faded into.
        guard fadeMs > 0, let next = queue.nextOnEnd, let current = queue.currentItem, !current.isRadioStation,
              !queue.items[next].isRadioStation else {
            dropPlan()
            unloadSpare()
            schedule(farCheckMs)
            return
        }
        let nextItem = queue.items[next]
        let position = deck.positionMs
        let speed = player.pace.speed
        if jumped(position, speed) {
            dropRunUp()
            dropPlan()
        }
        let currentSong = current.fadeSong(durationMs: lengthOf(deck, current))
        let nextSong = nextItem.fadeSong(durationMs: nextLengthOf(nextItem))
        let repeatOne = queue.repeatMode == .one
        let stopAtEnd = player.pauseAtEndOfSong
        // In real time: at 1.5x speed the song's last 6 seconds pass in 4.
        let remaining = Int(Double(currentSong.durationMs - position) / Double(speed))
        let plain = crossfadeLength(currentSong, nextSong, fadeMs: fadeMs, repeatOne: repeatOne, stopAtEndOfSong: stopAtEnd)
        let waiting = plain == 0 && waitsOnLength(currentSong, nextSong, fadeMs: fadeMs, repeatOne: repeatOne, stopAtEndOfSong: stopAtEnd)
        if waiting {
            // The next song's length is only known once it has opened, so open it early on the
            // spare and decide once it says.
            dropPlan()
            let lead = loadLeadMs(blendMs: 0, fadeMs: fadeMs, lengthKnown: false)
            if loadedFor != nextItem.entryId && remaining <= lead { load(nextItem, nil) }
            schedule(remaining > lead + farCheckMs ? farCheckMs : nearCheckMs)
            return
        }
        if plain == 0 {
            // Played gaplessly, by the usual rules: nothing to plan.
            dropPlan()
            unloadSpare()
            schedule(farCheckMs)
            return
        }
        if aligner == nil {
            scoutAhead(deck, current, nextItem, position, currentSong.durationMs)
            let key = keyFor(current, nextItem, currentSong, nextSong, repeatOne, stopAtEnd, speed, player.skipSilence)
            if key != planKey && readyToPlan(key, remaining) {
                makePlan(deck, key, currentSong, nextSong, position, repeatOne, stopAtEnd, speed, current, nextItem)
            }
        }
        guard let p = plan else {
            // Waiting on the scouts; they call back as soon as they are done.
            schedule(remaining > fadeMs + planLoadLeadMs * 2 ? farCheckMs : nearCheckMs)
            return
        }
        if p.kind == .gapless {
            unloadSpare()
            schedule(farCheckMs)
            return
        }
        let toStart = Int(Double(p.startMs - position) / Double(speed))
        if loadedFor != nextItem.entryId && toStart <= planLoadLeadMs { load(nextItem, p) }
        if loadedFor == nextItem.entryId && loadedPlan != p { repark(p) }
        if loadedFor == nextItem.entryId {
            if aligner == nil && Double(position) >= p.preRollAtMs() - Double(nearCheckMs) {
                if spare.hasEnoughToStart {
                    startRunUp(p, position)
                } else {
                    // The next song is not ready for its run-up: the playing song is left alone,
                    // and a later plan is made once it is.
                    let nextEntry = planKey?.next
                    if notReadyFor != nextEntry { playbackLog.info("automix: the next song was not ready for its run-up") }
                    notReadyFor = nextEntry
                    dropPlan()
                    schedule(nearCheckMs)
                    return
                }
            }
            if aligner != nil {
                if position >= p.startMs {
                    handOver(p)
                    schedule(nearCheckMs)
                    return
                }
                runUp(p, position)
            }
        }
        schedule(toStart > planLoadLeadMs + farCheckMs ? farCheckMs : nearCheckMs)
    }

    /// How long the song is: what the deck measured, or the listed length (corrected where
    /// playing it before found it wrong) for a stream that has not said.
    private func lengthOf(_ deck: Deck, _ item: QueueItem) -> Int {
        songLengthMs(listedMs: lengths.lengthMs(item.trackId, listedMs: item.durationMs), playerMs: deck.durationMs)
    }

    /// How long the next song is: what the spare measured once it holds that song, else the
    /// listed length, corrected where it was found wrong.
    private func nextLengthOf(_ item: QueueItem) -> Int {
        let listed = lengths.lengthMs(item.trackId, listedMs: item.durationMs)
        let spareMs = loadedFor == item.entryId && spare.item?.entryId == item.entryId ? spare.durationMs : nil
        return nextSongLengthMs(listedMs: listed, spareMs: spareMs)
    }

    /// Whether the song moved more than a plan can follow since the last check.
    private func jumped(_ position: Int, _ speed: Float) -> Bool {
        let now = nowMs
        let expected = Double(lastPosition) + Double(now - lastCheckAt) * Double(speed)
        let moved = lastPosition >= 0 && abs(Double(position) - expected) > Double(replanJumpMs)
        lastPosition = position
        lastCheckAt = now
        return moved
    }

    // MARK: Reading ahead

    /// Reads the end of the playing song once it has played a second, and the start of the next
    /// song as soon as it is known, each once per queue entry: from the server's profile of the
    /// song when it has one, else by scouting it.
    private func scoutAhead(_ deck: Deck, _ current: QueueItem, _ next: QueueItem, _ position: Int, _ lengthMs: Int) {
        guard let scout, settings.smart else { return }
        let context = player.streamContext()
        let currentEntry = current.entryId ?? current.trackId
        if tail?.entryId != currentEntry && position >= scoutAfterMs && lengthMs >= shortestAutomixSongMs {
            tail?.job?.cancel()
            let scouted = Scouted(currentEntry)
            tail = scouted
            withProfile(current, scouted, { $0.tailAnalysis() }) { [weak self] in
                let job = scout.read(current, context: context, fromMs: max(0, lengthMs - tailScoutMs), toMs: lengthMs,
                                     analyze: tailAnalyzer(current.tagTempo)) { analysis in
                    guard let self, self.tail === scouted else { return }
                    scouted.analysis = analysis
                    scouted.done = true
                    self.schedule(0)
                }
                scouted.job = job
            }
        }
        let nextEntry = next.entryId ?? next.trackId
        if head?.entryId != nextEntry {
            head?.job?.cancel()
            let scouted = Scouted(nextEntry)
            head = scouted
            withProfile(next, scouted, { $0.headAnalysis() }) { [weak self] in
                let job = scout.read(next, context: context, fromMs: 0, toMs: headScoutMs, analyze: headAnalyzer(next.tagTempo)) { analysis in
                    guard let self, self.head === scouted else { return }
                    scouted.analysis = analysis
                    scouted.done = true
                    self.schedule(0)
                }
                scouted.job = job
            }
        }
        // Once both are in, what the deck has heard of this song.
        if reading?.entryId != currentEntry && tail?.done == true && head?.done == true {
            let sound = deck.processor
            let tagBpm = current.tagTempo
            reading?.job?.cancel()
            let made = Reading(currentEntry)
            reading = made
            made.job = scout.run({ _ in sound.reading(currentEntry, tagBpm: tagBpm) }) { [weak self] value in
                guard let self, self.reading === made else { return }
                made.value = value
                made.done = true
                self.schedule(0)
            }
        }
    }

    /// Fills `scouted` from the server's profile of the song when it has one, at once when it is
    /// already here; otherwise, or once the server says it has none, runs `scoutIt`.
    private func withProfile(_ item: QueueItem, _ scouted: Scouted, _ part: @escaping (TransitionProfile) -> SectionAnalysis,
                             _ scoutIt: @escaping () -> Void) {
        guard let profiles else { return scoutIt() }
        let fill = { (profile: TransitionProfile) in
            scouted.profile = profile
            scouted.analysis = part(profile)
            scouted.done = true
        }
        if let cached = profiles.cached(item.uri) { return fill(cached) }
        let asked = profiles.request(item.uri) { [weak self] profile in
            guard let self, self.tail === scouted || self.head === scouted else { return }
            if let profile { fill(profile) } else { scoutIt() }
            self.schedule(0)
        }
        if !asked { scoutIt() }
    }

    private func keyFor(_ current: QueueItem, _ next: QueueItem, _ currentSong: FadeSong, _ nextSong: FadeSong,
                        _ repeatOne: Bool, _ stopAtEnd: Bool, _ speed: Float, _ skipSilence: Bool) -> PlanKey {
        let currentEntry = current.entryId ?? current.trackId
        let nextEntry = next.entryId ?? next.trackId
        return PlanKey(
            current: currentEntry, next: nextEntry, currentMs: currentSong.durationMs, nextMs: nextSong.durationMs,
            settings: settings, repeatOne: repeatOne, stopAtEnd: stopAtEnd, speed: speed, skipSilence: skipSilence,
            tail: tail?.entryId == currentEntry && tail?.done == true,
            head: head?.entryId == nextEntry && head?.done == true,
            reading: reading?.entryId == currentEntry && reading?.done == true)
    }

    /// A plan is made once everything it could use is in, or when there is no more time to
    /// wait; plain crossfades need nothing.
    private func readyToPlan(_ key: PlanKey, _ remaining: Int) -> Bool {
        if !settings.smart || scout == nil { return true }
        if key.tail && key.head && key.reading { return true }
        return remaining <= fadeMs + planLoadLeadMs + preRollMs + farCheckMs
    }

    private func makePlan(_ deck: Deck, _ key: PlanKey, _ currentSong: FadeSong, _ nextSong: FadeSong, _ position: Int,
                          _ repeatOne: Bool, _ stopAtEnd: Bool, _ speed: Float, _ current: QueueItem, _ nextItem: QueueItem) {
        let heard = reading?.entryId == key.current ? reading?.value : nil
        let served = tail?.entryId == key.current ? tail?.profile : nil
        let heardLevel = heard.flatMap { $0.heardMs >= levelHeardMs ? $0.bodyLevelDb : nil }
        let (level, tempoPrior) = heardFor(served, heardLevelDb: heardLevel, heardTempo: heard?.tempoPrior)
        let context = TransitionContext(
            nowMs: position, playedMs: heard.map { Int(Double($0.heardMs) * Double(speed)) } ?? position,
            repeatOne: repeatOne, stopAtEndOfSong: stopAtEnd, pace: Double(speed), skipSilence: player.skipSilence,
            currentGenre: current.genre, nextGenre: nextItem.genre, bodyLevelDb: level, tempoPrior: tempoPrior)
        let tailAnalysis = tail?.entryId == key.current ? tail?.analysis : nil
        let headAnalysis = head?.entryId == key.next ? head?.analysis : nil
        let made = planTransition(current: currentSong, next: nextSong, tail: tailAnalysis, head: headAnalysis,
                                  settings: settings.atSpeed(speed), context: context)
        planKey = key
        let sound = deck.processor
        plan = made
        sound.arm(nil)
        if made.kind == .gapless { return }
        // The playing song is armed once the next one is ready for its run-up, so a late plan
        // whose start has passed never fades it out while the next song is still loading.
        let measured = tailAnalysis.map { analysis in level.map(analysis.withBodyLevel) ?? analysis }
        outgoingGate = measured?.features.gateDb ?? level.map { max(silenceFloorDb, $0 - silenceBelowBodyDb) }
    }

    // MARK: The spare

    /// The spare gets the next song, parked silently where its run-up starts (the song's start
    /// when there is no plan yet).
    private func load(_ next: QueueItem, _ plan: TransitionPlan?) {
        let from = plan?.preRollFromMs() ?? 0
        // The same pace, so the blend does not jump in speed or pitch; a tempo-matched song gets
        // its rate from the start of its run-up.
        spare.setPace(pacedFor(plan, player.pace))
        spare.skipSilence = player.skipSilence
        spare.volume = 0
        spare.playWhenReady = false
        spare.pauseAtEndOfSong = false
        spare.startAfterMs = player.deck.startAfterMs
        armIncoming(plan, next)
        spare.load(player.makeSource(next, startMs: from))
        loadedFor = next.entryId
        loadedPlan = plan
    }

    /// A new plan for a song already loaded: armed again and moved to the new run-up start.
    private func repark(_ plan: TransitionPlan) {
        guard let item = spare.item else { return }
        armIncoming(plan, item)
        spare.setPace(pacedFor(plan, player.pace))
        // Parked there already, it is not moved: a move would make it load again, and a plan
        // made again while it loads would never find it ready.
        if needsRepark(spare.positionMs, plan.preRollFromMs()) { spare.seek(toMs: plan.preRollFromMs()) }
        loadedPlan = plan
    }

    private func pacedFor(_ plan: TransitionPlan?, _ pace: Pace) -> Pace {
        guard let rate = plan?.beatMatchRate else { return pace }
        return Pace(speed: Float(rate), pitch: pace.pitch)
    }

    private func armIncoming(_ plan: TransitionPlan?, _ item: QueueItem) {
        spare.processor.arm(plan.map { DeckTransition(entryId: item.entryId, plan: $0, incoming: true) })
    }

    /// The run-up: the spare plays, still silent, from where the next song should be now.
    private func startRunUp(_ plan: TransitionPlan, _ position: Int) {
        let entry = player.queue.currentItem.map { $0.entryId ?? $0.trackId }
        player.deck.processor.arm(DeckTransition(entryId: entry, plan: plan, incoming: false, gateDb: outgoingGate))
        let target = Int(plan.incomingAtMs(Double(position)))
        if target > spare.positionMs + nearCheckMs { spare.seek(toMs: target) }
        spare.playWhenReady = true
        aligner = Aligner(plan)
        alignment = nil
    }

    private func runUp(_ plan: TransitionPlan, _ position: Int) {
        guard let aligner, alignment == nil else { return }
        let step = aligner.observe(nowMs: nowMs, outgoingMs: Double(position), incomingMs: Double(spare.positionMs),
                                   incomingPlaying: spare.isPlaying)
        switch step {
        case .seek(let toMs): spare.seek(toMs: toMs)
        case .settled: settle(plan, step)
        case .wait: break
        }
    }

    /// The decks are lined up as far as they will be. Too far apart for the beat, the playing
    /// song's low-pass sweeps smoothly instead of in steps.
    private func settle(_ plan: TransitionPlan, _ step: Aligner.Step) {
        alignment = step
        if case .settled(_, let locked) = step, plan.barLocked && !locked {
            let entry = player.queue.currentItem.map { $0.entryId ?? $0.trackId }
            player.deck.processor.arm(DeckTransition(entryId: entry, plan: plan, incoming: false, stepped: false, gateDb: outgoingGate))
        }
    }

    private func handOver(_ plan: TransitionPlan) {
        let from = player.deck
        let into = spare
        var settled = alignment
        if settled == nil, let finished = aligner?.finish() {
            settle(plan, finished)
            settled = finished
        }
        aligner = nil
        // The old deck plays this song out, then stops instead of going on.
        from.pauseAtEndOfSong = true
        from.setFollowing(nil)
        outgoing = from
        blending = plan
        // Once the blend is over, the old deck is the spare for next time.
        spare = from
        loadedFor = nil
        loadedPlan = nil
        self.plan = nil
        planKey = nil
        var aligned = "alignment not measured"
        if case .settled(let error?, let locked) = settled {
            aligned = "aligned to \(Int(error.rounded())) ms" + (plan.barLocked && locked ? ", on the beat" : "")
        }
        playbackLog.info("automix: \(plan.reason, privacy: .public); \(aligned, privacy: .public)")
        if let rate = plan.beatMatchRate {
            easing = Easing(deck: into, plan: plan, enteredAt: nowMs, rate: Float(rate), after: player.pace)
        }
        player.handOver(into: into, from: from)
    }

    private func blendStep() {
        guard let from = outgoing else { return }
        let over = blending.map { from.positionMs >= $0.startMs + $0.overlapMs } ?? true
            || from.state == .ended || !from.playWhenReady
        if over { finishFade() } else { schedule(nearCheckMs) }
        if outgoing == nil { schedule(easing != nil ? nearCheckMs : 0) }
    }

    /// Eases a tempo-matched song back to its own speed after the blend, in small steps; the
    /// listener changing the speed ends it.
    private func easeRate() {
        guard let ease = easing else { return }
        if ease.deck !== player.deck || abs(ease.deck.pace.speed - ease.rate) > 1e-4 {
            easing = nil
            return
        }
        let since = Double(nowMs - ease.enteredAt)
        let target = ease.plan.incomingRateAt(since)
        let done = target == 1
        if done || abs(target - Double(ease.rate)) >= rateStep {
            ease.rate = done ? ease.after.speed : Float(target)
            ease.deck.setPace(Pace(speed: ease.rate, pitch: ease.after.pitch))
            if done { easing = nil }
        }
    }

    private func stopEasing() {
        guard let ease = easing else { return }
        easing = nil
        if ease.deck === player.deck { ease.deck.setPace(ease.after) }
    }

    /// Lets go of a blend: the listener changed the pace, so a tempo-matched song takes it.
    func paceChanged() {
        easing = nil
    }

    private func finishFade() {
        guard let from = outgoing else { return }
        let plan = blending
        outgoing = nil
        blending = nil
        if let plan, plan.overlapMs > 0 {
            let progress = Float(from.positionMs - plan.startMs) / Float(plan.overlapMs)
            if progress < 0.95 { playbackLog.info("automix: blend cut short at \(Int(min(max(progress, 0), 1) * 100))%") }
        }
        from.processor.arm(nil)
        from.clear()
        from.pauseAtEndOfSong = false
        // The incoming song is past its part by now, or is cut short: either way it plays on
        // untouched.
        player.deck.processor.arm(nil)
        player.endFade()
    }

    /// Stops a run-up: the spare goes quiet and back to where it was parked.
    private func dropRunUp() {
        guard aligner != nil else { return }
        aligner = nil
        alignment = nil
        unloadSpare()
    }

    /// Forgets the plan, and the playing deck's part in it.
    private func dropPlan() {
        if outgoing != nil { return }
        if aligner != nil { dropRunUp() }
        if plan != nil { player.deck.processor.arm(nil) }
        plan = nil
        planKey = nil
    }

    private func unloadSpare() {
        guard loadedFor != nil else { return }
        loadedFor = nil
        loadedPlan = nil
        aligner = nil
        alignment = nil
        spare.processor.arm(nil)
        spare.clear()
    }

    private func schedule(_ delayMs: Int) {
        cancelCheck()
        // A song easing back to its own speed is looked at often.
        let delay = easing != nil ? min(delayMs, nearCheckMs * 5) : delayMs
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.step() }
        }
        check = work
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(delay), execute: work)
    }

    private func cancelCheck() {
        check?.cancel()
        check = nil
    }
}
