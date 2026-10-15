import OctoKit
import UserNotifications
import SwiftUI

/// Family on the server in use: a manager's requests waiting and members first, then what the
/// account may do in plain words with the library's size, the account's requests, devices and
/// saved songs. The server decides; this shows what it says.
struct FamilyScreen: View {
    @Environment(Accounts.self) private var accounts
    @Environment(Router.self) private var router
    @Environment(Session.self) private var session
    @Environment(\.scenePhase) private var scenePhase
    @State private var changingPassword = false
    @State private var resetting: FamilyMember?

    var body: some View {
        let hub = accounts.family
        let model = hub.model
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ScreenTitle(FamilyText.family)
                if let info = model.info {
                    NoticesRow()
                    if let said = model.said { PanelLine(text: said, color: OctoColor.textSecondary) }
                    if let login = model.login {
                        title(FamilyText.yourLogin)
                        LoginCard(login: login, fallback: hub.serverAddress, changePassword: { changingPassword = true },
                                  showQr: { model.handOver.open() })
                    }
                    if model.approves { inbox(model) }
                    if let manager = info.manager { members(model, manager) }
                    plan(info.me)
                    requests(model)
                    devices(model)
                    saved(hub, me: info.me)
                } else {
                    PanelLine(text: model.problem ?? "Asking the server about your plan.")
                }
            }
            .padding(.top, 8 + detailTopGap)
        }
        .barClearance()
        .onAppear { model.watch() }
        .onDisappear { model.stop() }
        // Renewing the hand-over code pauses while the app is out of sight.
        .onChange(of: scenePhase, initial: true) { _, phase in model.handOver.sheetOnScreen(phase != .background) }
        .opensWhenAsked("reset_password") { resetting = model.info?.manager?.members.first }
        .sheet(isPresented: Binding(get: { model.handOver.sheet != nil }, set: { if !$0 { model.handOver.close() } })) {
            HandOverSheetHost(hub: hub).familySheet()
        }
        .sheet(isPresented: Binding(get: { model.invite != nil }, set: { if !$0 { model.closeInvite() } })) {
            InviteSheetHost(hub: hub).familySheet()
        }
        .sheet(isPresented: $changingPassword) {
            FamilyPasswordSheet(change: hub.changePassword, done: { words in
                changingPassword = false
                router.done(words)
            }, close: { changingPassword = false })
            .familySheet()
        }
    }

    private func title(_ text: String) -> some View {
        SectionTitle(text).padding(.top, 16)
    }

    // MARK: My plan

    @ViewBuilder
    private func plan(_ me: FamilyMe) -> some View {
        let can = me.abilities
        title(FamilyText.myPlan)
        VStack(alignment: .leading, spacing: 6) {
            Text(planTitle(me)).font(.octoBody).foregroundStyle(OctoColor.textPrimary)
            HStack {
                Text("Your library").font(.octoBodySmall).foregroundStyle(OctoColor.textSecondary)
                Spacer()
                Text(storageLine(usedBytes: me.storageUsedBytes, limitGb: can.storageLimitGb)).font(.octoCaption).foregroundStyle(OctoColor.textSecondary)
            }
            if let share = storageShare(usedBytes: me.storageUsedBytes, limitGb: can.storageLimitGb) {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2).fill(OctoColor.textMuted.opacity(0.25))
                        RoundedRectangle(cornerRadius: 2).fill(OctoColor.accent).frame(width: geometry.size.width * share)
                    }
                }
                .frame(height: 3)
            }
            if can.weeklyRequestLimit > 0 || me.requestsThisWeek > 0 {
                Text(weeklyLine(used: me.requestsThisWeek, limit: can.weeklyRequestLimit)).font(.octoCaption).foregroundStyle(OctoColor.textMuted)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
        ForEach(abilityLines(can), id: \.self) { line in
            HStack(spacing: 12) {
                Image(systemName: line.on ? "checkmark" : "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(line.on ? OctoColor.textSecondary : OctoColor.textMuted)
                    .frame(width: 16, height: 16)
                    .accessibilityHidden(true)
                Text(line.text).font(.octoBodySmall).foregroundStyle(line.on ? OctoColor.textPrimary : OctoColor.textMuted)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 6)
        }
        if can.importPlaylists {
            VStack(alignment: .leading, spacing: 8) {
                Text("Get my music").font(.octoBody).foregroundStyle(OctoColor.textPrimary)
                Text("Bring your playlists and liked songs over from Spotify, Apple Music, YouTube Music and more.")
                    .font(.octoCaption)
                    .foregroundStyle(OctoColor.textMuted)
                GlazeButton("Import", size: .small) { router.openInSettings(.imports) }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
        }
    }

    // MARK: Requests, devices, saved

    @ViewBuilder
    private func requests(_ model: FamilyModel) -> some View {
        title(FamilyText.requests)
        if model.requests.isEmpty {
            PanelLine(text: "No requests yet. Ask for a copy of a song found online from its menu: \(FamilyText.requestACopy).")
        }
        ForEach(model.requests) { request in
            FamilyItemLine(title: request.title.isEmpty ? request.target : request.title,
                           line: [request.artist, requestKindLine(request)].filter { !$0.isEmpty }.joined(separator: " · "),
                           state: request, cover: request.coverArt ?? request.target) {
                if request.state == .pending {
                    GlazeButton("Cancel", size: .extraSmall, enabled: !model.working) { model.cancel(request.id) }
                }
            }
        }
    }

    @ViewBuilder
    private func devices(_ model: FamilyModel) -> some View {
        title(FamilyText.devices)
        if model.devices.isEmpty { PanelLine(text: "Apps you sign in to with your login show here by themselves.") }
        ForEach(model.devices) { device in
            FamilyItemLine(title: device.name.isEmpty ? "A device" : device.name, line: deviceLine(device)) {
                if device.current {
                    Text("This phone").font(.octoCaption).foregroundStyle(OctoColor.textMuted)
                } else {
                    GlazeButton(FamilyText.removeFromList, size: .extraSmall, enabled: !model.working) { model.forget(device: device) }
                }
            }
        }
        VStack(alignment: .leading, spacing: 8) {
            Text(FamilyText.signOutEverywhere).font(.octoBody).foregroundStyle(OctoColor.textPrimary)
            Text(FamilyText.signOutEverywhereLine).font(.octoCaption).foregroundStyle(OctoColor.textMuted)
            HStack(spacing: 8) {
                GlazeButton(FamilyText.changePassword, size: .small) { changingPassword = true }
                GlazeButton(HandOverText.title, icon: .qrCode, size: .small) { model.handOver.open() }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func saved(_ hub: FamilyHub, me: FamilyMe) -> some View {
        let saved = hub.model.saved
        title(FamilyText.saved)
        if saved.isEmpty {
            PanelLine(text: "Songs and albums found online that you save show here.")
        } else {
            let asks = outsideActions(me).offersRequest
            ForEach(saved.songs) { song in
                FamilyItemLine(title: song.title, line: [song.artist, song.album].compactMap { $0 }.joined(separator: " · ")) {
                    HStack(spacing: 6) {
                        if asks { GlazeButton("Request", size: .extraSmall) { hub.ask(song.id, title: song.title) } }
                        GlazeButton("Remove", size: .extraSmall) { hub.model.unsave(song.id, album: false) }
                    }
                }
            }
            ForEach(saved.albums) { album in
                FamilyItemLine(title: album.name, line: "Album · \(album.artist)") {
                    HStack(spacing: 6) {
                        if asks { GlazeButton("Request", size: .extraSmall) { hub.ask(album.id, title: album.name) } }
                        GlazeButton("Remove", size: .extraSmall) { hub.model.unsave(album.id, album: true) }
                    }
                }
            }
        }
    }

    // MARK: Managers

    @ViewBuilder
    private func members(_ model: FamilyModel, _ manager: FamilyManager) -> some View {
        title(FamilyText.members)
        if manager.liveStreams > 0 { PanelLine(text: "\(manager.liveStreams) playing now") }
        ForEach(manager.members) { member in
            let name = member.displayName.isEmpty ? member.username : member.displayName
            FamilyItemLine(title: name,
                           line: "\(memberLine(member)) · \(storageLine(usedBytes: member.storageUsedBytes, limitGb: member.storageLimitGb))") {
                GlazeButton(FamilyText.resetPassword, size: .extraSmall, enabled: !model.working) { resetting = member }
                    .confirmationDialog("Reset \(name)'s password?",
                                        isPresented: Binding(get: { resetting?.id == member.id }, set: { if !$0 { resetting = nil } }),
                                        titleVisibility: .visible) {
                        Button(FamilyText.resetPassword, role: .destructive) { model.resetPassword(member) }
                    } message: {
                        Text("Their password stops working at once, on every app and device. You get a new sign-in link to give them, to choose another.")
                    }
            }
        }
        AddMemberBlock(model: model)
    }

    @ViewBuilder
    private func inbox(_ model: FamilyModel) -> some View {
        title(FamilyText.requestsWaiting)
        if model.inbox.isEmpty { PanelLine(text: "Nothing waiting.") }
        ForEach(model.inbox) { request in InboxLine(model: model, request: request) }
    }
}

/// On iPhone notices need the listener's yes; asked here, where it is clear what they are for.
private struct NoticesRow: View {
    @State private var allowed = true
    @Environment(\.openURL) private var openURL

    var body: some View {
        Group {
            if !allowed {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Hear when a request is decided").font(.octoBody).foregroundStyle(OctoColor.textPrimary)
                    Text("Octo can tell you when a request is approved, declined or added, and a manager when requests wait.")
                        .font(.octoCaption)
                        .foregroundStyle(OctoColor.textMuted)
                    GlazeButton("Turn on notices", size: .small) {
                        Task {
                            let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
                            if status == .denied, let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                                openURL(url)
                            } else {
                                allowed = await FamilyNotices.ask()
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
            }
        }
        .task { allowed = await FamilyNotices.allowed() }
    }
}

/// A row of a list: its title, a line under it, a request's state when it is one, and actions
/// at the end.
struct FamilyItemLine<Actions: View>: View {
    let title: String
    let line: String
    var state: FamilyRequest?
    var cover: String?
    @ViewBuilder var actions: Actions

    var body: some View {
        HStack(spacing: 0) {
            if let cover, !cover.isEmpty {
                BadgedCover(id: cover, size: 44, radius: 6, external: cover.hasPrefix("ext-")).padding(.trailing, 12)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.octoBodySmall).foregroundStyle(OctoColor.textPrimary).lineLimit(1)
                if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text(line).font(.octoCaption).foregroundStyle(OctoColor.textMuted).lineLimit(2)
                }
                if let state {
                    Text(requestStateLine(state)).font(.octoCaption).foregroundStyle(stateColor(state.state))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            actions.padding(.leading, 12)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    private func stateColor(_ state: FamilyRequestState) -> Color {
        switch state {
        case .done: OctoColor.signalGreen
        case .declined, .failed: OctoColor.signalOrange
        default: OctoColor.textSecondary
        }
    }
}

/// One waiting request: who asks, for what, a note for them, and the choice.
private struct InboxLine: View {
    let model: FamilyModel
    let request: FamilyRequest
    @State private var note = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 0) {
                let cover = request.coverArt ?? request.target
                if !cover.isEmpty { BadgedCover(id: cover, size: 44, radius: 6, external: cover.hasPrefix("ext-")).padding(.trailing, 12) }
                VStack(alignment: .leading, spacing: 1) {
                    Text(requestTitle(request)).font(.octoBody).foregroundStyle(OctoColor.textPrimary).lineLimit(2)
                    Text("\(request.displayName.isEmpty ? request.username : request.displayName) · \(requestKindLine(request))")
                        .font(.octoCaption)
                        .foregroundStyle(OctoColor.textMuted)
                }
            }
            GlassInput("A note for them (optional)", text: $note)
            HStack(spacing: 8) {
                AccentButton("Approve", size: .small, enabled: !model.working) { model.approve(request.id, note: note) }
                GlazeButton("Decline", size: .small, enabled: !model.working) { model.decline(request.id, note: note) }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }
}

/// A new member: the name the family sees, their username and what they may do. They get an
/// invite as a QR code or a link.
private struct AddMemberBlock: View {
    let model: FamilyModel
    @SceneStorage("family.add.name") private var name = ""
    @SceneStorage("family.add.username") private var username = ""
    @SceneStorage("family.add.preset") private var presetName = FamilyPreset.member.rawValue
    @SceneStorage("family.add.away") private var away = true
    @State private var typingUsername = false

    var body: some View {
        let preset = FamilyPreset(rawValue: presetName) ?? .member
        VStack(alignment: .leading, spacing: 8) {
            Text("Add a member").font(.octoBody).foregroundStyle(OctoColor.textPrimary)
            GlassInput("Their name, like Sam", text: $name, submitLabel: .next) { typingUsername = true }
                .textInputAutocapitalization(.words)
            GlassInput("Username, like sam", text: Binding(get: { username }, set: { username = $0.filter { !$0.isWhitespace }.lowercased() }),
                       focus: $typingUsername)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            HStack(spacing: 6) {
                ForEach(FamilyPreset.allCases, id: \.self) { choice in
                    if choice == preset {
                        AccentButton(OctoKit.presetName(choice), size: .extraSmall) { presetName = choice.rawValue }
                    } else {
                        GlazeButton(OctoKit.presetName(choice), size: .extraSmall) { presetName = choice.rawValue }
                    }
                }
            }
            Text(presetLine(preset)).font(.octoCaption).foregroundStyle(OctoColor.textMuted)
            Button { away.toggle() } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(FamilySheetText.allowAway).font(.octoBodySmall).foregroundStyle(OctoColor.textPrimary)
                        Text(FamilySheetText.allowAwayLine).font(.octoCaption).foregroundStyle(OctoColor.textMuted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    OctoSwitch(isOn: $away).allowsHitTesting(false).accessibilityHidden(true)
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(FamilySheetText.allowAway)
            .accessibilityValue(away ? "On" : "Off")
            .accessibilityAddTraits(.isToggle)
            AccentButton("Add and show their invite", size: .small,
                         enabled: !username.trimmingCharacters(in: .whitespaces).isEmpty && !model.working) {
                model.addMember(username: username, displayName: name, preset: preset, away: away)
                username = ""
                name = ""
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }
}

/// The hand-over sheet while the source has one, following its new codes.
private struct HandOverSheetHost: View {
    let hub: FamilyHub

    var body: some View {
        let model = hub.model
        if let sheet = model.handOver.sheet {
            HandOverSheetView(source: model.handOver, sheet: sheet, awayAllowed: model.me?.abilities.away != false,
                              server: hub.serverAddress,
                              avatarName: (model.me?.displayName).flatMap { $0.isEmpty ? nil : $0 } ?? (model.me?.username ?? ""),
                              owner: model.me?.role == .owner,
                              username: (model.me?.username).flatMap { $0.isEmpty ? nil : $0 })
                .id(sheet.id)
        }
    }
}

/// The invite sheet while the family has one open.
private struct InviteSheetHost: View {
    let hub: FamilyHub

    var body: some View {
        let model = hub.model
        if let invite = model.invite {
            InviteSheetView(invite: invite, server: hub.serverAddress, owner: model.me?.role == .owner,
                            newLink: model.sendNewLink, done: model.closeInvite)
        }
    }
}

/// The request sheet, over everything: which quality, the week's requests left, and whether the
/// library is full. Opened from a song's menu and from Saved.
struct FamilyRequestSheetHost: ViewModifier {
    @Environment(Accounts.self) private var accounts

    func body(content: Content) -> some View {
        let hub = accounts.family
        content.sheet(item: Binding(get: { hub.me == nil ? nil : hub.asking }, set: { if $0 == nil { hub.closeSheet() } })) { ask in
            if let me = hub.me {
                RequestSheetBody(hub: hub, ask: ask, sheet: requestSheet(me))
                    .padding(.top, 24)
                    .fittedSheet()
            }
        }
    }
}

extension View {
    /// A family sheet: as tall as the screen allows, with its handle showing, its own header
    /// and footer inside.
    func familySheet() -> some View {
        padding(.top, 16)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
    }
}

private struct RequestSheetBody: View {
    let hub: FamilyHub
    let ask: CopyAsk
    let sheet: RequestSheet
    @State private var picked: RequestQuality?

    var body: some View {
        let chosen = picked ?? sheet.initial
        VStack(alignment: .leading, spacing: 0) {
                Text(FamilyText.requestACopy).font(.octoSection).foregroundStyle(OctoColor.textPrimary).padding(.horizontal, 20)
                    .accessibilityAddTraits(.isHeader)
                Text(ask.title).font(.octoBodySmall).foregroundStyle(OctoColor.textSecondary).padding(.horizontal, 20).padding(.vertical, 4)
                ForEach(sheet.choices, id: \.self) { choice in
                    Button { picked = choice.quality } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(choice.label).font(.octoBody).foregroundStyle(choice.enabled ? OctoColor.textPrimary : OctoColor.textMuted)
                                Text(choice.detail).font(.octoCaption).foregroundStyle(OctoColor.textMuted)
                            }
                            Spacer()
                            if chosen == choice.quality {
                                Image(systemName: "checkmark").font(.system(size: 15, weight: .semibold)).foregroundStyle(OctoColor.textPrimary)
                                    .accessibilityLabel("Picked")
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!choice.enabled)
                    .accessibilityAddTraits(chosen == choice.quality ? .isSelected : [])
                }
                VStack(alignment: .leading, spacing: 4) {
                    if let line = sheet.storageLine { Text(line).font(.octoCaption).foregroundStyle(OctoColor.signalOrange) }
                    if let line = sheet.quotaLine { Text(line).font(.octoCaption).foregroundStyle(OctoColor.textSecondary) }
                    Text(sheet.approvalLine).font(.octoCaption).foregroundStyle(OctoColor.textMuted)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                AccentButton("Request", fillWidth: true) { hub.request(ask, quality: chosen) }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
        }
    }
}
