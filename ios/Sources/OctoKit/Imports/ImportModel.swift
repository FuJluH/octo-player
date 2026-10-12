import Foundation
import Observation

// "Get my music" and imports as every Octo app shows them: a tile for each service,
// TuneMyMusic's export page opened in the browser for the one tapped, then a wait for the file it
// saves, which comes back by a picker, a share or a paste; the Spotify sign-in; the lists; and
// the trickle that fetches what is missing.

public enum ImportText {
    public static let importTitle = "Import"
    public static let getMyMusic = "Get my music"
    public static let useDownloadedFile = "Use the file I just downloaded"
    public static let useAFile = "Use a file"
    public static let pasteAList = "Paste a list"
    public static let connectSpotifyKeepsUpdating = "Connect Spotify (keeps updating)"
    public static let pastedListName = "Pasted list"
    public static let serviceWords = "spotify apple music youtube music amazon music tidal deezer qobuz soundcloud pandora youtube"
    public static let getMyMusicLine = "Pick where your music is now. Octo opens TuneMyMusic, which saves your lists to a file for Octo to read."
    public static let pasteLine = "One song a line, as Artist - Title."
    public static let waitingAnyLine = "Pick a list file saved from TuneMyMusic or another app: CSV, TXT, JSON or ZIP."
    public static let notTuneMyMusic = "That export link does not go to TuneMyMusic, so Octo will not open it."
    public static let fileTooBig = "That file is over 64 MB, more than Octo takes."
    public static let fileEmpty = "That file is empty."
    public static let notAListFile = "Octo reads lists from CSV, TXT, JSON or ZIP files."
    public static let keepAsPlaylist = "Keep as playlist"
    public static let getMissingSongs = "Get missing songs"
    public static let removeList = "Remove this list?"
    /// How often to ask while something moves, and otherwise while the view is open.
    public static let busyPollMs = 3_000
    public static let idlePollMs = 20_000
}

/// The file types a list can come in, by name ending.
public let importFileEndings = ["txt", "csv", "zip", "json"]

/// Whether a file's name says it is a list Octo reads.
public func isImportFileName(_ name: String) -> Bool {
    guard let dot = name.range(of: ".", options: .backwards) else { return false }
    return importFileEndings.contains(String(name[dot.upperBound...]).lowercased())
}

/// Where a "Get my music" visit stands.
public enum ImportStep: Sendable, Equatable {
    /// The grid of services.
    case choose
    /// Spotify on a server that can sign in to it: keep it updating, or use a file.
    case spotifyWays(ImportServiceLink)
    /// The export page is open in the browser; the file comes back here.
    case waiting(ImportServiceLink?)
    /// A file or text on its way to the server.
    case sending(ImportServiceLink?, name: String)
    /// The server read it: its own words, and who approves downloads first, when someone does.
    case sent(message: String, approval: String?)

    /// The tile a step lights up, if any.
    public var service: ImportServiceLink? {
        switch self {
        case .spotifyWays(let service): service
        case .waiting(let service): service
        case .sending(let service, _): service
        default: nil
        }
    }
}

/// The only export pages Octo opens: https on tunemymusic.com or www.tunemymusic.com, with no
/// sign-in and the usual port. Answers the address as it will be opened, or nil.
public func tuneMyMusicUrl(_ url: String) -> String? {
    guard let parts = URLComponents(string: url.trimmingCharacters(in: .whitespacesAndNewlines)),
          parts.scheme?.lowercased() == "https", let host = parts.host?.lowercased(),
          host == "tunemymusic.com" || host == "www.tunemymusic.com",
          parts.user == nil, parts.password == nil, parts.port == nil || parts.port == 443
    else { return nil }
    var clean = parts
    clean.scheme = "https"
    clean.host = host
    clean.port = nil
    if clean.percentEncodedPath.isEmpty { clean.percentEncodedPath = "/" }
    return clean.url?.absoluteString
}

/// What to do on TuneMyMusic for this service.
public func waitingLine(_ service: ImportServiceLink) -> String {
    "Tap the \(service.tile.trimmingCharacters(in: .whitespaces).isEmpty ? service.name : service.tile) tile, sign in, choose your playlists or Liked songs, then Export to file as CSV."
}

/// The waiting step's heading.
public func waitingTitle(_ service: ImportServiceLink?) -> String {
    service.map { "Waiting for your \($0.name) file" } ?? "Waiting for your file"
}

