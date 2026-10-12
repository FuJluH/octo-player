import Foundation

/// How an output's lyrics timing reads in the settings, and where it starts when never set.
public enum LyricsOutputTiming {
    /// A tap moves the timing by this much.
    public static let stepMs = 50
    /// An output's timing goes no further either way, since a sound output is never seconds late.
    public static let limitMs = 2_000
    /// Where an output's timing starts when the listener never set one: words are mostly heard
    /// about 0.3 s late on the speaker or a cable, and 0.5 s over Bluetooth.
    public static let wiredMs = -300
    public static let bluetoothMs = -500

    /// What the stored settings call an output's timing.
    public static let keyPrefix = "lyrics_output_offset:"

    public static func automatic(_ outputKey: String) -> Int {
        outputKey.hasPrefix(AudioOutput.bluetoothPrefix) ? bluetoothMs : wiredMs
    }

    /// The timing after moving it some steps: later is up, earlier is down.
    public static func step(_ ms: Int, steps: Int) -> Int {
        min(max(ms + steps * stepMs, -limitMs), limitMs)
    }

    /// What an output's timing applies to, and, while it is the automatic one, what that is.
    public static func about(_ outputKey: String, automatic: Bool) -> String {
        automatic ? "Every song on this output. \(automaticNote(outputKey))" : "Every song on this output."
    }

    /// What the automatic timing is, in words.
    public static func automaticNote(_ outputKey: String) -> String {
        outputKey.hasPrefix(AudioOutput.bluetoothPrefix)
            ? "Automatic: \(label(bluetoothMs)), the usual for Bluetooth."
            : "Automatic: \(label(wiredMs)), the usual for a speaker or a cable."
    }

    /// The timing in words: "In time", "0.25 s later", "1.5 s earlier".
    public static func label(_ ms: Int) -> String {
        if ms == 0 { return "In time" }
        return ms > 0 ? "\(seconds(ms)) s later" : "\(seconds(ms)) s earlier"
    }

    /// The timing as a signed number of seconds: "0 s", "+0.75 s", "-1.5 s".
    public static func signed(_ ms: Int) -> String {
        if ms == 0 { return "0 s" }
        return ms > 0 ? "+\(seconds(ms)) s" : "-\(seconds(ms)) s"
    }

    /// Whole milliseconds as seconds with no trailing zeros: 750 is "0.75", 1500 is "1.5".
    static func seconds(_ ms: Int) -> String {
        let whole = abs(ms) / 1000
        var part = String(abs(ms) % 1000)
        while part.count < 3 { part = "0" + part }
        while part.hasSuffix("0") { part.removeLast() }
        return part.isEmpty ? "\(whole)" : "\(whole).\(part)"
    }
}
