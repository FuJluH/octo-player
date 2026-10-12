import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A member just added by a manager, and the link that invites them.
public struct FamilyMemberAdded: Decodable, Sendable, Equatable, CustomStringConvertible {
    public var member = FamilyMember()
    public var inviteLink = ""
    public var links: FamilyLinkChoices?
    public var inviteDays = 7
    public var anywhereAvailable = true
    public var awayAllowed = true
    public var homeOnly = false
    public var publicUrl: String?

    enum CodingKeys: String, CodingKey { case member, inviteLink, links, inviteDays, anywhereAvailable, awayAllowed, homeOnly, publicUrl }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        member = c.object(.member) ?? FamilyMember()
        inviteLink = c.string(.inviteLink) ?? ""
        links = c.object(.links)
        inviteDays = c.int(.inviteDays) ?? 7
        anywhereAvailable = c.bool(.anywhereAvailable) ?? true
        awayAllowed = c.bool(.awayAllowed) ?? true
        homeOnly = c.bool(.homeOnly) ?? false
        publicUrl = c.string(.publicUrl)
    }

    public var description: String { "FamilyMemberAdded(member=\(member.username))" }
}

/// A fresh sign-up link: a new invite for a member who has not signed up yet, or, after a
/// manager resets their password, one to choose a new one.
public struct FamilyNewInvite: Decodable, Sendable, Equatable, CustomStringConvertible {
    public var inviteLink = ""
    public var links: FamilyLinkChoices?
    public var inviteDays = 7
    public var expires: String?
    public var anywhereAvailable = true
    public var awayAllowed = true
    public var homeOnly = false
    public var publicUrl: String?

    enum CodingKeys: String, CodingKey { case inviteLink, links, inviteDays, expires, anywhereAvailable, awayAllowed, homeOnly, publicUrl }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        inviteLink = c.string(.inviteLink) ?? ""
        links = c.object(.links)
        inviteDays = c.int(.inviteDays) ?? 7
        expires = c.string(.expires)
        anywhereAvailable = c.bool(.anywhereAvailable) ?? true
        awayAllowed = c.bool(.awayAllowed) ?? true
        homeOnly = c.bool(.homeOnly) ?? false
        publicUrl = c.string(.publicUrl)
    }

    public var description: String { "FamilyNewInvite(anywhereAvailable=\(anywhereAvailable))" }
}

/// The presets a manager picks for a new member.
public enum FamilyPreset: String, CaseIterable, Sendable {
    case coAdmin = "CoAdmin", member = "Member", listener = "Listener", kid = "Kid"
}

/// The family page's own calls (/api/family): JSON both ways. From an app signed in to the
/// server, each call carries the same sign-in as every Subsonic call, so no password is ever
/// asked for. Without one (joining with an invite) the page's cookies, kept only by this
/// object, sign the new member in once the invite is accepted.
public final class FamilyWeb: @unchecked Sendable {
    private let server: URL
    private let session: URLSession
    private let headers: [String: String]
    private let sign: (@Sendable (URL) -> URL)?
    private let lock = NSLock()
    private var cookies: [String: String] = [:]

    public init(server: URL, session: URLSession, headers: [String: String] = [:], sign: (@Sendable (URL) -> URL)? = nil) {
        self.server = server
        self.session = session
        self.headers = headers
        self.sign = sign
    }

    /// Accepts an invite: the new member's name and the password they chose. Answers their username.
    public func join(token: String, password: String, displayName: String) async throws -> String {
        let user: FamilyWebUser = try await call("POST", "join", body: [
            "token": token, "password": password, "displayName": displayName.trimmingCharacters(in: .whitespacesAndNewlines),
        ])
        return user.username
    }

    /// A manager adds a member, and gets the link that invites them. Then whether they may listen
    /// away from home is set as an edit to their abilities.
    public func addMember(username: String, displayName: String, preset: FamilyPreset, away: Bool = true) async throws -> FamilyMemberAdded {
        let added: FamilyMemberAdded = try await call("POST", "members", body: [
            "username": username.trimmingCharacters(in: .whitespacesAndNewlines),
            "displayName": displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            "preset": preset.rawValue,
        ])
        let name = added.member.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? username.trimmingCharacters(in: .whitespacesAndNewlines) : added.member.username
        let _: FamilyMember = try await call("PUT", "members/\(encodeComponent(name))", body: ["edits": ["away": away]])
        return added
    }

