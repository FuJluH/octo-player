import Foundation
import Observation
import OctoKit
import UIKit

/// What the app was opened for from outside: the Family screen (a notice tapped), or a family
/// link (an invite, or a sign-in from another device).
enum FamilyOpen: Equatable {
    case family
    case join(FamilyLink)
}

/// A song or album found online to ask a copy of, for the request sheet.
struct CopyAsk: Identifiable, Equatable {
    let id: String
    let title: String
}

/// Family for the server in use: the shared model the Family screen shows, the account's
/// abilities that song menus and offline copies follow, the request sheet, and links into the
/// join form. Another account in use starts it over.
@MainActor
@Observable
final class FamilyHub {
    let model: FamilyModel
    /// The song the request sheet is open for, or nil while it is shut.
    private(set) var asking: CopyAsk?
    /// Outside songs saved here, shown before the server's lists catch up.
    private(set) var savedHere: Set<String> = []

    @ObservationIgnored private let session: Session
    @ObservationIgnored private let router: Router
    @ObservationIgnored private var watch: Watch<String?>?
    /// The clipboard text last offered, so the same link is offered once.
    @ObservationIgnored private var offered: String?

    init(session: Session, router: Router) {
        self.session = session
        self.router = router
        let store = FamilyNoticeStore()
        model = FamilyModel(
            client: { [weak session] in session?.client },
            supported: { [weak session] in session?.family == true },
            mainAddress: { [weak session] in session?.active?.address },
            answered: { [weak session] request in
                guard let account = session?.activeId else { return }
                store.alreadyTold(account, request)
            })
    }

    func start() {
        guard watch == nil else { return }
        watch = Watch({ [weak self] in self.flatMap { $0.session.client == nil ? nil : $0.session.activeId } }) { [weak self] _ in
            self?.accountChanged()
        }
        accountChanged()
    }

    /// Another account in use: nothing of the last one's stays, background checks follow
    /// whether Family is on, and the plan is read at once.
    private func accountChanged() {
        model.forget()
        savedHere = []
        asking = nil
        if session.family { FamilyNotices.schedule() } else { FamilyNotices.cancel() }
        Task { _ = await model.plan() }
    }

    /// Opens what was asked from outside the app, on the Settings tab.
    func open(_ what: FamilyOpen) {
        switch what {
        case .family:
            router.openInSettings(.family)
        case .join(let link):
            router.signIn = .join(familyAppLink(link))
        }
    }

    /// A family link on the clipboard when the app comes to the front is offered once, with a
    /// way to use it.
    func offerClipboard(_ text: String?) {
        guard let clip = text?.trimmingCharacters(in: .whitespacesAndNewlines), !clip.isEmpty, clip != offered,
              let link = parseFamilyLink(clip)
        else { return }
        offered = clip
        router.show(link.isInvite ? "A family invite is on the clipboard" : "A family sign-in link is on the clipboard",
                    action: "Use it") { [weak self] in self?.open(.join(link)) }
    }

    /// The address of the server in use, as people read it.
    var serverAddress: String { session.active.map { ServerAddress.shown($0.address) } ?? "" }

    var me: FamilyMe? { model.me }

    /// What a song found online offers this account.
    var outside: OutsideActions { session.family ? outsideActions(model.me) : .usual }

    var removesFromMine: Bool { session.family && offersRemoveFromMyLibrary(model.me) }

    func ask(_ id: String, title: String) {
        guard model.me != nil else { return }
        asking = CopyAsk(id: id.hasPrefix("find:") ? String(id.dropFirst(5)) : id, title: title)
    }

    func closeSheet() { asking = nil }

    func isSaved(_ id: String) -> Bool {
        let bare = id.hasPrefix("find:") ? String(id.dropFirst(5)) : id
        return savedHere.contains(id) || model.saved.songs.contains { $0.id == bare }
    }

    /// Saves a song found online, or takes it off Saved: it plays from the internet, and a copy
    /// can be asked for from Family.
    func toggleSaved(_ id: String, title: String) {
        guard id.hasPrefix("find:") || id.hasPrefix("ext-"), let client = session.client else { return }
        let bare = id.hasPrefix("find:") ? String(id.dropFirst(5)) : id
        let saving = !isSaved(id)
        Task {
            do {
                if saving { try await client.star(songId: bare) } else { try await client.unstar(songId: bare) }
                if saving { savedHere.insert(id) } else { savedHere.remove(id) }
                router.show(saving ? "Saved \(title). Find it in Family, under Saved." : "Took \(title) off Saved")
            } catch {
                let message = SubsonicError(error).message
                router.show(message.isEmpty ? "The server did not save it." : message)
            }
            await model.refresh()
        }
    }

    /// Sends the request from the sheet, and says what became of it.
    func request(_ ask: CopyAsk, quality: RequestQuality) {
        asking = nil
        Task {
            _ = await model.request(ask.id, quality: quality)
            if let said = model.said { router.show(said) }
        }
    }

    /// Takes a library song out of this member's own library.
    func removeFromMyLibrary(serverId: String?, title: String) {
        guard let serverId else {
            router.show("This song is not in your own library")
            return
        }
        guard let client = session.client else { return }
        Task {
            do {
                try await client.removeFromMyLibrary(serverId)
                router.show("Removed \(title) from your library", done: true)
            } catch {
                let message = SubsonicError(error).message
                router.show(message.isEmpty ? "The server kept \(title)." : message)
            }
        }
    }

    /// Changes the member's own password, which signs every other app and device out; this
    /// phone keeps the new one.
    func changePassword(current: String, new: String) async -> PasswordChange {
        await session.changePassword(current: current, new: new, family: model.me?.managed == true)
    }
}

/// What each account has been told about its family requests, so each decision is told once.
struct FamilyNoticeStore: Sendable {
    private let prefs = Prefs("family_notices")

    func read(_ account: String) -> NoticeMemory {
        guard let text = prefs.string("told", account), let data = text.data(using: .utf8),
              let memory = try? JSONDecoder().decode(NoticeMemory.self, from: data)
        else { return NoticeMemory() }
        return memory
    }

    func write(_ account: String, _ memory: NoticeMemory) {
        guard let data = try? JSONEncoder().encode(memory) else { return }
        prefs.set(String(decoding: data, as: UTF8.self), "told", account)
    }

    /// A request whose answer the request sheet already showed.
    func alreadyTold(_ account: String, _ request: FamilyRequest) {
        guard !account.isEmpty else { return }
        write(account, read(account).alreadyTold(request))
    }
}