/// What a member reads once their lists are in and wait for approval.
public func approvalLine(_ owner: String?) -> String {
    let name = owner?.trimmingCharacters(in: .whitespacesAndNewlines)
    return "Your lists are in. \(name?.isEmpty == false ? name! : "The owner") approves downloads before Octo fetches the missing songs."
}

extension ImportOverview {
    /// The approval line when this member's downloads wait for approval, else nil.
    public var approvalLine: String? {
        guard let approval, approval.needed else { return nil }
        return OctoKit.approvalLine(approval.by)
    }
}

extension ImportServiceLink {
    /// Whether a Spotify tile also offers the sign-in that keeps lists updating.
    public func offersSpotifySignIn(_ spotifyConnect: Bool) -> Bool { spotifyConnect && id == spotifyService }
}

/// One song's state, in the words the dashboard uses too.
public func trackStateLabel(_ state: ImportTrackState) -> String {
    switch state {
    case .have: "In your library"
    case .missing: "Missing"
    case .queued: "Queued"
    case .downloading: "Fetching"
    case .done: "Fetched"
    case .notFound: "Not found"
    case .skipped: "Skipped"
    case .unknown: "Unknown"
    }
}

extension ImportListSummary {
    /// Where a list came from, and who made it when someone else did.
    public var originLine: String {
        let source: String? = switch origin {
        case .spotifyLiked, .spotifyPlaylist: "Spotify"
        case .link: "Link"
        case .file: "File"
        case .unknown: nil
        }
        return [source, by.map { "by \($0)" }, gone ? "no longer on your Spotify" : nil].compactMap { $0 }.joined(separator: " · ")
    }

    /// "6 of 10 · 2 missing · 1 coming · 1 not found".
    public var countsLine: String {
        ["\(have) of \(total)", missing > 0 ? "\(missing) missing" : nil, coming > 0 ? "\(coming) coming" : nil,
         notFound > 0 ? "\(notFound) not found" : nil].compactMap { $0 }.joined(separator: " · ")
    }

    /// What goes and what stays when the list is removed.
    public var removeLine: String {
        var text = "Octo forgets \(name)"
        if getMissing { text += " and stops getting its missing songs" }
        text += ". Songs already in your library stay"
        if playlistId != nil { text += ", and so does its playlist" }
        return text + "."
    }
}

extension SpotifyStatus {
    /// The account's line: who is connected and until when, or what to do first.
    public func line(zone: TimeZone = .current) -> String {
        if !configured { return "Add your Spotify app's Client ID on the Octo dashboard first, on its Spotify import page." }
        if let redirectProblem { return "The redirect address on the server will not work: \(redirectProblem)" }
        if let problem { return problem }
        if connected {
            if let endsUtc { return "Spotify ends this sign-in on \(Self.day(endsUtc, zone)); connect again then." }
            return "Connected."
        }
        return "Connect opens Spotify in your browser to let Octo read your library."
    }

    public var title: String {
        if connected { return "Connected as \(account ?? "your account")" }
        if problem != nil { return "Sign in again" }
        return "Not connected"
    }

    static func day(_ utc: String, _ zone: TimeZone) -> String {
        guard let ms = epochMs(utc) else { return utc }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.timeZone = zone
        return formatter.string(from: Date(timeIntervalSince1970: Double(ms) / 1_000))
    }
}

extension TrickleStatus {
    /// What the trickle is doing, as a heading.
    public var title: String {
        switch stage {
        case .idle, .unknown: "Nothing to fetch"
        case .running: downloading > 0 ? "Fetching" : "Waiting for the next turn"
        case .paused: "Paused"
        case .off: "Off"
        case .yielding: "Waiting for other downloads"
        case .waitingForSoulseek: "Waiting for Soulseek"
        }
    }

    /// The trickle's line: the pace, when the next song starts, and the counts.
    public func line(zone: TimeZone = .current) -> String {
        var parts: [String] = []
        if stage == .off {
            parts.append("Songs an hour is 0 on the server, so nothing starts.")
        } else {
            parts.append("Up to \(perHour == 1 ? "1 song" : "\(perHour) songs") an hour.")
        }
        if stage == .running, downloading == 0, let nextUtc { parts.append("Next song at \(Self.time(nextUtc, zone)).") }
        if stage == .yielding { parts.append("Someone's own downloads come first.") }
        if stage == .waitingForSoulseek { parts.append("It goes on once Soulseek is back.") }
        let tally = [(queued, "waiting"), (downloading, "fetching"), (done, "fetched"), (notFound, "not found"), (skipped, "skipped")]
            .filter { $0.0 > 0 }.map { "\($0.0) \($0.1)" }.joined(separator: ", ")
        if !tally.isEmpty { parts.append(tally + ".") }
        return parts.joined(separator: " ")
    }

