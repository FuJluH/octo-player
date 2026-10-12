import OctoKit
import SwiftUI
import UniformTypeIdentifiers

/// Import: bring lists over from another service, a file or pasted text; Spotify kept in step;
/// the lists Octo holds and how full each is in the library; and the slow fetching of what is
/// missing. The server does the work; this page asks it while it shows.
struct ImportScreen: View {
    @Environment(Session.self) private var session
    @Environment(Accounts.self) private var accounts
    @State private var model: ImportModel?
    @State private var picking = false
    @State private var pasting = false
    @SceneStorage("import.link") private var link = ""
    @State private var removing: String?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ScreenTitle(ImportText.importTitle)
                if let model {
                    content(model)
                }
            }
            .padding(.top, 8 + detailTopGap)
        }
        .scrollDismissesKeyboard(.interactively)
        .barClearance()
        .onAppear {
            let model = model ?? makeModel()
            self.model = model
            model.watch()
            accounts.imports.showing = true
        }
        .onDisappear {
            model?.stop()
            accounts.imports.showing = false
        }
        .onChange(of: session.activeId) {
            model?.forget()
            model?.watch()
        }
        .task(id: "\(model?.overview != nil)|\(accounts.imports.waiting != nil)") { takeShared() }
        .opensWhenAsked("paste_list") { pasting = true }
        .opensWhenAsked("remove_list") { removing = model?.overview?.lists.first?.id }
        .fileImporter(isPresented: $picking, allowedContentTypes: ImportFiles.pickTypes) { result in
            guard case .success(let url) = result, let model else { return }
            ImportFiles.send(.file(ImportFiles.read(url), name: url.lastPathComponent, type: ImportFiles.type(of: url)), to: model)
        }
        .sheet(isPresented: $pasting) {
            PasteSheet(close: { pasting = false }) { text, name in
                model?.sendText(text, name: name.isEmpty ? ImportText.pastedListName : name)
            }
            .padding(.top, 24)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private func makeModel() -> ImportModel {
        let session = session
        return ImportModel(client: { session.client }, openUrl: { ImportBrowser.open($0) },
                           catcher: { host, path in await LoopbackListener.open(host: host, path: path) })
    }

    /// A list shared in goes to the server once it has answered with an overview.
    private func takeShared() {
        guard let model, model.overview != nil, let share = accounts.imports.take() else { return }
        ImportFiles.send(share, to: model)
    }

    @ViewBuilder
    private func content(_ model: ImportModel) -> some View {
        if let overview = model.overview {
            if let problem = overview.libraryProblem { line(problem, color: OctoColor.signalOrange) }
            if let services = model.services {
                GetMyMusicView(model: model, services: services, pick: { picking = true }, paste: { pasting = true })
                if let said = model.said { line(said, color: OctoColor.textSecondary) }
                SectionTitle("Spotify").padding(.top, 12)
                spotifyCard(model, overview.spotify, reading: overview.reading)
                publicLink(model)
            } else {
                spotifyCard(model, overview.spotify, reading: overview.reading)
                publicLink(model)
                if let said = model.said { line(said, color: OctoColor.textSecondary) }
            }
            if let openId = model.openId, let list = overview.lists.first(where: { $0.id == openId }) {
                openedList(model, list)
            } else {
                yourLists(model, overview)
            }
            trickle(model, overview.trickle)
        } else {
            line(model.problem ?? "Asking the server about your lists.")
        }
    }

    private func line(_ text: String, color: Color = OctoColor.textMuted) -> some View {
        Text(text)
            .font(.octoBodySmall)
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 6)
    }

    // MARK: Spotify

    private func spotifyCard(_ model: ImportModel, _ spotify: SpotifyStatus, reading: ImportReading) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(spotify.title).font(.octoBody).foregroundStyle(OctoColor.textPrimary)
            Text(spotify.line()).font(.octoCaption).foregroundStyle(OctoColor.textMuted)
            FlowRow(spacing: 8) {
                if model.signingIn {
                    GlazeButton("Cancel", size: .medium) { model.cancelSignIn() }
                } else {
                    GlazeButton(spotify.connected ? "Connect again" : "Connect Spotify", size: .medium,
                                enabled: spotify.configured && spotify.redirectProblem == nil) { model.connect() }
                    if spotify.connected {
                        GlazeButton("Read again", size: .medium, enabled: !reading.busy && !model.working, loading: reading.busy) {
                            model.readAgain()
                        }
                        GlazeButton("Disconnect", size: .medium, enabled: !model.working) { model.disconnect() }
                    }
                }
            }
            if let step = reading.step, !step.isEmpty {
                Text(step + "…").font(.octoCaption).foregroundStyle(OctoColor.textSecondary)
            } else if let error = reading.error, !error.isEmpty {
                Text(error).font(.octoCaption).foregroundStyle(OctoColor.textSecondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    private func publicLink(_ model: ImportModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Public link").font(.octoBody).foregroundStyle(OctoColor.textPrimary)
            Text("Share, then Copy link, on a Spotify playlist or album. A link shows Octo the first 100 songs.")
                .font(.octoCaption)
                .foregroundStyle(OctoColor.textMuted)
            HStack(spacing: 8) {
                GlassInput("https://open.spotify.com/playlist/…", text: $link, submitLabel: .done) { addLink(model) }
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                GlazeButton("Add", size: .medium, enabled: !link.trimmingCharacters(in: .whitespaces).isEmpty && !model.working) {
                    addLink(model)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    private func addLink(_ model: ImportModel) {
        let text = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        link = ""
        model.addLink(text)
    }

    // MARK: Lists

    @ViewBuilder
    private func yourLists(_ model: ImportModel, _ overview: ImportOverview) -> some View {
        SectionTitle("Your lists").padding(.top, 8)
        if overview.lists.isEmpty {
            if overview.spotify.connected {
                line("No lists yet. Read again to look at your Spotify once more.")
            } else if model.services != nil {
                line("No lists yet. Pick your service under Get my music, or add a link.")
            } else {
                line("No lists yet. Connect Spotify, or add a link.")
            }
        }
        ForEach(overview.lists) { list in listRow(model, list) }
    }

    private func listRow(_ model: ImportModel, _ list: ImportListSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { model.open(list.id) } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(list.name).font(.octoBody).foregroundStyle(OctoColor.textPrimary).lineLimit(2)
                    if !list.originLine.isEmpty {
                        Text(list.originLine).font(.octoCaption).foregroundStyle(OctoColor.textMuted)
                    }
                    Text(list.countsLine).font(.octoCaption).foregroundStyle(OctoColor.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            Meter(fraction: list.fraction)
            if let partial = list.partial, !partial.isEmpty { Text(partial).font(.octoCaption).foregroundStyle(OctoColor.textMuted) }
            if let note = list.playlistNote, !note.isEmpty { Text(note).font(.octoCaption).foregroundStyle(OctoColor.textMuted) }
            switchRow(ImportText.keepAsPlaylist, on: list.keepPlaylist, enabled: !model.working) { model.keepPlaylist(list.id, on: $0) }
            switchRow(ImportText.getMissingSongs, on: list.getMissing, enabled: !model.working) { model.getMissing(list.id, on: $0) }
            HStack(spacing: 8) {
                GlazeButton("Open", size: .small) { model.open(list.id) }
                if list.canRefresh {
                    GlazeButton("Read again", size: .small, enabled: !model.working) { model.readList(list.id) }
                }
                GlazeButton("Remove", size: .small, enabled: !model.working) { removing = list.id }
                    .confirmationDialog(ImportText.removeList,
                                        isPresented: Binding(get: { removing == list.id }, set: { if !$0 { removing = nil } }),
                                        titleVisibility: .visible) {
                        Button("Remove", role: .destructive) { model.remove(list.id) }
                    } message: {
                        Text(list.removeLine)
                    }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    private func switchRow(_ label: String, on: Bool, enabled: Bool, change: @escaping (Bool) -> Void) -> some View {
        HStack {
            Text(label).font(.octoBodySmall).foregroundStyle(OctoColor.textSecondary).frame(maxWidth: .infinity, alignment: .leading)
            OctoSwitch(isOn: Binding(get: { on }, set: change), enabled: enabled, label: label)
        }
    }

    @ViewBuilder
    private func openedList(_ model: ImportModel, _ list: ImportListSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(list.name).font(.octoSection).foregroundStyle(OctoColor.textPrimary)
            Text("\(list.countsLine). \(list.originLine)").font(.octoCaption).foregroundStyle(OctoColor.textMuted)
            GlazeButton("Back to your lists", size: .small) { model.close() }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        if let detail = model.detail, detail.list.id == list.id {
            let askable = detail.tracks.filter { $0.stage.askable }
            if !askable.isEmpty && !list.getMissing {
                GlazeButton("Get the \(askable.count) missing \(askable.count == 1 ? "song" : "songs") now", size: .medium,
                            enabled: !model.working) {
                    model.getSongs(list.id, keys: askable.map(\.key))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 6)
            }
            ForEach(Array(detail.tracks.enumerated()), id: \.offset) { _, track in TrackLine(track: track) }
        } else {
            line("Reading the list…")
        }
    }

    // MARK: Trickle

    @ViewBuilder
    private func trickle(_ model: ImportModel, _ trickle: TrickleStatus) -> some View {
        SectionTitle("Trickle").padding(.top, 12)
        VStack(alignment: .leading, spacing: 8) {
            Text(trickle.title).font(.octoBody).foregroundStyle(OctoColor.textPrimary)
            Text(trickle.line()).font(.octoCaption).foregroundStyle(OctoColor.textMuted)
            FlowRow(spacing: 8) {
                if trickle.stage != .idle || trickle.queued > 0 {
                    if trickle.stage == .paused {
                        GlazeButton("Go on", size: .small, enabled: !model.working) { model.resume() }
                    } else {
                        GlazeButton("Pause", size: .small, enabled: !model.working) { model.pause() }
                    }
                }
                if trickle.notFound > 0 {
                    GlazeButton("Try not found again", size: .small, enabled: !model.working) { model.retry() }
                }
                if trickle.done + trickle.notFound + trickle.skipped > 0 {
                    GlazeButton("Clear finished", size: .small, enabled: !model.working) { model.clearFinished() }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        if let current = trickle.current { TrackLine(track: current) }
        ForEach(Array(trickle.next.enumerated()), id: \.offset) { _, track in
            TrackLine(track: track) {
                GlazeButton("Skip", size: .extraSmall, enabled: !model.working) { model.skip(track.key) }.padding(.leading, 8)
            }
        }
        ForEach(Array(trickle.recent.enumerated()), id: \.offset) { _, track in
            TrackLine(track: track) {
                if track.stage == .notFound || track.stage == .skipped {
                    GlazeButton("Try again", size: .extraSmall, enabled: !model.working) { model.retry([track.key]) }.padding(.leading, 8)
                }
            }
        }
    }
}

/// How much of a list the library has: a 3 point line, the accent over a muted track.
private struct Meter: View {
    let fraction: Double

    var body: some View {
        GeometryReader { box in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2).fill(OctoColor.textMuted.opacity(0.25))
                RoundedRectangle(cornerRadius: 2).fill(OctoColor.accent).frame(width: box.size.width * fraction)
            }
        }
        .frame(height: 3)
        .accessibilityHidden(true)
    }
}

/// One song of a list or of the trickle: title, artist and the server's detail, then its state.
private struct TrackLine<Actions: View>: View {
    let track: ImportTrack
    @ViewBuilder var actions: Actions

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 1) {
                Text(track.title).font(.octoBodySmall).foregroundStyle(OctoColor.textPrimary).lineLimit(1)
                Text(track.artist).font(.octoCaption).foregroundStyle(OctoColor.textMuted).lineLimit(1)
                if let detail = track.detail, !detail.isEmpty {
                    Text(detail).font(.octoCaption).foregroundStyle(OctoColor.textMuted).lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(stateWords).font(.octoCaption).foregroundStyle(stateColor).padding(.leading, 12)
            actions
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    private var stateWords: String {
        let word = trackStateLabel(track.stage)
        guard let progress = track.progress else { return word }
        return "\(word) \(Int((progress * 100).rounded(.down)))%"
    }

    private var stateColor: Color {
        switch track.stage {
        case .have, .done: OctoColor.signalGreen
        case .notFound, .skipped: OctoColor.signalOrange
        default: OctoColor.textSecondary
        }
    }
}

extension TrackLine where Actions == EmptyView {
    init(track: ImportTrack) {
        self.init(track: track) { EmptyView() }
    }
}

/// "Get my music": the services as tiles, the step under way in a card, and the ways to use a
/// file already saved.
private struct GetMyMusicView: View {
    let model: ImportModel
    let services: ImportServices
    let pick: () -> Void
    let paste: () -> Void

    var body: some View {
        let sending = if case .sending = model.step { true } else { false }
        VStack(alignment: .leading, spacing: 24) {
            switch model.step {
            case .choose:
                grid(title: ImportText.getMyMusic, sending: sending)
                SettingsGroup(title: "Already have a file") {
                    fileRow(ImportText.useAFile, "CSV, TXT, JSON or ZIP, from Downloads or any folder.", button: "Choose", action: pick)
                    fileRow(ImportText.pasteAList, ImportText.pasteLine, button: "Paste", action: paste)
                }
            case .spotifyWays(let service):
                card(service.name, "Connecting keeps your Spotify lists updating in Octo. A file is a copy of them as they are today.") {
                    AccentButton(ImportText.connectSpotifyKeepsUpdating, size: .medium, enabled: !model.signingIn, fillWidth: true) {
                        model.connectSpotify()
                    }
                    GlazeButton(ImportText.useAFile, size: .medium, fillWidth: true) { model.openExport(service) }
                    GlazeButton("Back", size: .small, fillWidth: true) { model.backToServices() }
                }
                grid(title: "Pick another service", sending: sending)
            case .waiting(let service):
                card(waitingTitle(service), service.map(waitingLine) ?? ImportText.waitingAnyLine) {
                    AccentButton(ImportText.useDownloadedFile, size: .medium, fillWidth: true, action: pick)
                    GlazeButton(ImportText.pasteAList, size: .medium, fillWidth: true, action: paste)
                    if let service {
                        GlazeButton("Open TuneMyMusic again", size: .small, fillWidth: true) { model.openExport(service) }
                    }
                }
                grid(title: "Pick another service", sending: sending)
            case .sending(_, let name):
                card("Sending \(name)", "Octo reads your lists, then checks them against your library.") {
                    GlazeButton("Sending", size: .medium, enabled: false, loading: true, fillWidth: true) {}
                }
                grid(title: "Pick another service", sending: sending)
            case .sent(let message, let approval):
                card(message.isEmpty ? "Your lists are in." : message, approval) {
                    AccentButton("Import more", size: .medium, fillWidth: true) { model.backToServices() }
                }
                grid(title: "Pick another service", sending: sending)
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    private func card<Buttons: View>(_ heading: String, _ line: String?, @ViewBuilder buttons: () -> Buttons) -> some View {
        let made = buttons()
        return SettingsGroup {
            VStack(alignment: .leading, spacing: 10) {
                Text(heading).font(.octoBody).foregroundStyle(OctoColor.textPrimary)
                if let line { Text(line).font(.octoBodySmall).foregroundStyle(OctoColor.textSecondary) }
                VStack(spacing: 8) { made }.padding(.top, 4)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func grid(title: String, sending: Bool) -> some View {
        let chosen = model.step.service?.id
        let tiles = services.services
        return SettingsGroup(title: title) {
            VStack(alignment: .leading, spacing: 8) {
                if case .choose = model.step {
                    Text(ImportText.getMyMusicLine).font(.octoCaption).foregroundStyle(OctoColor.textMuted)
                }
                ForEach(Array(stride(from: 0, to: tiles.count, by: 2)), id: \.self) { start in
                    HStack(spacing: 8) {
                        tile(tiles[start], chosen: chosen, sending: sending)
                        if start + 1 < tiles.count {
                            tile(tiles[start + 1], chosen: chosen, sending: sending)
                        } else {
                            Color.clear.frame(maxWidth: .infinity, minHeight: 1)
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    private func tile(_ service: ImportServiceLink, chosen: String?, sending: Bool) -> some View {
        let picked = service.id == chosen
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return Button {
            if picked { model.openExport(service) } else { model.choose(service) }
        } label: {
            Text(service.name)
                .font(.system(size: 15, weight: .semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(10.0 / 15.0)
                .foregroundStyle(picked ? OctoColor.background : OctoColor.textPrimary)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(picked ? OctoColor.accent : OctoColor.accent.opacity(0.06), in: shape)
                .overlay(shape.strokeBorder(picked ? .clear : OctoColor.textMuted.opacity(0.25), lineWidth: 1))
                .overlay(alignment: .topTrailing) {
                    if picked {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .frame(width: 14, height: 14)
                            .foregroundStyle(OctoColor.background)
                            .padding(6)
                    }
                }
                .animation(.easeOut(duration: 0.2), value: picked)
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .disabled(sending)
        .opacity(sending ? 0.5 : 1)
        .accessibilityLabel(service.name)
        .accessibilityAddTraits(picked ? [.isSelected, .isButton] : .isButton)
    }

    private func fileRow(_ title: String, _ caption: String, button: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.octoBody).foregroundStyle(OctoColor.textPrimary)
                Text(caption).font(.octoCaption).foregroundStyle(OctoColor.textMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            GlazeButton(button, size: .small, action: action)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

/// The paste sheet: a name, the list one song a line, then Cancel and Import always in view.
private struct PasteSheet: View {
    let close: () -> Void
    let send: (String, String) -> Void
    @State private var name = ""
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(ImportText.pasteAList).font(.octoHeadline).foregroundStyle(OctoColor.textPrimary)
            Text(ImportText.pasteLine).font(.octoBodySmall).foregroundStyle(OctoColor.textSecondary)
            GlassInput("Name: Pasted list", text: $name, submitLabel: .next)
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text("Massive Attack - Angel").font(.octoBody).foregroundStyle(OctoColor.textMuted).padding(.horizontal, 19).padding(.vertical, 22)
                        .accessibilityHidden(true)
                }
                TextEditor(text: $text)
                    .font(.octoBody)
                    .scrollContentBackground(.hidden)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(14)
                    .accessibilityLabel(ImportText.pasteAList)
            }
            .frame(minHeight: 140, maxHeight: .infinity)
            .background(OctoColor.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(OctoColor.accent.opacity(0.1)))
            HStack(spacing: 10) {
                GlazeButton("Cancel", size: .medium, fillWidth: true, action: close)
                AccentButton("Import", size: .medium, enabled: !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, fillWidth: true) {
                    let list = text
                    let named = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    close()
                    send(list, named)
                    text = ""
                    name = ""
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }
}
