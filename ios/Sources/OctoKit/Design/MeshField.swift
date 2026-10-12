import Foundation

/// Four soft pools of color that drift around the corners. Each point takes a blend of the
/// four, the nearer pools counting for more, so the colors flow into each other with no edges.
/// A slight ripple bends the blend, and a touch of grain keeps smooth gradients from banding.
public enum MeshField {
    /// Where the four pools are at `time` seconds, as fractions of the width and height.
    public static func pools(_ time: Double) -> [(x: Double, y: Double)] {
        [
            (0.20 + 0.18 * sin(time * 0.20), 0.18 + 0.14 * cos(time * 0.31)),
            (0.82 + 0.16 * cos(time * 0.43), 0.26 + 0.16 * sin(time * 0.37)),
            (0.24 + 0.16 * cos(time * 0.53), 0.78 + 0.14 * sin(time * 0.61)),
            (0.80 + 0.14 * sin(time * 0.70), 0.84 + 0.12 * cos(time * 0.47)),
        ]
    }

    /// The grain at a point, from -0.004 to 0.004.
    public static func grain(_ x: Double, _ y: Double) -> Double {
        let v = sin(x * 12.9898 + y * 78.233) * 43758.5453
        return (v - v.rounded(.down) - 0.5) * 0.008
    }

    /// The color at (`x`, `y`) in a field `width` by `height`, from `colors` (four, each red,
    /// green and blue from 0 to 1), with pools placed by `pools`.
    public static func color(x: Double, y: Double, width: Double, height: Double,
                             time: Double, pools: [(x: Double, y: Double)],
                             colors: [(Double, Double, Double)]) -> (Double, Double, Double) {
        var u = x / width
        var v = y / height
        let aspect = width / height
        let du = 0.05 * sin(v * 3 + time * 0.3)
        let dv = 0.05 * sin(u * 3 + time * 0.3)
        u += du
        v += dv
        var r = 0.0, g = 0.0, b = 0.0, total = 0.0
        for (index, pool) in pools.enumerated() {
            let dx = (u - pool.x) * aspect
            let dy = v - pool.y
            let w = 1 / (dx * dx + dy * dy + 0.02)
            let c = colors[index]
            r += c.0 * w
            g += c.1 * w
            b += c.2 * w
            total += w
        }
        let n = grain(x, y)
        return (r / total + n, g / total + n, b / total + n)
    }

    /// The field drawn into `columns` by `rows` pixels standing for a `width` by `height` area,
    /// as RGBA bytes, top row first.
    public static func render(columns: Int, rows: Int, width: Double, height: Double, time: Double,
                              colors: [(Double, Double, Double)]) -> [UInt8] {
        guard columns > 0, rows > 0, colors.count >= 4 else { return [] }
        var out = [UInt8](repeating: 255, count: columns * rows * 4)
        let at = pools(time)
        let stepX = width / Double(columns)
        let stepY = height / Double(rows)
        func byte(_ v: Double) -> UInt8 { UInt8(max(0, min(255, (v * 255).rounded()))) }
        for row in 0..<rows {
            let y = (Double(row) + 0.5) * stepY
            for column in 0..<columns {
                let x = (Double(column) + 0.5) * stepX
                let c = color(x: x, y: y, width: width, height: height, time: time, pools: at, colors: colors)
                let i = (row * columns + column) * 4
                out[i] = byte(c.0)
                out[i + 1] = byte(c.1)
                out[i + 2] = byte(c.2)
            }
        }
        return out
    }
}