    static func time(_ utc: String, _ zone: TimeZone) -> String {
        guard let ms = epochMs(utc) else { return utc }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = zone
        return formatter.string(from: Date(timeIntervalSince1970: Double(ms) / 1_000))
    }
}

/// The Spotify sign-in from an app. Spotify sends the browser back to a page on this device,
/// which catches its answer, and the server, which holds the PKCE secret, finishes it. A server
/// whose redirect is its own https address finishes it by itself, and the app only opens the page.
public func signInToSpotify(_ client: SubsonicClient, open: @Sendable (String) async -> Void,
                            catcher: @Sendable (_ host: String, _ path: String) async -> (any LoopbackCatcher)?,
                            timeoutMs: Int = 10 * 60_000) async throws -> ImportAnswer {
    let spotify = try await client.imports().spotify
    if !spotify.configured || spotify.redirectProblem != nil { return ImportAnswer(ok: false, message: spotify.line()) }
    if spotify.octoFinishes {
        let start = try await client.importAction(ImportActions.connect)
        if let url = start.url { await open(url) }
        return start.ok ? ImportAnswer(ok: true, message: "Allow Octo in your browser. This page notices on its own when that is done.") : start
    }
    guard let (host, path) = LoopbackRules.usable(spotify.redirectUri), let catcher = await catcher(host, path) else {
        return ImportAnswer(ok: false, message: "The apps sign in with the redirect http://127.0.0.1/callback, with no port. Set that on the Spotify app and on the Octo dashboard, or connect from the dashboard.")
    }
    defer { catcher.close() }
    let start = try await client.importAction(ImportActions.connect, [("redirect", catcher.redirectUri)])
    guard start.ok, let url = start.url else { return start }
    await open(url)
    guard let back = await catcher.await(timeoutMs: timeoutMs) else {
        return ImportAnswer(ok: false, message: "Spotify did not answer. Connect again when you are ready.")
    }
    if back.error == "access_denied" { return ImportAnswer(ok: false, message: "Spotify says access was not allowed.") }
    if let error = back.error { return ImportAnswer(ok: false, message: "Spotify sent back an error: \(error)") }
    return try await client.importAction(ImportActions.finish, [("code", back.code ?? ""), ("state", back.state ?? "")])
}

/// A list another app shared to Octo: a file to read, or text that is the list itself.
public enum SharedImport: Sendable, Equatable {
    case file(ImportFileRead, name: String?, type: String?)
    case text(String, name: String?)
}

/// A file read for Import: its bytes, or why it could not be.
public enum ImportFileRead: Sendable, Equatable {
    case bytes(Data)
    case tooBig
    case unreadable
}

/// The share types Import takes, and the picker's.
public let importShareTypes: Set<String> = ["text/plain", "text/csv", "text/comma-separated-values"]
public let importPickTypes = ["text/plain", "text/csv", "text/comma-separated-values", "application/zip", "application/json"]

/// What shared text hands Import, or nil when it is not a list: blank text is not, and the
/// subject (trimmed) names it.
public func sharedText(_ text: String?, subject: String?) -> SharedImport? {
    guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
    let name = subject?.trimmingCharacters(in: .whitespacesAndNewlines)
    return .text(text, name: name?.isEmpty == false ? name : nil)
}

/// A name for a picked or shared file that the server reads by its ending: its own name when
/// that has one Octo knows, else one from its type.
public func importFileName(_ shown: String?, type: String?) -> String {
    let name = shown?.trimmingCharacters(in: .whitespacesAndNewlines)
    if let name, !name.isEmpty, isImportFileName(name) { return name }
    let kind = type?.split(separator: ";").first?.trimmingCharacters(in: .whitespaces).lowercased()
    let ending = switch kind {
    case "text/csv", "text/comma-separated-values": "csv"
    case "application/zip": "zip"
    case "application/json": "json"
    default: "txt"
    }
    return "\((name?.isEmpty == false ? name : nil) ?? "Shared list").\(ending)"
}