    /// A new invite link for a member, in place of the last one.
    public func newInvite(username: String) async throws -> FamilyNewInvite {
        try await call("POST", "members/\(encodeComponent(username))/invite", body: nil)
    }

    /// A manager resets a member's password: it stops working at once, and the answer is a new
    /// single-use link to choose another.
    public func resetMember(username: String) async throws -> FamilyNewInvite {
        try await call("POST", "members/\(encodeComponent(username))/reset", body: nil)
    }

    private func call<T: Decodable>(_ method: String, _ path: String, body: [String: Any]?) async throws -> T {
        guard var parts = URLComponents(url: server, resolvingAgainstBaseURL: false) else {
            throw SubsonicError.unreachable(server.absoluteString, certificate: false)
        }
        let basePath = parts.percentEncodedPath.hasSuffix("/") ? String(parts.percentEncodedPath.dropLast()) : parts.percentEncodedPath
        parts.percentEncodedPath = basePath + "/api/family/" + path
        guard let plain = parts.url else { throw SubsonicError.unreachable(server.absoluteString, certificate: false) }
        var request = URLRequest(url: sign?(plain) ?? plain, timeoutInterval: 20)
        request.httpMethod = method
        // The page's cookies live only in this object, never in the phone's cookie store.
        request.httpShouldHandleCookies = false
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        request.setValue("1", forHTTPHeaderField: "X-Octo-Family")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let cookieHeader = lock.withLock { cookies.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: "; ") }
        if !cookieHeader.isEmpty { request.setValue(cookieHeader, forHTTPHeaderField: "Cookie") }
        if method != "GET" {
            request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body ?? [:])
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw SubsonicError(error)
        }
        if let http = response as? HTTPURLResponse {
            keep(http)
            if !(200..<300).contains(http.statusCode) { throw failure(http.statusCode, data) }
        }
        let text = String(decoding: data, as: UTF8.self)
        let json = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Data("{}".utf8) : data
        do {
            return try JSONDecoder().decode(T.self, from: json)
        } catch {
            throw SubsonicError.notSubsonic("The server did not answer like an Octo server", status: nil)
        }
    }

    /// The page's cookies, a later one with the same name replacing the earlier.
    private func keep(_ response: HTTPURLResponse) {
        guard let url = response.url else { return }
        let fields = response.allHeaderFields.reduce(into: [String: String]()) { out, pair in
            if let name = pair.key as? String, let value = pair.value as? String { out[name] = value }
        }
        let found = HTTPCookie.cookies(withResponseHeaderFields: fields, for: url)
        guard !found.isEmpty else { return }
        lock.withLock { for cookie in found { cookies[cookie.name] = cookie.value } }
    }

    /// The server's own words when it gives them, else plain ones.
    private func failure(_ status: Int, _ body: Data) -> SubsonicError {
        let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
        let said = ((object?["message"] ?? object?["error"]) as? String).flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        switch status {
        case 401, 403: return .wrongCredentials(said ?? "The server did not take this sign-in for that.")
        case 404: return .notSubsonic(said ?? "This server has no family page. Update Octo on the server.", status: status)
        case 410: return .notFound(said ?? "That invite has been used or has expired. Ask for a new one.")
        default: return .server(code: status, message: said ?? "The server said no (HTTP \(status)).")
        }
    }
}

/// Who a family page sign-in is.
struct FamilyWebUser: Decodable {
    let username: String
    let role: String

    enum CodingKeys: String, CodingKey { case username, role }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        username = c.string(.username) ?? ""
        role = c.string(.role) ?? ""
    }
}

extension SubsonicClient {
    /// The family page's calls on this server, through this client's headers, each signed as
    /// every Subsonic call is.
    public func familyWeb() -> FamilyWeb {
        let client = self
        return FamilyWeb(server: baseURL, session: session, headers: headers) { url in client.signed(url) }
    }
}
