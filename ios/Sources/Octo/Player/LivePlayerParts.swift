import Observation
import OctoKit
import SwiftUI
import UIKit

// The full player's parts while a live station plays: the live bar in place of the scrub bar,
// Back, Play or Stop and Next for stations, the button for the song on air, the station's menu,
// its details, and the stations it was started from.

// MARK: The live bar

/// A live station's place: a calm thin line that cannot be dragged, how long the listener has
/// been on where a song shows its time gone, and the LIVE pill where a song shows its quality.
/// The codec and bitrate are in Station info.
struct LiveBar: View {
    let ink: Color
    let muted: Color
    @Environment(Player.self) private var player

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(ink.opacity(0.16))
                .frame(height: 3)
                .frame(height: 24)
                .accessibilityHidden(true)
            ZStack {
                HStack {
                    Text(player.listened)
                        .font(.octoCaption.monospacedDigit())
                        .foregroundStyle(muted)
                        .accessibilityLabel("Listening for \(player.listened)")
                    Spacer()
                }
                LivePill(beating: player.isPlaying)
            }
            .padding(.top, -8)
        }
    }
}

/// The LIVE pill: a red dot that beats gently while the station plays (still when motion is
/// reduced) and "LIVE", on a red tint.
struct LivePill: View {
    let beating: Bool
    @Environment(\.octoReduceMotion) private var calm
    @State private var motion = PlayerMotion.shared

    private static let red = Color(red: 1, green: 0.27, blue: 0.23)

    var body: some View {
        HStack(spacing: 6) {
            let moving = beating && !calm
            // A slow fade needs no more than 30 steps a second, except while the player moves.
            TimelineView(.animation(minimumInterval: pacedInterval(1.0 / 30, moving: motion.moving), paused: !moving)) { context in
                // Fades to a third and back every 1.8 s.
                let phase = context.date.timeIntervalSinceReferenceDate * .pi / 0.9
                Circle()
                    .fill(Self.red)
                    .frame(width: 7, height: 7)
                    .opacity(moving ? 0.675 + 0.325 * cos(phase) : 1)
            }
            .frame(width: 7, height: 7)
            Text("LIVE")
                .font(.octo(10.5, .bold, .caption2))
                .tracking(1)
                .foregroundStyle(Self.red)
        }
        .padding(.horizontal, 10)
        .frame(height: 24)
        .background(Capsule().fill(Self.red.opacity(0.16)))
        .overlay(Capsule().strokeBorder(Self.red.opacity(0.35), lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Live")
    }
}

// MARK: Transport

/// Previous station, Play or Stop, and next station. Back and Next show only when the station was
/// started from a list of more than one, and stop at its ends.
struct LiveTransport: View {
    let ink: Color
    let lineup: LiveLineup
    @Environment(Player.self) private var player

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            if lineup.shows {
                TransportButton(nudge: -8, label: "Previous station", action: player.previous) {
                    DimmedIcon(icon: .previous, size: 44, ink: ink)
                }
                .disabled(!lineup.hasPrevious)
                Spacer(minLength: 0)
            }
            TransportButton(nudge: 0, label: player.liveOn ? "Stop" : "Play", action: player.toggle) {
                ZStack {
                    if player.liveOn {
                        IconView(.stop, size: 56, color: ink).transition(PlayPop.transition)
                    } else {
                        IconView(.play, size: 56, color: ink).transition(PlayPop.transition)
                    }
                }
                .animation(.octoTween(fixed: 150), value: player.liveOn)
            }
            Spacer(minLength: 0)
            if lineup.shows {
                TransportButton(nudge: 8, label: "Next station", action: player.next) {
                    DimmedIcon(icon: .next, size: 44, ink: ink)
                }
                .disabled(!lineup.hasNext)
                Spacer(minLength: 0)
            }
        }
    }
}

/// An icon that fades while its button cannot be used.
private struct DimmedIcon: View {
    let icon: OctoIcon
    let size: CGFloat
    let ink: Color
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        IconView(icon, size: size, color: ink.opacity(enabled ? 1 : 0.3))
    }
}

// MARK: The song's button

