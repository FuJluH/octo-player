import Foundation

/// The easing curves Octo's motion uses, as plain functions of progress from 0 to 1.
enum Easing {
    /// Speeds up quickly and settles slowly.
    static func fastOutSlowIn(_ x: Double) -> Double { cubicBezier(0.4, 0, 0.2, 1, x) }
    /// Starts at full speed and settles slowly.
    static func linearOutSlowIn(_ x: Double) -> Double { cubicBezier(0, 0, 0.2, 1, x) }

    /// The y of a CSS-style cubic bezier from (0, 0) to (1, 1) at the point whose x is `x`.
    static func cubicBezier(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ x: Double) -> Double {
        let x = min(1, max(0, x))
        if x == 0 || x == 1 { return x }
        func at(_ t: Double, _ a: Double, _ b: Double) -> Double {
            let u = 1 - t
            return 3 * u * u * t * a + 3 * u * t * t * b + t * t * t
        }
        func slope(_ t: Double, _ a: Double, _ b: Double) -> Double {
            let u = 1 - t
            return 3 * u * u * a + 6 * u * t * (b - a) + 3 * t * t * (1 - b)
        }
        var t = x
        for _ in 0..<8 {
            let error = at(t, x1, x2) - x
            let d = slope(t, x1, x2)
            if abs(error) < 1e-6 { break }
            if abs(d) < 1e-6 { break }
            t -= error / d
        }
        if t < 0 || t > 1 || abs(at(t, x1, x2) - x) > 1e-4 {
            var low = 0.0
            var high = 1.0
            t = x
            for _ in 0..<40 {
                let value = at(t, x1, x2)
                if abs(value - x) < 1e-7 { break }
                if value < x { low = t } else { high = t }
                t = (low + high) / 2
            }
        }
        return at(t, y1, y2)
    }
}
