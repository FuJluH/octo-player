import AVFoundation
import Observation
import Intents
import OctoKit
import OctoSystem
import ShareInbox
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import UserNotifications

/// The ways into the app from outside it: Home Screen quick actions, files opened with Octo,
/// octo:// links, lists shared in for Import, family notices, and a family link on the
/// clipboard.
@MainActor
final class SystemEntries {
    static weak var shared: SystemEntries?

    let session: Session
    let player: Player
    let router: Router
    let accounts: Accounts
    var family: FamilyHub { accounts.family }
    /// A quick action tapped before the screen was up, run once it is.
    var pendingShortcut: LauncherShortcut?
    /// The shell's sheets and popups, once the screen is up.
    weak var overlays: Overlays?
    private var lastPasteboard = -1

    init(session: Session, player: Player, router: Router, accounts: Accounts) {
        self.session = session
        self.player = player
        self.router = router
        self.accounts = accounts
    }

    // MARK: Opened addresses

    /// An address the app was opened with: a widget's link, a family link, a list file for Import,
    /// or an audio file.
    func open(_ url: URL) {
        if let link = OctoLink(url) {
            SystemActions.shared?.open(link)
        } else if url.isFileURL {
            openFile(url)
        } else if url.scheme?.lowercased() == "octo", url.host?.lowercased() == "import" {
            takeShared()
        } else if let link = parseFamilyLink(url.absoluteString) {
            family.open(.join(link))
        }
    }

    /// A list "Share to Octo" left in the inbox goes to Import, once.
    func takeShared() {
        guard let inbox = OctoAppGroup.inbox(), inbox.waiting, let (drop, bytes) = inbox.take(),
              let share = Self.sharedImport(drop, bytes: bytes) else { return }
        accounts.imports.offer(share)
        router.openInSettings(.imports)
    }

    /// What Import takes from a share: a file read up to the limit, or the text itself named by
    /// the share's subject.
    static func sharedImport(_ drop: ShareDrop, bytes: Data?) -> SharedImport? {
        switch drop.kind {
        case .file:
            let read: ImportFileRead = drop.tooBig ? .tooBig : bytes.map(ImportFileRead.bytes) ?? .unreadable
            return .file(read, name: drop.name, type: drop.type)
        case .text:
            return sharedText(drop.text, subject: drop.name)
        }
    }

    private func openFile(_ url: URL) {
        let type = UTType(filenameExtension: url.pathExtension.lowercased())
        if let type, importFileTypes.contains(where: { type.conforms(to: $0) }) {
            accounts.imports.offer(.file(ImportFiles.read(url), name: url.lastPathComponent, type: type.preferredMIMEType))
            router.openInSettings(.imports)
            return
        }
        // An audio file plays as itself, read from where it is for as long as the app runs.
        Task { await playOpened(url) }
    }

    /// The list types Import takes from another app.
    private let importFileTypes: [UTType] = [.commaSeparatedText, .plainText, .json, .zip]

    /// Plays a file opened from another app: its tags give its title and artist; one that cannot
    /// be read says so.
    func playOpened(_ url: URL) async {
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            router.show("Octo cannot open that file")
            return
        }
        let asset = AVURLAsset(url: url)
        var title: String?
        var artist: String?
        if let metadata = try? await asset.load(.commonMetadata) {
            for item in metadata {
                guard let key = item.commonKey, let value = try? await item.load(.stringValue) else { continue }
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if key == .commonKeyTitle, !trimmed.isEmpty { title = trimmed }
                if key == .commonKeyArtist, !trimmed.isEmpty { artist = trimmed }
            }
        }
        let id = openedFileId(uri: url.absoluteString, title: title ?? titleFromName(url.lastPathComponent) ?? "", artist: artist ?? "")
        guard let song = openedFileSong(id) else {
            router.show("Octo cannot open that file")
            return
        }
        player.play([song], from: 0)
        router.drive = .openPlayer
    }

    // MARK: Quick actions

    /// Hands the quick actions to the Home Screen, each time the app opens, so their names
    /// follow the phone's language.
    func publishShortcuts() {
        UIApplication.shared.shortcutItems = LauncherShortcut.allCases.map { shortcut in
            UIApplicationShortcutItem(type: shortcut.rawValue, localizedTitle: shortcut.label, localizedSubtitle: nil,
                                      icon: UIApplicationShortcutIcon(systemImageName: shortcut.icon))
        }
    }

    /// Plays what a quick action asks for with the widgets' lists, then opens the player; with
    /// nothing to play it says so.
    func run(_ shortcut: LauncherShortcut) async {
        await SystemActions.shared?.run(shortcut)
    }

    // MARK: Clipboard

    /// When the app comes to the front, a family link newly on the clipboard is offered once.
    func checkClipboard() {
        let board = UIPasteboard.general
        guard board.changeCount != lastPasteboard else { return }
        lastPasteboard = board.changeCount
        guard board.hasStrings || board.hasURLs else { return }
        board.detectPatterns(for: [\.probableWebURL]) { [weak self] result in
            guard case .success(let found) = result, !found.isEmpty else { return }
            Task { @MainActor in self?.family.offerClipboard(board.string ?? board.url?.absoluteString) }
        }
    }
}