/// The button beside the song a live station has on air, from what `LiveLookup` found in Octo
/// for it (the one result whose title and artist both agree): the heart for a library song, a
/// plus that adds an outside song the way any outside song is added, and a plus that opens Search
/// when Octo has no song that is surely it. It starts over when the song on air changes.
@MainActor
@Observable
final class LiveSongControl {
    /// A tap waiting for the lookup's answer.
    private(set) var waiting = false
    /// Library track ids for songs found, by the song's id.
    private(set) var libraryIds: [String: String] = [:]
    @ObservationIgnored private var song = OnAir.nothing
    @ObservationIgnored private var task: Task<Void, Never>?

    struct Services {
        let session: Session
        let library: Library
        let likes: LikeStore
        let downloads: Downloads
        let family: FamilyHub
        let router: Router
        let openSearch: (String) -> Void
    }

    /// The song on air now: a new one calls off a tap still waiting.
    func follow(_ onAir: OnAir) {
        guard onAir.title != song.title || onAir.artist != song.artist else { return }
        song = onAir
        task?.cancel()
        task = nil
        waiting = false
    }

    /// The button for `onAir` now.
    func button(_ onAir: OnAir, _ services: Services) -> LiveSongButton {
        let lookup = LiveLookup.shared
        guard let found = lookup.found(onAir) else {
            return liveSongButton(onAir, match: nil, looked: lookup.answered(onAir), starred: false, inLibrary: false, adding: false)
        }
        let match = HeartCandidate(id: found.song.id, title: found.song.title, artist: found.song.artist ?? "", inLibrary: found.inLibrary)
        let liked = libraryIds[found.song.id].map(services.likes.isLiked)
        if found.inLibrary {
            return liveSongButton(onAir, match: match, looked: true, starred: liked ?? false, inLibrary: true, adding: false)
        }
        let phase = services.downloads.phase(found.song.id)
        let landed = phase == .done
        let saved = savesForFamily(services) && services.family.isSaved(findKey(found.song))
        let adding = phase.state == .requested || saved
        return liveSongButton(onAir, match: match, looked: true, starred: landed ? (liked ?? true) : adding, inLibrary: landed, adding: adding)
    }

    /// Reads which library song a song found is, so its heart shows whether it is liked.
    func resolve(_ found: LiveLookup.Found, _ services: Services) async {
        guard libraryIds[found.song.id] == nil else { return }
        let song = found.inLibrary ? found.song : services.downloads.librarySong(found.song.id)
        guard let song, let id = await PlayerSongFacts.libraryId(song, library: services.library) else { return }
        libraryIds[found.song.id] = id
    }

    /// A tap: waits for the lookup when it has not answered yet, then does what the button says.
    func tap(_ onAir: OnAir, _ services: Services) {
        guard !waiting, onAir.named else { return }
        guard LiveLookup.shared.answered(onAir) else {
            waiting = true
            task = Task { [weak self] in
                _ = await LiveLookup.shared.find(onAir, session: services.session)
                guard !Task.isCancelled, let self, self.song == onAir else { return }
                self.waiting = false
                guard LiveLookup.shared.answered(onAir) else {
                    services.router.show("Couldn't reach Octo. Try again.")
                    return
                }
                await self.act(onAir, services)
            }
            return
        }
        task = Task { [weak self] in await self?.act(onAir, services) }
    }

    private func act(_ onAir: OnAir, _ services: Services) async {
        let button = button(onAir, services)
        guard let found = LiveLookup.shared.found(onAir) else {
            if button == .search { services.openSearch(heartQuery(onAir)) }
            return
        }
        switch button {
        case .none, .search:
            return
        case .heart(let starred):
            await resolve(found, services)
            if let id = libraryIds[found.song.id] {
                if services.likes.isLiked(id) == starred { services.likes.toggle(id) }
            } else if !starred, let client = services.session.client, (try? await client.star(songId: found.song.id)) == nil {
                services.router.show("Couldn't heart \(found.song.title). Try again.")
            }
        case .add(let adding):
            if adding {
                if services.downloads.keepsLog {
                    services.router.showServerDownloads(songId: found.song.id)
                } else {
                    services.router.show("\(found.song.title) is on its way to your library.")
                }
            } else if savesForFamily(services) {
                services.family.toggleSaved(findKey(found.song), title: found.song.title)
            } else if !(await services.downloads.request(found.song)) {
                services.router.show("Couldn't add \(found.song.title). Try again.")
            }
        }
    }

    /// A family member whose outside songs are saved rather than added.
    private func savesForFamily(_ services: Services) -> Bool { services.family.outside.addLabel != nil }

    private func findKey(_ song: Song) -> String { song.id.hasPrefix(findPrefix) ? song.id : findId(song.id) }
}

