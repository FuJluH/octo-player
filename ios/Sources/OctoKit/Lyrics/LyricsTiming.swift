import Foundation

// Lyrics whose timing is off can be moved earlier or later by this much a step: for one song up
// to this far either way, for an output (the speaker, a pair of earbuds) up to the second limit,
// since a sound output is never seconds late.
public let TIMING_STEP_MS = 50
public let TIMING_LIMIT_MS = 10_000
public let OUTPUT_TIMING_LIMIT_MS = 2_000

/// A screen shows a frame about this many frames after the time it was drawn for: one to draw it
/// and one for the display to take it up.
public let SCREEN_FRAMES = 2

// A timing offset says how much later than written the words are heard: at +500 a line written
// at 1:00.00 is sung at 1:00.50. So the lyrics follow a clock that runs that far behind the song,
// and a tap on a line plays from where it is heard. The song's own offset and the output's add
// up: the words follow the song less both, and a tap plays from the line plus both.

/// Where in the lyrics the song is, at this point in the song.
public func lyricsClock(_ positionMs: Int, _ offsetMs: Int) -> Int { positionMs - offsetMs }

/// Where in the song a line written at this time is heard.
public func heardAt(_ lyricsMs: Int, _ offsetMs: Int) -> Int { max(lyricsMs + offsetMs, 0) }

/// The whole offset: the song's, and the output's on top.
public func totalOffset(songMs: Int, outputMs: Int) -> Int { songMs + outputMs }

/// The offset after moving it some steps: later is up, earlier is down.
public func stepTiming(_ offsetMs: Int, _ steps: Int, limitMs: Int = TIMING_LIMIT_MS) -> Int {
    (offsetMs + steps * TIMING_STEP_MS).clamped(-limitMs, limitMs)
}

/// How far ahead of the song the words are shown so they are on the screen when the song is
/// heard: the frames the screen takes, at its refresh rate. Every output starts from this, and
/// its own setting moves it from there.
public func screenLeadMs(_ refreshHz: Double) -> Int {
    let hz = refreshHz.isFinite && refreshHz >= 30 ? refreshHz : 60
    return -roundToLong(Double(SCREEN_FRAMES) * 1000.0 / hz)
}

// Where an output's timing starts when the listener never set one: the words are mostly heard
// this much late, about 0.3 s on the phone's own speaker, a cable or USB, and 0.5 s over
// Bluetooth, which holds more sound back. Starting there leaves most listeners nothing to move.
public let WIRED_OUTPUT_TIMING_MS = -300
public let BLUETOOTH_OUTPUT_TIMING_MS = -500

/// The start of a Bluetooth output's key; the rest is the device's name.
public let BLUETOOTH_OUTPUT_PREFIX = AudioOutput.bluetoothPrefix

public func automaticOutputTiming(_ outputKey: String) -> Int {
    outputKey.hasPrefix(BLUETOOTH_OUTPUT_PREFIX) ? BLUETOOTH_OUTPUT_TIMING_MS : WIRED_OUTPUT_TIMING_MS
}

/// An output's timing, and whether it is the automatic one (never set by the listener) rather
/// than one they set, 0 included.
public struct OutputTiming: Equatable, Sendable {
    public var ms: Int
    public var automatic: Bool

    public init(_ ms: Int, automatic: Bool) {
        self.ms = ms
        self.automatic = automatic
    }
}

public func outputTimingIn(_ offsets: [String: Int], _ outputKey: String) -> OutputTiming {
    if let set = offsets[outputKey] { return OutputTiming(set, automatic: false) }
    return OutputTiming(automaticOutputTiming(outputKey), automatic: true)
}

/// An output's offset from what is kept, the automatic one for an output never moved.
public func outputOffsetIn(_ offsets: [String: Int], _ outputKey: String) -> Int { outputTimingIn(offsets, outputKey).ms }

/// The same for an output that may have been saved under another key before: what it was set to
/// there, else its automatic timing.
public func outputTimingIn(_ offsets: [String: Int], _ output: AudioOutput) -> OutputTiming {
    if let set = SoundOutputs.savedFor(offsets, output) { return OutputTiming(set, automatic: false) }
    return OutputTiming(automaticOutputTiming(output.key), automatic: true)
}

public func outputOffsetIn(_ offsets: [String: Int], _ output: AudioOutput) -> Int { outputTimingIn(offsets, output).ms }

/// The stored name an output's timing is kept under.
public let OUTPUT_OFFSET_PREFIX = "lyrics_output_offset:"

/// The stored name a song's timing is kept under.
public let SONG_OFFSET_PREFIX = "offset:"

/// Every output's offset out of the stored settings, by output key.
public func outputOffsetsIn(_ stored: [String: Any]) -> [String: Int] {
    var found: [String: Int] = [:]
    for (name, value) in stored where name.hasPrefix(OUTPUT_OFFSET_PREFIX) {
        let key = String(name.dropFirst(OUTPUT_OFFSET_PREFIX.count))
        if let number = value as? Int { found[key] = number } else if let number = value as? NSNumber { found[key] = number.intValue }
    }
    return found
}

/// What an output's timing applies to, and, while it is the automatic one, what that is.
public func outputTimingAbout(_ outputKey: String, automatic: Bool) -> String {
    automatic ? "Every song on this output. \(automaticTimingNote(outputKey))" : "Every song on this output."
}

/// What the automatic timing is, in words, for the settings.
public func automaticTimingNote(_ outputKey: String) -> String {
    outputKey.hasPrefix(BLUETOOTH_OUTPUT_PREFIX)
        ? "Automatic: \(timingLabel(BLUETOOTH_OUTPUT_TIMING_MS)), the usual for Bluetooth."
        : "Automatic: \(timingLabel(WIRED_OUTPUT_TIMING_MS)), the usual for a speaker or a cable."
}

/// The offsets in words, song and output, for a menu line; nil when neither was moved. An
/// output on its automatic timing was not moved.
public func timingSummary(_ songMs: Int, _ outputMs: Int, _ outputLabel: String, outputAutomatic: Bool = false) -> String? {
    var parts: [String] = []
    if songMs != 0 { parts.append("This song \(signedTiming(songMs))") }
    if outputMs != 0 && !outputAutomatic { parts.append("\(outputLabel) \(signedTiming(outputMs))") }
    return parts.isEmpty ? nil : parts.joined(separator: " · ")
}

/// The offset in words: "In time", "0.25 s later", "1.5 s earlier".
public func timingLabel(_ offsetMs: Int) -> String {
    if offsetMs == 0 { return "In time" }
    let seconds = plainSeconds(abs(offsetMs))
    return offsetMs > 0 ? "\(seconds) s later" : "\(seconds) s earlier"
}

/// The offset as a signed number of seconds, for the timing control: "0 s", "+0.75 s", "-1.5 s".
public func signedTiming(_ offsetMs: Int) -> String {
    if offsetMs == 0 { return "0 s" }
    let seconds = plainSeconds(abs(offsetMs))
    return offsetMs > 0 ? "+\(seconds) s" : "-\(seconds) s"
}

// Milliseconds as seconds with trailing zeros cut: 250 is "0.25", 1000 is "1".
private func plainSeconds(_ ms: Int) -> String {
    let whole = ms / 1000
    var fraction = String(ms % 1000)
    while fraction.count < 3 { fraction = "0" + fraction }
    while fraction.hasSuffix("0") { fraction.removeLast() }
    return fraction.isEmpty ? String(whole) : "\(whole).\(fraction)"
}
