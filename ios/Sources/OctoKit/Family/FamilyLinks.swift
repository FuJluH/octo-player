import Foundation

// What a family link carries. Three kinds are read, each in the https form a QR code or a
// shared link uses and the app's own octo:// form:
//
// An invite, for signing up:
//   <server>/family/join#invite=<token>
//   octo://join?server=<address>&invite=<token>
// A sign-in to fill in, for a member who has a login:
//   octo://signin?server=<address>&home=<address>&username=<name>
// A sign-in handed over from the same person's other device:
//   <server>/family/signin#t=<token>&k=<key>&s=<address>&h=<address>&u=<name>
//   octo://handover?t=<token>&k=<key>&s=<address>&h=<address>&u=<name>
//   intent://handover?t=...#Intent;scheme=octo;package=...;end (as Android browsers hand it on)
//
// Secrets ride in the part after #, which browsers never send to a server. `server` is the
// address that works from anywhere, which may carry a path; `home` is the server's address on
// its home network.

public enum FamilyLink: Sendable, Equatable, CustomStringConvertible {
    case invite(FamilyInviteLink)
    case prefill(FamilySignInPrefill)
    case handOver(FamilyHandOverLink)

    public var server: String {
        switch self {
        case .invite(let link): link.server
        case .prefill(let link): link.server
        case .handOver(let link): link.server
        }
    }

    public var home: String? {
        switch self {
        case .invite(let link): link.home
        case .prefill(let link): link.home
        case .handOver(let link): link.home
        }
    }

    public var isInvite: Bool {
        if case .invite = self { return true }
        return false
    }

    public var description: String {
        switch self {
        case .invite(let link): link.description
        case .prefill(let link): "FamilySignInPrefill(server=\(link.server), username=\(link.username), home=\(link.home ?? "null"))"
        case .handOver(let link): link.description
        }
    }
}

public struct FamilyInviteLink: Sendable, Equatable, CustomStringConvertible {
    public var server: String
    public var token: String
    public var home: String?

    public init(server: String, token: String, home: String? = nil) {
        self.server = server
        self.token = token
        self.home = home
    }

    public var description: String { "FamilyInviteLink(server=\(server), home=\(home ?? "null"))" }
}

/// The server and username to fill into the sign-in form; the person types the password.
public struct FamilySignInPrefill: Sendable, Equatable {
    public var server: String
    public var username: String
    public var home: String?

    public init(server: String, username: String = "", home: String? = nil) {
        self.server = server
        self.username = username
        self.home = home
    }
}

/// A hand-over from another device: the token to redeem, on `base` (the address the link was
/// opened on, or the server for the app's own form), the key that opens what the other device
/// sends, and the username when the link names it. The key never leaves this device.
public struct FamilyHandOverLink: Sendable, Equatable, CustomStringConvertible {
    public var base: String
    public var token: String
    public var key: String
    public var server: String
    public var home: String?
    public var username: String?

    public init(base: String, token: String, key: String, server: String, home: String? = nil, username: String? = nil) {
        self.base = base
        self.token = token
        self.key = key
        self.server = server
        self.home = home
        self.username = username
    }

    public var description: String {
        "FamilyHandOverLink(base=\(base), server=\(server), home=\(home ?? "null"), username=\(username ?? "null"))"
    }
}

/// Reads a family link, or nil when the text is not one. Spaces around it are ignored, so a
/// pasted link works.
public func parseFamilyLink(_ text: String) -> FamilyLink? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    let lower = trimmed.lowercased()
    func query() -> String { after(trimmed, "?").map { before($0, "#") } ?? "" }
    if lower.hasPrefix("octo://join") { return parseAppInvite(query()) }
    if lower.hasPrefix("octo://signin") { return parseAppSignIn(query()) }
    if lower.hasPrefix("octo://handover") || lower.hasPrefix("intent://handover") {
        return handOverIn(readParams(query()), base: nil).map(FamilyLink.handOver)
    }
    if lower.hasPrefix("https://") || lower.hasPrefix("http://") { return parseWebLink(trimmed) }
    return nil
}

private func after(_ text: String, _ mark: String) -> String? {
    text.range(of: mark).map { String(text[$0.upperBound...]) }
}

private func before(_ text: String, _ mark: String) -> String {
    text.range(of: mark).map { String(text[..<$0.lowerBound]) } ?? text
}

private func nonEmpty(_ text: String?) -> String? {
    guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
    return trimmed
}

private func parseAppInvite(_ query: String) -> FamilyLink? {
    let params = readParams(query)
    guard let server = nonEmpty(params["server"]), let token = nonEmpty(params["invite"]) else { return nil }
    return .invite(FamilyInviteLink(server: server, token: token, home: homeIn(params, "home")))
}

