import Foundation
import OctoKit
import ShareInbox
import SwiftUI

/// Where the account parts join the data parts: what "forget here" also forgets, and Octo's
/// admin pages for the downloads follower.
@MainActor
enum AccountHooks {
    static func install(_ data: DataServices, session: Session, family: FamilyHub) {
        // Offline copies follow the family plan; without a family they are always allowed.
        data.offline.offlineCopiesAllowed = { [weak family] in offlineCopiesAllowed(await family?.model.plan()) }
        // A server taken off the list with "forget here" loses where its admin pages were, and
        // what its family notices already told.
        data.serverSwitch.onForget("octo_admin") { account in OctoAdminPages.shared.forget(server: account) }
        data.serverSwitch.onForget("family_notices") { account in Prefs("family_notices").forgetAccount(account) }
        // ...and the playlists it used lately, and its live lists.
        data.serverSwitch.onForget("recent_playlists") { account in UserDefaults.standard.removeObject(forKey: "playlists.recent.\(account)") }
        data.serverSwitch.onForget("live_lists") { account in UserDefaults.standard.removeObject(forKey: "live_lists.lists:\(account)") }
        data.downloads.adminPages = Downloads.AdminPages(
            locate: { [weak session] in
                guard let session, session.runsOcto else { return nil }
                return await OctoAdminPages.shared.locate(OctoAdminPages.signIn(session))
            },
            downloaded: { [weak session] base in
                let signIn = session.flatMap(OctoAdminPages.signIn)
                return try await OctoAdminPages.shared.downloads(base, signIn).map {
                    Downloads.AdminDownload(title: $0.title, artist: $0.artist)
                }
            })
        #if DEBUG
        Drive.steps.append { name, value in
            guard name == "account" else { return false }
            await AccountDrive.run(value, session: session, serverSwitch: data.serverSwitch)
            return true
        }
        #endif
    }
}

#if DEBUG
/// The account part's OCTO_DRIVE steps, each `account:WHAT`:
/// - `account:server` opens Settings > Server and sync (also `settings:server`)
/// - `account:shares`, `account:radio`, `account:family`, `account:admin`, `account:import`
///   open those pages on the Settings tab
/// - `account:password` opens the Server page's Change password sheet
/// - `account:signout` asks before signing out of the server in use
/// - `account:handover` opens Family and its Sign in on another device sheet
/// - `account:invite` shows the invite sheet with a sample link (nothing is sent)
/// - `account:request` opens the Request a copy sheet for a sample song (nothing is sent)
/// - `account:share` opens the share card for the first song playing or a sample
/// - `account:signin`, `account:add`, `account:edit`, `account:again`, `account:connection`
///   open the sign-in screen in that mode (edit, again and connection for the server in use)
/// - `account:join:LINK` opens the sign-in screen joining with a family link
/// - `account:scan` opens the sign-in screen with the family QR scanner
/// - `account:shortcut:NAME` runs a Home Screen quick action (`shuffle_all`, `liked`,
///   `recently_added`, `resume`)
/// - `account:open:URL` opens the app with an address, as another app would
/// - `account:shared:TEXT` leaves TEXT in the share inbox, as "Share to Octo" does, and takes it
///   into Import
/// - `account:use:TEXT` makes the kept server whose id or address holds TEXT the one in use, as
///   tapping it in Servers does (one needing its password again is left as it is)
/// - `account:remove:TEXT` takes the kept server whose id or address holds TEXT off the list,
///   deleting what the phone keeps for it, as Remove and delete does
@MainActor
enum AccountDrive {
    static func run(_ value: String, session: Session, serverSwitch: ServerSwitch) async {
        guard let entries = SystemEntries.shared else { return }
        let router = entries.router
        let accounts = entries.accounts
        let parts = value.split(separator: ":", maxSplits: 1).map(String.init)
        let what = parts.first ?? ""
        let rest = parts.count > 1 ? parts[1] : ""
        let named = session.servers.first { $0.id == rest || $0.address.absoluteString.contains(rest) }
        switch what {
        case "use":
            guard let named, !named.signedOut else { return }
            switch await serverSwitch.switchTo(named.id) {
            case .done(let notice): if let notice { router.done(notice) }
            case .needsPassword, .failed: break
            }
        case "remove":
            if let named { serverSwitch.remove(named.id, forgetHere: true) }
        case "server": await SettingsNavigator.shared.drive("settings", "server", router: router)
        case "shares": router.openInSettings(.shares)
        case "radio": router.openInSettings(.radioStations)
        case "family": router.openInSettings(.family)
        case "admin": router.openInSettings(.admin)
        case "import": router.openInSettings(.imports)
        case "password", "signout":
            await SettingsNavigator.shared.drive("settings", "server", router: router)
            try? await Task.sleep(for: .milliseconds(700))
            SettingsNavigator.shared.popup = what == "password" ? SettingsIndex.changePassword.id : SettingsIndex.disconnect.id
        case "handover":
            router.openInSettings(.family)
            try? await Task.sleep(for: .milliseconds(600))
            accounts.family.model.handOver.open()
        case "invite": DriveSheets.invite(server: session.active.map { ServerAddress.shown($0.address) } ?? "https://music.example.com")
        case "request": accounts.family.ask("drive-sample", title: "Angel")
        case "share":
            let song = entries.player.current
            accounts.share(ShareRequest(ids: [song?.id ?? "drive-sample"], title: song?.title ?? "Angel"))
        case "signin": router.signIn = .signIn
        case "add": router.signIn = .add
        case "edit": if let server = session.active { router.signIn = .edit(server) }
        case "again": if let server = session.active { router.signIn = .again(server, note: serverSwitchPasswordRefusedWords(server.name)) }
        case "connection": if let server = session.active { router.signIn = .editConnection(server) }
        case "join": router.signIn = .join(rest)
        case "scan":
            SignInView.scanOnOpen = true
            router.signIn = .signIn
        case "shortcut": if let shortcut = LauncherShortcut(rawValue: rest) { await entries.run(shortcut) }
        case "open": if let url = URL(string: rest) { entries.open(url) }
        case "shared":
            let text = rest.isEmpty ? "Massive Attack - Angel\nMGMT - Kids" : rest
            try? OctoAppGroup.inbox()?.put(.text(text, subject: "Shared list"))
            entries.takeShared()
        default: break
        }
    }
}

/// Sheets the drive steps show with sample content, so they can be seen without changing the server.
@MainActor
enum DriveSheets {
    static func invite(server: String) {
        guard let overlays = SystemEntries.shared?.overlays else { return }
        let id = UUID()
        let sample = InviteSheet(name: "Sam", username: "sam", url: "\(server)/family/join#invite=drive-sample-token")
        overlays.showSheet(id, tall: true, scrolls: false, content: AnyView(
            InviteSheetView(invite: sample, server: server, owner: true, newLink: {}, done: { overlays.hideSheet(id) })
        )) { overlays.hideSheet(id) }
    }
}
#endif
