import Foundation
import Observation

/// The "Sign in on another device" QR code while it shows: its token and key, how renewing it
/// goes, a device asking to sign in, and how handing the sign-in over went. Each one opened has
/// its own `id`, so an answer for one already closed is dropped. Never printed.
public struct HandOverSheet: Sendable, Equatable, CustomStringConvertible {
    public var id = 0
    public var start: FamilySignInStart?
    /// Made on this device; it is only ever in the QR code.
    public var key = ""
    public var openedAt: Int64 = 0
    public var loading = false
    public var error: String?
    /// Open ten minutes: renewing stopped, and the sheet asks.
    public var stale = false
    public var refreshFailed = false
    public var retryAt: Int64 = 0
    /// How many times the code was renewed, for the "New code" notice.
    public var renewed = 0
    /// A device that scanned the code and waits for Allow or Deny.
    public var asking: FamilySignInPending?
    public var sending = false
    /// How it ended: handed over, or why not.
    public var done: String?
    public var failed: String?

    public init(id: Int = 0, start: FamilySignInStart? = nil, key: String = "", openedAt: Int64 = 0) {
        self.id = id
        self.start = start
        self.key = key
        self.openedAt = openedAt
    }

    public var waiting: Bool { start == nil && error == nil }

    /// The QR code's link both ways: the family page through the outside address or the home
    /// one, then the token, the key, the server the new device signs in to that way, the home
    /// address, and the username for the page to show.
    public func options(awayAllowed: Bool, username: String? = nil) -> LinkOptions? {
        guard let begun = start else { return nil }
        let home = begun.servers.home.map(handOverBase)
        func link(_ page: String?, _ server: String?) -> String? {
            guard let page else { return nil }
            let base = handOverBase(page)
            return familySignInUrl(base: base, token: begun.token, key: key, server: server.map(handOverBase) ?? base, home: home, username: username)
        }
        let anywhere = link(begun.links.anywhere, begun.servers.anywhere)
        return LinkOptions(anywhere: anywhere, home: link(begun.links.home, begun.servers.home),
                           anywhereAvailable: begun.anywhereAvailable && anywhere != nil, awayAllowed: awayAllowed)
    }

    public var description: String { "HandOverSheet(id=\(id), loading=\(loading), asking=\(asking != nil), done=\(done != nil))" }
}

/// A server's address from what the server answered: a bare address, or a family page on it.
func handOverBase(_ text: String) -> String {
    ServerAddress.trimmedSlash(linkServer(text) ?? text)
}

/// The name and platform of the device asking, as the prompt shows them.
public func askingTitle(_ asking: FamilySignInPending) -> String {
    "Sign in on \(asking.deviceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "a new device" : asking.deviceName)?"
}

public func askingLine(_ asking: FamilySignInPending) -> String {
    [asking.platform, "It gets your sign-in for this server. Allow it only if it's yours."]
        .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.joined(separator: " · ")
}

public enum HandOverText {
    public static let title = "Sign in on another device"
    public static let caption = "Scan with Octo on the new device, or with its camera"
    public static let failed = "Couldn't make a code. Try again."
    public static let sendFailed = "Couldn't send your sign-in. Make a new code and try again."
    public static let allow = "Allow"
    public static let deny = "Deny"
    /// How long before expiry a code is renewed, how often a failed renewal is tried again, and
    /// how long the sheet renews at most.
    public static let leadMs: Int64 = 5_000
    public static let retryMs: Int64 = 10_000
    public static let forMs: Int64 = 10 * 60 * 1_000
}

/// The signed-in device's side of a hand-over. While the sheet shows and the app is on screen:
/// the code renews a few seconds before it expires (with a new key), and the server is asked
/// every couple of seconds whether a device redeemed it. Nothing is sent until the person allows
/// that device; then the sign-in is sealed with the key and handed over.
@MainActor
@Observable
public final class HandOverSource {
    public private(set) var sheet: HandOverSheet?
    public private(set) var onScreen = true

    @ObservationIgnored private let client: @MainActor () -> SubsonicClient?
    @ObservationIgnored private let displayName: @MainActor () -> String
    @ObservationIgnored private let mainAddress: @MainActor () -> URL?
    @ObservationIgnored private let clock: @MainActor () -> Int64
    @ObservationIgnored private let tickMs: Int
    @ObservationIgnored private let askEveryMs: Int
    @ObservationIgnored private let newKey: () -> String
    @ObservationIgnored private var opened = 0
    @ObservationIgnored private var running: Task<Void, Never>?

