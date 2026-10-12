import Foundation

/// One step of an outline, in absolute coordinates: arcs and the shorthand curves are turned
/// into cubic curves, so a drawing surface only needs these four.
public enum PathStep: Sendable, Equatable {
    case move(Double, Double)
    case line(Double, Double)
    case cubic(Double, Double, Double, Double, Double, Double)
    case close
}

/// Reads SVG path data (every command, absolute or relative) into steps.
public enum PathData {
    public static func steps(_ data: String) -> [PathStep] { parse(data).steps }

    /// The steps, and whether the whole text was read.
    public static func parse(_ data: String) -> (steps: [PathStep], complete: Bool) {
        var reader = Reader(Array(data.utf8))
        var steps: [PathStep] = []
        var command: UInt8 = 0
        var x = 0.0, y = 0.0
        var startX = 0.0, startY = 0.0
        // The last control point, for the smooth curve commands.
        var lastCubic: (Double, Double)?
        var lastQuad: (Double, Double)?

        while true {
            reader.skipSeparators()
            guard let c = reader.peek() else { break }
            if isCommand(c) {
                command = c
                reader.advance()
            } else if command == 0 {
                break
            }
            let relative = command >= 97
            let ox = relative ? x : 0
            let oy = relative ? y : 0
            var nextCubic: (Double, Double)?
            var nextQuad: (Double, Double)?
            switch command | 0x20 {
            case UInt8(ascii: "m"):
                guard let px = reader.number(), let py = reader.number() else { return (steps, false) }
                x = ox + px
                y = oy + py
                startX = x
                startY = y
                steps.append(.move(x, y))
                // Pairs after a move are lines.
                command = relative ? UInt8(ascii: "l") : UInt8(ascii: "L")
            case UInt8(ascii: "l"):
                guard let px = reader.number(), let py = reader.number() else { return (steps, false) }
                x = ox + px
                y = oy + py
                steps.append(.line(x, y))
            case UInt8(ascii: "h"):
                guard let px = reader.number() else { return (steps, false) }
                x = ox + px
                steps.append(.line(x, y))
            case UInt8(ascii: "v"):
                guard let py = reader.number() else { return (steps, false) }
                y = oy + py
                steps.append(.line(x, y))
            case UInt8(ascii: "c"):
                guard let x1 = reader.number(), let y1 = reader.number(), let x2 = reader.number(),
                      let y2 = reader.number(), let px = reader.number(), let py = reader.number() else { return (steps, false) }
                steps.append(.cubic(ox + x1, oy + y1, ox + x2, oy + y2, ox + px, oy + py))
                nextCubic = (ox + x2, oy + y2)
                x = ox + px
                y = oy + py
            case UInt8(ascii: "s"):
                guard let x2 = reader.number(), let y2 = reader.number(), let px = reader.number(),
                      let py = reader.number() else { return (steps, false) }
                let c1 = lastCubic.map { (2 * x - $0.0, 2 * y - $0.1) } ?? (x, y)
                steps.append(.cubic(c1.0, c1.1, ox + x2, oy + y2, ox + px, oy + py))
                nextCubic = (ox + x2, oy + y2)
                x = ox + px
                y = oy + py
            case UInt8(ascii: "q"):
                guard let qx = reader.number(), let qy = reader.number(), let px = reader.number(),
                      let py = reader.number() else { return (steps, false) }
                let q = (ox + qx, oy + qy)
                let end = (ox + px, oy + py)
                steps.append(quad(from: (x, y), q, end))
                nextQuad = q
                x = end.0
                y = end.1
            case UInt8(ascii: "t"):
                guard let px = reader.number(), let py = reader.number() else { return (steps, false) }
                let q = lastQuad.map { (2 * x - $0.0, 2 * y - $0.1) } ?? (x, y)
                let end = (ox + px, oy + py)
                steps.append(quad(from: (x, y), q, end))
                nextQuad = q
                x = end.0
                y = end.1
            case UInt8(ascii: "a"):
                guard let rx = reader.number(), let ry = reader.number(), let rotation = reader.number(),
                      let large = reader.flag(), let sweep = reader.flag(),
                      let px = reader.number(), let py = reader.number() else { return (steps, false) }
                let end = (ox + px, oy + py)
                steps.append(contentsOf: arc(from: (x, y), to: end, rx: rx, ry: ry, rotation: rotation, large: large, sweep: sweep))
                x = end.0
                y = end.1
            case UInt8(ascii: "z"):
                steps.append(.close)
                x = startX
                y = startY
                // A new command must follow.
                command = 0
            default:
                return (steps, false)
            }
            lastCubic = nextCubic
            lastQuad = nextQuad
        }
        return (steps, reader.peek() == nil)
    }

    private static func isCommand(_ c: UInt8) -> Bool {
        switch c | 0x20 {
        case UInt8(ascii: "m"), UInt8(ascii: "l"), UInt8(ascii: "h"), UInt8(ascii: "v"), UInt8(ascii: "c"),
             UInt8(ascii: "s"), UInt8(ascii: "q"), UInt8(ascii: "t"), UInt8(ascii: "a"), UInt8(ascii: "z"):
            return (c >= 65 && c <= 90) || (c >= 97 && c <= 122)
        default:
            return false
        }
    }

