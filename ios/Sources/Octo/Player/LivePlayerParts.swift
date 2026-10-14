import Observation
import OctoKit
import SwiftUI
import UIKit

// The full player's parts while a live station plays: the live bar in place of the scrub bar,
// Back, Play or Stop and Next for stations, the heart for the song on air, the station's menu,
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

    private static let red = Color(red: 1, green: 0.27, blue: 0.23)

    var body: some View {
        HStack(spacing: 6) {
            let moving = beating && !calm
            TimelineView(.animation(paused: !moving)) { context in
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

// MARK: The heart

/// The heart for the song a live station has on air. A tap stars the song `LiveLookup` found in
/// Octo for it, the one result whose title and artist both agree: a library song is liked, a
/// song from outside the library is asked for, the way any outside song is. It starts over when
/// the song on air changes.
@MainActor
@Observable
final class LiveHeart {
    enum State: Equatable {
        case idle
        case looking
        /// Liked in the library, by its library id.
        case liked(String)
        /// Asked for from outside the library.
        case asked
    }

    private(set) var state: State = .idle
    /// The song on air the state is for.
    @ObservationIgnored private var song = OnAir.nothing
    @ObservationIgnored private var looking: Task<Void, Never>?

    var filled: Bool {
        switch state {
        case .liked, .asked: true
        case .idle, .looking: false
        }
    }

    /// The song on air now: a new one starts the heart over.
    func follow(_ onAir: OnAir) {
        guard onAir.title != song.title || onAir.artist != song.artist else { return }
        song = onAir
        looking?.cancel()
        looking = nil
        state = .idle
    }

    struct Services {
        let session: Session
        let library: Library
        let likes: LikeStore
        let downloads: Downloads
        let family: FamilyHub
        let router: Router
        let openSearch: (String) -> Void
    }

    func tap(_ services: Services) {
        switch state {
        case .looking:
            return
        case .liked(let trackId):
            services.likes.toggle(trackId)
            state = .idle
            return
        case .asked:
            services.router.show("\(song.title) is on its way to your library.")
            return
        case .idle:
            break
        }
        let onAir = song
        let query = heartQuery(onAir)
        guard onAir.named, services.session.client != nil else {
            missing(onAir, query, services)
            return
        }
        state = .looking
        // The same lookup the cover uses: the answer is usually there already.
        looking = Task { [weak self] in
            let found = await LiveLookup.shared.find(onAir, session: services.session)
            guard !Task.isCancelled, let self, self.song == onAir else { return }
            guard let found else {
                self.state = .idle
                self.missing(onAir, query, services)
                return
            }
            if found.inLibrary {
                await self.like(found.song, for: onAir, services)
            } else {
                await self.ask(found.song, for: onAir, services)
            }
        }
    }

    /// Likes the library song found for `onAir`, unless another song came on air meanwhile.
    private func like(_ song: Song, for onAir: OnAir, _ services: Services) async {
        let trackId = await PlayerSongFacts.libraryId(song, library: services.library)
        guard self.song == onAir else { return }
        if let trackId {
            if !services.likes.isLiked(trackId) { services.likes.toggle(trackId) }
            state = .liked(trackId)
        } else if let client = services.session.client, (try? await client.star(songId: song.id)) != nil {
            // On the server but not yet in the phone's library: starred there.
            state = .asked
        } else {
            state = .idle
            services.router.show("Couldn't heart \(song.title). Try again.")
        }
    }

    /// Asks for the outside song found for `onAir`, the way any song from outside the library is.
    private func ask(_ song: Song, for onAir: OnAir, _ services: Services) async {
        guard self.song == onAir else { return }
        if services.family.outside.addLabel != nil {
            let id = song.id.hasPrefix(findPrefix) ? song.id : findId(song.id)
            if !services.family.isSaved(id) { services.family.toggleSaved(id, title: song.title) }
            state = .asked
            return
        }
        if await services.downloads.request(song) {
            state = .asked
            services.router.done("Adding \(song.title) to your library")
        } else {
            state = .idle
            services.router.show("Couldn't ask for \(song.title). Try again.")
        }
    }

    private func missing(_ onAir: OnAir, _ query: String, _ services: Services) {
        services.router.show("Couldn't find \(onAir.title) in Octo", action: "Search") { services.openSearch(query) }
    }
}

/// The heart beside a live station's song: shown only while the station names a song.
struct LiveHeartButton: View {
    let onAir: OnAir
    let ink: Color
    let heart: LiveHeart
    let openSearch: (String) -> Void
    @Environment(Session.self) private var session
    @Environment(Library.self) private var library
    @Environment(LikeStore.self) private var likes
    @Environment(Downloads.self) private var downloads
    @Environment(Accounts.self) private var accounts
    @Environment(Router.self) private var router
    @State private var beats = 0

    var body: some View {
        Group {
            if onAir.named {
                Button {
                    if !heart.filled { beats += 1 }
                    heart.tap(LiveHeart.Services(session: session, library: library, likes: likes, downloads: downloads,
                                                 family: accounts.family, router: router, openSearch: openSearch))
                } label: {
                    ZStack {
                        if heart.state == .looking {
                            ProgressView().tint(ink)
                        } else {
                            IconView(heart.filled ? .liked : .like, size: 24, color: heart.filled ? ink : ink.opacity(0.6))
                                .iconGlow(heart.filled, color: ink)
                                .iconAccent(.pulse, trigger: beats)
                        }
                    }
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(NoPress())
                .accessibilityLabel(heartLabel)
                .accessibilityValue(heart.filled ? "Hearted" : "Not hearted")
            } else {
                Color.clear.frame(width: 44, height: 44)
            }
        }
        .onChange(of: onAir, initial: true) { _, now in heart.follow(now) }
    }

    private var heartLabel: String {
        onAir.artist.isEmpty ? "Heart \(onAir.title)" : "Heart \(onAir.title) by \(onAir.artist)"
    }
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
