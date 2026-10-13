import Foundation
import Testing
@testable import OctoKit

/// The shared crossfade curve vectors, as the file has them.
private struct FadeCurveVectors: Decodable {
    struct Point: Decodable {
        let t: Double
        let out: Double
        let incoming: Double

        enum CodingKeys: String, CodingKey { case t, out, incoming = "in" }
    }

    struct Case: Decodable {
        let curve: String
        let overlapMs: Double
        let points: [Point]
    }

    let tolerance: Double
    let cases: [Case]

    static let shared = try! JSONDecoder().decode(FadeCurveVectors.self, from: Data(fadeCurveVectorsJSON.utf8))
}

@Suite struct FadeCurveTests {
    private let overlap = 8_000

    @Test func everyCurveMatchesTheSharedVectors() {
        let vectors = FadeCurveVectors.shared
        #expect(Set(vectors.cases.map(\.curve)) == Set(FadeCurve.allCases.map(\.storedName)))
        for c in vectors.cases {
            let curve = FadeCurve.stored(c.curve, or: .equalPower)
            #expect(curve.storedName == c.curve)
            for point in c.points {
                let gains = fadeGains(curve, point.t, overlapMs: Int(c.overlapMs))
                #expect(abs(gains.out - point.out) <= vectors.tolerance, "\(c.curve) \(c.overlapMs) out at \(point.t)")
                #expect(abs(gains.incoming - point.incoming) <= vectors.tolerance, "\(c.curve) \(c.overlapMs) in at \(point.t)")
            }
        }
    }

    @Test func equalPowerIsTheCrossfadeAsItWas() {
        for step in 0...100 {
            let t = Double(step) / 100
            let gains = fadeGains(.equalPower, t, overlapMs: overlap)
            #expect(gains.out == automixOutGain(t, 0))
            #expect(gains.incoming == automixInGain(t, 0))
            #expect(abs(gains.out - Double(fadeOutVolume(Float(t)))) < 1e-6)
            #expect(abs(gains.incoming - Double(fadeInVolume(Float(t)))) < 1e-6)
        }
        let plain = fixedCrossfadePlan(lenA: 200_000, length: 8_000, why: "smart transitions off")
        #expect(plain.curve == nil)
        #expect(plain.k == 0)
        #expect(plain.headroomDb == 0)
        #expect(fixedCrossfadePlan(lenA: 200_000, length: 8_000, why: "smart transitions off", curve: .equalPower) == plain)
    }

    @Test func everyCurveStartsWithTheOldSongAndEndsWithTheNew() {
        for curve in FadeCurve.allCases {
            for length in [500, 8_000, 16_000] {
                let start = fadeGains(curve, 0, overlapMs: length)
                let end = fadeGains(curve, 1, overlapMs: length)
                #expect(abs(start.out - 1) < 1e-12 && abs(start.incoming) < 1e-12, "\(curve) start")
                #expect(abs(end.out) < 1e-12 && abs(end.incoming - 1) < 1e-12, "\(curve) end")
                // Outside the blend, held at its ends.
                #expect(fadeGains(curve, -1, overlapMs: length) == start)
                #expect(fadeGains(curve, 2, overlapMs: length) == end)
            }
        }
    }

    @Test func noCurveGoesAboveFullOrBelowSilence() {
        for curve in FadeCurve.allCases {
            for step in 0...1_000 {
                let gains = fadeGains(curve, Double(step) / 1_000, overlapMs: overlap)
                #expect(gains.out >= 0 && gains.out <= 1, "\(curve) out")
                #expect(gains.incoming >= 0 && gains.incoming <= 1, "\(curve) in")
            }
        }
    }

    @Test func theOldSongOnlyFallsAndTheNewOneOnlyRises() {
        for curve in FadeCurve.allCases {
            var last = fadeGains(curve, 0, overlapMs: overlap)
            for step in 1...1_000 {
                let now = fadeGains(curve, Double(step) / 1_000, overlapMs: overlap)
                #expect(now.out <= last.out + 1e-12, "\(curve) out")
                #expect(now.incoming >= last.incoming - 1e-12, "\(curve) in")
                last = now
            }
        }
    }

    @Test func linearIsStraight() {
        for t in [0.1, 0.25, 0.5, 0.9] {
            let gains = fadeGains(.linear, t, overlapMs: overlap)
            #expect(abs(gains.out - (1 - t)) < 1e-12)
            #expect(abs(gains.incoming - t) < 1e-12)
        }
    }

    @Test func sCurveKeepsTheLoudnessSteady() {
        for step in 0...100 {
            let t = Double(step) / 100
            let gains = fadeGains(.sCurve, t, overlapMs: overlap)
            #expect(abs(gains.out * gains.out + gains.incoming * gains.incoming - 1) < 1e-9)
            #expect(abs(gains.out - (1 - sCurve(t))) < 1e-12)
        }
        // Holds longer than equal power early on, and swaps faster in the middle.
        #expect(fadeGains(.sCurve, 0.1, overlapMs: overlap).out > fadeGains(.equalPower, 0.1, overlapMs: overlap).out)
    }

