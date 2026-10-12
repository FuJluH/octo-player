import OctoKit
import SwiftUI

/// The server's internet radio stations. Tapping one plays it. An admin can add stations and
/// change or delete them, except ones the server keeps.
struct RadioStationsScreen: View {
    @Environment(ServerControls.self) private var controls
    @Environment(Session.self) private var session
    @Environment(Player.self) private var player
    @Environment(Discovery.self) private var discovery
    @State private var stations: LoadState<[ServerStationDetails]> = .loading
    @State private var form: StationFormRequest?
    @State private var saving = false
    @State private var problem: String?
    @State private var starting: String?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ScreenTitle("Radio stations")
                if controls.isAdmin {
                    GlazeButton("Add station", size: .medium) {
                        problem = nil
                        form = StationFormRequest(StationDraft())
                    }
                    .padding(.leading, 20)
                    .padding(.bottom, 8)
                }
                switch stations {
                case .loading:
                    LoadingSpinner(size: 22).frame(maxWidth: .infinity).padding(.top, 24)
                case .failed(let words):
                    Text(words).font(.octoBodySmall).foregroundStyle(OctoColor.textMuted).padding(.horizontal, 20)
                    GlazeButton("Try again", size: .medium) { Task { await reload() } }
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                case .ready(let list) where list.isEmpty:
                    Text("No stations on this server yet.")
                        .font(.octoBodySmall)
                        .foregroundStyle(OctoColor.textMuted)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 4)
                case .ready(let list):
                    ForEach(list) { station in row(station, readOnly: !controls.canEdit(stationId: station.id, coverArt: station.coverArt), admin: controls.isAdmin) }
                }
            }
            .padding(.top, 8 + detailTopGap)
        }
        .barClearance()
        .task { await reload() }
        .opensWhenAsked("add_station") {
            guard controls.isAdmin else { return }
            problem = nil
            form = StationFormRequest(StationDraft())
        }
        .sheet(item: Binding(get: { form }, set: { if $0 != nil || !saving { form = $0 } })) { request in
            StationForm(draft: request.draft, saving: saving, problem: problem, save: save, delete: delete)
                .interactiveDismissDisabled(saving)
        }
    }

    private func row(_ station: ServerStationDetails, readOnly: Bool, admin: Bool) -> some View {
        HStack(spacing: 14) {
            Button { play(station, readOnly: readOnly) } label: {
                HStack(spacing: 14) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 19))
                        .foregroundStyle(OctoColor.textSecondary)
                        .frame(width: 22, height: 22)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(station.name).font(.octoBodySmall).foregroundStyle(OctoColor.textPrimary).lineLimit(1)
                        Text(stationLine(station, readOnly: readOnly)).font(.octoCaption).foregroundStyle(OctoColor.textMuted).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 48)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if admin && !readOnly {
                Button {
                    problem = nil
                    form = StationFormRequest(StationDraft(station.id, station.name, station.streamUrl, station.homePageUrl ?? ""))
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 17))
                        .foregroundStyle(OctoColor.textMuted)
                        .frame(width: 48, height: 48)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit \(station.name)")
            }
        }
        .padding(.leading, 20)
        .padding(.trailing, 8)
        .padding(.vertical, 6)
        .frame(minHeight: 60)
        .opacity(starting == station.id ? 0.5 : 1)
        .animation(.easeInOut(duration: 0.2), value: starting)
    }

    private func reload() async {
        stations = .loading
        do {
            stations = .ready(try await controls.stations())
        } catch is CancellationError {
        } catch {
            stations = .failed(userMessage(plainError(error)))
        }
    }

    /// A station the server made plays the songs it has lined up; any other plays its stream.
    private func play(_ station: ServerStationDetails, readOnly: Bool) {
        guard starting == nil else { return }
        let stream = station.streamUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard readOnly else {
            if !stream.isEmpty, let song = radioSong(radioId(streamUrl: station.streamUrl, name: station.name)) { player.play([song], from: 0) }
            return
        }
        starting = station.id
        Task {
            defer { starting = nil }
            do {
                let songs = try await discovery.stationSongs(station.id)
                if !songs.isEmpty {
                    player.play(songs, from: 0)
                } else if !stream.isEmpty, let song = radioSong(radioId(streamUrl: station.streamUrl, name: station.name)) {
                    player.play([song], from: 0)
                }
            } catch {
                if isCancellation(error) { return }
                if case .notFound = SubsonicError(error) {
                    // Made anew on the server since the list was read: read it again.
                    await reload()
                } else {
                    playbackLog.warning("station failed to start: \(String(describing: type(of: error)), privacy: .public)")
                }
            }
        }
    }

    private func save(_ next: StationDraft) {
        act(next) { controls in
            let home = next.homePage.trimmingCharacters(in: .whitespacesAndNewlines)
            if let id = next.id {
                try await controls.updateStation(id, streamUrl: next.stream, name: next.name, homepageUrl: home.isEmpty ? nil : home)
            } else {
                try await controls.createStation(streamUrl: next.stream, name: next.name, homepageUrl: home.isEmpty ? nil : home)
            }
        }
    }

    private func delete(_ next: StationDraft) {
        act(next) { controls in if let id = next.id { try await controls.deleteStation(id) } }
    }

    /// Runs a change, then closes the form and reads the list again. A refusal stays in the
    /// form, in words.
    private func act(_ next: StationDraft, _ call: @escaping (ServerControls) async throws -> Void) {
        guard !saving else { return }
        saving = true
        problem = nil
        let controls = controls
        Task {
            do {
                try await call(controls)
                saving = false
                form = nil
                await reload()
            } catch {
                saving = false
                if let id = next.id, stationChangeRefused(error) || !controls.canEdit(stationId: id, coverArt: nil) {
                    problem = "The server keeps this station as it is."
                } else {
                    problem = userMessage(plainError(error))
                }
            }
        }
    }
}

