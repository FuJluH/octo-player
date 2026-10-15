import OctoKit
import SwiftUI
import UIKit

/// The full player, over every page and the bar. Its background follows the song's artwork as
/// the settings choose, and every word and icon takes the color that reads on it. Pull down
/// anywhere to close; swipe the artwork sideways to skip. Upright, lyrics fold the artwork away
/// and the controls into a bar; sideways, the artwork stays and the lyrics take the other half.
struct NowPlayingView: View {
    let dismiss: () -> Void
    @Environment(Player.self) private var player
    @Environment(Session.self) private var session
    @Environment(Router.self) private var router
    @Environment(LibraryActions.self) private var libraryActions
    @Environment(LyricsStore.self) private var lyrics
    @Environment(ArtworkColorStore.self) private var colorStore
    @Environment(Library.self) private var library
    @Environment(LikeStore.self) private var likes
    @Environment(\.octoReduceMotion) private var calm
    @Environment(\.scenePhase) private var scenePhase
    @State private var settings = AppSettings.shared
    @State private var look = PlayerLook.shared
    @State private var facts = PlayerSongFacts()
    @State private var drive = PlayerDrive.shared
    @State private var flight = CoverFlight.shared
    @State private var animated = AnimatedArtStore.shared
    /// The full-screen loop (or its still) fills the player: the card steps aside and the words
    /// take the loop's shade.
    @State private var backdropCovers = false
    /// How the top of the full-screen loop looks, for the status bar.
    @State private var loopLooks: LoopLook?
    /// Where the title row sits, for the full-screen loop to be gone just above it.
    @State private var backdropFit = BackdropTitle()

    // The way in and out.
    /// The opening and closing: read only by the parts that move with it, so the player is not
    /// laid out again for each step.
    @State private var entrance = PlayerEntrance()
    @State private var fold = 0.0
    @State private var lyricsAlpha = 0.0
    @State private var lyricsLayer = false

    // The pull and the artwork's swipe.
    @State private var pull = PlayerPull()
    /// The drag's own bookkeeping, changed on every move and never drawn.
    @State private var book = DragBook()
    @State private var swipe = ArtSwipe()
    @State private var ticks = 0
    @State private var places = ArtPlaces()
    @GestureState private var dragging = false

    // What opens over the player.
    @State private var showsQueue = false
    @State private var showsSleep = false
    /// The sleep card's page as it opens: the timer, or the speed a page further.
    @State private var sleepOpening = TimePage.sleep
    @State private var showsSpeed = false
    @State private var airPlay = AirPlayTrigger()
    @State private var showsTiming = false
    @State private var showsChooser = false
    /// While a live station plays: its details, and the stations it was started from.
    @State private var showsStationInfo = false
    @State private var showsStations = false
    @State private var liveSong = LiveSongControl()

    private static let pullShare: CGFloat = 0.45
    /// The player's own space, which a pull moves as a whole.
    nonisolated private static let space = "player"
    private static let slop: CGFloat = 8
    private static let skipAt: CGFloat = 88
    /// The line at the top, holding the album's name.
    private static let topLineHeight: CGFloat = 40

    private var colors: PlayerColors {
        // Under a Full screen loop the background is drawn brighter; the words are picked for
        // that, so small text keeps 4.5:1 (the background is dimmed further if it must be).
        guard backdropCovers, case .backdrop = loop else { return look.colors }
        let gain = Float(FullScreenLook.backgroundGain)
        switch settings.player.background.mode {
        case .immersive: return look.colors.over(look.cover?.range.scaled(FinalGain * gain))
        case .artwork: return look.colors.over(look.cover?.range.scaled(gain))
        default: return look.colors
        }
    }

    /// The album whose animated art the player shows: the playing song's, on the server.
    private var loopAlbumId: String? { animated.albumId(of: player.current) }

    /// The square loop plays in the card: the background holds still under it. A full-screen loop
    /// dissolves into the background, which keeps moving as chosen.
    private var isCoverLoop: Bool {
        if case .cover = loop { return true }
        return false
    }

    private var isBackdropLoop: Bool {
        if case .backdrop = loop { return backdropCovers }
        return false
    }

    /// Where the playing album's animated art goes, as the setting has it.
    private var loop: PlayerLoop { settings.animatedArt.inPlayer(animated.known(loopAlbumId)) }

    private var ink: Color { colors.content }
    private var muted: Color { mutedInk(ink, dark: colors.dark) }
    private var accent: Color { accentInk(ink, dark: colors.dark) }