    private static func quad(from p0: (Double, Double), _ q: (Double, Double), _ p: (Double, Double)) -> PathStep {
        .cubic(p0.0 + 2 / 3 * (q.0 - p0.0), p0.1 + 2 / 3 * (q.1 - p0.1),
               p.0 + 2 / 3 * (q.0 - p.0), p.1 + 2 / 3 * (q.1 - p.1), p.0, p.1)
    }

    /// An elliptical arc as cubic curves, each spanning at most a quarter turn.
    static func arc(from p0: (Double, Double), to p1: (Double, Double), rx: Double, ry: Double,
                    rotation: Double, large: Bool, sweep: Bool) -> [PathStep] {
        if p0 == p1 { return [] }
        var rx = abs(rx)
        var ry = abs(ry)
        if rx == 0 || ry == 0 { return [.line(p1.0, p1.1)] }
        let phi = rotation * Double.pi / 180
        let cosPhi = cos(phi)
        let sinPhi = sin(phi)
        let dx = (p0.0 - p1.0) / 2
        let dy = (p0.1 - p1.1) / 2
        let x1 = cosPhi * dx + sinPhi * dy
        let y1 = -sinPhi * dx + cosPhi * dy
        let lambda = (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry)
        if lambda > 1 {
            rx *= lambda.squareRoot()
            ry *= lambda.squareRoot()
        }
        let num = rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1
        let den = rx * rx * y1 * y1 + ry * ry * x1 * x1
        var factor = den == 0 ? 0 : max(0, num / den).squareRoot()
        if large == sweep { factor = -factor }
        let cx1 = factor * rx * y1 / ry
        let cy1 = -factor * ry * x1 / rx
        let cx = cosPhi * cx1 - sinPhi * cy1 + (p0.0 + p1.0) / 2
        let cy = sinPhi * cx1 + cosPhi * cy1 + (p0.1 + p1.1) / 2

        func angle(_ ux: Double, _ uy: Double, _ vx: Double, _ vy: Double) -> Double {
            let dot = ux * vx + uy * vy
            let length = (ux * ux + uy * uy).squareRoot() * (vx * vx + vy * vy).squareRoot()
            var a = acos(max(-1, min(1, dot / length)))
            if ux * vy - uy * vx < 0 { a = -a }
            return a
        }
        let theta1 = angle(1, 0, (x1 - cx1) / rx, (y1 - cy1) / ry)
        var delta = angle((x1 - cx1) / rx, (y1 - cy1) / ry, (-x1 - cx1) / rx, (-y1 - cy1) / ry)
        if !sweep && delta > 0 { delta -= 2 * Double.pi }
        if sweep && delta < 0 { delta += 2 * Double.pi }

        let segments = max(1, Int((abs(delta) / (Double.pi / 2)).rounded(.up)))
        let step = delta / Double(segments)
        let k = 4.0 / 3.0 * tan(step / 4)
        var steps: [PathStep] = []
        var t = theta1
        func point(_ a: Double) -> (Double, Double) {
            let ex = rx * cos(a)
            let ey = ry * sin(a)
            return (cosPhi * ex - sinPhi * ey + cx, sinPhi * ex + cosPhi * ey + cy)
        }
        func tangent(_ a: Double) -> (Double, Double) {
            let ex = -rx * sin(a)
            let ey = ry * cos(a)
            return (cosPhi * ex - sinPhi * ey, sinPhi * ex + cosPhi * ey)
        }
        for i in 0..<segments {
            let a0 = t
            let a1 = t + step
            let s = point(a0)
            let e = i == segments - 1 ? p1 : point(a1)
            let d0 = tangent(a0)
            let d1 = tangent(a1)
            steps.append(.cubic(s.0 + k * d0.0, s.1 + k * d0.1, e.0 - k * d1.0, e.1 - k * d1.1, e.0, e.1))
            t = a1
        }
        return steps
    }

    private struct Reader {
        let bytes: [UInt8]
        var index = 0

        init(_ bytes: [UInt8]) { self.bytes = bytes }

        func peek() -> UInt8? { index < bytes.count ? bytes[index] : nil }
        mutating func advance() { index += 1 }

        mutating func skipSeparators() {
            while let c = peek(), c == 32 || c == 44 || c == 9 || c == 10 || c == 13 { advance() }
        }

        /// An arc's flag: a single 0 or 1, which may run straight into the next number.
        mutating func flag() -> Bool? {
            skipSeparators()
            guard let c = peek(), c == 48 || c == 49 else { return nil }
            advance()
            return c == 49
        }

        mutating func number() -> Double? {
            skipSeparators()
            let start = index
            if let c = peek(), c == 43 || c == 45 { advance() }
            var digits = false
            var dot = false
            while let c = peek() {
                if c >= 48 && c <= 57 {
                    digits = true
                    advance()
                } else if c == 46 && !dot {
                    dot = true
                    advance()
                } else {
                    break
                }
            }
            if digits, let c = peek(), c == 101 || c == 69 {
                let mark = index
                advance()
                if let s = peek(), s == 43 || s == 45 { advance() }
                var exponent = false
                while let d = peek(), d >= 48 && d <= 57 {
                    exponent = true
                    advance()
                }
                if !exponent { index = mark }
            }
            guard digits else {
                index = start
                return nil
            }
            return Double(String(decoding: bytes[start..<index], as: UTF8.self))
        }
    }
}
