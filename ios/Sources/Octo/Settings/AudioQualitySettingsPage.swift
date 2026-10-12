import OctoKit
import SwiftUI

/// The account's own quality on an Octo server with Family on, and who picks this phone's.
/// Read at start and whenever the account in use changes, so the page usually opens with it known.
@MainActor
@Observable
final class AccountQualityModel {
    static let shared = AccountQualityModel()

    /// The account's quality and the family's limits, once read.
    private(set) var quality: AccountQuality?
    /// Who picks this phone's quality, once this phone is found in the account's devices.
    private(set) var follows: QualityFollows?
    private(set) var deviceId: String?
    /// What went wrong with the last change, in words. The page does not show it.
    private(set) var problem: String?

    @ObservationIgnored private weak var session: Session?
    @ObservationIgnored private var readFor: String?

    private init() {}

    /// Whether the server in use has Family on.
    var familyOn: Bool {
        guard let session, session.client != nil else { return false }
        if let profile = session.profile { return profile.lists(octoFamilyExtension, version: 1) }
        return session.active?.extensions.contains("\(octoFamilyExtension):1") ?? false
    }

    /// Whether this app's own stream size applies now.
    var appPicks: Bool { AccountQualityWords.appPicksQuality(familyOn: familyOn, follows: follows) }

    func attach(_ session: Session) {
        self.session = session
    }

    /// Reads the account unless it was already read for this account.
    func load(force: Bool = false) async {
        guard let session, let client = session.client, familyOn else {
            quality = nil
            follows = nil
            deviceId = nil
            readFor = nil
            AppSettings.shared.applyQuality()
            return
        }
        let account = session.activeId
        if !force, readFor == account, quality != nil { return }
        if readFor != account {
            // Another account: nothing of the last one's stays, so until this one is read the
            // page shows only this app's quality and streams ask for the file as it is.
            quality = nil
            follows = nil
            deviceId = nil
            readFor = account
            AppSettings.shared.applyQuality()
        }
        guard let read = try? await client.accountQuality(), session.activeId == account else { return }
        quality = read
        let devices = try? await client.qualityDevices()
        guard session.activeId == account else { return }
        if let devices {
            // A list without this phone in it leaves its mode unknown.
            let me = devices.first(where: \.current)
            follows = me?.quality
            deviceId = me?.id
        }
        AppSettings.shared.applyQuality()
    }

    /// Sets the account's quality at home or away. The row changes once the server answers.
    func setQuality(home: AccountStreamQuality? = nil, away: AccountStreamQuality? = nil) async {
        guard let client = session?.client else { return }
        do {
            quality = try await client.setAccountQuality(home: home, away: away)
            problem = nil
        } catch {
            problem = Self.words(error)
        }
        await load(force: true)
    }

    /// Sets who picks this phone's quality; the row changes at once.
    func setFollows(_ mode: QualityFollows) async {
        guard let client = session?.client, let deviceId else { return }
        follows = mode
        AppSettings.shared.applyQuality()
        do {
            try await client.setQualityFollows(deviceId: deviceId, mode)
            problem = nil
        } catch {
            problem = Self.words(error)
        }
        await load(force: true)
    }

    private static func words(_ error: Error) -> String {
        if error is URLError { return "Octo can't reach the server right now." }
        if case OctoError.server(_, let message) = error, !message.isEmpty { return message }
        return "The server said no."
    }
}

/// Audio quality: with Family on, the account's own quality at home and away (kept on the server
/// for every app), the family's limits in plain words, and who picks this phone's quality. Then
/// this app's own quality on Wi-Fi and on mobile data.
struct AudioQualitySettingsPage: View {
    var highlight: String?
    @State private var settings = AppSettings.shared
    @State private var model = AccountQualityModel.shared