/// The Import view's state for the server in use: the overview, the services and where a "Get
/// my music" visit stands, the list opened, the last thing the server said, and the Spotify
/// sign-in while it waits for the browser. The server does the work; this asks it, every few
/// seconds while the view is open and something moves.
@MainActor
@Observable
public final class ImportModel {
    public private(set) var overview: ImportOverview?
    /// The services, on a server that lists them (octoImports version 2); nil on an older one.
    public private(set) var services: ImportServices?
    public private(set) var step: ImportStep = .choose
    public private(set) var problem: String?
    public private(set) var openId: String?
    public private(set) var detail: ImportListDetail?
    /// What the server said about the last thing asked, in its own words.
    public private(set) var said: String?
    public private(set) var working = false
    public private(set) var signingIn = false

    @ObservationIgnored private let client: @MainActor () -> SubsonicClient?
    @ObservationIgnored private let openUrl: @MainActor (String) -> Void
    @ObservationIgnored private let catcher: @Sendable (String, String) async -> (any LoopbackCatcher)?
    @ObservationIgnored private let busyPollMs: Int
    @ObservationIgnored private let idlePollMs: Int
    @ObservationIgnored private var filesKnown: Bool?
    @ObservationIgnored private var watching: Task<Void, Never>?
    @ObservationIgnored private var signIn: Task<Void, Never>?

    public init(client: @escaping @MainActor () -> SubsonicClient?, openUrl: @escaping @MainActor (String) -> Void = { _ in },
                catcher: @escaping @Sendable (String, String) async -> (any LoopbackCatcher)? = { _, _ in nil },
                busyPollMs: Int = ImportText.busyPollMs, idlePollMs: Int = ImportText.idlePollMs) {
        self.client = client
        self.openUrl = openUrl
        self.catcher = catcher
        self.busyPollMs = busyPollMs
        self.idlePollMs = idlePollMs
    }

