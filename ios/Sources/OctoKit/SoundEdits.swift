import Foundation

// The changes the Sound page makes to the settings, kept apart from the page so they can be
// tested on their own.

public enum SoundEdits {
    /// How many filters a parametric curve can have.
    public static let maxFilters = 16
    /// The range the curve is drawn over, and a filter can be moved across.
    public static let minHz = 20.0
    public static let maxHz = 20_000.0
    /// How narrow or wide a filter can be made.
    public static let minQ = 0.1
    public static let maxQ = 10.0
    /// What the label for an unnamed curve says.
    public static let custom = "Custom"

    /// Rounds half up, toward positive infinity, the way the other apps round readings.
    static func roundHalfUp(_ value: Double) -> Int { Int((value + 0.5).rounded(.down)) }

    /// A gain in tenths of a decibel, inside the slider range. Close to zero snaps to zero, so
    /// flat is easy to find again by hand.
    public static func cleanGain(_ db: Double) -> Double {
        let clamped = min(gainRangeDb, max(-gainRangeDb, db))
        if abs(clamped) < 0.25 { return 0 }
        return Double(roundHalfUp(clamped * 10)) / 10
    }

    /// A preset's curve on the ten bands, switching the equalizer on so the listener hears what
    /// they picked.
    public static func withPreset(_ settings: SoundSettings, _ preset: EqPreset) -> SoundSettings {
        var s = settings
        s.eqEnabled = true
        s.mode = .graphic
        s.graphicGains = preset.gains
        s.preset = preset.name
        return s
    }

    /// One band moved by hand. The curve no longer matches a preset.
    public static func withBandGain(_ settings: SoundSettings, band: Int, gainDb: Double) -> SoundSettings {
        guard settings.graphicGains.indices.contains(band) else { return settings }
        var s = settings
        s.graphicGains[band] = cleanGain(gainDb)
        s.preset = nil
        return s
    }

    /// The ten bands as parametric filters: the same sound, now free to move.
    public static func seedFromGraphic(_ gains: [Double]) -> [EqFilter] {
        zip(graphicBands, gains).map { EqFilter(type: .peak, frequency: $0, gainDb: $1, q: graphicQ) }
    }

    /// Switches between the ten bands and free filters. Going to parametric starts from the ten
    /// bands, so the sound does not jump; only a flat set of bands leaves filters made earlier
    /// in place.
    public static func withMode(_ settings: SoundSettings, _ mode: EqMode) -> SoundSettings {
        guard mode != settings.mode else { return settings }
        var s = settings
        s.mode = mode
        if mode == .parametric {
            let keep = !settings.filters.isEmpty && settings.graphicGains.allSatisfy { $0 == 0 }
            s.filters = keep ? settings.filters : seedFromGraphic(settings.graphicGains)
        }
        return s
    }

    /// One filter changed by hand, kept inside the ranges the page offers.
    public static func withFilter(_ settings: SoundSettings, index: Int, _ filter: EqFilter) -> SoundSettings {
        guard settings.filters.indices.contains(index) else { return settings }
        var clean = filter
        clean.frequency = min(maxHz, max(minHz, filter.frequency))
        clean.gainDb = cleanGain(filter.gainDb)
        clean.q = min(maxQ, max(minQ, filter.q))
        var s = settings
        s.filters[index] = clean
        s.preset = nil
        return s
    }

    /// A new flat filter in the widest empty stretch of the curve, or nothing new once there are
    /// as many as the equalizer takes.
    public static func withNewFilter(_ settings: SoundSettings) -> SoundSettings {
        guard settings.filters.count < maxFilters else { return settings }
        var s = settings
        s.filters.append(EqFilter(type: .peak, frequency: emptiestFrequency(settings.filters.map(\.frequency)), gainDb: 0, q: 1))
        s.preset = nil
        return s
    }

    public static func withoutFilter(_ settings: SoundSettings, index: Int) -> SoundSettings {
        guard settings.filters.indices.contains(index) else { return settings }
        var s = settings
        s.filters.remove(at: index)
        s.preset = nil
        return s
    }

    /// The middle, on the log scale, of the widest gap between the frequencies already used,
    /// rounded to a tidy number.
    public static func emptiestFrequency(_ used: [Double]) -> Double {
        let points = ([minHz, maxHz] + used.map { min(maxHz, max(minHz, $0)) }).sorted()
        var best = (points[0], points[1])
        var widest = -Double.infinity
        for (a, b) in zip(points, points.dropFirst()) where log(b / a) > widest {
            widest = log(b / a)
            best = (a, b)
        }
        return tidyHz(sqrt(best.0 * best.1))
    }

    /// A frequency rounded the way a person would type it: 47, 120, 1,300, 12,000.
    public static func tidyHz(_ hz: Double) -> Double {
        let step: Double = hz < 100 ? 1 : (hz < 1_000 ? 10 : (hz < 10_000 ? 100 : 1_000))
        return min(maxHz, max(minHz, Double(roundHalfUp(hz / step)) * step))
    }

    /// What the preset row marks as chosen: the preset the ten bands came from, or "Custom" for a
    /// curve changed by hand or made of free filters.
    public static func presetLabel(_ settings: SoundSettings) -> String {
        settings.mode == .graphic ? (settings.preset ?? custom) : custom
    }

    /// The equalizer in a few words, for the line that opens the Sound page.
    public static func soundSummary(_ settings: SoundSettings) -> String {
        if !settings.eqEnabled { return "Equalizer off" }
        if let correction = settings.correction { return "Equalizer on, \(presetLabel(settings)), with \(correction.name)" }
        return "Equalizer on, \(presetLabel(settings))"
    }

    /// A frequency as a short label: 31, 500, 1k, 1.2k, 16k.
    public static func shortHz(_ hz: Double) -> String {
        if hz < 1_000 { return String(roundHalfUp(hz)) }
        let k = Double(roundHalfUp(hz / 100)) / 10
        return k == k.rounded(.down) ? "\(Int(k))k" : String(format: "%.1fk", locale: Locale(identifier: "en_US_POSIX"), k)
    }

    /// A frequency as a reading: 62 Hz, 1.2 kHz.
    public static func readHz(_ hz: Double) -> String {
        hz < 1_000 ? "\(roundHalfUp(hz)) Hz" : "\(shortHz(hz).dropLast()) kHz"
    }

    /// A gain as a reading: +3.5 dB, 0 dB, -2 dB.
    public static func readDb(_ db: Double) -> String {
        let tenths = roundHalfUp(db * 10)
        if tenths == 0 { return "0 dB" }
        let sign = tenths > 0 ? "+" : "-"
        let size = abs(tenths)
        let number = size % 10 == 0 ? "\(size / 10)" : "\(size / 10).\(size % 10)"
        return "\(sign)\(number) dB"
    }

    /// What a screen reader says for a point on the curve: "62 Hz, +3 dB".
    public static func describeNode(hz: Double, db: Double) -> String {
        "\(roundHalfUp(hz)) Hz, \(readDb(db))"
    }

    /// A balance in words: Center, 30% left, 100% right.
    public static func readBalance(_ value: Double) -> String {
        let percent = roundHalfUp(abs(value) * 100)
        if percent == 0 { return "Center" }
        return value < 0 ? "\(percent)% left" : "\(percent)% right"
    }
}
