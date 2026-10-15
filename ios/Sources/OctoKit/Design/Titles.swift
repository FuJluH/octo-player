import Foundation

/// How much to scale type down so a word `widest` wide fits a line `width` wide: not at all
/// when it fits, else a touch under the exact share, so rounding never leaves it a point over.
public func fitScale(widest: Double, width: Double) -> Double {
    widest <= width || widest <= 0 || width <= 0 ? 1 : width / widest * 0.98
}

/// The least a title's type is set at, as a share of its size; a word wider than that wraps.
public let titleLeastShare = 0.5

/// The title with a place a line may end after each underscore that joins two words: an
/// invisible zero-width space, which the reader never sees.
public func breakableText(_ text: String) -> String {
    var out = ""
    let characters = Array(text)
    for (index, c) in characters.enumerated() {
        out.append(c)
        if c == "_", index + 1 < characters.count {
            let next = characters[index + 1]
            if !next.isWhitespace && next != "_" { out.append("\u{200B}") }
        }
    }
    return out
}

/// Whether a title and its buttons share one line: only when the whole title fits beside them.
public func actionsBeside(titleWidth: Double, actionsWidth: Double, gap: Double, width: Double?) -> Bool {
    guard let width else { return true }
    return titleWidth + gap + actionsWidth <= width
}