    var body: some View {
        GeometryReader { outer in
            let insets = outer.safeAreaInsets
            GeometryReader { screen in
                let size = screen.size
                let area = CGSize(width: size.width - insets.leading - insets.trailing, height: size.height - insets.top - insets.bottom)
                let sideways = area.width > area.height
                let roomy = !sideways || area.height >= 360
                let cap = size.height * Self.pullShare
                ZStack {
                    PlayerBackground(prefs: settings.player.background, colors: colors, cover: look.cover,
                                     coverId: player.current?.coverArt, live: settings.player.liveBackground, calm: calm,
                                     playing: player.isPlaying, bpm: facts.bpm, entrance: entrance,
                                     focused: focused, rests: isCoverLoop,
                                     gain: isBackdropLoop ? FullScreenLook.backgroundGain : 1)
                    if case .backdrop(let clip) = loop {
                        BackdropFrame(clip: clip, albumId: loopAlbumId, entrance: entrance, pull: pull, fit: backdropFit,
                                      darkInk: colors.dark, base: colors.base,
                                      lyricsOpen: lyrics.open, covers: { backdropCovers = $0 },
                                      looked: { loopLooks = $0 })
                    }
                    Group {
                        if sideways {
                            sidewaysLayout(insets, roomy: roomy)
                        } else {
                            uprightLayout(insets)
                        }
                    }
                    .foregroundStyle(ink)
                    .animation(.octoTween(fixed: 500), value: colors.dark)
                    // An upright drag that starts on a line pulls the player down too.
                    .environment(\.passedDrag, PassedDrag(moved: { dragMoved($0, cap: cap, onCard: false) },
                                                          ended: { dragEnded($0, $1, cap: cap) },
                                                          cancelled: dragTakenOver))
                }
                .frame(width: size.width, height: size.height)
                .coordinateSpace(.named(Self.space))
                .modifier(PulledFrame(pull: pull, cap: cap))
                .contentShape(Rectangle())
                .gesture(playerDrag(cap: cap, folded: lyrics.open && !sideways))
            }
            .ignoresSafeArea()
        }
        .background(PlayerStatusBar(dark: backdropCovers ? (loopLooks?.topLight ?? colors.dark) : colors.dark))
        .sensoryFeedback(.impact(flexibility: .rigid, intensity: 0.8), trigger: ticks)
        .onChange(of: dragging) { _, now in
            guard !now, book.axis != .undecided else {
                if !now { resetDrag() }
                return
            }
            dragTakenOver()
        }
        .onChange(of: lookAsk, initial: true) { _, ask in
            look.follow(coverId: ask.coverId, prefs: ask.prefs, live: ask.live, artwork: ask.artwork, client: session.client)
        }
        .onChange(of: factsAsk, initial: true) { _, _ in
            facts.follow(player.current, item: player.currentItem, library: library)
        }
        .onChange(of: player.current?.id, initial: true) { _, id in
            lyrics.attach(player)
            lyrics.songChanged(id)
        }
        .onChange(of: router.lyricsRequested, initial: true) { _, asked in
            guard asked else { return }
            router.lyricsRequested = false
            if !lyrics.open && player.live == nil { toggleLyrics() }
        }
        // A live station has no lyrics: they close, and its controls show.
        .onChange(of: player.currentItem?.isRadioStation == true, initial: true) { _, live in
            if live && lyrics.open { toggleLyrics() }
        }
        .onChange(of: lyrics.open) { _, open in showLyrics(open, animated: true) }
        .onChange(of: drive.request, initial: true) { _, request in
            guard let request else { return }
            drive.taken()
            take(request)
        }
        .task(id: loopAlbumId) { _ = await animated.want(loopAlbumId) }
        .onAppear(perform: arrive)
        .accessibilityAction(.escape) { close() }
        .sheet(isPresented: $showsChooser) {
            if let song = player.current {
                LyricsChooserContent(song: song) { showsChooser = false }
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
        .sheet(isPresented: $showsQueue) {
            QueueSheet()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showsStations) {
            StationListSheet { showsStations = false }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showsStationInfo) {
            if let live = player.live {
                StationInfoSheet(shown: live, coverArt: player.current?.coverArt) { showsStationInfo = false }
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    /// The wash slows to 10 frames a second while a card is open over it or the app is not in
    /// front.
    private var focused: Bool {
        scenePhase == .active && !(showsSleep || showsSpeed || showsTiming || showsChooser || showsStationInfo || showsStations)
    }

    // MARK: Layouts

    private func uprightLayout(_ insets: EdgeInsets) -> some View {
        let open = lyrics.open
        return VStack(spacing: 0) {
            topLine
            artStage(maxSide: .infinity, folds: true)
            ZStack(alignment: .bottom) {
                if open {
                    LyricsBar(ink: ink, close: toggleLyrics, timing: $showsTiming) { showsChooser = true }
                        .padding(.horizontal, -12)
                        .padding(.bottom, 12)
                        .transition(swap)
                } else {
                    controls(roomy: true)
                        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named(Self.space)).minY } action: { top in
                            if abs((backdropFit.top ?? -1) - top) > 0.5 { backdropFit.top = top }
                        }
                        .padding(.bottom, 16)
                        .modifier(Rising(entrance: entrance))
                        .transition(swap)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, insets.top)
        .padding(.bottom, insets.bottom)
        .overlay {
            if lyricsLayer {
                LyricsPane(edgeBleed: 24, ink: ink)
                    .padding(.top, insets.top + Self.topLineHeight + 8)
                    .padding(.bottom, insets.bottom + 76 + 8)
                    .padding(.horizontal, 24)
                    .opacity(lyricsAlpha)
            }
        }
    }

    private func sidewaysLayout(_ insets: EdgeInsets, roomy: Bool) -> some View {
        HStack(spacing: 32) {
            artStage(maxSide: 420, folds: false)
                .padding(.vertical, 12)
            ZStack {
                if lyrics.open {
                    VStack(spacing: 0) {
                        topLine
                        LyricsPane(edgeBleed: 0, ink: ink)
                            .padding(.vertical, 4)
                        LyricsBar(ink: ink, close: toggleLyrics, timing: $showsTiming) { showsChooser = true }
                            .padding(.horizontal, -12)
                            .padding(.bottom, 8)
                    }
                    .transition(swap)
                } else {
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        topLine
                        controls(roomy: roomy)
                            .modifier(Rising(entrance: entrance))
                        Spacer(minLength: 0)
                    }
                    .transition(swap)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 24)
        .padding(.top, insets.top)
        .padding(.bottom, insets.bottom)
        .padding(.leading, insets.leading)
        .padding(.trailing, insets.trailing)
    }

    /// The controls going and coming as lyrics open and close: out over 160 ms, in over 240 ms a
    /// moment later; with less motion they change at once.
    private var swap: AnyTransition {
        calm ? .identity : .asymmetric(insertion: .opacity.animation(.octoTween(fixed: 240, OctoEasing.standard, delay: 120)),
                                       removal: .opacity.animation(.octoTween(fixed: 160, OctoEasing.standard)))
    }

    // MARK: Top line

    /// The album the song is from, alone at the top: the player closes with a pull down, and
    /// AirPlay and Sound are in the More menu.
    private var topLine: some View {
        ZStack {
            // Over the Full screen loop the art runs clean to the top, so the name stays out.
            if !backdropCovers, let song = player.current, let name = albumLabel(song.album, song.title, facts.albumSongs) {
                albumName(name, song: song)
            }
            HiddenRoutePicker(trigger: airPlay)
                .frame(width: 1, height: 1)
                .accessibilityHidden(true)
        }
        .frame(height: Self.topLineHeight)
    }

    @ViewBuilder
    private func albumName(_ name: String, song: Song) -> some View {
        let words = Text(name)
            .font(.octoCaption)
            .foregroundStyle(muted)
            .lineLimit(1)
            .padding(.vertical, 8)
        if let albumId = song.albumId, !albumId.isEmpty, !isFind(song.id), !albumId.hasPrefix(findPrefix) {
            Button {
                close { router.go(.album(Album(id: albumId, name: name, artist: song.artist ?? "", coverArt: song.coverArt))) }
            } label: { words }
                .buttonStyle(NoPress())
                .accessibilityHint("Open album")
                .padding(.horizontal, 24)
        } else {
            words.padding(.horizontal, 24)
        }
    }

    // MARK: Artwork

    /// The artwork in the room it has. Upright it is placed by `ArtPlacement` (as wide as the room
    /// allows, a calm margin under the top line, the spare height mostly below it); sideways it is
    /// centered, at most `maxSide`.
    private func artStage(maxSide: CGFloat, folds: Bool) -> some View {
        GeometryReader { box in
            let upright = folds ? ArtPlacement.upright(width: Double(box.size.width), height: Double(box.size.height)) : nil
            let side = upright.map { CGFloat($0.side) } ?? max(0, min(maxSide, box.size.width, box.size.height))
            let folded = folds ? fold : 0
            PlayerCardCover(entrance: entrance, coverId: player.current?.coverArt, live: player.live, side: side,
                            online: player.current?.isExternal ?? false)
                .overlay {
                    if case .cover(let clip) = loop {
                        CardLoop(clip: clip, albumId: loopAlbumId, side: side, entrance: entrance, pull: pull, flight: flight,
                                 folded: folds && lyrics.open)
                    }
                }
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                    flight.cardPlaced(frame)
                    places.card = frame
                }
                .elevation3()
                .opacity(flight.hidesCard ? 0 : 1)
                // A full-screen loop takes the card's place, as the cover it was.
                .opacity(backdropCovers ? 0 : 1)
                .animation(.easeInOut(duration: Double(loopFadeMs) / 1000), value: backdropCovers)
                .scaleEffect(player.isPlaying ? 1 : 0.84)
                .animation(.octoSpring(0.6, 300), value: player.isPlaying)
                .scaleEffect(1 - 0.08 * folded)
                .opacity(1 - folded)
                .modifier(SwipedCard(swipe: swipe, width: box.size.width))
                .padding(.top, upright.map { CGFloat($0.top) } ?? 0)
                .frame(width: box.size.width, height: box.size.height, alignment: upright == nil ? .center : .top)
                .accessibilityHidden(true)
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { places.stage = $0 }
    }

    // MARK: Controls

    private func controls(roomy: Bool) -> some View {
        let gap: CGFloat = roomy ? 12 : 4
        return VStack(spacing: 0) {
            if let song = player.current, let live = player.live, let lineup = player.lineup {
                liveControls(song, live, lineup, roomy: roomy, gap: gap)
            } else if let song = player.current {
                // The heart and More sit on the middle of the name's capitals, the same for a
                // song and a station.
                HStack(alignment: .playerTitleLine, spacing: 0) {
                    ZStack(alignment: .leading) {
                        PlayerTitleBlock(song: song, ink: ink, accent: accent, openArtist: artistOpener(song))
                            .id(song.id)
                            .transition(.asymmetric(insertion: .opacity.animation(.octoTween(fixed: 250, OctoEasing.standard)),
                                                    removal: .opacity.animation(.octoTween(fixed: 150, OctoEasing.standard))))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    titleButtons {
                        keeper(song)
                        moreButton
                    }
                }
                .environment(\.titleIcons, titleIcons)
                if facts.rating > 0 {
                    RatingStars(rating: facts.rating)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 2)
                }
                PlayerProgress(ink: ink, muted: muted, song: song, speedOpen: $showsSpeed)
                    .padding(.top, 12)
                PlayerTransport(ink: ink)
                    .padding(.top, gap)
                if roomy {
                    PlayerVolume(ink: ink, muted: muted)
                        .padding(.top, 8)
                }
                switches
                    .padding(.top, gap)
                    .padding(.bottom, gap)
            }
        }
    }

    /// The controls while a live station plays: the song on air with its button, the live bar,
    /// stations in place of songs, and only the switches that mean something live. The button
    /// and More sit level with the title's line, not the middle of the title and the line under it.
    @ViewBuilder
    private func liveControls(_ song: Song, _ live: LiveShown, _ lineup: LiveLineup, roomy: Bool, gap: CGFloat) -> some View {
        HStack(alignment: .playerTitleLine, spacing: 0) {
            ZStack(alignment: .leading) {
                PlayerTitleBlock(song: song, ink: ink, accent: accent, openArtist: nil)
                    .id("\(song.id)|\(live.title)")
                    .transition(.asymmetric(insertion: .opacity.animation(.octoTween(fixed: 250, OctoEasing.standard)),
                                            removal: .opacity.animation(.octoTween(fixed: 150, OctoEasing.standard))))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            titleButtons {
                LiveSongButtonView(onAir: live.onAir, ink: ink, control: liveSong, openSearch: openSearch)
                liveMoreButton(live)
            }
        }
        .environment(\.titleIcons, titleIcons)
        LiveBar(ink: ink, muted: muted)
            .padding(.top, 12)
        LiveTransport(ink: ink, lineup: lineup)
            .padding(.top, gap)
        if roomy {
            PlayerVolume(ink: ink, muted: muted)
                .padding(.top, 8)
        }
        liveSwitches(lineup)
            .padding(.top, gap)
            .padding(.bottom, gap)
    }

    /// The live station's menu, then AirPlay and Sound.
    private func liveMoreButton(_ live: LiveShown) -> some View {
        Menu {
            if let item = player.currentItem {
                LiveMenuItems(trackId: item.trackId, onAir: live.onAir, showInfo: { showsStationInfo = true }, openSearch: openSearch)
            }
            Section {
                PlayerMenuExtras(airPlay: airPlay) { route in close { router.go(route) } }
            }
        } label: {
            TitleGlyph(icon: .more, color: ink.opacity(titleIcons.alpha))
                .contentShape(Rectangle())
        }
        .menuOrder(.fixed)
        .accessibilityLabel("More")
    }

    /// The name's buttons side by side, reaching into the side margin so the gap between the
    /// heart and the dots is also the gap from the dots to the screen's edge.
    private func titleButtons<Buttons: View>(@ViewBuilder _ buttons: () -> Buttons) -> some View {
        HStack(spacing: 0) { buttons() }
            .padding(.trailing, -titleIcons.reach(sideMargin: Self.sideMargin))
    }

    /// The title row's icon measures for the phone's text size, as quiet as the background
    /// allows.
    private var titleIcons: TitleIcons {
        var icons = TitleIcons.current()
        icons.alpha = Double(colors.quiet)
        return icons
    }

    /// The room between the player's content and the screen's sides.
    private static let sideMargin: CGFloat = 24

    /// While a live station plays: the stations it was started from (when there is more than
    /// one), and the sleep timer.
    private func liveSwitches(_ lineup: LiveLineup) -> some View {
        HStack(spacing: 20) {
            if lineup.shows {
                PlayerSwitch(icon: .queue, label: "Stations", lit: false, ink: ink, state: "\(lineup.ids.count) stations") { showsStations = true }
            }
            sleepSwitch
        }
        .frame(maxWidth: .infinity)
    }

    /// Closes the player and opens Search on `text`.
    private func openSearch(_ text: String) {
        close { router.openSearch(text) }
    }

    private func artistOpener(_ song: Song) -> (() -> Void)? {
        guard let artistId = song.artistId, !artistId.isEmpty else { return nil }
        return { close { router.go(.artist(id: artistId, name: song.artist ?? "")) } }
    }

    /// The heart for a library song; for a song found online, the add button.
    @ViewBuilder
    private func keeper(_ song: Song) -> some View {
        if song.isExternal || isFind(song.id) {
            AddToLibraryButton(song: song, size: PlayerTitleRow.buttonSize, iconSize: titleIcons.pointSize / 0.84, ink: ink).id(song.id)
        } else if let trackId = facts.trackId {
            PlayerHeart(liked: likes.isLiked(trackId), ink: ink) { likes.toggle(trackId) }
        } else {
            Color.clear.frame(width: PlayerTitleRow.buttonSize, height: PlayerTitleRow.buttonSize)
        }
    }

    /// The song playing as the song menu takes it.
    private var menuSubject: SongSubject? {
        player.current.map { SongSubject(track: libraryActions.state.provisional($0), song: $0) }
    }

    /// The song menu for the song playing, the same one every song row opens.
    private var moreButton: some View {
        Menu {
            if let menuSubject {
                SongMenuItems(subject: menuSubject) {
                    PlayerMenuExtras(airPlay: airPlay) { route in close { router.go(route) } }
                }
            }
        } label: {
            TitleGlyph(icon: .more, color: ink.opacity(titleIcons.alpha))
                .contentShape(Rectangle())
        }
        .menuOrder(.fixed)
        .disabled(menuSubject == nil)
        .accessibilityLabel("More")
    }

    private var switches: some View {
        HStack(spacing: 20) {
            PlayerSwitch(icon: .lyrics, label: "Lyrics", lit: lyrics.open, ink: ink, state: lyrics.open ? "Showing" : "Hidden",
                         action: toggleLyrics)
            PlayerSwitch(icon: .queue, label: "Up next", lit: false, ink: ink, state: "Off") { showsQueue = true }
            sleepSwitch
            PlayerSwitch(icon: .shuffle, label: "Shuffle", lit: player.shuffled, ink: ink) { player.toggleShuffle() }
            PlayerSwitch(icon: player.repeatMode == .one ? .repeatOne : .repeatAll, label: "Repeat", lit: player.repeatMode != .off,
                         ink: ink, state: repeatWords) { player.cycleRepeat() }
        }
        .frame(maxWidth: .infinity)
    }

    private var sleepSwitch: some View {
        let state = player.sleepState
        return PlayerSwitch(icon: .sleepTimer, label: "Sleep timer", lit: state != .off, ink: ink,
                            state: sleepSummary(state)) { openSleep(.sleep) }
            .overlay(alignment: .topTrailing) {
                if case .counting(let left) = state {
                    SleepBadge(minutes: (left + 59_999) / 60_000)
                        .offset(x: 6, y: -4)
                }
            }
            .glassPopover(isPresented: $showsSleep) {
                TimeCard(start: .sleep, opening: sleepOpening) { showsSleep = false }
            }
    }

    private var repeatWords: String {
        switch player.repeatMode {
        case .off: "Off"
        case .all: "All songs"
        case .one: "This song"
        }
    }

    // MARK: Opening and closing

    private func arrive() {
        #if DEBUG
        FlightProbe.note("player arrives")
        #endif
        PlayerMotion.shared.moved(for: PlayerMotionClock.openSeconds)
        flight.playerOpening(flightKey(player.current))
        showLyrics(lyrics.open, animated: false)
        withAnimation(PlayerDolly.open) { entrance.dolly = 1 }
        withAnimation(.octoSpring(1, 1500)) { entrance.corner = 3 }
        withAnimation(.octoSpring(0.68, 400)) { entrance.rise = 0 }
        withAnimation(.octoTween(fixed: 380, OctoEasing.standard, delay: 80)) { entrance.riseAlpha = 1 }
    }

    /// Closes the player: the background draws back and the cover rounds as it flies home. `then`
    /// opens a page in its place as the player goes.
    private func close(then go: (() -> Void)? = nil) {
        guard !entrance.closing else { return }
        entrance.closing = true
        PlayerMotion.shared.moved(for: PlayerMotionClock.closeSeconds)
        flight.playerClosing(flightKey(player.current))
        withAnimation(PlayerDolly.close) { entrance.dolly = 0 }
        withAnimation(.octoSpring(1, 1500)) { entrance.corner = 50 }
        DispatchQueue.main.async {
            go?()
            withAnimation(.octoSpring(1, 400)) { dismiss() }
        }
    }

    private func toggleLyrics() {
        withAnimation(calm ? nil : .timingCurve(0.4, 0, 0.2, 1, duration: 0.36)) { lyrics.toggle() }
    }

    /// Folds the artwork and fades the lyrics in, or the other way.
    private func showLyrics(_ open: Bool, animated: Bool) {
        if open { lyricsLayer = true }
        guard animated, !calm else {
            fold = open ? 1 : 0
            lyricsAlpha = open ? 1 : 0
            if !open { lyricsLayer = false }
            return
        }
        withAnimation(.octoTween(fixed: 300, OctoEasing.standard)) { fold = open ? 1 : 0 }
        if open {
            withAnimation(.octoTween(fixed: 360, OctoEasing.standard, delay: 120)) { lyricsAlpha = 1 }
        } else {
            withAnimation(.octoTween(fixed: 360, OctoEasing.standard)) {
                lyricsAlpha = 0
            } completion: {
                if !lyrics.open { lyricsLayer = false }
            }
        }
    }

    /// Opens the sleep card on its timer, or on the speed a page further.
    private func openSleep(_ page: TimePage) {
        sleepOpening = page
        showsSleep = true
    }

    // MARK: Gestures

    /// A downward drag anywhere pulls the player down; a sideways one that starts on the artwork
    /// swipes it. Nothing is decided until the finger lifts.
    private func playerDrag(cap: CGFloat, folded: Bool) -> some Gesture {
        DragGesture(minimumDistance: Self.slop, coordinateSpace: .global)
            .updating($dragging) { _, state, _ in state = true }
            .onChanged { value in
                dragMoved(value.translation, cap: cap, onCard: !folded && places.card.contains(value.startLocation))
            }
            .onEnded { value in dragEnded(value.translation, value.velocity, cap: cap) }
    }

    /// The finger moved `t` from where it went down. The artwork decides once, from the first
    /// clear movement: sideways is its swipe, anything else is left for the pull. The pull starts
    /// once the finger has gone the slop downward; going the slop upward first only moves the
    /// point it is measured from. Then it follows the finger at 0.82, held between 0 and `cap`.
    private func dragMoved(_ t: CGSize, cap: CGFloat, onCard: Bool) {
        let dx = t.width
        let dy = t.height
        if book.axis == .undecided {
            if onCard && !book.artDecided {
                switch dragAxis(dx, dy, slop: Self.slop) {
                case .horizontal:
                    book.axis = .horizontal
                    // A new swipe takes over from one still settling.
                    book.settle += 1
                case .vertical:
                    book.artDecided = true
                case .undecided:
                    break
                }
            }
            if book.axis == .undecided {
                let moved = dy - book.slopOrigin
                if moved <= -Self.slop {
                    book.slopOrigin = dy
                } else if moved >= Self.slop {
                    book.axis = .vertical
                    PlayerMotion.shared.hold(true)
                    pull.distance = min(max((moved - Self.slop) * 0.82, 0), cap)
                    book.lastDy = dy
                    return
                }
            }
        }
        switch book.axis {
        case .vertical:
            pull.distance = min(max(pull.distance + (dy - book.lastDy) * 0.82, 0), cap)
            book.lastDy = dy
        case .horizontal:
            swipe.offset = dx * 0.55
            mark(abs(dx) >= Self.skipAt)
        case .undecided:
            break
        }
    }

    /// The finger lifted: a flick down or a pull past half the way closes, unless it was moving
    /// back up; a swipe of the artwork skips or springs back.
    private func dragEnded(_ t: CGSize, _ velocity: CGSize, cap: CGFloat) {
        let taken = book.axis
        resetDrag()
        switch taken {
        case .vertical:
            let speed = velocity.height
            if speed > 1200 || (pull.distance > cap / 2 && speed > -150) {
                close()
            } else {
                withAnimation(.octoSpring(0.8, 400)) { pull.distance = 0 }
            }
        case .horizontal:
            finishSwipe(t.width, velocity.width)
        case .undecided:
            break
        }
    }

    /// A drag taken over by something else ends as if it went nowhere.
    private func dragTakenOver() {
        let taken = book.axis
        resetDrag()
        switch taken {
        case .vertical:
            withAnimation(.octoSpring(0.8, 400)) { pull.distance = 0 }
        case .horizontal:
            finishSwipe(0, 0)
        case .undecided:
            break
        }
    }

    private func resetDrag() {
        if book.axis == .vertical { PlayerMotion.shared.hold(false) }
        book.axis = .undecided
        book.artDecided = false
        book.slopOrigin = 0
        book.lastDy = 0
    }

    /// One tick each time the finger passes the point where letting go skips.
    private func mark(_ past: Bool) {
        guard past != book.armed else { return }
        book.armed = past
        if past { ticks += 1 }
    }

    /// Settles a swipe of the artwork. A skip carries it on out the way it was going, changes the
    /// song, and brings the new one in from 20% out on the other side; otherwise it springs back.
    /// A new swipe calls off a settle still under way.
    private func finishSwipe(_ offset: CGFloat, _ velocity: CGFloat) {
        var result = swipeSkip(offset: Double(offset), velocity: Double(velocity), distance: Double(Self.skipAt), fling: 900)
        // A live station swipes to the next or previous station of its list, and not past its ends.
        if let lineup = player.lineup {
            if (result == .next && !lineup.hasNext) || (result == .previous && !lineup.hasPrevious) { result = .stay }
        }
        if result != .stay && !book.armed { ticks += 1 }
        book.armed = false
        book.settle += 1
        let token = book.settle
        let width = max(places.stage.width, 1)
        switch result {
        case .stay:
            withAnimation(.octoSpring(0.8, 400)) { swipe.offset = 0 }
        case .next, .previous:
            let way: CGFloat = result == .next ? -1 : 1
            withAnimation(.octoTween(fixed: 120)) {
                swipe.offset = way * width / 2
            } completion: {
                guard token == book.settle else { return }
                if result == .next { player.next() } else { player.previous() }
                var still = Transaction()
                still.disablesAnimations = true
                withTransaction(still) { swipe.offset = -way * width * 0.2 }
                DispatchQueue.main.async {
                    guard token == book.settle else { return }
                    withAnimation(.octoSpring(0.8, 300)) { swipe.offset = 0 }
                }
            }
        }
    }

    // MARK: Following

    private struct LookAsk: Equatable {
        let coverId: String?
        let prefs: BackgroundPrefs
        let live: Bool
        let artwork: ArtworkColors?
    }

    private var lookAsk: LookAsk {
        let coverId = player.current?.coverArt
        // The classic mesh counts as moving only on a phone that can draw it.
        return LookAsk(coverId: coverId, prefs: settings.player.background, live: settings.player.liveBackground && WashGPU.shared != nil,
                       artwork: colorStore.colors(for: coverId))
    }

    private struct FactsAsk: Equatable {
        let songId: String?
        let library: Int
        let ratings: Int
    }

    private var factsAsk: FactsAsk {
        FactsAsk(songId: player.current?.id, library: library.libraryVersion, ratings: library.ratingsVersion)
    }

    // MARK: Drive steps

    private func take(_ request: PlayerDrive.Request) {
        switch request.name {
        case "close": close()
        case "album":
            // As the song menu's Go to album does: the page opens and the player closes around it.
            if let song = player.current, let albumId = song.albumId, !albumId.isEmpty {
                router.go(.album(Album(id: albumId, name: song.album ?? "", artist: song.artist ?? "", coverArt: song.coverArt)))
            }
        case "queue":
            if player.live != nil { showsStations = true } else { showsQueue = true }
        case "stationinfo": showsStationInfo = true
        case "sleep":
            if let minutes = Int(request.value) { player.startSleep(minutes: minutes) }
            openSleep(.sleep)
        case "speed": showsSpeed = true
        case "speedpage": openSleep(.speed)
        case "more", "rate":
            if let menuSubject { libraryActions.previewMenu(.song(menuSubject)) }
        case "timing":
            if !lyrics.open { toggleLyrics() }
            // The lyrics bar comes in with the lyrics; its popover opens once it is there.
            Task {
                try? await Task.sleep(for: .milliseconds(500))
                showsTiming = true
            }
        case "chooser":
            if !lyrics.open { toggleLyrics() }
            showsChooser = true
        case "look":
            if let style = LyricsStyle(rawValue: request.value.capitalized) { settings.setLyricsStyle(style) }
            if !lyrics.open { toggleLyrics() }
        case "background":
            let modes: [String: BackgroundMode] = ["immersive": .immersive, "artwork": .artwork, "color": .color, "classic": .classic]
            if let mode = modes[request.value] { settings.setBackground { $0.mode = mode } }
        case "pulltest", "swipetest":
            // A finger's moves fed to the drag one display frame apart: down to a third of the
            // screen (or sideways), held, then let go without closing or skipping.
            let height = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.screen.bounds.height ?? 852
            let cap = height * Self.pullShare
            let sideways = request.name == "swipetest"
            Task {
                #if DEBUG
                BodyTrace.mark("\(request.name) start")
                #endif
                for step in 0...90 {
                    let move = CGFloat(step) * 3
                    dragMoved(sideways ? CGSize(width: move * 0.8, height: 0) : CGSize(width: 0, height: move),
                              cap: cap, onCard: sideways)
                    try? await Task.sleep(for: .milliseconds(8))
                }
                #if DEBUG
                BodyTrace.mark("\(request.name) release")
                #endif
                dragEnded(.zero, .zero, cap: cap)
            }
        default: break
        }
    }
}

/// How far the player is pulled down. Only `PulledFrame` reads it, so a pull moves the frame
/// without the player inside it being laid out again.
@MainActor
@Observable
final class PlayerPull {
    var distance: CGFloat = 0
}

/// The pulled player: rounded at the corners, a little smaller, and moved down by the pull.
private struct PulledFrame: ViewModifier {
    let pull: PlayerPull
    let cap: CGFloat

    func body(content: Content) -> some View {
        let travel = min(max(pull.distance, 0), cap)
        let pulled = cap > 0 ? travel / cap : 0
        content
            .clipShape(RoundedRectangle(cornerRadius: travel > 0 ? 28 * min(pulled * 5, 1) : 0, style: .continuous))
            .scaleEffect(1 - 0.06 * pulled)
            .offset(y: travel)
    }
}

/// Where the artwork is on screen, for the gestures. Not watched: it changes on every frame of a
/// pull or a swipe, and nothing drawn depends on it.
private final class ArtPlaces {
    var card: CGRect = .zero
    var stage: CGRect = .zero
}

/// How far the artwork is swiped sideways. Only `SwipedCard` reads it, so a swipe moves the card
/// without the player around it being laid out again.
@MainActor
@Observable
final class ArtSwipe {
    var offset: CGFloat = 0
}

/// The swiped card: moved sideways and fading as it goes, down to half at half the stage's width.
private struct SwipedCard: ViewModifier {
    let swipe: ArtSwipe
    let width: CGFloat

    func body(content: Content) -> some View {
        let swiped = 1 - 0.5 * min(abs(swipe.offset) / max(width / 2, 1), 1)
        content
            .opacity(swiped)
            .offset(x: swipe.offset)
    }
}

/// A drag's bookkeeping on the player: which way it went, where its slop is measured from, the
/// last finger height, the swipe's settles and whether a release would skip. Not watched: it
/// changes on every move, and nothing drawn depends on it.
private final class DragBook {
    var axis: DragAxis = .undecided
    /// The artwork has made its one decision for this drag and left it to the pull.
    var artDecided = false
    /// Where the pull's slop is measured from: the touch, or the last point the finger went past
    /// it upward.
    var slopOrigin: CGFloat = 0
    var lastDy: CGFloat = 0
    /// Counts the artwork's settles, so a new swipe calls off one still under way.
    var settle = 0
    var armed = false
}

/// The player coming in and going: the background's dolly from 0 to 1, the card's corners (a share
/// of its side, from round to nearly square), and the controls rising into place.
@MainActor
@Observable
final class PlayerEntrance {
    var dolly = 0.0
    var closing = false
    var corner: CGFloat = 50
    var rise: CGFloat = 28
    var riseAlpha = 0.0
}

/// The controls rising into place as the player opens.
private struct Rising: ViewModifier {
    let entrance: PlayerEntrance

    func body(content: Content) -> some View {
        content
            .offset(y: entrance.rise)
            .opacity(entrance.riseAlpha)
    }
}

/// The square loop over the card, its corners following the card's. It plays once the cover has
/// landed and the player is still, holds while the player is pulled, and goes as the player
/// closes or lyrics fold the card away. Only this reads the pull and the flight, so neither lays
/// the player out again.
private struct CardLoop: View {
    let clip: AnimatedClip
    let albumId: String?
    let side: CGFloat
    let entrance: PlayerEntrance
    let pull: PlayerPull
    let flight: CoverFlight
    let folded: Bool

    var body: some View {
        CoverLoop(clip: clip, albumId: albumId, side: side, radius: side * entrance.corner / 100,
                  shown: !entrance.closing && !folded, held: pull.distance > 0 || flight.hidesCard)
    }
}

/// The full-screen loop behind the player, holding while the player is pulled and going as it
/// closes.
private struct BackdropFrame: View {
    let clip: AnimatedClip
    let albumId: String?
    let entrance: PlayerEntrance
    let pull: PlayerPull
    let fit: BackdropTitle
    let darkInk: Bool
    let base: UInt32
    let lyricsOpen: Bool
    let covers: (Bool) -> Void
    let looked: (LoopLook) -> Void

    var body: some View {
        PlayerBackdrop(clip: clip, albumId: albumId, titleTop: fit.top, darkInk: darkInk, base: base, shown: !entrance.closing,
                       held: pull.distance > 0, lyricsOpen: lyricsOpen, covers: covers, looked: looked)
    }
}

/// Where the player's title row starts, in the player's own space. Only the full-screen loop
/// reads it, so its layout never lays out the player again.
@MainActor
@Observable
final class BackdropTitle {
    var top: CGFloat?
}

/// The card's cover, its corners following the opening and closing. A live station shows the
/// song on air's artwork, else its logo, else the tile Octo draws for it.
private struct PlayerCardCover: View {
    let entrance: PlayerEntrance
    let coverId: String?
    let live: LiveShown?
    let side: CGFloat
    let online: Bool

    var body: some View {
        if let live {
            LiveCover(live, coverArt: coverId, size: side, radius: side * entrance.corner / 100)
        } else {
            Cover(id: coverId, size: side, radius: side * entrance.corner / 100, online: online)
        }
    }
}
