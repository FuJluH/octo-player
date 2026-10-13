import Foundation

/// How synced lyrics are shown.
public enum LyricsStyle: String, Codable, Sendable, CaseIterable {
    case flowing = "Flowing"
    case classic = "Classic"

    public var label: String {
        switch self {
        case .flowing: "Flowing"
        case .classic: "Classic"
        }
    }

    public var about: String {
        switch self {
        case .flowing: "Lines ripple into place, words fill with light and long notes bloom."
        case .classic: "The line being sung grows and its words brighten in place."
        }
    }
}

/// One of the look's sliders: its percent range and where it starts.
public enum LookDial: String, Sendable, CaseIterable {
    case emphasis = "Emphasis"
    case glow = "Glow"
    case lift = "Lift"
    case speed = "Speed"
    case inactiveScale = "InactiveScale"
    case fade = "Fade"
    case cascade = "Cascade"

    public var key: String {
        switch self {
        case .emphasis: "lyrics_fx_emphasis"
        case .glow: "lyrics_fx_glow"
        case .lift: "lyrics_fx_lift"
        case .speed: "lyrics_fx_speed"
        case .inactiveScale: "lyrics_fx_inactive_scale"
        case .fade: "lyrics_fx_fade"
        case .cascade: "lyrics_fx_cascade"
        }
    }

    public var range: ClosedRange<Int> {
        switch self {
        case .emphasis: 0...200
        case .glow: 0...200
        case .lift: 0...200
        case .speed: 50...200
        case .inactiveScale: 60...100
        case .fade: 0...200
        case .cascade: 0...200
        }
    }

    public var `default`: Int {
        switch self {
        case .emphasis: 100
        case .glow: 100
        case .lift: 100
        case .speed: 100
        case .inactiveScale: 80
        case .fade: 100
        case .cascade: 100
        }
    }
}

/// How the flowing lyrics look, in percent where it is a slider.
public struct LyricsLook: Equatable, Sendable, Codable {
    public var style: LyricsStyle
    /// How much long notes swell, spread and rise.
    public var emphasis: Int
    /// How strongly long notes glow.
    public var glow: Int
    /// How far sung words rise and bob.
    public var lift: Int
    /// How quickly lines move into place.
    public var speed: Int
    /// The size of the lines not being sung.
    public var inactiveScale: Int
    /// How soft the edge of the word fill is.
    public var fade: Int
    /// How far apart the lines start moving when the focus moves.
    public var cascade: Int
    /// Sung lines stay above the current one, dimmed, so the lyrics fill the screen instead of
    /// starting halfway down.
    public var keepCompleted: Bool
    /// The lines bend around a drum.
    public var arc: Bool
    /// Notes held out among quick singing bloom too, not only those held a second or more, and
    /// sung words rise a little further.
    public var bloomFast: Bool

    public init(
        style: LyricsStyle = .flowing,
        emphasis: Int = LookDial.emphasis.default,
        glow: Int = LookDial.glow.default,
        lift: Int = LookDial.lift.default,
        speed: Int = LookDial.speed.default,
        inactiveScale: Int = LookDial.inactiveScale.default,
        fade: Int = LookDial.fade.default,
        cascade: Int = LookDial.cascade.default,
        keepCompleted: Bool = true,
        arc: Bool = false,
        bloomFast: Bool = true
    ) {
        self.style = style
        self.emphasis = emphasis
        self.glow = glow
        self.lift = lift
        self.speed = speed
        self.inactiveScale = inactiveScale
        self.fade = fade
        self.cascade = cascade
        self.keepCompleted = keepCompleted
        self.arc = arc
        self.bloomFast = bloomFast
    }

    public func percent(_ dial: LookDial) -> Int {
        switch dial {
        case .emphasis: emphasis
        case .glow: glow
        case .lift: lift
        case .speed: speed
        case .inactiveScale: inactiveScale
        case .fade: fade
        case .cascade: cascade
        }
    }

    public func with(_ dial: LookDial, percent: Int) -> LyricsLook {
        let value = percent.clamped(dial.range.lowerBound, dial.range.upperBound)
        var look = self
        switch dial {
        case .emphasis: look.emphasis = value
        case .glow: look.glow = value
        case .lift: look.lift = value
        case .speed: look.speed = value
        case .inactiveScale: look.inactiveScale = value
        case .fade: look.fade = value
        case .cascade: look.cascade = value
        }
        return look
    }

    /// As fractions, for the drawing.
    public func fraction(_ dial: LookDial) -> Double {
        Double(percent(dial).clamped(dial.range.lowerBound, dial.range.upperBound)) / 100.0
    }

    enum CodingKeys: String, CodingKey { case style, emphasis, glow, lift, speed, inactiveScale, fade, cascade, keepCompleted, arc, bloomFast }

    // A saved look may leave out any field, and in a backup name a style this app does not know;
    // either takes its default.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        style = try c.choice(LyricsStyle.self, forKey: .style, decoder) ?? .flowing
        emphasis = try c.decodeIfPresent(Int.self, forKey: .emphasis) ?? LookDial.emphasis.default
        glow = try c.decodeIfPresent(Int.self, forKey: .glow) ?? LookDial.glow.default
        lift = try c.decodeIfPresent(Int.self, forKey: .lift) ?? LookDial.lift.default
        speed = try c.decodeIfPresent(Int.self, forKey: .speed) ?? LookDial.speed.default
        inactiveScale = try c.decodeIfPresent(Int.self, forKey: .inactiveScale) ?? LookDial.inactiveScale.default
        fade = try c.decodeIfPresent(Int.self, forKey: .fade) ?? LookDial.fade.default
        cascade = try c.decodeIfPresent(Int.self, forKey: .cascade) ?? LookDial.cascade.default
        keepCompleted = try c.decodeIfPresent(Bool.self, forKey: .keepCompleted) ?? true
        arc = try c.decodeIfPresent(Bool.self, forKey: .arc) ?? false
        bloomFast = try c.decodeIfPresent(Bool.self, forKey: .bloomFast) ?? true
    }
}
