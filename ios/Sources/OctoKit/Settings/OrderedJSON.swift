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

    /// The string, when this is one.
    public var text: String? {
        if case .string(let text) = self { return text }
        return nil
    }

    /// The whole number, when this is one.
    public var whole: Int64? {
        if case .int(let number) = self { return number }
        return nil
    }

    /// The number, whole or not, when this is one.
    public var decimal: Double? {
        switch self {
        case .int(let number): return Double(number)
        case .double(let number): return number
        default: return nil
        }
    }

    public func pretty(indent: Int = 0) -> String {
        let pad = String(repeating: " ", count: indent * 4)
        let inner = String(repeating: " ", count: (indent + 1) * 4)
        switch self {
        case .object(let pairs):
            if pairs.isEmpty { return "{}" }
            return "{\n" + pairs.map { "\(inner)\(Self.quoted($0.0)): \($0.1.pretty(indent: indent + 1))" }.joined(separator: ",\n") + "\n\(pad)}"
        case .array(let items):
            if items.isEmpty { return "[]" }
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

    /// Text that is not JSON.
    public struct NotJSON: Error {}

    /// Reads JSON text strictly: no comments, no comma before a closing bracket and nothing after
    /// the value. A number with no fraction or exponent that fits in 64 bits is whole, any other
    /// number a decimal. Object keys keep their order, a key written twice included.
    public static func parse(_ text: String) throws -> OrderedJSON {
        var reader = JSONReader(Array(text.utf8))
        reader.skipSpace()
        let value = try reader.value(depth: 0)
        reader.skipSpace()
        guard reader.atEnd else { throw NotJSON() }
        return value
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

/// Walks JSON text byte by byte for `OrderedJSON.parse`.
private struct JSONReader {
    private static let quote = UInt8(ascii: "\""), backslash = UInt8(ascii: "\\"), colon = UInt8(ascii: ":"), comma = UInt8(ascii: ",")
    private static let openBrace = UInt8(ascii: "{"), closeBrace = UInt8(ascii: "}")
    private static let openBracket = UInt8(ascii: "["), closeBracket = UInt8(ascii: "]")
    private static let minus = UInt8(ascii: "-"), plus = UInt8(ascii: "+"), dot = UInt8(ascii: ".")
    private static let zero = UInt8(ascii: "0"), nine = UInt8(ascii: "9")
    /// How deep arrays and objects may sit inside each other.
    private static let maxDepth = 512

    private let bytes: [UInt8]
    private var at = 0

    init(_ bytes: [UInt8]) { self.bytes = bytes }

    var atEnd: Bool { at >= bytes.count }

    private var next: UInt8? { at < bytes.count ? bytes[at] : nil }

    mutating func skipSpace() {
        while let byte = next, byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D { at += 1 }
    }

    private mutating func expect(_ byte: UInt8) throws {
        guard next == byte else { throw OrderedJSON.NotJSON() }
        at += 1
    }

    private mutating func word(_ text: String, _ value: OrderedJSON) throws -> OrderedJSON {
        for byte in text.utf8 { try expect(byte) }
        return value
    }

    mutating func value(depth: Int) throws -> OrderedJSON {
        guard depth < Self.maxDepth, let byte = next else { throw OrderedJSON.NotJSON() }
        switch byte {
        case Self.openBrace: return try object(depth)
        case Self.openBracket: return try array(depth)
        case Self.quote: return .string(try string())
        case UInt8(ascii: "t"): return try word("true", .bool(true))
        case UInt8(ascii: "f"): return try word("false", .bool(false))
        case UInt8(ascii: "n"): return try word("null", .null)
        default: return try number()
        }
    }

    private mutating func object(_ depth: Int) throws -> OrderedJSON {
        at += 1
        var pairs: [(String, OrderedJSON)] = []
        skipSpace()
        if next == Self.closeBrace {
            at += 1
            return .object(pairs)
        }
        while true {
            skipSpace()
            guard next == Self.quote else { throw OrderedJSON.NotJSON() }
            let key = try string()
            skipSpace()
            try expect(Self.colon)
            skipSpace()
            pairs.append((key, try value(depth: depth + 1)))
            skipSpace()
            if next == Self.comma {
                at += 1
                continue
            }
            try expect(Self.closeBrace)
            return .object(pairs)
        }
    }

    private mutating func array(_ depth: Int) throws -> OrderedJSON {
        at += 1
        var items: [OrderedJSON] = []
        skipSpace()
        if next == Self.closeBracket {
            at += 1
            return .array(items)
        }
        while true {
            skipSpace()
            items.append(try value(depth: depth + 1))
            skipSpace()
            if next == Self.comma {
                at += 1
                continue
            }
            try expect(Self.closeBracket)
            return .array(items)
        }
    }

    /// A quoted string. A lone half of a surrogate pair reads as U+FFFD.
    private mutating func string() throws -> String {
        at += 1
        var out: [UInt8] = []
        while true {
            guard let byte = next else { throw OrderedJSON.NotJSON() }
            at += 1
            switch byte {
            case Self.quote:
                return String(decoding: out, as: UTF8.self)
            case Self.backslash:
                guard let escape = next else { throw OrderedJSON.NotJSON() }
                at += 1
                switch escape {
                case Self.quote, Self.backslash, UInt8(ascii: "/"): out.append(escape)
                case UInt8(ascii: "b"): out.append(0x08)
                case UInt8(ascii: "f"): out.append(0x0C)
                case UInt8(ascii: "n"): out.append(0x0A)
                case UInt8(ascii: "r"): out.append(0x0D)
                case UInt8(ascii: "t"): out.append(0x09)
                case UInt8(ascii: "u"):
                    var code = try hex4()
                    if (0xD800...0xDBFF).contains(code), at + 1 < bytes.count, bytes[at] == Self.backslash, bytes[at + 1] == UInt8(ascii: "u") {
                        let mark = at
                        at += 2
                        let low = try hex4()
                        if (0xDC00...0xDFFF).contains(low) {
                            code = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00)
                        } else {
                            at = mark
                        }
                    }
                    out.append(contentsOf: String(Unicode.Scalar(code) ?? "\u{FFFD}").utf8)
                default:
                    throw OrderedJSON.NotJSON()
                }
            default:
                out.append(byte)
            }
        }
    }

    private mutating func hex4() throws -> UInt32 {
        guard at + 4 <= bytes.count, let code = UInt32(String(decoding: bytes[at..<(at + 4)], as: UTF8.self), radix: 16) else {
            throw OrderedJSON.NotJSON()
        }
        at += 4
        return code
    }

    private func isDigit(_ byte: UInt8?) -> Bool { byte.map { $0 >= Self.zero && $0 <= Self.nine } ?? false }

    private mutating func digits() throws {
        guard isDigit(next) else { throw OrderedJSON.NotJSON() }
        while isDigit(next) { at += 1 }
    }

    private mutating func number() throws -> OrderedJSON {
        let start = at
        if next == Self.minus { at += 1 }
        if next == Self.zero { at += 1 } else { try digits() }
        var whole = true
        if next == Self.dot {
            whole = false
            at += 1
            try digits()
        }
        if next == UInt8(ascii: "e") || next == UInt8(ascii: "E") {
            whole = false
            at += 1
            if next == Self.plus || next == Self.minus { at += 1 }
            try digits()
        }
        let text = String(decoding: bytes[start..<at], as: UTF8.self)
        if whole, let number = Int64(text) { return .int(number) }
        guard let number = Double(text) else { throw OrderedJSON.NotJSON() }
        return .double(number)
    }
}