    var body: some View {
        let familyOn = model.familyOn
        let me = familyOn ? model.quality : nil
        let wifiLimit = me?.homeLimit ?? 0
        let mobileLimit = me?.awayLimit ?? 0
        SettingsPageFrame(title: SettingsPage.audioQuality.title, highlight: highlight) {
            if let me {
                SettingsGroup(title: "Your account, on every app", icon: SettingsIcon.listeners) {
                    ForEach(me.limitLines, id: \.self) { NoteRow($0, color: OctoColor.signalOrange) }
                    ChoiceRow(SettingsIndex.accountHome, value: me.home.name,
                              question: accountQuestion(AccountQualityWords.atHome, me.home, limit: me.homeLimit) { quality in
                                  Task { await model.setQuality(home: quality) }
                              })
                    ChoiceRow(SettingsIndex.accountAway, value: me.away.name,
                              question: accountQuestion(AccountQualityWords.away, me.away, limit: me.awayLimit) { quality in
                                  Task { await model.setQuality(away: quality) }
                              })
                }
                if let follows = model.follows {
                    SettingsGroup(title: AccountQualityWords.onThisDevice, icon: SettingsIcon.phone) {
                        ChoiceRow(SettingsIndex.deviceQuality, value: follows.name, question: SettingsQuestion(
                            AccountQualityWords.onThisDevice, QualityFollows.allCases, current: follows,
                            answer: { SettingsAnswer($0.name, $0.line) }, pick: { mode in Task { await model.setFollows(mode) } }))
                    }
                }
            }
            SettingsGroup(title: familyOn ? "This app's quality" : "Streaming", icon: SettingsIcon.wifi) {
                if !model.appPicks {
                    NoteRow("Your account's choice applies now. These apply when this phone is left to the app.")
                }
                ChoiceRow(SettingsIndex.streamWifi, value: settings.stream.wifi.label,
                          question: streamQuestion(SettingsIndex.streamWifi.title, settings.stream.wifi, limit: wifiLimit, pick: settings.setStreamWifi))
                ChoiceRow(SettingsIndex.streamMobile, value: settings.stream.mobile.label,
                          question: streamQuestion(SettingsIndex.streamMobile.title, settings.stream.mobile, limit: mobileLimit,
                                                   pick: settings.setStreamMobile))
            }
        }
        .task { await model.load() }
    }

    /// A family quality as its list shows it: Original says what it is, a bitrate above the
    /// family's limit says it plays at the limit, and Original under a limit cannot be picked.
    private func accountQuestion(_ title: String, _ current: AccountStreamQuality, limit: Int,
                                 pick: @escaping (AccountStreamQuality) -> Void) -> SettingsQuestion {
        let options = AccountQualityWords.options(limitKbps: limit)
        return SettingsQuestion(title: title, answers: options.map { option in
            if let blocked = option.blocked { return SettingsAnswer(AccountQualityWords.originalLabel, blocked, enabled: false) }
            if option.quality == .original { return SettingsAnswer(AccountQualityWords.originalLabel) }
            if option.limited { return SettingsAnswer(option.name, "Plays at \(limit) kbps, your family's limit") }
            return SettingsAnswer(option.name, option.line)
        }, selected: options.firstIndex { $0.quality == current } ?? -1) { pick(options[$0].quality) }
    }

    /// A stream size as its list shows it, with roughly how much data an hour uses. Under a family
    /// limit Original cannot be picked and says why.
    private func streamQuestion(_ title: String, _ current: StreamQuality, limit: Int, pick: @escaping (StreamQuality) -> Void) -> SettingsQuestion {
        SettingsQuestion(title, StreamQuality.allCases, current: current, answer: { quality in
            guard quality.kbps != nil else {
                if let blocked = AccountQualityWords.originalBlocked(by: limit) {
                    return SettingsAnswer(StreamQuality.originalLabel, blocked, enabled: false)
                }
                return SettingsAnswer(StreamQuality.originalLabel)
            }
            return SettingsAnswer(quality.label, SettingsWords.streamDetail(quality))
        }, pick: pick)
    }
}
