import OctoKit
import SwiftUI

/// Home: the title, the cards that ask or offer something, then either the empty card with the
/// charts or the shelves in the order kept in Settings, the hidden ones left out, and a way to
/// change them at the end. A shelf with nothing in it is left out, title and all.
struct HomeView: View {
    @Environment(Session.self) private var session
    @Environment(Player.self) private var player
    @Environment(Router.self) private var router
    @Environment(Library.self) private var library
    @Environment(Discovery.self) private var discovery
    @Environment(ServerSync.self) private var serverSync
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.refreshLibrary) private var refreshLibrary
    @State private var model = HomeModel()
    @State private var settings = AppSettings.shared
    @State private var liveRadio = LiveRadioStore.shared
    @State private var reading = false

    var body: some View {
        let layout = model.layout
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ScreenTitle("Home")
                if layout.askAccess { accessCard }
                ResumeCard()
                if model.whatsNewDue { whatsNewCard }
                if layout.empty {
                    emptyCard(offerAccess: !layout.askAccess)
                    // An empty library is where the charts help most: songs to start from.
                    songShelf("Charts", model.charts, destination: .charts)
                } else if layout.shelves {
                    // Each shelf in its own stack, so a shelf moved in Settings moves as one.
                    ForEach(settings.homeSections.filter(\.shown)) { entry in
                        VStack(alignment: .leading, spacing: 0) { shelf(entry.section) }
                    }
                    editHomeButton
                }
            }
            .animation(.easeInOut(duration: 0.25), value: model.whatsNewDue)
            .animation(.easeInOut(duration: 0.25), value: layout)
            .animation(.easeInOut(duration: 0.3), value: settings.homeSections)
        }
        .barClearance()
        // A pull looks at the library again first, then picks the random shelves from what it
        // holds now; the stations are asked for at once.
        .refreshable {
            model.refreshStations()
            let words = await refreshLibrary?()
            await model.refresh()
            if let words { router.show(words) }
        }
        .onAppear {
            model.attach(library: library, discovery: discovery, player: player, router: router)
            model.shown()
        }
        .task(id: library.stamp(.library, .plays, .likes, .favorites, .pins, .playlists)) { await model.readLibrary() }
        .task(id: "\(model.songCount ?? -1)|\(serverSync.last?.at ?? 0)") {
            await model.reroll(for: "\(model.songCount ?? -1)|\(serverSync.last?.at ?? 0)")
        }
        .onChange(of: discovery.stationsFrom, initial: true) { _, _ in model.stationsSourceChanged() }
        // A list found gone on its own page leaves Home.
        .onChange(of: discovery.goneLists) { _, gone in model.listsGone(gone) }
        // A server shelf shown again, or the empty card's chart, is asked for then.
        .onChange(of: settings.homeSections) { _, _ in model.sectionsChanged() }
        .onChange(of: model.songCount == 0) { _, _ in model.sectionsChanged() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { model.shown() } }
        // Home is in front again after another tab or the full player.
        .background { WakeWatch { model.shown() } }
        .whatsNewPanel(isPresented: $reading) { model.dismissWhatsNew() }
    }

    // MARK: Shelves

    /// One shelf of Home, by its id.
    @ViewBuilder
    private func shelf(_ section: HomeSection) -> some View {
        switch section {
        case .pinned: pinnedShelf
        case .recentlyPlayed:
            albumShelf(section.title, model.recentlyPlayed, destination: .library(.history(mostPlayed: false)))
        case .madeForYou: stationShelf(section.title, model.madeForYou, counts: true)
        case .stations: stationShelf(section.title, octoRadio(model.stations), counts: false)
        case .internetRadio: liveRadioShelf(section.title)
        case .yearMixes, .genreMixes, .artistMixes, .countryMixes: stationShelf(section.title, model.mixes[section] ?? [], counts: true)
        case .recentlyAdded: albumShelf(section.title, model.recentlyAdded)
        case .mostPlayed: songShelf(section.title, model.mostPlayed.map(\.asSong), destination: .library(.history(mostPlayed: true)))
        case .favoriteAlbums: albumShelf(section.title, model.favoriteAlbums, destination: .library(.favorites(.albums)))
        case .charts: songShelf(section.title, model.charts, destination: .charts)
        case .artists: artistShelf
        case .somethingDifferent: albumShelf(section.title, model.surprise)
        case .notPlayedLately: albumShelf(section.title, model.revisit.notPlayedLately)
        case .neverFinished: albumShelf(section.title, model.revisit.neverFinished)
        case .neverPlayed: albumShelf(section.title, model.revisit.neverPlayed)
        }
    }

    /// A row of the library's artists, picked at random.
    @ViewBuilder
    private var artistShelf: some View {
        if !model.artists.isEmpty {
            SectionTitle(HomeSection.artists.title).padding(.top, 18)
            SideScroller {
                ForEach(model.artists) { artist in
                    ArtistCircle(id: artist.pageId(discovery.sourceId), name: artist.name, coverArt: coverId(of: artist.artwork),
                                 library: artist)
                }
            }
        }
    }

    /// A quiet way to the page that orders and hides the shelves, after the last one.
    private var editHomeButton: some View {
        GlazeButton("Edit Home", size: .small) { router.go(.homeSections) }
            .frame(maxWidth: .infinity)
            .padding(.top, 32)
            .padding(.bottom, 8)
    }

    @ViewBuilder
    private func albumShelf(_ title: String, _ albums: [LibraryAlbum], destination: Route? = nil) -> some View {
        if !albums.isEmpty {
            HomeShelfTitle(title: title, destination: destination)
            SideScroller {
                ForEach(albums) { AlbumCard(album: $0.asAlbum, library: $0) }
            }
        }
    }

    /// A row of songs; tapping one plays the row from that song.
    @ViewBuilder
    private func songShelf(_ title: String, _ songs: [Song], destination: Route? = nil) -> some View {
        if !songs.isEmpty {
            HomeShelfTitle(title: title, destination: destination)
            SideScroller {
                ForEach(Array(songs.enumerated()), id: \.element.id) { position, song in
                    SongCard(song: song, list: songs, position: position)
                }
            }
        }
    }

    /// The server's stations, the internet radio stations added to it, or the lists and mixes it
    /// made for the listener (`counts` shows how many songs each holds); tapping one opens its
    /// songs and its play button plays them, while an internet radio station plays its stream.
    /// Their titles are never buttons.
    @ViewBuilder
    private func stationShelf(_ title: String, _ stations: [Station], counts: Bool) -> some View {
        if !stations.isEmpty {
            SectionTitle(title).padding(.top, 18)
            SideScroller {
                ForEach(stations) { station in
                    StationCard(name: station.name, coverArt: coverId(of: station.artwork) ?? station.id,
                                songCount: counts ? station.songCount : nil, loading: model.startingStation == station.id,
                                open: stationHasPlayButton(station) ? station.asPlaylist.map(Route.playlist) : nil) {
                        model.playStation(station)
                    }
                    .animation(.easeInOut(duration: 0.2), value: model.startingStation)
                }
            }
        }
    }

    /// Live radio: a way to the stations near the listener first, then the stations kept on the
    /// phone, then the internet radio stations on the server, each stream once. Its title opens
    /// the near-you page too.
    @ViewBuilder
    private func liveRadioShelf(_ title: String) -> some View {
        let kept = liveRadio.kept.stations
        let keptStreams = Set(kept.map(\.streamUrl))
        let server = internetRadio(model.stations).filter { !keptStreams.contains($0.streamUrl ?? "") }
        // Every station on the shelf, in its order: Back and Next step through them.
        let shelf = kept.map { (stream: $0.streamUrl, id: $0.radioId()) } + server.map(serverStationEntry)
        HomeShelfTitle(title: title, destination: .liveRadioNear)
        SideScroller {
            FindNearbyCard()
            ForEach(kept) { station in
                KeptStationCard(station: station) { liveRadio.play(station, among: shelf, on: player) }
            }
            ForEach(Array(server.enumerated()), id: \.element.id) { place, station in
                StationCard(name: station.name, coverArt: coverId(of: station.artwork) ?? station.id, songCount: nil,
                            loading: model.startingStation == station.id, open: nil) {
                    player.playStations(shelf, tapped: kept.count + place)
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: kept.map(\.uuid))
    }

    /// One of the server's internet radio stations as the queue holds it, with its server cover
    /// and website.
    private func serverStationEntry(_ station: Station) -> (stream: String, id: String) {
        let stream = (station.streamUrl ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let cover = coverId(of: station.artwork) ?? station.id
        return (stream, radioId(streamUrl: stream, name: station.name, details: RadioDetails(coverArt: cover, homepage: station.homepage ?? "")))
    }

    /// The first shelf: albums, artists and playlists pinned there, in their order.
    @ViewBuilder
    private var pinnedShelf: some View {
        if !model.pins.isEmpty {
            SectionTitle("Pinned").padding(.top, 18)
            SideScroller {
                ForEach(model.pins) { pin in
                    switch pin {
                    case .album(let album):
                        AlbumCard(album: album.asAlbum, library: album)
                    case .artist(let artist):
                        PinnedCard(title: artist.name, subtitle: "Artist",
                                   route: .artist(id: artist.pageId(discovery.sourceId), name: artist.name)) {
                            Cover(id: artist.artwork, size: 150, radius: 75)
                        }
                        .contextMenu { CollectionMenuItems(subject: .artist(artist)) }
                    case .playlist(let summary):
                        if let playlist = summary.asPlaylist(discovery.sourceId) {
                            PinnedCard(title: summary.name, subtitle: "Playlist", route: .playlist(playlist)) {
                                PlaylistCover(playlist: summary, size: 150)
                            }
                            .contextMenu { CollectionMenuItems(subject: .playlist(summary)) }
                        }
                    }
                }
            }
            .animation(.easeInOut(duration: 0.25), value: model.pins.map(\.id))
        }
    }

    // MARK: Cards

    /// A quiet ask for the music on the phone, above everything else. "Not now" puts it away for
    /// good; the empty Library pages still offer access.
    private var accessCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Music on this phone").font(.octoBodySmall).foregroundStyle(.white)
            Text("Allow access to play the music already on your phone here too.")
                .font(.octoCaption)
                .foregroundStyle(OctoColor.textSecondary)
            HStack(spacing: 12) {
                AccentButton(model.access == .deniedForever ? accessButtonLabel(model.access) : "Allow") { model.requestAccess() }
                GlazeButton("Not now") { model.dismissAccess() }
            }
            .padding(.top, 10)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(Glass.octo, in: .rect(cornerRadius: 20))
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    /// A quiet card, once after an update, saying what is new.
    private var whatsNewCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("New in Octo").font(.octoCaption).foregroundStyle(OctoColor.textMuted)
            Text(WhatsNew.summary).font(.octoBody).foregroundStyle(.white).lineLimit(2)
            HStack(spacing: 12) {
                GlazeButton("See what's new") { reading = true }
                GlazeButton("Dismiss") { model.dismissWhatsNew() }
            }
            .padding(.top, 12)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(Glass.octo, in: .rect(cornerRadius: 20))
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    /// A library with no songs at all, from anywhere. `offerAccess` is off while the access card
    /// above already asks.
    private func emptyCard(offerAccess: Bool) -> some View {
        let askAccess = offerAccess && model.access != .granted
        let signIn = session.client == nil
        return VStack(alignment: .leading, spacing: 6) {
            Text("No music yet").font(.octoHeadline).foregroundStyle(.white)
            Text("Songs on this phone and on your server show up here on their own.")
                .font(.octoBodySmall)
                .foregroundStyle(OctoColor.textMuted)
            if askAccess || signIn {
                FlowRow(spacing: 12) {
                    if askAccess { GlazeButton(accessButtonLabel(model.access)) { model.requestAccess() } }
                    if signIn { GlazeButton("Sign in to a server") { router.signIn = .signIn } }
                }
                .padding(.top, 12)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
    }
}

/// A shelf's name, 18 below what is above it. One that leads to a page of its own is a button,
/// with a chevron saying so drawn into the title's end margin.
struct HomeShelfTitle: View {
    let title: String
    var destination: Route?

    var body: some View {
        if let destination {
            NavigationLink(value: destination) {
                HStack(spacing: 0) {
                    Text(title)
                        .font(.octoSection)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(OctoColor.textMuted)
                        .frame(width: 22, height: 22)
                        .offset(x: -16)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 18)
            .accessibilityLabel(title)
            .accessibilityHint("Open \(title)")
            .accessibilityAddTraits(.isHeader)
        } else {
            SectionTitle(title).padding(.top, 18)
        }
    }
}

/// An artist or playlist on the pinned shelf, as wide as an album card: its picture, its name, and
/// what it is.
private struct PinnedCard<Picture: View>: View {
    let title: String
    let subtitle: String
    let route: Route
    @ViewBuilder let picture: Picture

    var body: some View {
        NavigationLink(value: route) {
            VStack(alignment: .leading, spacing: 0) {
                picture
                Spacer().frame(height: 8)
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(subtitle).font(.octoCaption).foregroundStyle(OctoColor.textMuted).lineLimit(1)
            }
            .frame(width: 150, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScale(scale: 0.97))
    }
}
