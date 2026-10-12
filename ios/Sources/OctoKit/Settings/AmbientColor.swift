import Foundation

/// Artwork colors made safe to glow behind the pages, as 0xAARRGGBB numbers.
public enum AmbientColor {
    /// Colors are held to this lightness and saturation before they glow, so a white or neon
    /// cover still comes through as a dark, soft tint.
    public static let maxLightness: Float = 0.5
    public static let maxSaturation: Float = 0.55

    /// The page background the glow sits on.
    public static let base: UInt32 = 0xFF0C0C0D

    /// Quiet shades of the app's own accent, for a song without artwork.
    public static let quiet: [UInt32] = [0xFF2A3438, 0xFF1A1A1B, 0xFF3A4A50, 0xFF0A0B0F]

    /// The same hue, no brighter and no more saturated than the limits above.
    public static func safe(_ argb: UInt32) -> UInt32 {
        let (h, s, l) = toHsl(argb)
        return fromHsl(h, min(s, maxSaturation), min(l, maxLightness))
    }

    static func toHsl(_ argb: UInt32) -> (Float, Float, Float) {
        let r = Float((argb >> 16) & 0xFF) / 255
        let g = Float((argb >> 8) & 0xFF) / 255
        let b = Float(argb & 0xFF) / 255
        let high = max(r, max(g, b))
        let low = min(r, min(g, b))
        let lightness = (high + low) / 2
        let spread = high - low
        if spread == 0 { return (0, 0, lightness) }
        let saturation = spread / (1 - abs(2 * lightness - 1))
        var hue: Float
        if high == r {
            hue = ((g - b) / spread).truncatingRemainder(dividingBy: 6)
            if hue < 0 { hue += 6 }
        } else if high == g {
            hue = (b - r) / spread + 2
        } else {
            hue = (r - g) / spread + 4
        }
        return (hue * 60, min(max(saturation, 0), 1), lightness)
    }

    static func fromHsl(_ hue: Float, _ saturation: Float, _ lightness: Float) -> UInt32 {
        let chroma = (1 - abs(2 * lightness - 1)) * saturation
        var sector = (hue / 60).truncatingRemainder(dividingBy: 2)
        if sector < 0 { sector += 2 }
        let x = chroma * (1 - abs(sector - 1))
        let m = lightness - chroma / 2
        let (r, g, b): (Float, Float, Float) = switch min(max(Int(hue / 60), 0), 5) {
        case 0: (chroma, x, 0)
        case 1: (x, chroma, 0)
        case 2: (0, chroma, x)
        case 3: (0, x, chroma)
        case 4: (x, 0, chroma)
        default: (chroma, 0, x)
        }
        func byte(_ v: Float) -> UInt32 { UInt32(min(max(Int(((v + m) * 255 + 0.5).rounded(.down)), 0), 255)) }
        return 0xFF00_0000 | (byte(r) << 16) | (byte(g) << 8) | byte(b)
    }
}
