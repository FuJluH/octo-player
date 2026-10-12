import SwiftUI

/// Octo's octopus, drawn from the same vector as every Octo icon (`tools/appicon/octopus.svg`).
/// The paths live in `OctopusArt+Paths.swift`, which the icon script writes.
enum OctopusArt {
    struct Part: Sendable {
        /// The gradient's colours at the part's top and bottom, and where those are.
        let top: UInt32
        let bottom: UInt32
        let from: CGFloat
        let to: CGFloat
        let path: String
    }

    /// Each part's outline, parsed once.
    static let outlines: [Path] = parts.map { SVGPath.parse($0.path) }
}

/// The octopus as a view. In colour by default; `tint` draws the whole silhouette in one colour,
/// the way Octo marks a song or album that came through Octo rather than from the library.
struct OctopusMark: View {
    var tint: Color?

    var body: some View {
        Canvas { context, size in
            let art = OctopusArt.size
            let scale = min(size.width / art.width, size.height / art.height)
            context.translateBy(x: (size.width - art.width * scale) / 2, y: (size.height - art.height * scale) / 2)
            context.scaleBy(x: scale, y: scale)
            for (part, outline) in zip(OctopusArt.parts, OctopusArt.outlines) {
                if let tint {
                    context.fill(outline, with: .color(tint))
                } else {
                    context.fill(outline, with: .linearGradient(
                        Gradient(colors: [Color(hex: part.top), Color(hex: part.bottom)]),
                        startPoint: CGPoint(x: 0, y: part.from), endPoint: CGPoint(x: 0, y: part.to)))
                }
            }
        }
        .aspectRatio(OctopusArt.size.width / OctopusArt.size.height, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// Reads the path commands the icon script writes (M, L, C and Z, absolute or relative).
enum SVGPath {
    static func parse(_ data: String) -> Path {
        var path = Path()
        var numbers: [CGFloat] = []
        var command: Character = "M"
        var point = CGPoint.zero
        var start = CGPoint.zero

        func flush() {
            let relative = command.isLowercase
            func at(_ i: Int) -> CGPoint {
                let p = CGPoint(x: numbers[i], y: numbers[i + 1])
                return relative ? CGPoint(x: point.x + p.x, y: point.y + p.y) : p
            }
            switch command.uppercased() {
            case "M":
                var i = 0
                while i + 1 < numbers.count {
                    let p = at(i)
                    if i == 0 { path.move(to: p); start = p } else { path.addLine(to: p) }
                    point = p
                    i += 2
                }
            case "L":
                var i = 0
                while i + 1 < numbers.count {
                    point = at(i)
                    path.addLine(to: point)
                    i += 2
                }
            case "C":
                var i = 0
                while i + 5 < numbers.count {
                    let c1 = at(i), c2 = at(i + 2), end = at(i + 4)
                    path.addCurve(to: end, control1: c1, control2: c2)
                    point = end
                    i += 6
                }
            case "Z":
                path.closeSubpath()
                point = start
            default:
                break
            }
            numbers.removeAll(keepingCapacity: true)
        }

        var token = ""
        func endNumber() {
            if let value = Double(token) { numbers.append(CGFloat(value)) }
            token = ""
        }
        for character in data {
            switch character {
            case "M", "m", "L", "l", "C", "c", "Z", "z":
                endNumber()
                flush()
                command = character
            case ",", " ", "\n", "\t":
                endNumber()
            case "-":
                endNumber()
                token = "-"
            default:
                token.append(character)
            }
        }
        endNumber()
        flush()
        return path
    }
}
