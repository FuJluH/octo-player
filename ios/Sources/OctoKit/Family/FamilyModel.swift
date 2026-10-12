import Foundation
import Observation

/// The outside songs and albums the account saved: hearted songs found online, kept as links
/// that play from the source.
public struct SavedOutside: Sendable, Equatable {
    public var songs: [Song] = []
    public var albums: [Album] = []

    public init(songs: [Song] = [], albums: [Album] = []) {
        self.songs = songs
        self.albums = albums
    }

    public var isEmpty: Bool { songs.isEmpty && albums.isEmpty }
}

/// The parts of the Family view, in the order other platforms show them.
public enum FamilySection: CaseIterable, Sendable {
    case login, plan, saved, requests, devices, members, inbox

    public var title: String {
        switch self {
        case .login: FamilyText.yourLogin
        case .plan: FamilyText.myPlan
        case .saved: FamilyText.saved
        case .requests: FamilyText.requests
        case .devices: FamilyText.devices
        case .members: FamilyText.members
        case .inbox: FamilyText.requestsWaiting
        }
    }
}

@MainActor
private final class ModelBox {
    weak var model: FamilyModel?
}

/// How often the open view reads the server again.
public let familyPollMs = 30_000

/// The Family view's state for the server in use. It is there only while the server lists
/// octoFamily (`supported`); everything else waits on the server, which decides.
@MainActor
@Observable
public final class FamilyModel {
    /// "Sign in on another device": the QR code and the device asking.
    public let handOver: HandOverSource

    /// The member's one login, for the Your login card; nil until read, and for accounts the
    /// family does not manage.
    public private(set) var login: FamilyLogin?
    public private(set) var info: FamilyInfo?
    /// Why the server could not be read.
    public private(set) var problem: String?
    /// The account's own requests, newest first as the server lists them.
    public private(set) var requests: [FamilyRequest] = []
    /// Every member's waiting requests, for a manager who approves.
    public private(set) var inbox: [FamilyRequest] = []
    public private(set) var devices: [FamilyDevice] = []
    public private(set) var saved = SavedOutside()
    /// What the server said about the last thing asked, in its own words.
    public private(set) var said: String?
    public private(set) var working = false
    /// A new member's invite, shown as a QR code with a way to copy it, until closed.
    public private(set) var invite: InviteSheet?

    @ObservationIgnored private let client: @MainActor () -> SubsonicClient?
    @ObservationIgnored private let supported: @MainActor () -> Bool
    @ObservationIgnored private let answered: @MainActor (FamilyRequest) -> Void
    @ObservationIgnored private let pollMs: Int
    @ObservationIgnored private var watching: Task<Void, Never>?
    /// Members added here who may not listen away from home: their sheets offer only the home link.
    @ObservationIgnored private var keptHome: Set<String> = []