private func parseAppSignIn(_ query: String) -> FamilyLink? {
    let params = readParams(query)
    guard let server = nonEmpty(params["server"]).flatMap(addressIn) else { return nil }
    return .prefill(FamilySignInPrefill(server: server, username: params["username"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                                        home: homeIn(params, "home")))
}

private func parseWebLink(_ text: String) -> FamilyLink? {
    guard let fragment = after(text, "#"), !fragment.isEmpty,
          let url = ServerAddress.httpURL(before(text, "#")),
          var parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
    else { return nil }
    let segments = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }
    guard segments.count >= 2, segments[segments.count - 2] == "family" else { return nil }
    parts.percentEncodedPath = segments.dropLast(2).isEmpty ? "/"
        : "/" + segments.dropLast(2).map { $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? $0 }.joined(separator: "/")
    parts.query = nil
    parts.fragment = nil
    guard let baseURL = parts.url else { return nil }
    let base = ServerAddress.trimmedSlash(baseURL.absoluteString)
    let params = readParams(fragment)
    switch segments[segments.count - 1] {
    case "join":
        return nonEmpty(params["invite"]).map { .invite(FamilyInviteLink(server: base, token: $0, home: homeIn(params, "home"))) }
    case "signin":
        return handOverIn(params, base: base).map(FamilyLink.handOver)
    default:
        return nil
    }
}

/// A hand-over's token, key and addresses; the token is redeemed on `base`, or on the server
/// address when the link names none.
private func handOverIn(_ params: [String: String], base: String?) -> FamilyHandOverLink? {
    guard let token = nonEmpty(params["t"]), let key = nonEmpty(params["k"]),
          let server = nonEmpty(params["s"]).flatMap(addressIn) ?? base
    else { return nil }
    return FamilyHandOverLink(base: base ?? server, token: token, key: key, server: server, home: homeIn(params, "h"),
                              username: nonEmpty(params["u"]))
}

/// An address a link names, when it is an address at all.
private func addressIn(_ text: String) -> String? {
    ServerAddress.normalized(text).map { ServerAddress.trimmedSlash(ServerAddress.written($0)) }
}

private func homeIn(_ params: [String: String], _ name: String) -> String? {
    nonEmpty(params[name]).flatMap(addressIn)
}

private func readParams(_ text: String) -> [String: String] {
    var params: [String: String] = [:]
    for part in text.split(separator: "&", omittingEmptySubsequences: false) {
        guard let at = part.firstIndex(of: "="), at != part.startIndex else { continue }
        params[String(part[..<at])] = decodeComponent(String(part[part.index(after: at)...]))
    }
    return params
}

/// The https link for an invite.
public func familyInviteUrl(server: String, token: String, home: String? = nil) -> String {
    ServerAddress.trimmedSlash(server.trimmingCharacters(in: .whitespacesAndNewlines))
        + "/family/join#invite=" + encodeComponent(token) + homePart(home)
}

/// The https link for a hand-over, opened on `base`: the token, the key, the addresses the new
/// device signs in to, and the username for the page.
public func familySignInUrl(base: String, token: String, key: String, server: String, home: String? = nil, username: String? = nil) -> String {
    ServerAddress.trimmedSlash(base.trimmingCharacters(in: .whitespacesAndNewlines)) + "/family/signin#"
        + handOverParams(token: token, key: key, server: server, home: home, username: username)
}

private func handOverParams(token: String, key: String, server: String, home: String?, username: String?) -> String {
    var text = "t=\(encodeComponent(token))&k=\(encodeComponent(key))&s=\(encodeComponent(ServerAddress.trimmedSlash(server.trimmingCharacters(in: .whitespacesAndNewlines))))"
    if let home = nonEmpty(home) { text += "&h=\(encodeComponent(ServerAddress.trimmedSlash(home)))" }
    if let username = nonEmpty(username) { text += "&u=\(encodeComponent(username))" }
    return text
}

/// The app's own form of a link, for opening Octo directly.
public func familyAppLink(_ link: FamilyLink) -> String {
    switch link {
    case .invite(let invite):
        return "octo://join?server=\(encodeComponent(invite.server))&invite=\(encodeComponent(invite.token))\(homePart(invite.home))"
    case .prefill(let prefill):
        let user = prefill.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : "&username=\(encodeComponent(prefill.username))"
        return "octo://signin?server=\(encodeComponent(prefill.server))\(homePart(prefill.home))\(user)"
    case .handOver(let handOver):
        return "octo://handover?" + handOverParams(token: handOver.token, key: handOver.key, server: handOver.server,
                                                   home: handOver.home, username: handOver.username)
    }
}

private func homePart(_ home: String?) -> String {
    nonEmpty(home).map { "&home=\(encodeComponent($0))" } ?? ""
}

/// Percent-encodes text the way RFC 3986 asks: letters, digits and - . _ ~ stay; every other
/// character goes as its UTF-8 bytes, %XX each.
public func encodeComponent(_ text: String) -> String {
    var out = ""
    for byte in text.utf8 {
        switch byte {
        case UInt8(ascii: "A")...UInt8(ascii: "Z"), UInt8(ascii: "a")...UInt8(ascii: "z"), UInt8(ascii: "0")...UInt8(ascii: "9"),
             UInt8(ascii: "-"), UInt8(ascii: "."), UInt8(ascii: "_"), UInt8(ascii: "~"):
            out.append(Character(UnicodeScalar(byte)))
        default:
            out.append(String(format: "%%%02X", byte))
        }
    }
    return out
}

/// Reads percent-encoded text; a plus is read as a space, as forms send it. Text that cannot be
/// read is kept as typed.
public func decodeComponent(_ text: String) -> String {
    percentDecoded(text.replacingOccurrences(of: "+", with: " ")) ?? text
}

/// The family link in a QR code's text, or nil when it holds something else.
public func familyLinkInQr(_ text: String?) -> FamilyLink? {
    text.flatMap(parseFamilyLink)
}
