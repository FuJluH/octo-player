import Foundation

// Addresses the way the other apps read and write them.
extension ServerAddress {
    /// Whatever someone typed as a server's base address, a missing scheme read as http:
    /// "192.168.50.21:5274", "https://music.example.com/" and ".../rest" all work.
    public static func normalized(_ input: String) -> URL? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "http://" + text }
        return normalize(text).map(lowercasingHost)
    }

    /// An http or https address with a host, as it is, or nil when the text is not one.
    public static func httpURL(_ text: String) -> URL? {
        guard let parts = URLComponents(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = parts.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = parts.host, !host.isEmpty
        else { return nil }
        return parts.url.map(lowercasingHost)
    }

    /// An address as the other apps write it: a slash after a bare host. Server ids are made
    /// from this, so the same account gets the same id everywhere.
    public static func written(_ url: URL) -> String {
        var text = url.absoluteString
        if url.path.isEmpty, !text.hasSuffix("/") { text += "/" }
        return text
    }

    /// An address with no slash at the end, from text: "https://example.com/octo".
    public static func trimmedSlash(_ text: String) -> String {
        var out = text
        while out.hasSuffix("/") { out.removeLast() }
        return out
    }

    /// The address with only its scheme, host and port: where an address lives.
    public static func root(_ url: URL) -> URL? {
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        parts.path = "/"
        parts.query = nil
        parts.fragment = nil
        parts.user = nil
        parts.password = nil
        return parts.url.map(lowercasingHost)
    }

    /// Where a request goes: scheme, host and port, the port written even when it is the
    /// scheme's own. Two addresses with the same origin reach the same server. Nil for an
    /// address with no scheme or host.
    public static func origin(_ url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(), let host = url.host?.lowercased(), !host.isEmpty else { return nil }
        let port = url.port ?? (scheme == "https" ? 443 : scheme == "http" ? 80 : -1)
        return "\(scheme)://\(host):\(port)"
    }

    static func lowercasingHost(_ url: URL) -> URL {
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false), let host = parts.host,
              host != host.lowercased()
        else { return url }
        parts.host = host.lowercased()
        return parts.url ?? url
    }
}
