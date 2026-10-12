import BackgroundTasks
import Foundation
import OctoKit
import UserNotifications

/// Family requests checked in the background: once when the server comes into use, then about
/// every half hour as iOS allows, posting a notice for each decision and, for a manager, the
/// requests waiting.
@MainActor
enum FamilyNotices {
    /// The background refresh the checks run in.
    static let taskId = "app.winters.octo.family-notices"
    /// Set at launch, so a check in the background finds the signed-in server.
    static weak var session: Session?

    /// Starts the checks for a server with Family on: one now, then every 30 minutes.
    static func schedule() {
        Task { await check() }
        scheduleNext()
    }

    /// A server without Family, or none: no checks.
    static func cancel() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskId)
    }

    static func scheduleNext() {
        let request = BGAppRefreshTaskRequest(identifier: taskId)
        request.earliestBeginDate = Date(timeIntervalSinceNow: Double(familyCheckMs) / 1_000)
        try? BGTaskScheduler.shared.submit(request)
    }

    /// One look at the family's requests: what to tell this account, posted, and remembered.
    static func check() async {
        for _ in 0..<80 where session?.client == nil { try? await Task.sleep(for: .milliseconds(250)) }
        guard let session, session.family, let client = session.client, let account = session.activeId else { return }
        let store = FamilyNoticeStore()
        guard let (notices, memory) = try? await checkFamilyNotices(client, memory: store.read(account)) else { return }
        store.write(account, memory)
        await post(notices)
    }

    /// Nothing posts without permission or with no notices. Each notice replaces the earlier one
    /// about the same request, or the waiting count.
    static func post(_ notices: [FamilyNotice]) async {
        guard !notices.isEmpty else { return }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        for notice in notices {
            let content = UNMutableNotificationContent()
            content.title = notice.title
            content.body = notice.text
            content.threadIdentifier = "family"
            content.userInfo = ["open": "family"]
            try? await center.add(UNNotificationRequest(identifier: notice.key, content: content, trigger: nil))
        }
    }

    /// Whether notices may be posted now.
    static func allowed() async -> Bool {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        return status == .authorized || status == .provisional || status == .ephemeral
    }

    /// Asks for permission to post; answers whether it is given.
    static func ask() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }
}
