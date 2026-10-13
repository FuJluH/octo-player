import Foundation
import Testing
@testable import OctoKit

@Suite struct SoundJsonTests {
    func json(_ settings: SoundSettings) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try! encoder.encode(settings), as: UTF8.self)
    }

    func read(_ text: String) throws -> SoundSettings {
        try JSONDecoder().decode(SoundSettings.self, from: Data(text.utf8))
    }

    @Test func defaultsAreLeftOut() {
        #expect(json(SoundSettings()) == "{}")
    }

    @Test func aCurveMadeByHandIsANullPreset() throws {
        var custom = SoundSettings()
        custom.preset = nil
        #expect(json(custom) == #"{"preset":null}"#)
        #expect(try read("{}").preset == "Flat")
        #expect(try read(#"{"preset":null}"#).preset == nil)
        #expect(try read(#"{"preset":"Rock"}"#).preset == "Rock")
    }

    @Test func readsTheOtherAppsFieldsAndIgnoresUnknownOnes() throws {
        let text = """
        {"eqEnabled":true,"mode":"Parametric","graphicGains":[1.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,-2.5],
         "filters":[{"type":"LowShelf","frequency":105.0,"gainDb":6.4,"q":0.7},{"frequency":1000.0,"gainDb":-3.0},
                    {"type":"HighShelf","frequency":9000.0,"gainDb":2.0,"enabled":false}],
         "preset":null,"preampDb":-2.5,"autoPreamp":false,
         "correction":{"name":"HD 650","source":"oratory1990","preampDb":-6.0,"filters":[{"frequency":60.0,"gainDb":3.0}]},
         "replayGain":"Smart","replayGainPreampDb":2.0,"replayGainFallbackDb":-6.0,"preventClipping":false,
         "limiter":false,"balance":-0.5,"mono":true,"somethingNew":42}
        """
        let s = try read(text)
        #expect(s.eqEnabled)
        #expect(s.mode == .parametric)
        #expect(s.graphicGains.last == -2.5)
        #expect(s.filters == [
            EqFilter(type: .lowShelf, frequency: 105, gainDb: 6.4, q: 0.7),
            EqFilter(type: .peak, frequency: 1_000, gainDb: -3, q: graphicQ),
            EqFilter(type: .highShelf, frequency: 9_000, gainDb: 2, q: graphicQ, enabled: false),
        ])
        #expect(s.preset == nil)
        #expect(s.preampDb == -2.5)
        #expect(!s.autoPreamp)
        #expect(s.correction?.name == "HD 650")
        #expect(s.correction?.filters == [EqFilter(frequency: 60, gainDb: 3)])
        #expect(s.replayGain == .smart)
        #expect(s.replayGainPreampDb == 2)
        #expect(s.replayGainFallbackDb == -6)
        #expect(!s.preventClipping)
        #expect(!s.limiter)
        #expect(s.balance == -0.5)
        #expect(s.mono)
        #expect(try read(json(s)) == s)
    }

    @Test func filtersLeaveOutTheirUsualValues() {
        var s = SoundSettings()
        s.filters = [EqFilter(type: .peak, frequency: 1_000, gainDb: 3, q: graphicQ), EqFilter(type: .highShelf, frequency: 8_000, gainDb: -2, q: 0.7, enabled: false)]
        #expect(json(s) == #"{"filters":[{"frequency":1000,"gainDb":3},{"enabled":false,"frequency":8000,"gainDb":-2,"q":0.7,"type":"HighShelf"}]}"#)
    }

    @Test func anUnreadableMapReadsAsEmpty() {
        #expect(SoundProfiles.decode(nil).isEmpty)
        #expect(SoundProfiles.decode("not json").isEmpty)
        #expect(SoundProfiles.decode(#"{"all":{"mode":"Sideways"}}"#).isEmpty)
        var loud = SoundSettings()
        loud.replayGain = .album
        let map = ["all": loud, "bluetooth:Enco X3": SoundSettings()]
        #expect(SoundProfiles.decode(SoundProfiles.encode(map)) == map)
    }

    @Test func aRestoreReplacesTheOutputsItNamesAndKeepsTheRest() {
        var a = SoundSettings()
        a.mono = true
        var b = SoundSettings()
        b.balance = 0.3
        let saved = ["all": SoundSettings(), "wired": a]
        let restored = SoundProfiles.restoring(["wired": b, "usb:DAC": a], into: saved)
        #expect(restored == ["all": SoundSettings(), "wired": b, "usb:DAC": a])
    }
}

@Suite struct PerOutputTests {
    let buds = AudioOutput(key: "bluetooth:Enco X3", label: "Enco X3", formerKeys: ["bluetooth:AA:01"])

    func mono(_ s: SoundSettings) -> SoundSettings {
        var m = s
        m.mono = true
        return m
    }

    @Test func offTheSharedSetPlaysEverywhere() {
        var shared = SoundSettings()
        shared.balance = 0.2
        var own = SoundSettings()
        own.balance = -0.4
        let saved = ["all": shared, "bluetooth:Enco X3": own]
        #expect(SoundOutputs.current(saved, perOutput: false, output: buds) == shared)
        #expect(SoundOutputs.current(saved, perOutput: true, output: buds) == own)
        #expect(SoundOutputs.current(saved, perOutput: true, output: .phoneSpeaker) == shared)
        #expect(SoundOutputs.current([:], perOutput: true, output: .phoneSpeaker) == SoundSettings())
    }

