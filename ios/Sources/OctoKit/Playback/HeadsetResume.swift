import Foundation

/// How long after headphones went away the music still comes back when they return. Past this,
/// connecting them is taken as something new.
public let resumeWindowMs = 30 * 60_000

/// Headphones that can bring the music back: over a cable (a USB headset counts), or over
/// Bluetooth.
public enum HeadsetKind: String, Sendable { case wired = "Wired", bluetooth = "Bluetooth" }

/// The headphone switches, as the settings keep them.
public struct ResumePrefs: Sendable, Equatable {
    public var resumeWired = false
    public var resumeBluetooth = false
    public var resumeAlways = false

    public init(resumeWired: Bool = false, resumeBluetooth: Bool = false, resumeAlways: Bool = false) {
        self.resumeWired = resumeWired
        self.resumeBluetooth = resumeBluetooth
        self.resumeAlways = resumeAlways
    }
}

/// The kind of an output by the system's name for its port: wired headphones, a USB headset,
/// Bluetooth music and Bluetooth LE. The speaker and Bluetooth for calls are neither.
public func headsetKind(portType: String) -> HeadsetKind? {
    switch portType {
    case "Headphones", "USBAudio": .wired
    case "BluetoothA2DPOutput", "BluetoothLE": .bluetooth
    default: nil
    }
}

/// Whether headphones that just connected should start the music: their kind is switched on,
/// nothing is playing, there is a queue, and either the music was paused by the output going away
/// (a cable pulled, Bluetooth dropped) in the last 30 minutes, or "always play on connect" is on.
public func shouldResumeOnConnect(_ kind: HeadsetKind, prefs: ResumePrefs, playing: Bool, hasQueue: Bool, lostOutputAt: Int?, now: Int) -> Bool {
    let wanted = kind == .wired ? prefs.resumeWired : prefs.resumeBluetooth
    if !wanted || playing || !hasQueue { return false }
    if prefs.resumeAlways { return true }
    guard let lostOutputAt else { return false }
    return (0...resumeWindowMs).contains(now - lostOutputAt)
}

/// Whether music carries on on the phone when playing on another device (AirPlay) ends. Picking
/// the phone moves the music across as it was. When it ends any other way (the device went away,
/// or was taken over from elsewhere), the music pauses unless the listener asked for it to keep
/// playing.
public func playsOnReturn(wasPlaying: Bool, chosen: Bool, keepPlaying: Bool) -> Bool {
    wasPlaying && (chosen || keepPlaying)
}

/// The sound needs a moment to move to newly connected headphones; Bluetooth takes longer than a
/// cable. Playing sooner would start on the speaker.
public let wiredSettleMs = 500
public let bluetoothSettleMs = 1_500

/// Songs played this recently are not picked again by Autoplay.
public let autoplayRecentPlays = 50

/// How near the end of the last song Autoplay's songs go in: early enough for the server to
/// answer and for a crossfade to load the next one.
public let autoplayLeadMs = 20_000
public let autoplayLoadAheadMs = 15_000

/// How often Autoplay looks at how far into the last song the player is.
public let autoplayWatchEveryMs = 1_000

/// Whether it is time to add songs: Autoplay is on, repeat is off, nothing comes after the song
/// that is on, and it is within `leadMs` of its end.
public func autoplayDue(_ enabled: Bool, repeatMode: RepeatMode, hasNext: Bool, remainingMs: Int, leadMs: Int) -> Bool {
    enabled && repeatMode == .off && !hasNext && remainingMs <= leadMs
}

/// How far ahead of the end Autoplay adds: a planned blend can start up to
/// `longestEarlyExitMs` before the end.
public func autoplayLead(crossfadeMs: Int) -> Int {
    let early = crossfadeMs > 0 ? longestEarlyExitMs : 0
    return max(autoplayLeadMs, crossfadeMs + early + autoplayLoadAheadMs)
}
