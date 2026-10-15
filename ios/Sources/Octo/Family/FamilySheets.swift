import OctoKit
import SwiftUI

/// A new member's invite, or the new sign-in link after a password reset: the QR code of the
/// link for where they will use it, the link itself, what happens next, and a new link.
struct InviteSheetView: View {
    let invite: InviteSheet
    let server: String
    let owner: Bool
    let newLink: () -> Void
    let done: () -> Void
    @State private var picked: LinkReach?

    var body: some View {
        let options = invite.options
        let reach = picked ?? options.defaultReach
        let url = options.linkFor(reach)
        VStack(spacing: 0) {
            SheetHeader(name: invite.name, title: invite.title, subtitle: FamilySheetText.inviteSubtitle, close: done)
            GeometryReader { geometry in
                SheetScrollArea(target: "then") {
                    if options.choosable {
                        ReachChooser(question: reachQuestion(own: false), reach: reach, options: options, owner: owner, server: server) { picked = $0 }
                    }
                    if url != nil || invite.loading || invite.url == nil {
                        let side = qrSide(geometry.size.width - 40)
                        VStack(spacing: 6) {
                            if let url {
                                QrWell(link: url, label: "QR code for \(invite.name)'s invite link", side: side)
                                Text(inviteCaption(invite.name)).font(.octoCaption).foregroundStyle(OctoColor.textMuted).multilineTextAlignment(.center)
                            } else {
                                QrPlaceholder(side: side + 16)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    if let url { SheetSection(label: "Open the link") { SheetLinkRow(url: url) } }
                    SheetSection(label: "Then") {
                        Text(inviteNext(invite.name)).font(.octoBodySmall).foregroundStyle(OctoColor.textPrimary).id("then")
                        if let error = invite.error { Text(error).font(.octoCaption).foregroundStyle(OctoColor.signalOrange) }
                    }
                }
            }
            SheetFooter(done: done) {
                Button(action: newLink) {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.up").font(.system(size: 14))
                        Text(FamilySheetText.sendNewLink).font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(OctoColor.accentHover)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .disabled(invite.loading)
                .opacity(invite.loading ? 0.5 : 1)
            }
        }
        .id(invite.username)
    }
}

/// "Sign in on another device": the QR code that hands this phone's sign-in to another device
/// of the same person, renewed while it shows, and the question when a device scans it.
struct HandOverSheetView: View {
    let source: HandOverSource
    let sheet: HandOverSheet
    let awayAllowed: Bool
    let server: String
    let avatarName: String
    let owner: Bool
    let username: String?
    @State private var now = Date()
    @State private var picked: LinkReach?
    @State private var notice = false

    var body: some View {
        if let asking = sheet.asking {
            AskingView(asking: asking, sending: sheet.sending, allow: source.allow, deny: source.deny)
        } else {
            codeBody
        }
    }

    private var codeBody: some View {
        let start = sheet.start
        let seconds = secondsLeft(start?.expires, nowMs: Int64(now.timeIntervalSince1970 * 1_000))
        let ended = sheet.done != nil || sheet.failed != nil
        let subtitle = if sheet.done != nil { "Handed over" } else if sheet.waiting { "Making a code" } else if sheet.stale { "This code expired" } else { countdownLine(seconds) }
        let warn = start != nil && !sheet.stale && !ended && countdownWarns(seconds)
        let options = sheet.options(awayAllowed: awayAllowed, username: username)
        let reach = picked ?? options?.defaultReach ?? .anywhere
        return VStack(spacing: 0) {
            SheetHeader(name: avatarName, title: HandOverText.title, subtitle: subtitle,
                        subtitleColor: warn ? OctoColor.signalOrange : OctoColor.textMuted, clock: !ended, close: source.close)
            GeometryReader { geometry in
                SheetScrollArea(target: "what") {
                    let side = qrSide(geometry.size.width - 40)
                    if let done = sheet.done {
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark").font(.system(size: 16, weight: .semibold)).foregroundStyle(OctoColor.signalGreen)
                                .frame(width: 32, height: 32).background(OctoColor.signalGreen.opacity(0.18), in: Circle())
                            Text(done).font(.octoBodySmall).foregroundStyle(OctoColor.textPrimary)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AccountColor.fill, in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(OctoColor.hairline))
                    } else if let failed = sheet.failed {
                        ProblemCard(words: failed, retry: source.newCode)
                    } else if let error = sheet.error, start == nil {
                        ProblemCard(words: error, retry: source.retry)
                    } else if let options {
                        if options.choosable {
                            ReachChooser(question: reachQuestion(own: true), reach: reach, options: options, owner: owner, server: server) { picked = $0 }
                        }
                        codeAndLink(options.linkFor(reach), side: side)
                    } else {
                        QrPlaceholder(side: side + 16, label: "Making a code").frame(maxWidth: .infinity)
                    }
                }
            }
            SheetFooter(done: source.close) { EmptyView() }
        }
        .task {
            while !Task.isCancelled {
                let ms = Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 1)
                try? await Task.sleep(for: .seconds(1 - ms))
                now = Date()
                if start != nil, !sheet.stale, !ended, let words = countdownAnnouncement(secondsLeft(sheet.start?.expires, nowMs: Int64(now.timeIntervalSince1970 * 1_000))) {
                    if words != lastAnnounced { UIAccessibility.post(notification: .announcement, argument: words) }
                    lastAnnounced = words
                }
            }
        }
        .task(id: sheet.renewed) {
            guard sheet.renewed > 0 else { return }
            withAnimation(.easeInOut(duration: 0.2)) { notice = true }
            UIAccessibility.post(notification: .announcement, argument: FamilySheetText.newCode)
            try? await Task.sleep(for: .milliseconds(FamilySheetText.newCodeMs))
            withAnimation(.easeInOut(duration: 0.2)) { notice = false }
        }
    }

    @State private var lastAnnounced: String?

    @ViewBuilder
    private func codeAndLink(_ link: String?, side: CGFloat) -> some View {
        if let link {
            VStack(spacing: 6) {
                QrWell(link: link, label: "QR code to sign in on another device", side: side, dim: sheet.stale, tag: "family-sheet-qr") {
                    if sheet.stale {
                        VStack(spacing: 10) {
                            Text(FamilySheetText.stillThere).font(.octoBody).foregroundStyle(OctoColor.textPrimary)
                            AccentButton(FamilySheetText.makeNewCode, size: .small, bright: true, action: source.newCode)
                        }
                    }
                }
                ZStack {
                    if notice {
                        HStack(spacing: 5) {
                            Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold))
                            Text(FamilySheetText.newCode).font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(OctoColor.textPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 2)
                        .background(OctoColor.accentSelected, in: Capsule())
                        .transition(.opacity)
                    } else {
                        Text(HandOverText.caption).font(.octoCaption).foregroundStyle(OctoColor.textMuted).multilineTextAlignment(.center).transition(.opacity)
                    }
                }
                .frame(minHeight: 18)
            }
            .frame(maxWidth: .infinity)
            SheetSection(label: "Or open this link on it") { SheetLinkRow(url: link) }
        }
        SheetSection(label: "What happens") {
            NumberedSteps(steps: [
                "The new device scans this code or opens the link.",
                "This phone asks you to allow it.",
                "Your sign-in goes over sealed. The server can't read it.",
            ])
        }
        .id("what")
        if sheet.refreshFailed {
            Text(FamilySheetText.renewFailed).font(.octoCaption).foregroundStyle(OctoColor.signalOrange)
        }
    }
}

/// A device scanned the code: its name large, its platform, and Allow or Deny.
struct AskingView: View {
    let asking: FamilySignInPending
    let sending: Bool
    let allow: () -> Void
    let deny: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                Image(systemName: "iphone")
                    .font(.system(size: 26))
                    .foregroundStyle(OctoColor.textPrimary)
                    .frame(width: 64, height: 64)
                    .background(OctoColor.accentSelected, in: Circle())
                Text("Sign in on").font(.octoCaption).foregroundStyle(OctoColor.textMuted)
                Text(asking.deviceName.trimmingCharacters(in: .whitespaces).isEmpty ? "A new device" : asking.deviceName)
                    .font(.octoTitle)
                    .foregroundStyle(OctoColor.textPrimary)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                if !asking.platform.isEmpty { Text(asking.platform).font(.octoBody).foregroundStyle(OctoColor.textSecondary) }
                Text("It gets your sign-in for this server. Allow it only if this device is yours.")
                    .font(.octoCaption)
                    .foregroundStyle(OctoColor.textMuted)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
            Spacer(minLength: 0)
            SoftHairline()
            HStack(spacing: 10) {
                GlazeButton(HandOverText.deny, size: .medium, enabled: !sending, fillWidth: true, action: deny)
                AccentButton(HandOverText.allow, size: .medium, bright: true, loading: sending, fillWidth: true, action: allow)
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 12)
        }
        .onAppear { UIAccessibility.post(notification: .announcement, argument: askingTitle(asking)) }
    }
}

