import Foundation

/// The blur behind the background, as its own maths gives it: a 9-tap weighting from the center
/// out, taps 0.03 x strength texels apart across and 0.04 x strength down, run across and down
/// twice.
public let BlurTaps: [Float] = [0.1027, 0.0984, 0.0867, 0.0702, 0.0523, 0.0358, 0.0225, 0.0130, 0.0069]
public let BlurStrength: Float = 30
public let BlurStepAcross: Float = 0.03 * BlurStrength
public let BlurStepDown: Float = 0.04 * BlurStrength

/// Softer than the taps alone give: on a phone the wash read as too sharp, so the blur is widened
/// by this much.
public let WashBlurBoost: Float = 2.5

/// The taps add up to a little under 1, so each of the four passes dims the picture by that much.
public var BlurPassGain: Float { BlurTaps[0] + 2 * BlurTaps.dropFirst().reduce(0, +) }

/// The spread (standard deviation, in taps) of the bell curve the weights follow, from the
/// fall-off between the center and the last tap.
public var BlurSigmaTaps: Float { (64 / (2 * log(BlurTaps[0] / BlurTaps[8]))).squareRoot() }

/// The whole blur's spread in texels of the 512 square: one pass's spread times the tap spacing,
/// and two passes add up as the square root of two.
public func blurSigmaTexels(_ step: Float) -> Float { BlurSigmaTaps * step * Float(2).squareRoot() }

/// The radius a platform blur is asked for, for a spread: it turns a radius r into a spread of
/// 0.57735 r + 0.5.
public func blurRadiusFor(_ sigma: Float) -> Float { max((sigma - 0.5) / 0.57735, 0) }

/// The spread a platform blur gives for a radius.
public func blurSigmaFor(_ radius: Float) -> Float { 0.57735 * radius + 0.5 }

/// The final pass brightens by 1.5. It also carries the four blur passes' dimming, which a blur
/// whose weights add to exactly 1 leaves out.
public var FinalGain: Float {
    let g = BlurPassGain
    return 1.5 * g * g * g * g
}

/// The spreads of the wash's blur across and down, in texels of the 512 square.
public var WashBlurSigmaAcross: Float { blurSigmaFor(blurRadiusFor(blurSigmaTexels(BlurStepAcross)) * WashBlurBoost) }
public var WashBlurSigmaDown: Float { blurSigmaFor(blurRadiusFor(blurSigmaTexels(BlurStepDown)) * WashBlurBoost) }
