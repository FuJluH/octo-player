import Foundation

/// The Q of a Butterworth second-order section: flat, no bump at the cutoff.
public let butterworthQ = 0.7071067811865476

/// A cutoff is kept below this share of the sample rate so the filter stays stable at any rate.
public let highestCutoffShare = 0.45

/// A second-order filter section (the common "cookbook" low-pass and high-pass), run one sample
/// at a time. Coefficients are normalized so a0 is 1: y = b0 x + b1 x1 + b2 x2 - a1 y1 - a2 y2.
public final class Biquad {
    public let b0: Double, b1: Double, b2: Double, a1: Double, a2: Double
    private var x1 = 0.0
    private var x2 = 0.0
    private var y1 = 0.0
    private var y2 = 0.0

    public init(b0: Double, b1: Double, b2: Double, a1: Double, a2: Double) {
        self.b0 = b0
        self.b1 = b1
        self.b2 = b2
        self.a1 = a1
        self.a2 = a2
    }

    public func process(_ x: Double) -> Double {
        let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2 = x1
        x1 = x
        y2 = y1
        y1 = y
        return y
    }

    public func reset() {
        x1 = 0
        x2 = 0
        y1 = 0
        y2 = 0
    }

    public static func lowPass(sampleRate: Int, hz: Double, q: Double = butterworthQ) -> Biquad {
        let (c, alpha) = shape(sampleRate, hz, q)
        let a0 = 1 + alpha
        return Biquad(b0: (1 - c) / 2 / a0, b1: (1 - c) / a0, b2: (1 - c) / 2 / a0, a1: -2 * c / a0, a2: (1 - alpha) / a0)
    }

    public static func highPass(sampleRate: Int, hz: Double, q: Double = butterworthQ) -> Biquad {
        let (c, alpha) = shape(sampleRate, hz, q)
        let a0 = 1 + alpha
        return Biquad(b0: (1 + c) / 2 / a0, b1: -(1 + c) / a0, b2: (1 + c) / 2 / a0, a1: -2 * c / a0, a2: (1 - alpha) / a0)
    }

    /// cos(w0) and alpha for a cutoff, with the cutoff held between 1 Hz and
    /// `highestCutoffShare` of the rate.
    private static func shape(_ sampleRate: Int, _ hz: Double, _ q: Double) -> (Double, Double) {
        let cutoff = min(max(hz, 1.0), Double(sampleRate) * highestCutoffShare)
        let w0 = 2 * Double.pi * cutoff / Double(sampleRate)
        return (cos(w0), sin(w0) / (2 * q))
    }
}

