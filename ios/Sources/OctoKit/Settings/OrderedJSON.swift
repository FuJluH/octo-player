import Foundation

/// JSON whose object keys keep the order they were written in, printed the way the other Octo
/// apps print their files: four spaces an indent, `"key": value`.
public indirect enum OrderedJSON: Equatable, Sendable {
    case object([(String, OrderedJSON)])
    case array([OrderedJSON])
    case string(String)
    case int(Int64)
    case double(Double)
    case bool(Bool)
    case null

    public static func == (a: OrderedJSON, b: OrderedJSON) -> Bool { a.pretty() == b.pretty() }

    /// An object with nil values left out entirely.
    public static func fields(_ pairs: [(String, OrderedJSON?)]) -> OrderedJSON {
        .object(pairs.compactMap { key, value in value.map { (key, $0) } })
    }

    public static func strings(_ values: [String]) -> OrderedJSON { .array(values.map { .string($0) }) }

    public func pretty(indent: Int = 0) -> String {
        let pad = String(repeating: " ", count: indent * 4)
        let inner = String(repeating: " ", count: (indent + 1) * 4)
        switch self {
        case .object(let pairs):
            if pairs.isEmpty { return "{\n\(pad)}" }
            return "{\n" + pairs.map { "\(inner)\(Self.quoted($0.0)): \($0.1.pretty(indent: indent + 1))" }.joined(separator: ",\n") + "\n\(pad)}"
        case .array(let items):
            if items.isEmpty { return "[\n\(pad)]" }
            return "[\n" + items.map { inner + $0.pretty(indent: indent + 1) }.joined(separator: ",\n") + "\n\(pad)]"
        case .string(let text): return Self.quoted(text)
        case .int(let n): return String(n)
        case .double(let d): return Self.number(d)
        case .bool(let b): return b ? "true" : "false"
        case .null: return "null"
        }
    }

    /// A decimal as the other apps write one: 1.0 stays "1.0", 1.3 is "1.3".
    static func number(_ d: Double) -> String {
        guard d.isFinite else { return "0.0" }
        if d == d.rounded(), abs(d) < 1e15 { return String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), d) }
        return "\(d)"
    }

    static func quoted(_ text: String) -> String {
        var out = "\""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if scalar.value < 0x20 {
                    out += String(format: "\\u%04x", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        return out + "\""
    }
}