/// Changing a family member's password: the current one, the new one twice with how strong it
/// looks. It signs every other app and device out.
struct FamilyPasswordSheet: View {
    let change: (String, String) async -> PasswordChange
    let done: (String) -> Void
    let close: () -> Void
    @State private var draft = PasswordDraft()
    @State private var busy = false
    @State private var problem: String?
    /// The field with the focus, by its place.
    @State private var typing: Int?

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: FamilyText.changePassword, subtitle: FamilyText.signOutEverywhereLine, clock: false, close: close)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    field("Current password", $draft.current, 0)
                    field("New password, at least \(minPassword) characters", $draft.new, 1)
                    if let strength = passwordStrength(draft.new) { Text(strength).font(.octoCaption).foregroundStyle(OctoColor.textMuted) }
                    field("New password again", $draft.confirm, 2)
                    if let problem { Text(problem).font(.octoCaption).foregroundStyle(OctoColor.error) }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 6)
            }
            SoftHairline()
            HStack(spacing: 10) {
                GlazeButton("Cancel", size: .medium, enabled: !busy, fillWidth: true, action: close)
                AccentButton(FamilyText.changePassword, size: .medium, bright: true, loading: busy, fillWidth: true, action: go)
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 12)
        }
    }

    /// One password field; Next hands the focus to the field after it, Done on the last sends.
    private func field(_ placeholder: String, _ text: Binding<String>, _ index: Int) -> some View {
        GlassInput(placeholder, text: Binding(get: { text.wrappedValue }, set: { text.wrappedValue = $0; problem = nil }), secure: true,
                   submitLabel: index == 2 ? .done : .next,
                   focus: Binding(get: { typing == index }, set: { now in if now { typing = index } else if typing == index { typing = nil } })) {
            if index == 2 { go() } else { typing = index + 1 }
        }
        .textContentType(index == 0 ? .password : .newPassword)
    }

    private func go() {
        if let problem = passwordDraftProblem(draft) {
            self.problem = problem
            return
        }
        busy = true
        problem = nil
        let draft = draft
        Task {
            let result = await change(draft.current, draft.new)
            busy = false
            if result == .changed { done(passwordChangeWords(result, family: true)) } else { problem = passwordChangeWords(result, family: true) }
        }
    }
}

