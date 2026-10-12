import Foundation

/// Lyrics whose timing is off can be moved earlier or later, a step at a time, this far for one
/// song. An output's own limit and step are in `LyricsOutputTiming`.
public let TIMING_LIMIT_MS = 10_000

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

/// A song's offset after moving it some steps: later is up, earlier is down.
public func stepTiming(_ offsetMs: Int, _ steps: Int, limitMs: Int = TIMING_LIMIT_MS) -> Int {
    (offsetMs + steps * LyricsOutputTiming.stepMs).clamped(-limitMs, limitMs)
}

/// How far ahead of the song the words are shown so they are on the screen when the song is
/// heard: the frames the screen takes, at its refresh rate. Every output starts from this, and
/// its own setting moves it from there.
public func screenLeadMs(_ refreshHz: Double) -> Int {
    let hz = refreshHz.isFinite && refreshHz >= 30 ? refreshHz : 60
    return -roundToLong(Double(SCREEN_FRAMES) * 1000.0 / hz)
}

/// An output's timing from what is kept: what it was set to under its key, or under a key it had
/// before (earbuds once named by their address), else its automatic timing.
public func outputTimingIn(_ offsets: [String: Int], _ output: AudioOutput) -> (ms: Int, automatic: Bool) {
    if let set = SoundOutputs.savedFor(offsets, output) { return (set, false) }
    return (LyricsOutputTiming.automatic(output.key), true)
}

/// The stored name a song's timing is kept under.
public let SONG_OFFSET_PREFIX = "offset:"

/// The offsets in words, song and output, for a menu line; nil when neither was moved. An
/// output on its automatic timing was not moved.
public func timingSummary(_ songMs: Int, _ outputMs: Int, _ outputLabel: String, outputAutomatic: Bool = false) -> String? {
    var parts: [String] = []
    if songMs != 0 { parts.append("This song \(LyricsOutputTiming.signed(songMs))") }
    if outputMs != 0 && !outputAutomatic { parts.append("\(outputLabel) \(LyricsOutputTiming.signed(outputMs))") }
    return parts.isEmpty ? nil : parts.joined(separator: " · ")
}