/// The button beside a live station's song: the heart, the plus, or nothing while no song is
/// named.
struct LiveSongButtonView: View {
    let onAir: OnAir
    let ink: Color
    let control: LiveSongControl
    let openSearch: (String) -> Void
    @Environment(Session.self) private var session
    @Environment(Library.self) private var library
    @Environment(LikeStore.self) private var likes
    @Environment(Downloads.self) private var downloads
    @Environment(Accounts.self) private var accounts
    @Environment(Router.self) private var router
    @Environment(\.octoReduceMotion) private var calm
    @Environment(\.titleIcons) private var titleIcons
    @State private var beats = 0
    @State private var release: (@Sendable () -> Void)?

    private var services: LiveSongControl.Services {
        LiveSongControl.Services(session: session, library: library, likes: likes, downloads: downloads, family: accounts.family,
                                 router: router, openSearch: openSearch)
    }

    var body: some View {
        let button = control.button(onAir, services)
        let found = LiveLookup.shared.found(onAir)
        Group {
            if button == .none {
                Color.clear.frame(width: 44, height: 44)
            } else {
                Button {
                    if case .heart(false) = button { beats += 1 }
                    control.tap(onAir, services)
                } label: {
                    ZStack {
                        if control.waiting {
                            ProgressView().tint(ink)
                        } else {
                            face(button, found)
                        }
                    }
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(NoPress())
                .accessibilityLabel(liveSongButtonLabel(button, onAir))
            }
        }
        .onChange(of: onAir, initial: true) { _, now in control.follow(now) }
        .task(id: found?.song.id) {
            guard let found else { return }
            await control.resolve(found, services)
        }
        // An outside song's download is followed while its button shows.
        .onChange(of: found.flatMap { $0.inLibrary ? nil : $0.song.id }, initial: true) { _, id in
            release?()
            release = id.map { downloads.showing($0) }
        }
        .onDisappear {
            release?()
            release = nil
        }
    }

    @ViewBuilder
    private func face(_ button: LiveSongButton, _ found: LiveLookup.Found?) -> some View {
        switch button {
        case .heart(let starred):
            TitleGlyph(icon: starred ? .liked : .like, color: starred ? ink : ink.opacity(quiet))
                .iconGlow(starred, color: ink)
                .iconAccent(.pulse, trigger: beats)
        case .add(let adding):
            let phase = found.map { downloads.phase($0.song.id) } ?? .none
            if adding && phase != .none {
                DownloadRing(phase: phase, calm: calm).frame(width: 24, height: 24)
            } else if adding {
                Image(systemName: "checkmark").font(.system(size: 20, weight: .semibold)).foregroundStyle(ink)
            } else {
                plus
            }
        case .search:
            plus
        case .none:
            EmptyView()
        }
    }

    private var plus: some View {
        TitleGlyph(icon: .addToLibrary, color: ink.opacity(quiet))
    }

    /// How strongly the plus and the empty heart show: a step quieter than the name.
    private var quiet: Double { titleIcons?.alpha ?? Double(PlayerTitleRow.iconAlpha) }
}

// MARK: The menu

/// The More menu while a live station plays: its details, keeping it on the phone, adding it to
/// the server (admins only), and finding or copying the song on air.
struct LiveMenuItems: View {
    let trackId: String
    let onAir: OnAir
    let showInfo: () -> Void
    let openSearch: (String) -> Void
    @Environment(Router.self) private var router
    @Environment(Session.self) private var session
    @Environment(ServerControls.self) private var controls
    @State private var radio = LiveRadioStore.shared