    public init(client: @escaping @MainActor () -> SubsonicClient?, supported: @escaping @MainActor () -> Bool,
                mainAddress: @escaping @MainActor () -> URL? = { nil },
                answered: @escaping @MainActor (FamilyRequest) -> Void = { _ in }, pollMs: Int = familyPollMs,
                clock: @escaping @MainActor () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1_000) }, tickMs: Int = 250,
                askEveryMs: Int = 2_000, newKey: @escaping () -> String = HandOverBox.newKey) {
        self.client = client
        self.supported = supported
        self.answered = answered
        self.pollMs = pollMs
        let box = ModelBox()
        handOver = HandOverSource(client: client, displayName: { box.model?.info?.me.displayName ?? "" }, mainAddress: mainAddress,
                                  clock: clock, tickMs: tickMs, askEveryMs: askEveryMs, newKey: newKey)
        box.model = self
    }

    public var available: Bool { supported() }
    public var me: FamilyMe? { info?.me }
    public var manages: Bool { info?.manager != nil }
    public var approves: Bool { info?.me.abilities.approveRequests == true }
    /// This device, as the server lists it, once read.
    public var thisDevice: FamilyDevice? { devices.first { $0.current } }
    /// Who picks this device's audio quality; nil until read.
    public var deviceMode: QualityFollows? { thisDevice?.quality }

    /// The sections this account sees, for platforms that show the shared order.
    public func sections() -> [FamilySection] {
        FamilySection.allCases.filter { section in
            switch section {
            case .login: login != nil
            case .members: manages
            case .inbox: approves
            default: true
            }
        }
    }

    /// While the view shows: read now, then again now and then.
    public func watch() {
        if let watching, !watching.isCancelled { return }
        let every = pollMs
        watching = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(nanoseconds: UInt64(every) * 1_000_000)
            }
        }
    }

    public func stop() {
        watching?.cancel()
        watching = nil
    }

    /// Another server or account: nothing of this one's stays.
    public func forget() {
        stop()
        info = nil
        problem = nil
        requests = []
        inbox = []
        devices = []
        saved = SavedOutside()
        login = nil
        handOver.close()
        said = nil
        invite = nil
    }

    /// Reads the account's abilities only, for the parts of the app that follow it. Nil without
    /// a family.
    public func plan() async -> FamilyMe? {
        guard supported() else { return nil }
        if let info { return info.me }
        guard let client = client(), let read = try? await client.family() else { return nil }
        info = read
        // This device's quality mode decides how the app asks for songs.
        if let found = try? await client.familyDevices() { devices = found }
        return read.me
    }

    public func refresh() async {
        guard let client = client() else { return }
        guard supported() else {
            forget()
            return
        }
        do {
            let read = try await client.family()
            info = read
            problem = nil
            let approves = read.me.abilities.approveRequests
            async let mine = client.familyRequests()
            async let mineDevices = client.familyDevices()
            async let waiting = Self.waiting(client, approves)
            async let starred = try? client.starred()
            async let own = try? client.familyLogin()
            requests = try await mine
            devices = try await mineDevices
            inbox = try await waiting
            if let found = await starred {
                saved = SavedOutside(songs: found.song.filter(\.isExternal), albums: found.album.filter(\.isExternal))
            }
            login = await own
        } catch is CancellationError {
            return
        } catch {
            problem = Self.readProblem(error)
        }
    }

    private static func waiting(_ client: SubsonicClient, _ approves: Bool) async throws -> [FamilyRequest] {
        approves ? try await client.familyRequests(all: true, state: .pending) : []
    }

    static func readProblem(_ error: Error) -> String {
        let failure = SubsonicError(error)
        if failure.isUnreachable { return "Octo can't reach the server right now." }
        return failure.message.isEmpty ? "The server did not answer." : failure.message
    }

    /// Asks for a copy and answers what became of it, or nil when it could not be asked (the
    /// reason is in `said`).
    @discardableResult
    public func request(_ id: String, quality: RequestQuality) async -> FamilyRequest? {
        guard let client = client() else { return nil }
        working = true
        defer {
            working = false
            Task { await self.refresh() }
        }
        do {
            let made = try await client.requestCopy(id, quality: quality)
            said = requestAnswerLine(made)
            answered(made)
            requests = [made] + requests.filter { $0.id != made.id }
            return made
        } catch {
            let message = SubsonicError(error).message
            said = message.isEmpty ? "The request did not go through." : message
            return nil
        }
    }

    public func requestCopy(_ id: String, quality: RequestQuality) {
        Task { await request(id, quality: quality) }
    }

    public func cancel(_ id: String) {
        act { client in _ = try await client.cancelFamilyRequest(id); return "Request cancelled" }
    }

    public func approve(_ id: String, note: String? = nil) {
        act { client in "Approved \(requestTitle(try await client.decideFamilyRequest(id, approve: true, note: note)))" }
    }

    public func decline(_ id: String, note: String? = nil) {
        act { client in "Declined \(requestTitle(try await client.decideFamilyRequest(id, approve: false, note: note)))" }
    }

    /// Takes a device off the list. It comes back if it signs in again.
    public func forget(device: FamilyDevice) {
        act { client in
            try await client.forgetFamilyDevice(device.id)
            return "\(device.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "The device" : device.name) is off the list"
        }
    }

    /// Takes a song out of this member's own library.
    public func removeFromMyLibrary(_ id: String, title: String) {
        act { client in
            try await client.removeFromMyLibrary(id)
            return "Removed \(title) from your library"
        }
    }

    /// Takes an outside song or album off the saved list.
    public func unsave(_ id: String, album: Bool) {
        act { client in
            if album { try await client.unstar(albumId: id) } else { try await client.unstar(songId: id) }
            return "Removed from Saved"
        }
    }

    /// A manager adds a member, who may listen away from home or not; their invite shows as a
    /// QR code to scan or a link to send.
    public func addMember(username: String, displayName: String, preset: FamilyPreset, away: Bool = true) {
        manage { web in
            let added = try await web.addMember(username: username, displayName: displayName, preset: preset, away: away)
            let name = [added.member.displayName, displayName, username].first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? username
            let member = added.member.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? username.trimmingCharacters(in: .whitespacesAndNewlines) : added.member.username
            if away { self.keptHome.remove(member) } else { self.keptHome.insert(member) }
            self.invite = InviteSheet(name: name, username: member, url: added.inviteLink, links: added.links,
                                      anywhereAvailable: added.anywhereAvailable, homeOnly: added.homeOnly,
                                      awayAllowed: away && added.awayAllowed)
            return "Added \(name)"
        }
    }

    /// A manager resets a member's password: it stops working at once, and a new sign-up link
    /// shows in the invite sheet for them to choose another.
    public func resetPassword(_ member: FamilyMember) {
        manage { web in
            let fresh = try await web.resetMember(username: member.username)
            let name = member.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? member.username : member.displayName
            self.invite = InviteSheet(name: name, username: member.username, url: fresh.inviteLink, links: fresh.links,
                                      anywhereAvailable: fresh.anywhereAvailable, homeOnly: fresh.homeOnly,
                                      awayAllowed: fresh.awayAllowed && !self.keptHome.contains(member.username), reset: true)
            return "\(name)'s password no longer works"
        }
    }

    /// A new link for the invite that is open, in place of the last one.
    public func sendNewLink() {
        guard let client = client(), let asked = invite else { return }
        invite?.loading = true
        invite?.error = nil
        Task {
            let web = client.familyWeb()
            let got: Result<FamilyNewInvite, Error>
            do {
                got = .success(asked.reset ? try await web.resetMember(username: asked.username) : try await web.newInvite(username: asked.username))
            } catch {
                got = .failure(error)
            }
            guard var now = invite, now.username == asked.username else { return }
            switch got {
            case .success(let fresh):
                now.url = fresh.inviteLink
                now.links = fresh.links
                now.anywhereAvailable = fresh.anywhereAvailable
                now.homeOnly = fresh.homeOnly
                now.awayAllowed = now.awayAllowed && fresh.awayAllowed
                now.loading = false
            case .failure:
                now.loading = false
                now.error = FamilySheetText.linkFailed
            }
            invite = now
        }
    }

    public func closeInvite() { invite = nil }

    public func clearSaid() { said = nil }

    /// A change on the family page, signed as every call this app makes.
    private func manage(_ change: @escaping @MainActor (FamilyWeb) async throws -> String?) {
        guard let client = client() else { return }
        Task {
            working = true
            do {
                if let words = try await change(client.familyWeb()) { said = words }
            } catch {
                said = Self.actionProblem(error)
            }
            working = false
            await refresh()
        }
    }

    private func act(_ call: @escaping @MainActor (SubsonicClient) async throws -> String?) {
        guard let client = client() else { return }
        Task {
            working = true
            do {
                if let words = try await call(client) { said = words }
            } catch {
                said = Self.actionProblem(error)
            }
            working = false
            await refresh()
        }
    }

    static func actionProblem(_ error: Error) -> String {
        let failure = SubsonicError(error)
        if failure.isUnreachable { return "Octo can't reach the server right now." }
        return failure.message.isEmpty ? "The server said no." : failure.message
    }
}
