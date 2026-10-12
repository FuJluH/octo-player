import Foundation

/// Turns whatever someone typed into a server's base address, the way the other Octo apps do:
/// "192.168.50.21:5274",
/// "https://music.example.com/" and ".../rest" all work. With no scheme typed, plain http on
/// the home network, where servers seldom have a certificate, and https anywhere else.
public enum ServerAddress {
    public static func parse(_ typed: String) -> URL? {
        var text = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") {
            guard let probe = normalize("http://" + text) else { return nil }
            text = (isPrivate(probe) ? "http://" : "https://") + text
        }
        return normalize(text)
    }

    /// The base address: no name or password, no query, and a pasted `/rest` or `/app` dropped.
    static func normalize(_ text: String) -> URL? {
        guard var parts = URLComponents(string: text),
              let scheme = parts.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = parts.host, !host.isEmpty
        else { return nil }
        parts.scheme = scheme
        parts.user = nil
        parts.password = nil
        parts.query = nil
        parts.fragment = nil
        var segments = parts.path.split(separator: "/").map(String.init)
        if let last = segments.last, last == "rest" || last == "app" { segments.removeLast() }
        parts.path = segments.isEmpty ? "" : "/" + segments.joined(separator: "/")
        return parts.url
    }

    /// True when the address stays inside a home network, going only by the address itself.
    public static func isPrivate(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        if host == "localhost" || host.hasSuffix(".local") || host.hasSuffix(".lan") || host.hasSuffix(".home.arpa") {
            return true
        }
        if host.contains(":") {
            return host == "::1" || host.hasPrefix("fc") || host.hasPrefix("fd") || host.hasPrefix("fe80")
        }
        let parts = host.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else { return false }
        let (a, b) = (parts[0], parts[1])
        return a == 10 || a == 127 || (a == 172 && (16...31).contains(b))
            || (a == 192 && b == 168) || (a == 169 && b == 254)
    }

    /// How the sign-in page reaches a server: encrypted or plain.
    public enum Scheme: String, Sendable, CaseIterable {
        case https, http

        public var prefix: String { rawValue + "://" }
    }

    /// A typed or pasted address split into the scheme it starts with (nil when it names none)
    /// and the rest: "HTTP://music.lan" gives http and "music.lan".
    public static func split(_ typed: String) -> (Scheme?, String) {
        let text = typed.drop { $0 == " " }
        for scheme in Scheme.allCases where text.lowercased().hasPrefix(scheme.prefix) {
            return (scheme, String(text.dropFirst(scheme.prefix.count)))
        }
        return (nil, typed)
    }

    /// The scheme for an address nobody picked one for: http on the home network, https elsewhere.
    public static func automaticScheme(_ rest: String) -> Scheme {
        guard let url = normalize("http://" + rest.trimmingCharacters(in: .whitespaces)) else { return .https }
        return isPrivate(url) ? .http : .https
    }

    /// The server's address from a chosen scheme and the rest, or nil when the rest is not one.
    public static func url(_ scheme: Scheme, _ rest: String) -> URL? {
        let text = rest.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.contains("://") else { return nil }
        return normalize(scheme.prefix + text)
    }

    /// What the home network address field holds.
    public enum HomeReading: Equatable, Sendable {
        /// Blank, or the main address again: no home address.
        case none
        case address(URL)
        /// Text that is not an address.
        case unreadable
    }

    /// The home network address as typed. A missing scheme is read as http, since the home
    /// network is where servers seldom have a certificate.
    public static func home(_ typed: String, main: URL?) -> HomeReading {
        if typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .none }
        guard let home = normalized(typed) else { return .unreadable }
        if let main, home == normalized(main.absoluteString) { return .none }
        return .address(home)
    }

    /// An address as people read it: no slash at the end.
    public static func shown(_ url: URL) -> String {
        var text = url.absoluteString
        while text.hasSuffix("/") { text.removeLast() }
        return text
    }
}