    public init(client: @escaping @MainActor () -> SubsonicClient?, displayName: @escaping @MainActor () -> String = { "" },
                mainAddress: @escaping @MainActor () -> URL? = { nil },
                clock: @escaping @MainActor () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1_000) },
                tickMs: Int = 250, askEveryMs: Int = 2_000, newKey: @escaping () -> String = HandOverBox.newKey) {
        self.client = client
        self.displayName = displayName
        self.mainAddress = mainAddress
        self.clock = clock
        self.tickMs = tickMs
        self.askEveryMs = askEveryMs
        self.newKey = newKey
    }

    /// Opens the sheet with a fresh code.
    public func open() {
        opened += 1
        sheet = HandOverSheet(id: opened, key: newKey(), openedAt: clock())
        let id = opened
        Task { await begin(id) }
    }

    public func close() {
        running?.cancel()
        running = nil
        sheet = nil
    }

    public func sheetOnScreen(_ visible: Bool) { onScreen = visible }

    /// After ten minutes, or after a failure: a fresh code, renewing again.
    public func newCode() {
        guard var open = sheet else { return }
        open.openedAt = clock()
        open.stale = false
        open.refreshFailed = false
        open.error = nil
        open.failed = nil
        open.done = nil
        open.asking = nil
        sheet = open
        let id = open.id
        Task { await begin(id) }
    }

    public func retry() { newCode() }

    /// The device asking is the person's own: tell the server, then seal this device's sign-in
    /// with the key and hand it over.
    public func allow() {
        guard let open = sheet, let asking = open.asking, let start = open.start, let client = client() else { return }
        running?.cancel()
        sheet?.sending = true
        let signIn = signInOf(client, open)
        Task {
            var sent = true
            do {
                try await client.decideFamilySignIn(token: start.token, allow: true)
                try await client.putFamilySignInBox(token: start.token, box: try HandOverBox.seal(signIn, key: open.key))
            } catch {
                sent = false
            }
            guard var now = sheet, now.id == open.id else { return }
            now.sending = false
            now.asking = nil
            if sent {
                let name = asking.deviceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "your other device" : asking.deviceName
                now.done = "Sent to \(name). It's signing in now."
            } else {
                now.failed = HandOverText.sendFailed
            }
            sheet = now
        }
    }

    /// Not the person's device: tell the server no, and show a fresh code, since this one is used up.
    public func deny() {
        guard let open = sheet, let start = open.start, let client = client() else { return }
        sheet?.asking = nil
        sheet?.loading = true
        Task {
            try? await client.decideFamilySignIn(token: start.token, allow: false)
            await renew(open.id)
        }
    }

    /// What travels in the box: this app's own sign-in for the server.
    private func signInOf(_ client: SubsonicClient, _ open: HandOverSheet) -> HandOverSignIn {
        let servers = open.start?.servers
        let anywhere = servers?.anywhere.map(handOverBase)
        let home = servers?.home.map(handOverBase)
        let mode = switch client.credentials.mode {
        case .token: "Token"
        case .legacyPassword: "LegacyPassword"
        case .apiKey: "ApiKey"
        }
        return HandOverSignIn(username: client.credentials.username, secret: client.handOverSecret(), mode: mode,
                              server: anywhere ?? ServerAddress.shown(mainAddress() ?? client.baseURL), home: home, displayName: displayName())
    }

    private func begin(_ id: Int) async {
        running?.cancel()
        guard sheet?.id == id else { return }
        sheet?.loading = true
        sheet?.error = nil
        let started = await startCode()
        guard sheet?.id == id else { return }
        guard let started else {
            sheet?.loading = false
            sheet?.error = HandOverText.failed
            return
        }
        sheet?.start = started.0
        sheet?.key = started.1
        sheet?.loading = false
        running = Task { await watch(id) }
    }

    /// A new token, and a new key to go with it.
    private func startCode() async -> (FamilySignInStart, String)? {
        guard let client = client() else { return nil }
        guard let start = try? await client.startFamilySignIn() else { return nil }
        return (start, newKey())
    }

    private func renew(_ id: Int) async {
        guard sheet?.id == id else { return }
        sheet?.loading = true
        let started = await startCode()
        guard var now = sheet, now.id == id else { return }
        now.loading = false
        if let started {
            now.start = started.0
            now.key = started.1
            now.refreshFailed = false
            now.renewed += 1
        } else {
            now.refreshFailed = true
            now.retryAt = clock() + HandOverText.retryMs
        }
        sheet = now
        if running == nil || running?.isCancelled == true { running = Task { await watch(id) } }
    }

    private func watch(_ id: Int) async {
        // Counted in ticks, not by the clock, which only says when codes expire.
        var sinceAsk = askEveryMs
        while !Task.isCancelled {
            guard let open = sheet, open.id == id else { return }
            let busy = open.loading || open.sending || open.asking != nil || open.done != nil || open.failed != nil || open.stale
            if onScreen, !busy, let start = open.start {
                let due = open.refreshFailed ? open.retryAt : expiresAtMs(start.expires).map { $0 - HandOverText.leadMs }
                if let due, clock() >= due {
                    if clock() - open.openedAt >= HandOverText.forMs {
                        sheet?.stale = true
                        sheet?.refreshFailed = false
                        return
                    }
                    await renew(id)
                } else if !open.refreshFailed, sinceAsk >= askEveryMs {
                    sinceAsk = 0
                    let asking = try? await client()?.familySignInPending(token: start.token)
                    if let asking, let now = sheet, now.id == id, now.start?.token == start.token { sheet?.asking = asking }
                }
            }
            try? await Task.sleep(nanoseconds: UInt64(tickMs) * 1_000_000)
            sinceAsk += tickMs
        }
    }
}