    var body: some View {
        Button("Station info", systemImage: "info.circle", action: showInfo)
        if let station = liveStationOf(trackId) {
            if radio.isKept(station.uuid) {
                Button("Remove station", systemImage: "bookmark.slash") {
                    radio.drop(station.uuid)
                    router.undoable("No longer kept: \(station.name)") { radio.keep(station) }
                }
            } else {
                Button("Keep station", systemImage: "bookmark") {
                    radio.keep(station)
                    router.done("Kept \(station.name). It shows on Home under Live radio.")
                }
            }
            if session.client != nil && controls.isAdmin {
                Button("Add to your server", systemImage: "plus.circle") {
                    let controls = controls
                    let router = router
                    Task { await addStationToServer(station, controls: controls, router: router) }
                }
            }
        }
        if onAir.named {
            Button("Find this song in Octo", systemImage: "magnifyingglass") { openSearch(heartQuery(onAir)) }
            Button("Copy song name", systemImage: "doc.on.doc") {
                UIPasteboard.general.string = onAir.artist.isEmpty ? onAir.title : "\(onAir.artist) - \(onAir.title)"
                router.done("Copied")
            }
        }
    }
}

// MARK: Station info

/// A live station's details on one screen: its logo and name, how it streams, where it is, what
/// it plays and its website, with Done always in sight.
struct StationInfoSheet: View {
    let shown: LiveShown
    let coverArt: String?
    let done: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            SheetScrollArea {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 14) {
                        LiveCover(logo: shown.details.logo, coverArt: coverArt, name: shown.station, size: 64)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(shown.station)
                                .font(.octoHeadline)
                                .foregroundStyle(.white)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(shown.subtitle)
                                .font(.octoBodySmall)
                                .foregroundStyle(OctoColor.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ForEach(rows, id: \.label) { row in
                        SheetSection(label: row.label) {
                            Text(row.value).font(.octoBody).foregroundStyle(.white).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if let site = website {
                        SheetSection(label: "Website") {
                            Link(destination: site) {
                                Text(site.host() ?? site.absoluteString)
                                    .font(.octoBody)
                                    .foregroundStyle(OctoColor.accent)
                                    .underline()
                            }
                        }
                    }
                }
                .padding(.top, 20)
                .padding(.bottom, 8)
            }
            SheetFooter(done: done) { EmptyView() }
        }
        .background(OctoColor.sheetFill)
    }

    private struct Row {
        let label: String
        let value: String
    }

    private var rows: [Row] {
        let details = shown.details
        let codec = details.codec.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let place = [details.state, details.country.isEmpty ? details.countryCode : details.country]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.joined(separator: ", ")
        var rows: [Row] = []
        if !codec.isEmpty && codec != "UNKNOWN" { rows.append(Row(label: "Codec", value: codec)) }
        if details.bitrate > 0 { rows.append(Row(label: "Bitrate", value: "\(details.bitrate) kbps")) }
        if !place.isEmpty { rows.append(Row(label: "Where", value: place)) }
        if !details.tags.isEmpty { rows.append(Row(label: "Plays", value: details.tags.prefix(5).joined(separator: ", "))) }
        rows.append(Row(label: "Stream", value: shown.streamUrl))
        return rows
    }

    private var website: URL? {
        let text = shown.details.homepage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: text), url.scheme == "https" || url.scheme == "http" else { return nil }
        return url
    }
}

// MARK: The stations

/// The stations the one on now was started from, in order. The one playing is filled with the
/// accent and checked; tapping another switches to it.
struct StationListSheet: View {
    let done: () -> Void
    @Environment(Player.self) private var player

    var body: some View {
        VStack(spacing: 0) {
            Text("Stations")
                .font(.octoSection)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 8)
            if let lineup = player.lineup {
                SheetScrollArea(startAt: "station-\(lineup.index)") {
                    ForEach(Array(lineup.ids.enumerated()), id: \.offset) { place, id in
                        row(id, place: place, on: place == lineup.index)
                            .id("station-\(place)")
                    }
                    .padding(.horizontal, -10)
                }
            }
            Spacer(minLength: 0)
            SheetFooter(done: done) { EmptyView() }
        }
        .background(OctoColor.sheetFill)
    }

    @ViewBuilder
    private func row(_ id: String, place: Int, on: Bool) -> some View {
        let station = radioOf(id)
        let details = radioDetailsOf(id)
        let name = station.map { $0.name.isEmpty ? $0.stream : $0.name } ?? ""
        let line = liveSubtitle(.nothing, station: name, details: details)
        Button {
            if !on { player.jump(to: place) }
        } label: {
            HStack(spacing: 12) {
                LiveCover(logo: details.logo, coverArt: details.coverArt.isEmpty ? nil : details.coverArt, name: name, size: 44, radius: 6)
                VStack(alignment: .leading, spacing: 0) {
                    Text(name).font(.octo(15, .semibold)).foregroundStyle(on ? Color.black : .white).lineLimit(2)
                    Text(on ? "Playing now" : line)
                        .font(.octoCaption)
                        .foregroundStyle(on ? Color.black.opacity(0.7) : OctoColor.textMuted)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if on {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.black)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(on ? OctoColor.accent : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityValue(on ? "Playing now" : line)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