    @Test func evenInLoudnessFallsTheSameDecibelsEveryMoment() {
        for t in [0.1, 0.25, 0.5, 0.75, 0.9] {
            let gains = fadeGains(.evenLoudness, t, overlapMs: overlap)
            #expect(abs(20 * log10(gains.out) - evenLoudnessFloorDb * t / evenLoudnessFloorAt) < 1e-9)
        }
        // At the floor, then a straight line to silence.
        #expect(abs(fadeGains(.evenLoudness, 0.95, overlapMs: overlap).out - 0.001) < 1e-12)
        #expect(abs(fadeGains(.evenLoudness, 0.975, overlapMs: overlap).out - 0.0005) < 1e-12)
        #expect(fadeGains(.evenLoudness, 0.3, overlapMs: overlap).incoming == fadeGains(.evenLoudness, 0.7, overlapMs: overlap).out)
    }

    @Test func mixOnlyPlaysBothInFullBetweenQuickFades() {
        let ramp = mixOnlyRampMs / Double(overlap)
        let middle = fadeGains(.mixOnly, 0.5, overlapMs: overlap)
        #expect(middle.out == 1 && middle.incoming == 1)
        #expect(fadeGains(.mixOnly, ramp, overlapMs: overlap).incoming == 1)
        #expect(fadeGains(.mixOnly, ramp / 2, overlapMs: overlap).incoming < 1)
        #expect(fadeGains(.mixOnly, 1 - ramp, overlapMs: overlap).out == 1)
        #expect(fadeGains(.mixOnly, 1 - ramp / 2, overlapMs: overlap).out < 1)
        // A blend too short for two whole quick fades gives each half of it.
        let short = fadeGains(.mixOnly, 0.5, overlapMs: 500)
        #expect(abs(short.out - 1) < 1e-12 && abs(short.incoming - 1) < 1e-12)
        let plan = fixedCrossfadePlan(lenA: 200_000, length: overlap, why: "smart transitions off", curve: .mixOnly)
        #expect(plan.headroomDb == mixOnlyHeadroomDb)
        #expect(plan.curve == .mixOnly)
        // Through the middle both songs play the headroom down.
        let outgoing = DeckTransition(entryId: "a", plan: plan, incoming: false)
        let incoming = DeckTransition(entryId: "b", plan: plan, incoming: true)
        let headroom = pow(10, -mixOnlyHeadroomDb / 20)
        #expect(abs(outgoing.gainAt(0.5) - headroom) < 1e-12)
        #expect(abs(incoming.gainAt(0.5) - headroom) < 1e-12)
    }

    @Test func withSmartTransitionsOffTheChosenCurvePlays() {
        let a = FadeSong(albumId: nil, albumOrder: nil, durationMs: 200_000)
        let b = FadeSong(albumId: nil, albumOrder: nil, durationMs: 180_000)
        let settings = AutomixSettings(maxOverlapMs: 8_000, smart: false, fadeCurve: .linear)
        let plan = planTransition(current: a, next: b, tail: nil, head: nil, settings: settings)
        #expect(plan.kind == .crossfade)
        #expect(plan.curve == .linear)
        #expect(plan.headroomDb == 0)
        #expect(abs(plan.outGain(0.25) - 0.75) < 1e-12)
        #expect(abs(plan.inGain(0.25) - 0.25) < 1e-12)
        #expect(plan.reason.hasSuffix(", linear fade"))
        let deck = DeckTransition(entryId: "a", plan: plan, incoming: false)
        #expect(abs(deck.gainAt(0.5) - 0.5) < 1e-12)
    }

    @Test func automixKeepsItsOwnCurves() {
        let a = FadeSong(albumId: nil, albumOrder: nil, durationMs: 200_000)
        let b = FadeSong(albumId: nil, albumOrder: nil, durationMs: 180_000)
        for curve in FadeCurve.allCases {
            let settings = AutomixSettings(maxOverlapMs: 8_000, smart: true, fadeCurve: curve)
            let plan = planTransition(current: a, next: b, tail: nil, head: nil, settings: settings)
            #expect(plan.curve == nil)
            #expect(plan == planTransition(current: a, next: b, tail: nil, head: nil, settings: AutomixSettings(maxOverlapMs: 8_000)))
        }
    }

    @Test func theChoiceIsKeptByTheOtherAppsNames() {
        #expect(FadeCurve.allCases.map(\.storedName) == ["EqualPower", "Linear", "SCurve", "EvenLoudness", "MixOnly"])
        #expect(FadeCurve.stored("Bungee", or: .equalPower) == .equalPower)
        #expect(PlayerPrefs().crossfadeCurve == .equalPower)
    }

    @Test func goesThroughABackupAndBack() {
        var backup = Backup()
        var player = PlayerPrefs()
        player.crossfadeCurve = .sCurve
        backup.player = player
        let text = BackupFile.encode(backup)
        #expect(text.contains("\"crossfadeCurve\": \"SCurve\""))
        guard case .read(let read) = BackupFile.decode(text) else { Issue.record("not read"); return }
        #expect(read.player?.crossfadeCurve == .sCurve)
        guard case .read(let odd) = BackupFile.decode(#"{"player": {"crossfadeCurve": "Bungee"}}"#) else { Issue.record("not read"); return }
        #expect(odd.player?.crossfadeCurve == .equalPower)
    }
}