/// The station form opened once: a station to change, or a new one. Each opening is its own, so
/// the form starts afresh, and keeps its words while it slides away.
private struct StationFormRequest: Identifiable {
    let id = UUID()
    let draft: StationDraft

    init(_ draft: StationDraft) { self.draft = draft }
}

/// The station form: a name, its stream and an optional home page; Save, and for a station
/// already there, Delete after asking. It scrolls when it is taller than the sheet allows. Next
/// on the keyboard moves from the name to the stream to the home page.
private struct StationForm: View {
    @State var draft: StationDraft
    let saving: Bool
    let problem: String?
    let save: (StationDraft) -> Void
    let delete: (StationDraft) -> Void
    @State private var confirming = false
    @State private var height: CGFloat?
    @State private var nameFocused = false
    @State private var streamFocused = false
    @State private var homePageFocused = false

    init(draft: StationDraft, saving: Bool, problem: String?, save: @escaping (StationDraft) -> Void, delete: @escaping (StationDraft) -> Void) {
        _draft = State(initialValue: draft)
        self.saving = saving
        self.problem = problem
        self.save = save
        self.delete = delete
    }

    var body: some View {
        ScrollView {
            content
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .presentationDetents(height.map { [.height($0)] } ?? [.medium])
        .presentationDragIndicator(.visible)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(draft.id == nil ? "Add station" : "Edit station").font(.octoBody).foregroundStyle(OctoColor.textPrimary)
            GlassInput("Name", text: $draft.name, submitLabel: .next, focus: $nameFocused, onSubmit: { streamFocused = true })
                .textInputAutocapitalization(.words)
            GlassInput("Stream address", text: $draft.stream, submitLabel: .next, focus: $streamFocused, onSubmit: { homePageFocused = true })
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            GlassInput("Home page (optional)", text: $draft.homePage, focus: $homePageFocused, onSubmit: { homePageFocused = false })
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if let problem { Text(problem).font(.octoCaption).foregroundStyle(OctoColor.error) }
            HStack(spacing: 12) {
                AccentButton("Save", size: .medium, enabled: draft.ready, loading: saving) { save(draft) }
                if draft.id != nil {
                    GlazeButton("Delete", size: .medium, enabled: !saving) { confirming = true }
                        .confirmationDialog("Delete \"\(draft.name)\" from the server?", isPresented: $confirming, titleVisibility: .visible) {
                            Button("Delete", role: .destructive) { delete(draft) }
                        }
                }
            }
        }
        .font(.octoBody)
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