/// Your login: the server's addresses and the username, each with a copy button, and the
/// password, changed from here. Under it, signing in on another device, opening it in Octo, and
/// how to use it in each app.
struct LoginCard: View {
    let login: FamilyLogin
    let fallback: String
    let changePassword: () -> Void
    let showQr: () -> Void
    @State private var open: String? = "Octo"

    var body: some View {
        let anywhere = login.anywhereAvailable && login.awayAllowed ? login.servers.anywhere : nil
        let home = login.servers.home
        let main = anywhere ?? home ?? fallback
        VStack(alignment: .leading, spacing: 10) {
            SoftCard {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Server").font(.octoCaption).foregroundStyle(OctoColor.textMuted)
                    HStack(spacing: 0) {
                        MonoValue(text: main)
                        CopyButton(value: main, name: "Copy server")
                    }
                    if let anywhere, let home, home != anywhere {
                        HStack(spacing: 0) {
                            Text("At home: ").font(.octoCaption).foregroundStyle(OctoColor.textMuted)
                            MonoValue(text: home)
                            CopyButton(value: home, name: "Copy home address")
                        }
                    }
                    if anywhere == nil && home != nil {
                        Text(FamilyText.homeOnlyLogin).font(.octoCaption).foregroundStyle(OctoColor.textMuted).padding(.bottom, 4)
                    }
                }
                .padding(.leading, 14)
                .padding(.trailing, 2)
                .padding(.top, 8)
                .padding(.bottom, 6)
                SoftHairline()
                HStack(spacing: 0) {
                    Text("Username").font(.octoCaption).foregroundStyle(OctoColor.textMuted).frame(width: 84, alignment: .leading)
                    MonoValue(text: login.username)
                    CopyButton(value: login.username, name: "Copy username")
                }
                .frame(minHeight: 46)
                .padding(.leading, 14)
                .padding(.trailing, 2)
                SoftHairline()
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Password").font(.octoCaption).foregroundStyle(OctoColor.textMuted)
                        Text(FamilyText.passwordLine).font(.octoBodySmall).foregroundStyle(OctoColor.textPrimary)
                    }
                    Spacer()
                    GlazeButton(FamilyText.changePassword, size: .small, action: changePassword)
                }
                .padding(.leading, 14)
                .padding(.trailing, 10)
                .padding(.vertical, 8)
            }
            HStack(spacing: 8) {
                AccentButton(HandOverText.title, icon: .qrCode, size: .small, bright: true, action: showQr)
                GlazeButton(FamilyText.openInOcto, size: .small) {
                    let link = FamilyLink.prefill(FamilySignInPrefill(server: main, username: login.username, home: home.flatMap { $0 == main ? nil : $0 }))
                    SystemEntries.shared?.family.open(.join(link))
                }
            }
            Text(FamilyText.useInAnyApp).font(.system(size: 12, weight: .semibold)).foregroundStyle(OctoColor.textSecondary)
            SoftCard {
                ForEach(Array(loginSteps(server: main, username: login.username).enumerated()), id: \.offset) { index, app in
                    let expanded = open == app.app
                    if index > 0 { SoftHairline() }
                    Button { open = expanded ? nil : app.app } label: {
                        HStack {
                            Text(app.app).font(.system(size: 14, weight: .semibold)).foregroundStyle(OctoColor.textPrimary)
                            Spacer()
                            Image(systemName: expanded ? "chevron.up" : "chevron.right").font(.system(size: 13)).foregroundStyle(OctoColor.textMuted)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(expanded ? "Hide steps" : "Show steps")
                    if expanded {
                        NumberedSteps(steps: app.steps).padding(.horizontal, 14).padding(.bottom, 12)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
    }
}
