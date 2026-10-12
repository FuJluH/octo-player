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

    // The way in and out.
    @State private var dolly = 0.0
    @State private var closing = false
    @State private var corner: CGFloat = 50
    @State private var rise: CGFloat = 28
    @State private var riseAlpha = 0.0
    @State private var fold = 0.0
    @State private var lyricsAlpha = 0.0
    @State private var lyricsLayer = false

    // The pull and the artwork's swipe.
    @State private var pull: CGFloat = 0
    @State private var axis: DragAxis = .undecided
    /// The artwork has made its one decision for this drag and left it to the pull.
    @State private var artDecided = false
    /// Where the pull's slop is measured from: the touch, or the last point the finger went past
    /// it upward.
    @State private var slopOrigin: CGFloat = 0
    @State private var lastDy: CGFloat = 0
    @State private var card: CGFloat = 0
    /// Counts the artwork's settles, so a new swipe calls off one still under way.
    @State private var settle = 0
    @State private var armed = false
    @State private var ticks = 0
    @State private var stage: CGRect = .zero
    @State private var cardFrame: CGRect = .zero
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

    private static let pullShare: CGFloat = 0.45
    private static let slop: CGFloat = 8
    private static let skipAt: CGFloat = 88
    /// The line at the top, holding the album's name.
    private static let topLineHeight: CGFloat = 40

    private var colors: PlayerColors { look.colors }
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
                let travel = min(max(pull, 0), cap)
                let pulled = cap > 0 ? travel / cap : 0
                ZStack {
                    PlayerBackground(prefs: settings.player.background, colors: colors, cover: look.cover,
                                     coverId: player.current?.coverArt, live: settings.player.liveBackground, calm: calm,
                                     playing: player.isPlaying, bpm: facts.bpm, dolly: dolly, closing: closing,
                                     focused: focused)
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
                .clipShape(RoundedRectangle(cornerRadius: travel > 0 ? 28 * min(pulled * 5, 1) : 0, style: .continuous))
                .scaleEffect(1 - 0.06 * pulled)
                .offset(y: travel)
                .contentShape(Rectangle())
                .gesture(playerDrag(cap: cap, folded: lyrics.open && !sideways))
            }
            .ignoresSafeArea()
        }
        .background(PlayerStatusBar(dark: colors.dark))
        .sensoryFeedback(.impact(flexibility: .rigid, intensity: 0.8), trigger: ticks)
        .onChange(of: dragging) { _, now in
            guard !now, axis != .undecided else {
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
            if !lyrics.open { toggleLyrics() }
        }
        .onChange(of: lyrics.open) { _, open in showLyrics(open, animated: true) }
        .onChange(of: drive.request, initial: true) { _, request in
            guard let request else { return }
            drive.taken()
            take(request)
        }
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
    }

    /// The wash slows to 10 frames a second while a card is open over it or the app is not in
    /// front.
    private var focused: Bool {
        scenePhase == .active && !(showsSleep || showsSpeed || showsTiming || showsChooser)
    }

    // MARK: Layouts

    private func uprightLayout(_ insets: EdgeInsets) -> some View {
        let open = lyrics.open
        return VStack(spacing: 0) {
            topLine
            artStage(maxSide: 312, folds: true)
            ZStack(alignment: .bottom) {
                if open {
                    LyricsBar(ink: ink, close: toggleLyrics, timing: $showsTiming) { showsChooser = true }
                        .padding(.horizontal, -12)
                        .padding(.bottom, 12)
                        .transition(swap)
                } else {
                    controls(roomy: true)
                        .padding(.bottom, 16)
                        .offset(y: rise)
                        .opacity(riseAlpha)
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
                            .offset(y: rise)
                            .opacity(riseAlpha)
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
            if let song = player.current, let name = albumLabel(song.album, song.title, facts.albumSongs) {
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

    private func artStage(maxSide: CGFloat, folds: Bool) -> some View {
        GeometryReader { box in
            let side = max(0, min(maxSide, box.size.width, box.size.height))
            let folded = folds ? fold : 0
            let swiped = 1 - 0.5 * min(abs(card) / max(box.size.width / 2, 1), 1)
            Cover(id: player.current?.coverArt, size: side, radius: side * corner / 100)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                    flight.cardPlaced(frame)
                    cardFrame = frame
                }
                .elevation3()
                .opacity(flight.hidesCard ? 0 : 1)
                .scaleEffect(player.isPlaying ? 1 : 0.84)
                .animation(.octoSpring(0.6, 300), value: player.isPlaying)
                .scaleEffect(1 - 0.08 * folded)
                .opacity((1 - folded) * swiped)
                .offset(x: card)
                .frame(width: box.size.width, height: box.size.height)
                .accessibilityHidden(true)
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { stage = $0 }
    }

    // MARK: Controls

    private func controls(roomy: Bool) -> some View {
        let gap: CGFloat = roomy ? 12 : 4
        return VStack(spacing: 0) {
            if let song = player.current {
                HStack(spacing: 0) {
                    ZStack(alignment: .leading) {
                        PlayerTitleBlock(song: song, ink: ink, accent: accent, openArtist: artistOpener(song))
                            .id(song.id)
                            .transition(.asymmetric(insertion: .opacity.animation(.octoTween(fixed: 250, OctoEasing.standard)),
                                                    removal: .opacity.animation(.octoTween(fixed: 150, OctoEasing.standard))))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    keeper(song)
                    moreButton
                }
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

    private func artistOpener(_ song: Song) -> (() -> Void)? {
        guard let artistId = song.artistId, !artistId.isEmpty else { return nil }
        return { close { router.go(.artist(id: artistId, name: song.artist ?? "")) } }
    }

    /// The heart for a library song; for a song found online, the add button.
    @ViewBuilder
    private func keeper(_ song: Song) -> some View {
        if song.isExternal || isFind(song.id) {
            AddToLibraryButton(song: song).id(song.id)
        } else if let trackId = facts.trackId {
            PlayerHeart(liked: likes.isLiked(trackId), ink: ink) { likes.toggle(trackId) }
        } else {
            Color.clear.frame(width: 44, height: 44)
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
            IconView(.more, size: 24, color: ink.opacity(0.6))
                .frame(width: 44, height: 44)
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
            let state = player.sleepState
            PlayerSwitch(icon: .sleepTimer, label: "Sleep timer", lit: state != .off, ink: ink,
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
            PlayerSwitch(icon: .shuffle, label: "Shuffle", lit: player.shuffled, ink: ink) { player.toggleShuffle() }
            PlayerSwitch(icon: player.repeatMode == .one ? .repeatOne : .repeatAll, label: "Repeat", lit: player.repeatMode != .off,
                         ink: ink, state: repeatWords) { player.cycleRepeat() }
        }
        .frame(maxWidth: .infinity)
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
        flight.playerOpening(player.current?.coverArt)
        showLyrics(lyrics.open, animated: false)
        withAnimation(PlayerDolly.open) { dolly = 1 }
        withAnimation(.octoSpring(1, 1500)) { corner = 3 }
        withAnimation(.octoSpring(0.68, 400)) { rise = 0 }
        withAnimation(.octoTween(fixed: 380, OctoEasing.standard, delay: 80)) { riseAlpha = 1 }
    }

    /// Closes the player: the background draws back and the cover rounds as it flies home. `then`
    /// opens a page in its place as the player goes.
    private func close(then go: (() -> Void)? = nil) {
        guard !closing else { return }
        closing = true
        flight.playerClosing(player.current?.coverArt)
        withAnimation(PlayerDolly.close) { dolly = 0 }
        withAnimation(.octoSpring(1, 1500)) { corner = 50 }
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
                dragMoved(value.translation, cap: cap, onCard: !folded && cardFrame.contains(value.startLocation))
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
        if axis == .undecided {
            if onCard && !artDecided {
                switch dragAxis(dx, dy, slop: Self.slop) {
                case .horizontal:
                    axis = .horizontal
                    // A new swipe takes over from one still settling.
                    settle += 1
                case .vertical:
                    artDecided = true
                case .undecided:
                    break
                }
            }
            if axis == .undecided {
                let moved = dy - slopOrigin
                if moved <= -Self.slop {
                    slopOrigin = dy
                } else if moved >= Self.slop {
                    axis = .vertical
                    pull = min(max((moved - Self.slop) * 0.82, 0), cap)
                    lastDy = dy
                    return
                }
            }
        }
        switch axis {
        case .vertical:
            pull = min(max(pull + (dy - lastDy) * 0.82, 0), cap)
            lastDy = dy
        case .horizontal:
            card = dx * 0.55
            mark(abs(dx) >= Self.skipAt)
        case .undecided:
            break
        }
    }

    /// The finger lifted: a flick down or a pull past half the way closes, unless it was moving
    /// back up; a swipe of the artwork skips or springs back.
    private func dragEnded(_ t: CGSize, _ velocity: CGSize, cap: CGFloat) {
        let taken = axis
        resetDrag()
        switch taken {
        case .vertical:
            let speed = velocity.height
            if speed > 1200 || (pull > cap / 2 && speed > -150) {
                close()
            } else {
                withAnimation(.octoSpring(0.8, 400)) { pull = 0 }
            }
        case .horizontal:
            finishSwipe(t.width, velocity.width)
        case .undecided:
            break
        }
    }

    /// A drag taken over by something else ends as if it went nowhere.
    private func dragTakenOver() {
        let taken = axis
        resetDrag()
        switch taken {
        case .vertical:
            withAnimation(.octoSpring(0.8, 400)) { pull = 0 }
        case .horizontal:
            finishSwipe(0, 0)
        case .undecided:
            break
        }
    }

    private func resetDrag() {
        axis = .undecided
        artDecided = false
        slopOrigin = 0
        lastDy = 0
    }

    /// One tick each time the finger passes the point where letting go skips.
    private func mark(_ past: Bool) {
        guard past != armed else { return }
        armed = past
        if past { ticks += 1 }
    }

    /// Settles a swipe of the artwork. A skip carries it on out the way it was going, changes the
    /// song, and brings the new one in from 20% out on the other side; otherwise it springs back.
    /// A new swipe calls off a settle still under way.
    private func finishSwipe(_ offset: CGFloat, _ velocity: CGFloat) {
        let result = swipeSkip(offset: Double(offset), velocity: Double(velocity), distance: Double(Self.skipAt), fling: 900)
        if result != .stay && !armed { ticks += 1 }
        armed = false
        settle += 1
        let token = settle
        let width = max(stage.width, 1)
        switch result {
        case .stay:
            withAnimation(.octoSpring(0.8, 400)) { card = 0 }
        case .next, .previous:
            let way: CGFloat = result == .next ? -1 : 1
            withAnimation(.octoTween(fixed: 120)) {
                card = way * width / 2
            } completion: {
                guard token == settle else { return }
                if result == .next { player.next() } else { player.previous() }
                var still = Transaction()
                still.disablesAnimations = true
                withTransaction(still) { card = -way * width * 0.2 }
                DispatchQueue.main.async {
                    guard token == settle else { return }
                    withAnimation(.octoSpring(0.8, 300)) { card = 0 }
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
        case "queue": showsQueue = true
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
        default: break
        }
    }
}