    /// While the page shows: read now, then again soon while anything moves.
    public func watch() {
        if let watching, !watching.isCancelled { return }
        watching = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                let wait = self.overview?.moving == true || self.signingIn ? self.busyPollMs : self.idlePollMs
                try? await Task.sleep(nanoseconds: UInt64(wait) * 1_000_000)
            }
        }
    }

    public func stop() {
        watching?.cancel()
        watching = nil
    }

    /// Another server: nothing of this one's stays.
    public func forget() {
        stop()
        signIn?.cancel()
        signingIn = false
        overview = nil
        services = nil
        filesKnown = nil
        step = .choose
        problem = nil
        openId = nil
        detail = nil
        said = nil
    }

    public func refresh() async {
        guard let client = client() else { return }
        do {
            overview = try await client.imports()
            problem = nil
            await readServices(client)
        } catch is CancellationError {
            return
        } catch {
            let failure = SubsonicError(error)
            if failure.isUnreachable {
                problem = "Octo can't reach the server right now."
            } else {
                problem = overview == nil ? "This server has no imports yet. Update Octo on the server to use it." : failure.message
            }
        }
        guard let id = openId else { return }
        if let read = try? await client.importList(id), openId == id { detail = read }
    }

    /// The services, once the server says it has them. Asked once a server; a server that could
    /// not say is asked again next time.
    private func readServices(_ client: SubsonicClient) async {
        if filesKnown == nil { filesKnown = await client.supportsIfKnown(octoImports, version: octoImportsFiles) }
        guard filesKnown == true, services == nil else { return }
        services = try? await client.importServices()
    }

    /// A service's tile tapped. Spotify, when the server can sign in to it, first offers that;
    /// every other service opens its export page.
    public func choose(_ service: ImportServiceLink) {
        if case .sending = step { return }
        said = nil
        if service.offersSpotifySignIn(services?.spotifyConnect == true) { step = .spotifyWays(service) } else { openExport(service) }
    }

    /// Opens the service's export page on TuneMyMusic and waits for the file. Any other address is refused.
    public func openExport(_ service: ImportServiceLink) {
        guard let url = tuneMyMusicUrl(service.exportUrl) else {
            said = ImportText.notTuneMyMusic
            step = .choose
            return
        }
        openUrl(url)
        step = .waiting(service)
    }

    /// Waits for a file with no service picked: one saved earlier.
    public func useAFile() {
        if case .sending = step { return }
        said = nil
        step = .waiting(nil)
    }

    /// The Spotify sign-in from the Spotify tile; its lists keep updating.
    public func connectSpotify() {
        step = .choose
        connect()
    }

    public func backToServices() {
        if case .sending = step { return }
        step = .choose
    }

    /// Sends a list file to the server. A refused file leaves the wait open to try another.
    public func sendFile(name: String, bytes: Data) {
        let refused: String? = if !isImportFileName(name) {
            ImportText.notAListFile
        } else if bytes.isEmpty {
            ImportText.fileEmpty
        } else if Int64(bytes.count) > importFileMaxBytes {
            ImportText.fileTooBig
        } else {
            nil
        }
        if let refused {
            said = refused
            return
        }
        send(name) { try await $0.importFile(name: name, bytes: bytes) }
    }

    /// Sends a typed or pasted list to the server.
    public func sendText(_ text: String, name: String = ImportText.pastedListName) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let called = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? ImportText.pastedListName : name
        send(called) { try await $0.importText(name: called, text: text) }
    }

    /// Something that went wrong before a file could be sent, in words to show.
    public func tell(_ words: String) { said = words }

    private func send(_ name: String, _ call: @escaping (SubsonicClient) async throws -> ImportAnswer) {
        guard let client = client() else { return }
        if case .sending = step { return }
        let waiting = step.service
        step = .sending(waiting, name: name)
        said = nil
        Task {
            do {
                let answer = try await call(client)
                if answer.ok {
                    await refresh()
                    step = .sent(message: answer.message, approval: overview?.approvalLine)
                    return
                }
                said = answer.message.isEmpty ? "The server could not read that file." : answer.message
                step = .waiting(waiting)
            } catch {
                let message = SubsonicError(error).message
                said = message.isEmpty ? "Octo could not reach the server." : message
                step = .waiting(waiting)
            }
            await refresh()
        }
    }

    /// Opens Spotify in the browser and waits for its answer on this device.
    public func connect() {
        guard let client = client(), !signingIn else { return }
        let open = openUrl
        let catcher = catcher
        signIn = Task {
            signingIn = true
            said = "Allow Octo in your browser, then come back here."
            do {
                said = try await signInToSpotify(client, open: { url in await MainActor.run { open(url) } }, catcher: catcher).message
            } catch is CancellationError {
            } catch {
                said = SubsonicError(error).message
            }
            signingIn = false
            await refresh()
        }
    }

    public func cancelSignIn() {
        signIn?.cancel()
        signingIn = false
        said = nil
    }

    public func disconnect() { act(ImportActions.disconnect) }
    public func readAgain() { act(ImportActions.read) }
    public func keepPlaylist(_ id: String, on: Bool) { act(ImportActions.playlist, [("id", id), ("on", on ? "true" : "false")]) }
    public func getMissing(_ id: String, on: Bool) { act(ImportActions.fetch, [("id", id), ("on", on ? "true" : "false")]) }
    public func getSongs(_ id: String, keys: [String]) { act(ImportActions.songs, [("id", id)], keys: keys) }
    public func readList(_ id: String) { act(ImportActions.refresh, [("id", id)]) }
    public func pause() { act(ImportActions.pause) }
    public func resume() { act(ImportActions.resume) }
    public func retry(_ keys: [String] = []) { act(ImportActions.retry, keys: keys) }
    public func skip(_ key: String) { act(ImportActions.skip, keys: [key]) }
    public func clearFinished() { act(ImportActions.clear) }

    public func remove(_ id: String) {
        if openId == id { close() }
        act(ImportActions.remove, [("id", id)])
    }

    /// A public playlist or album by its link; the new list opens.
    public func addLink(_ url: String) {
        act(ImportActions.addLink, [("url", url.trimmingCharacters(in: .whitespacesAndNewlines))]) { [weak self] answer in
            if let id = answer.listId { self?.open(id) }
        }
    }

    public func open(_ id: String) {
        if openId != id { detail = nil }
        openId = id
        Task { await refresh() }
    }

    public func close() {
        openId = nil
        detail = nil
    }

    private func act(_ action: String, _ params: [(String, String)] = [], keys: [String] = [], then: (@MainActor (ImportAnswer) -> Void)? = nil) {
        guard let client = client() else { return }
        Task {
            working = true
            do {
                let answer = try await client.importAction(action, params, keys: keys)
                said = answer.message
                if answer.ok { then?(answer) }
            } catch {
                let message = SubsonicError(error).message
                said = message.isEmpty ? "Octo could not reach the server." : message
            }
            working = false
            await refresh()
        }
    }
}