    @Test func turningItOnStartsEachOutputFromTheSharedSet() {
        var shared = SoundSettings()
        shared.balance = 0.2
        let saved = SoundOutputs.saving(mono, to: ["all": shared], perOutput: true, output: buds)
        var expected = shared
        expected.mono = true
        #expect(saved["bluetooth:Enco X3"] == expected)
        #expect(saved["all"] == shared)
    }

    @Test func anEditMovesAnOldKeyToTheCurrentOne() {
        var old = SoundSettings()
        old.balance = 0.6
        let saved = SoundOutputs.saving(mono, to: ["bluetooth:AA:01": old], perOutput: true, output: buds)
        var expected = old
        expected.mono = true
        #expect(saved == ["bluetooth:Enco X3": expected])
    }

    @Test func offAnEditSavesTheSharedSetAndRemovesNothing() {
        let saved = SoundOutputs.saving(mono, to: ["bluetooth:AA:01": SoundSettings()], perOutput: false, output: buds)
        #expect(saved.keys.sorted() == ["all", "bluetooth:AA:01"])
        #expect(saved["all"]?.mono == true)
    }
}

@Suite struct UserPresetTests {
    let gains = [1.0, 2, 3, 4, 5, 6, 7, 8, 9, 10]

    @Test func savingReplacesTheSameNameInAnyCaseAndGoesLast() {
        var list = UserPresetRules.saving("Mine", gains: gains, to: [])
        list = UserPresetRules.saving("Other", gains: gains, to: list)
        list = UserPresetRules.saving("  mine ", gains: Array(repeating: 0, count: 10), to: list)
        #expect(list.map(\.name) == ["Other", "mine"])
        #expect(list.last?.gains == Array(repeating: 0, count: 10))
        #expect(UserPresetRules.saving("Short", gains: [1, 2], to: list) == list)
        #expect(UserPresetRules.saving("   ", gains: gains, to: list) == list)
    }

    @Test func deletingTakesTheExactName() {
        let list = [EqPreset(name: "Mine", gains: gains), EqPreset(name: "mine", gains: gains)]
        #expect(UserPresetRules.deleting("Mine", from: list).map(\.name) == ["mine"])
    }

    @Test func storedPresetsWithoutTenGainsAreLeftOut() {
        let stored = #"[{"name":"Good","gains":[0,0,0,0,0,0,0,0,0,1]},{"name":"Bad","gains":[1,2]}]"#
        #expect(UserPresetRules.decode(stored).map(\.name) == ["Good"])
        #expect(UserPresetRules.decode("nope").isEmpty)
        let list = [EqPreset(name: "Good", gains: gains)]
        #expect(UserPresetRules.decode(UserPresetRules.encode(list)) == list)
    }

    @Test func aRestoreAddsNamedPresetsReplacingTheSameName() {
        let list = [EqPreset(name: "Mine", gains: gains), EqPreset(name: "Kept", gains: gains)]
        let backup = [EqPreset(name: " MINE ", gains: Array(repeating: 1, count: 10)), EqPreset(name: "", gains: gains), EqPreset(name: "Odd", gains: [1])]
        let restored = UserPresetRules.restoring(backup, into: list)
        #expect(restored.map(\.name) == ["Kept", "MINE"])
        #expect(restored.last?.gains == Array(repeating: 1, count: 10))
    }

    @Test func builtInNamesAndCustomCannotBeUsed() {
        #expect(UserPresetRules.canSaveAs("My curve"))
        #expect(!UserPresetRules.canSaveAs("  "))
        #expect(!UserPresetRules.canSaveAs("custom"))
        #expect(!UserPresetRules.canSaveAs("bass boost"))
        #expect(!UserPresetRules.canSaveAs(" Rock "))
    }

    @Test func aBackupSaysWhatSoundItHolds() {
        let profiles = ["all": SoundSettings(), "wired": SoundSettings()]
        #expect(SoundBackupWords.lines(perOutput: true, profiles: profiles, presets: []) == ["1 output with its own sound"])
        #expect(SoundBackupWords.lines(perOutput: false, profiles: profiles, presets: []).isEmpty)
        #expect(SoundBackupWords.lines(perOutput: true, profiles: ["all": SoundSettings()], presets: []).isEmpty)
        let two = [EqPreset(name: "A", gains: gains), EqPreset(name: "B", gains: gains)]
        #expect(SoundBackupWords.lines(perOutput: true, profiles: ["a": SoundSettings(), "b": SoundSettings()], presets: two)
            == ["2 outputs with their own sound", "2 equalizer presets"])
        #expect(SoundBackupWords.lines(perOutput: false, profiles: nil, presets: Array(two.prefix(1))) == ["1 equalizer preset"])
    }

    @Test func theSoundPageHasSixSearchEntries() {
        #expect(SoundSearchEntry.all.map(\.title) == ["Sound for each output", "Equalizer", "Loudness", "Balance", "Headphone correction", "Crossfeed"])
        #expect(Set(SoundSearchEntry.all.map(\.id)).count == 6)
    }
}