/// The quick actions on Octo's Home Screen icon, in the order shown.
enum LauncherShortcut: String, CaseIterable {
    case shuffleAll = "shuffle_all"
    case liked
    case recentlyAdded = "recently_added"
    case resume

    var label: String {
        switch self {
        case .shuffleAll: "Shuffle all"
        case .liked: "Liked songs"
        case .recentlyAdded: "Recently added"
        case .resume: "Resume"
        }
    }

    var icon: String {
        switch self {
        case .shuffleAll: "shuffle"
        case .liked: "heart.fill"
        case .recentlyAdded: "square.stack"
        case .resume: "play.fill"
        }
    }
}

/// Where radio stations and opened files play from: their own address, never the server's.
enum QueueItemStreams {
    static func isOwn(_ song: Song) -> Bool { isRadio(song.id) || isOpenedFile(song.id) }

    static func address(of song: Song) -> URL? {
        if let station = radioOf(song.id) { return URL(string: station.stream) }
        if let file = openedFileOf(song.id) { return URL(string: file.uri) }
        return nil
    }
}

/// The app's delegate: quick actions, notices tapped, and the scene that hands them on.
final class OctoAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        if let item = options.shortcutItem, let shortcut = LauncherShortcut(rawValue: item.type) {
            MainActor.assumeIsolated { SystemEntries.shared?.pendingShortcut = shortcut }
        }
        let configuration = UISceneConfiguration(name: nil, sessionRole: session.role)
        configuration.delegateClass = OctoSceneDelegate.self
        return configuration
    }

    /// "Play Drake in Octo" asked of Siri, in the car too, is answered by the app itself.
    func application(_ application: UIApplication, handlerFor intent: INIntent) -> Any? {
        intent is INPlayMediaIntent ? SiriMediaHandler() : nil
    }

    /// Siri hands the request over to play, with the app started in the background if need be.
    func application(_ application: UIApplication, handle intent: INIntent, completionHandler: @escaping (INIntentResponse) -> Void) {
        guard let intent = intent as? INPlayMediaIntent, let actions = SystemActions.shared else {
            completionHandler(INPlayMediaIntentResponse(code: .failure, userActivity: nil))
            return
        }
        let ask = voiceAsk(SiriMediaHandler.request(intent))
        let shuffle = intent.playShuffled == true
        Task {
            let words = await actions.voice(ask)
            // "Shuffle ..." asks for the songs in a random order.
            if words == nil, shuffle, !actions.player.shuffled { actions.player.toggleShuffle() }
            completionHandler(INPlayMediaIntentResponse(code: words == nil ? .success : .failure, userActivity: nil))
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    /// A family notice tapped opens the Family screen.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        completionHandler()
        Task { @MainActor in SystemEntries.shared?.family.open(.family) }
    }
}

final class OctoSceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem) async -> Bool {
        guard let shortcut = LauncherShortcut(rawValue: shortcutItem.type) else { return false }
        await SystemEntries.shared?.run(shortcut)
        return true
    }
}

extension View {
    /// Everything the app answers from outside its screens: addresses opened with it, the
    /// clipboard, quick actions, the share card and the request sheet.
    func systemEntries() -> some View { modifier(SystemEntryHost()) }
}

private struct SystemEntryHost: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(Overlays.self) private var overlays

    func body(content: Content) -> some View {
        content
            .shareCardHost()
            .modifier(FamilyRequestSheetHost())
            .onOpenURL { url in SystemEntries.shared?.open(url) }
            .onAppear { SystemEntries.shared?.overlays = overlays }
            .onChange(of: scenePhase, initial: true) { _, phase in
                guard phase == .active, let entries = SystemEntries.shared else { return }
                entries.publishShortcuts()
                entries.takeShared()
                entries.checkClipboard()
                if let shortcut = entries.pendingShortcut {
                    entries.pendingShortcut = nil
                    Task { await entries.run(shortcut) }
                }
            }
    }
}
