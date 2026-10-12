import OctoKit
import SwiftUI

/// What Octo is doing, from its own admin pages on the home network: its health and its
/// services', the stations and how far they have learned, the latest downloads, and where
/// downloads land. Everything else is on the full admin pages.
struct OctoAdminScreen: View {
    @Environment(Session.self) private var session
    @Environment(\.openURL) private var openURL
    @State private var model: OctoAdminModel?
    @SceneStorage("admin.showAll") private var showAll = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ScreenTitle("Octo admin")
                if let model { content(model) }
            }
            .padding(.top, 8 + detailTopGap)
        }
        .refreshable { await model?.refresh() }
        .barClearance()
        .onAppear {
            guard model == nil else { return }
            let made = OctoAdminModel(admin: OctoAdminPages.shared, signIn: { [session] in OctoAdminPages.signIn(session) })
            model = made
            made.open()
        }
        .onChange(of: session.activeId) { model?.serverChanged() }
        .onDisappear { model?.stop() }
    }

    @ViewBuilder
    private func content(_ model: OctoAdminModel) -> some View {
        switch model.place {
        case .looking:
            LoadingSpinner(size: 22).frame(maxWidth: .infinity).padding(.top, 24)
        case .away:
            VStack(spacing: 16) {
                Text("Octo's admin is only available on your home network")
                    .font(.octoBodySmall)
                    .foregroundStyle(OctoColor.textSecondary)
                    .multilineTextAlignment(.center)
                AccentButton("Try again", action: model.tryAgain)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 32)
            .padding(.vertical, 48)
        case .found:
            health(model)
            stations(model)
            downloads(model)
            library(model)
            openFull(model)
        }
    }

    private func sectionTitle(_ text: String, extra: CGFloat) -> some View {
        SectionTitle(text).padding(.top, extra)
    }

    @ViewBuilder
    private func section<T>(_ load: AdminLoad<T>, @ViewBuilder ready: (T) -> some View) -> some View {
        switch load {
        case .loading: LoadingSpinner(size: 22).frame(maxWidth: .infinity).padding(.vertical, 8)
        case .failed(let words): note(words)
        case .ready(let value): ready(value)
        }
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.octoBodySmall).foregroundStyle(OctoColor.textMuted).padding(.horizontal, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Health

    @ViewBuilder
    private func health(_ model: OctoAdminModel) -> some View {
        sectionTitle("Health", extra: 8)
        section(model.status) { status in
            HealthRow(name: "Octo", health: status.octo)
            ForEach(status.services, id: \.key) { service in HealthRow(name: serviceName(service.key), health: service.health) }
        }
    }

    // MARK: Stations

    @ViewBuilder
    private func stations(_ model: OctoAdminModel) -> some View {
        sectionTitle("Stations", extra: 18)
        section(model.radio) { radio in
            if !radio.enabled {
                note("Stations are switched off in Octo")
            } else {
                if let learning = radio.learning {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(learningLine(learning)).font(.octoBodySmall).foregroundStyle(OctoColor.textPrimary)
                        Text(adminAgo(learning.lastRefreshSuccessUtc, nowMs: epochNowMs()).map { "Last refreshed \($0)" } ?? "Not refreshed yet")
                            .font(.octoCaption)
                            .foregroundStyle(OctoColor.textMuted)
                        if let problem = refreshProblem(learning.lastRefreshError) {
                            Text(problem).font(.octoCaption).foregroundStyle(OctoColor.error).lineLimit(2)
                        }
                    }
                    .padding(.horizontal, 20)
                }
                if radio.stations.isEmpty { note("No stations yet") }
                ForEach(Array(radio.stations.enumerated()), id: \.offset) { _, station in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(station.name).font(.octoBodySmall).foregroundStyle(OctoColor.textPrimary).lineLimit(1)
                        Text(stationSongs(station.trackCount)).font(.octoCaption).foregroundStyle(OctoColor.textMuted)
                    }
                    .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                    .padding(.horizontal, 20)
                    .accessibilityElement(children: .combine)
                }
                let busy = model.refreshingStations || radio.learning?.refreshing == true
                GlazeButton(busy ? "Refreshing" : "Refresh stations", enabled: !busy, action: model.refreshStations)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                if let problem = model.stationsProblem {
                    Text(problem).font(.octoCaption).foregroundStyle(OctoColor.error).padding(.horizontal, 20).padding(.top, 4)
                }
            }
        }
    }

    // MARK: Downloads

    @ViewBuilder
    private func downloads(_ model: OctoAdminModel) -> some View {
        sectionTitle("Downloads", extra: 18)
        section(model.downloads) { records in
            if records.isEmpty {
                note("Nothing downloaded yet")
            } else {
                let now = epochNowMs()
                ForEach(Array((showAll ? records : Array(records.prefix(30))).enumerated()), id: \.offset) { _, record in
                    DownloadRow(record: record, nowMs: now)
                }
                if records.count > 30 {
                    GlazeButton(showAll ? "Show fewer" : "Show all") { showAll.toggle() }
                        .padding(.leading, 20)
                        .padding(.top, 8)
                }
            }
        }
    }

    // MARK: Library

    @ViewBuilder
    private func library(_ model: OctoAdminModel) -> some View {
        sectionTitle("Library", extra: 18)
        section(model.library) { status in
            VStack(alignment: .leading, spacing: 6) {
                if !status.effectiveDownloadPath.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text(status.effectiveDownloadPath).font(.system(size: 12, design: .monospaced)).foregroundStyle(OctoColor.textMuted)
                }
                let problems = libraryProblems(status)
                if problems.isEmpty {
                    Text("Downloads go straight into your library").font(.octoBodySmall).foregroundStyle(OctoColor.textSecondary)
                }
                ForEach(problems, id: \.self) { problem in
                    Text(problem).font(.octoBodySmall).foregroundStyle(OctoColor.error)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func openFull(_ model: OctoAdminModel) -> some View {
        Button {
            if let url = model.pageUrl { openURL(url) }
        } label: {
            HStack {
                Text("Open full admin").font(.octoBody).foregroundStyle(OctoColor.textPrimary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 22, height: 22)
                    .foregroundStyle(OctoColor.textMuted)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 20)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, 18)
    }
}

/// One service's health: its dot, its name and what it says.
private struct HealthRow: View {
    let name: String
    let health: AdminHealth

    var body: some View {
        let dot = healthDot(health)
        HStack(alignment: .top, spacing: 14) {
            Circle()
                .fill(color(dot))
                .frame(width: 8, height: 8)
                .padding(.top, 6)
                .accessibilityLabel(word(dot))
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.octoBodySmall).foregroundStyle(dot == .notSetUp ? OctoColor.textMuted : OctoColor.textPrimary)
                let detail = dot == .notSetUp ? "Not set up" : health.detail
                if !detail.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text(detail).font(.octoCaption).foregroundStyle(OctoColor.textMuted).lineLimit(3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    private func color(_ dot: HealthDot) -> Color {
        switch dot {
        case .ok: Color(hex: 0x8FBFA0)
        case .warning: Color(hex: 0xE3B35B)
        case .down: OctoColor.error
        case .notSetUp: OctoColor.accent.opacity(0.3)
        }
    }

    private func word(_ dot: HealthDot) -> String {
        switch dot {
        case .ok: "Working"
        case .warning: "Needs a look"
        case .down: "Not working"
        case .notSetUp: "Not set up"
        }
    }
}

/// A song Octo downloaded: its cover, title, who it is by and the kind of file, and when.
private struct DownloadRow: View {
    let record: DownloadRecord
    let nowMs: Int64

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(OctoColor.backgroundTertiary)
                if let cover = record.coverArtUrl, let url = URL(string: cover) {
                    AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: { Color.clear }
                        .accessibilityHidden(true)
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 1) {
                Text(record.title).font(.octoBodySmall).foregroundStyle(OctoColor.textPrimary).lineLimit(1)
                Text(downloadLine(record)).font(.octoCaption).foregroundStyle(OctoColor.textMuted).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let when = adminAgo(record.downloadedAt, nowMs: nowMs) {
                Text(when).font(.octoCaption).foregroundStyle(OctoColor.textMuted)
            }
        }
        .padding(.horizontal, 20)
        .frame(minHeight: 56)
    }
}

/// Where the admin pages were found, kept per server on the phone, and who is asking.
@MainActor
enum OctoAdminPages {
    static let shared = OctoAdmin(store: AdminPrefsStore())

    static func signIn(_ session: Session) -> AdminSignIn? {
        guard let client = session.client, let server = session.active else { return nil }
        return AdminSignIn(server: server.id, client: client, primary: server.address, keptServers: session.servers.count)
    }
}

/// The "octo_admin" store for the addresses found.
struct AdminPrefsStore: AdminAddressStore {
    private let prefs = Prefs("octo_admin")

    func string(_ key: String) -> String? { prefs.string(key) }
    func set(_ value: String?, _ key: String) { prefs.set(value, key) }
}
