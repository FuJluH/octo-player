import Foundation
import Network
import Observation
import OctoKit
import UIKit

/// Every setting the Settings pages keep, in one place. Each group lives in its own preferences
/// suite, under the same names the other Octo apps use ("player", "offline", "lyrics",
/// "listenbrainz", "updates", "playlist_art", "library", "home"), so any part of the app can read a value
/// here and a backup carries the same keys. Changes apply at once: whatever reads a value sees
/// the new one on its next look.
@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings()

    private(set) var player: PlayerPrefs
    private(set) var stream: StreamPrefs
    private(set) var offline: OfflinePrefs
    /// Whether the screen stays on while lyrics show in the player.
    private(set) var keepScreenOn: Bool
    private(set) var lyricsLook: LyricsLook
    /// Each output's lyrics timing the listener set, in ms, by output key.
    private(set) var outputTimings: [String: Int]
    private(set) var listenBrainz: ListenBrainzPrefs
    private(set) var playlistCovers: PlaylistCoverStyle
    /// Phone music folders left out of the library, by name.
    private(set) var excludedFolders: Set<String>
    private(set) var checkUpdatesAutomatically: Bool
    private(set) var earlyVersions: Bool
    /// Whether a ready update goes in on its own; kept as "Ask" or "OnQuit".
    private(set) var installUpdates: String
    /// Home's shelves in their order, each shown or hidden.
    private(set) var homeSections: [HomeSectionEntry]

    /// True while the phone's connection is mobile data (not Wi-Fi, not a cable).
    private(set) var onMobileData = false

    @ObservationIgnored private let playerStore = UserDefaults(suiteName: "player") ?? .standard
    @ObservationIgnored private let offlineStore = UserDefaults(suiteName: "offline") ?? .standard
    @ObservationIgnored private let lyricsStore = UserDefaults(suiteName: "lyrics") ?? .standard
    @ObservationIgnored let listenBrainzStore = UserDefaults(suiteName: "listenbrainz") ?? .standard
    @ObservationIgnored private let updatesStore = UserDefaults(suiteName: "updates") ?? .standard
    @ObservationIgnored private let playlistArtStore = UserDefaults(suiteName: "playlist_art") ?? .standard
    @ObservationIgnored private let libraryStore = UserDefaults(suiteName: "library") ?? .standard
    @ObservationIgnored private let homeStore = UserDefaults(suiteName: "home") ?? .standard
    @ObservationIgnored private let network = NWPathMonitor()
    @ObservationIgnored private weak var session: Session?
    @ObservationIgnored private var familyAppPicks: @MainActor () -> Bool = { true }

    private init() {
        player = Self.readPlayer(playerStore)
        stream = Self.readStream(playerStore)
        offline = Self.readOffline(offlineStore)
        keepScreenOn = lyricsStore.object(forKey: Keys.keepScreenOn) as? Bool ?? true
        lyricsLook = Self.readLook(lyricsStore)
        outputTimings = Self.readOutputTimings(lyricsStore)
        listenBrainz = ListenBrainzPrefs()
        playlistCovers = PlaylistCoverStyle.stored(playlistArtStore.string(forKey: Keys.playlistCovers), or: .designed)
        excludedFolders = Set(libraryStore.stringArray(forKey: Keys.excludedFolders) ?? [])
        checkUpdatesAutomatically = updatesStore.object(forKey: Keys.checkAutomatically) as? Bool ?? true
        earlyVersions = updatesStore.object(forKey: Keys.earlyVersions) as? Bool ?? false
        let install = updatesStore.string(forKey: Keys.install)
        installUpdates = install == "OnQuit" ? "OnQuit" : "Ask"
        homeSections = homeSectionOrder(stored: homeStore.string(forKey: homeSectionsKey))
        listenBrainz = readListenBrainz()
        migrateOldQuality()
        network.pathUpdateHandler = { [weak self] path in
            // Mobile data: connected, with neither Wi-Fi nor a cable.
            let mobile = path.status == .satisfied && !path.usesInterfaceType(.wifi) && !path.usesInterfaceType(.wiredEthernet)
            Task { @MainActor in
                guard let self, self.onMobileData != mobile else { return }
                self.onMobileData = mobile
                self.applyQuality()
            }
        }
        network.start(queue: DispatchQueue(label: "app.winters.octo.settings.network"))
    }

    // MARK: Streaming quality in use

    /// Hands the session the stream size this phone asks for now, and keeps it up to date.
    /// `appPicks` says whether this app's own choice applies (no family, or this phone left to
    /// the app).
    func attach(session: Session, appPicks: @escaping @MainActor () -> Bool = { true }) {
        self.session = session
        familyAppPicks = appPicks
        applyQuality()
    }

    /// The stream size this phone asks for now: on mobile data the mobile data choice, otherwise
    /// (Wi-Fi, a cable, or no connection at all) the Wi-Fi choice; the file as it is when this app
    /// does not pick the quality, so the server applies the account's own.
    var qualityInUse: StreamQuality {
        guard familyAppPicks() else { return .original }
        return onMobileData ? stream.mobile : stream.wifi
    }

    func applyQuality() {
        guard let session else { return }
        let quality = qualityInUse
        if session.quality != quality { session.quality = quality }
    }

    /// The first builds kept one stream size; it becomes this app's size on Wi-Fi and on mobile
    /// data, once ever. The old value is still written as the size in use changes, so it is
    /// never read again after the first start that looks.
    private func migrateOldQuality() {
        let old = UserDefaults.standard
        let moved = old.bool(forKey: Self.oldQualityMovedKey)
        let stored = old.object(forKey: Self.oldQualityKey) != nil ? old.integer(forKey: Self.oldQualityKey) : nil
        let chosen = playerStore.string(forKey: Keys.streamWifi) != nil || playerStore.string(forKey: Keys.streamMobile) != nil
        let quality = movedStreamQuality(oldKbps: stored, alreadyMoved: moved, sizesChosen: chosen)
        if !moved { old.set(true, forKey: Self.oldQualityMovedKey) }
        guard let quality else { return }
        setStreamWifi(quality)
        setStreamMobile(quality)
    }

    private static let oldQualityKey = "stream.quality"
    private static let oldQualityMovedKey = "stream.quality.moved"

    // MARK: Player

    /// Changes the player settings, writing only what changed.
    func update(_ change: (inout PlayerPrefs) -> Void) {
        var next = player
        change(&next)
        next = next.sane()
        guard next != player else { return }
        writePlayer(from: player, to: next)
        player = next
    }

    func setCrossfade(_ on: Bool) { update { $0.crossfade = on } }
    func setCrossfadeSeconds(_ seconds: Int) { update { $0.crossfadeSeconds = seconds } }
    func setCrossfadeCurve(_ curve: FadeCurve) { update { $0.crossfadeCurve = curve } }
    func setSmartTransitions(_ on: Bool) { update { $0.smartTransitions = on } }
    func setFilterSweeps(_ on: Bool) { update { $0.filterSweeps = on } }
    func setMatchTempo(_ on: Bool) { update { $0.matchTempo = on } }
    func setLyricsOnline(_ on: Bool) { update { $0.lyricsOnline = on } }
    func setSpeed(_ speed: Float) { update { $0.speed = Pace.snapSpeed(speed) } }
    func setKeepPitch(_ on: Bool) { update { $0.keepPitch = on } }
    func setPitchSemitones(_ semitones: Int) { update { $0.pitchSemitones = semitones } }
    func setSkipSilence(_ on: Bool) { update { $0.skipSilence = on } }
    func setAutoplay(_ on: Bool) { update { $0.autoplay = on } }
    func setRadioDiscovery(_ value: RadioDiscovery) { update { $0.radioDiscovery = value } }
    func setRadioAdventure(_ value: RadioAdventure) { update { $0.radioAdventure = value } }
    func setRadioVariety(_ value: RadioVariety) { update { $0.radioVariety = value } }
    func setRadioFavorites(_ on: Bool) { update { $0.radioFavorites = on } }
    func setResumeWired(_ on: Bool) { update { $0.resumeWired = on } }
    func setResumeBluetooth(_ on: Bool) { update { $0.resumeBluetooth = on } }
    func setResumeAlways(_ on: Bool) { update { $0.resumeAlways = on } }
    func setCastKeepPlaying(_ on: Bool) { update { $0.castKeepPlaying = on } }
    func setLiveBackground(_ on: Bool) { update { $0.liveBackground = on } }
    func setReduceMotion(_ on: Bool) { update { $0.reduceMotion = on } }

    /// Whether what moves only for show holds still: Octo's own switch, or the phone's Reduce
    /// Motion. Read wherever motion is drawn.
    var motionReduced: Bool { player.reduceMotion || UIAccessibility.isReduceMotionEnabled }
    func setLibraryOnly(_ on: Bool) { update { $0.libraryOnly = on } }
    func setAccent(_ accent: AccentChoice) { update { $0.accent = accent } }
    func setGlassTint(_ on: Bool) { update { $0.glassTint = on } }
    func setAmbientStrength(_ strength: AmbientStrength) { update { $0.ambient.strength = strength } }

    func setAmbientArea(_ area: AmbientArea, _ on: Bool) {
        update {
            switch area {
            case .home: $0.ambient.home = on
            case .library: $0.ambient.library = on
            case .search: $0.ambient.search = on
            case .settings: $0.ambient.settings = on
            }
        }
    }

    func setAmbientBar(_ on: Bool) { update { $0.ambient.bar = on } }
    func setAmbientPageArtwork(_ on: Bool) { update { $0.ambient.pageArtwork = on } }

    /// The player's background settings, all seven written at once.
    func setBackground(_ change: (inout BackgroundPrefs) -> Void) {
        var next = player.background
        change(&next)
        next = next.sane()
        writeBackground(next)
        var prefs = player
        prefs.background = next
        player = prefs
    }

    /// Normal speed and pitch again: the stored speed, keep pitch and pitch shift are removed.
    func resetPace() {
        for key in [Keys.speed, Keys.keepPitch, Keys.pitchSemitones] { playerStore.removeObject(forKey: key) }
        var prefs = player
        prefs.speed = 1
        prefs.keepPitch = true
        prefs.pitchSemitones = 0
        player = prefs
    }

    // MARK: Streaming

    func setCopies(_ value: CopyPreference) {
        playerStore.set(value.storedName, forKey: Keys.copies)
        stream.copies = value
    }

    func setStreamWifi(_ value: StreamQuality) {
        playerStore.set(value.storedName, forKey: Keys.streamWifi)
        stream.wifi = value
        applyQuality()
    }

    func setStreamMobile(_ value: StreamQuality) {
        playerStore.set(value.storedName, forKey: Keys.streamMobile)
        stream.mobile = value
        applyQuality()
    }

    func setStartAfter(_ value: StartAfter) {
        playerStore.set(value.storedName, forKey: Keys.startAfter)
        stream.startAfter = value
    }

    // MARK: Offline

    func setCacheSize(_ value: CacheSize) {
        offlineStore.set(value.storedName, forKey: Keys.cacheSize)
        offline.cacheSize = value
    }

    func setPrefetchWifi(_ count: Int) {
        let held = count.held(to: OfflinePrefs.prefetchRange)
        offlineStore.set(held, forKey: Keys.prefetchWifi)
        offline.prefetchWifi = held
    }

    func setPrefetchMobile(_ count: Int) {
        let held = count.held(to: OfflinePrefs.prefetchRange)
        offlineStore.set(held, forKey: Keys.prefetchMobile)
        offline.prefetchMobile = held
    }

    func setDownloadQuality(_ value: StreamQuality) {
        offlineStore.set(value.storedName, forKey: Keys.downloadQuality)
        offline.downloadQuality = value
    }

    func setWifiOnly(_ on: Bool) {
        offlineStore.set(on, forKey: Keys.wifiOnly)
        offline.wifiOnly = on
    }

    func setStreamOnWifi(_ on: Bool) {
        offlineStore.set(on, forKey: Keys.streamOnWifi)
        offline.streamOnWifi = on
    }

    func setKeepLiked(_ on: Bool) {
        offlineStore.set(on, forKey: Keys.keepLiked)
        offline.keepLiked = on
    }

    func setPlaylistKept(_ id: String, kept: Bool) {
        var ids = Set(offline.keptPlaylists)
        if kept { ids.insert(id) } else { ids.remove(id) }
        offline.keptPlaylists = ids.sorted()
        offlineStore.set(offline.keptPlaylists, forKey: Keys.keptPlaylists)
    }

    /// Puts back the offline settings from a backup in one go. Its kept playlists join the ones
    /// already kept here.
    func restoreOffline(_ prefs: OfflinePrefs, keptPlaylistIds: [String]) {
        setCacheSize(prefs.cacheSize)
        setPrefetchWifi(prefs.prefetchWifi)
        setPrefetchMobile(prefs.prefetchMobile)
        setDownloadQuality(prefs.downloadQuality)
        setWifiOnly(prefs.wifiOnly)
        setStreamOnWifi(prefs.streamOnWifi)
        setKeepLiked(prefs.keepLiked)
        offline.keptPlaylists = Set(offline.keptPlaylists).union(keptPlaylistIds).sorted()
        offlineStore.set(offline.keptPlaylists, forKey: Keys.keptPlaylists)
    }

    /// Puts back every player and streaming setting from a backup in one go.
    func restore(player restored: PlayerPrefs, stream restoredStream: StreamPrefs) {
        let next = restored.sane()
        writePlayer(from: nil, to: next)
        player = next
        setCopies(restoredStream.copies)
        setStreamWifi(restoredStream.wifi)
        setStreamMobile(restoredStream.mobile)
        setStartAfter(restoredStream.startAfter)
    }

    // MARK: Lyrics

    func setKeepScreenOn(_ on: Bool) {
        lyricsStore.set(on, forKey: Keys.keepScreenOn)
        keepScreenOn = on
    }

    func setLyricsStyle(_ style: LyricsStyle) {
        lyricsStore.set(style.rawValue, forKey: Keys.lyricsStyle)
        lyricsLook.style = style
    }

    func setLookDial(_ dial: LookDial, _ percent: Int) {
        let look = lyricsLook.with(dial, percent: percent)
        lyricsStore.set(look.percent(dial), forKey: dial.key)
        lyricsLook = look
    }

    func setKeepCompleted(_ on: Bool) {
        lyricsStore.set(on, forKey: Keys.keepCompleted)
        lyricsLook.keepCompleted = on
    }

    func setArc(_ on: Bool) {
        lyricsStore.set(on, forKey: Keys.arc)
        lyricsLook.arc = on
    }

    func setBloomFast(_ on: Bool) {
        lyricsStore.set(on, forKey: Keys.bloomFast)
        lyricsLook.bloomFast = on
    }

    /// Puts back the whole look from a backup, each dial held to its range.
    func restoreLook(_ look: LyricsLook) {
        setLyricsStyle(look.style)
        for dial in LookDial.allCases { setLookDial(dial, look.percent(dial)) }
        setKeepCompleted(look.keepCompleted)
        setArc(look.arc)
        setBloomFast(look.bloomFast)
    }

    /// An output's lyrics timing, and whether it is the automatic one (never set by the listener).
    func outputTiming(_ outputKey: String) -> (ms: Int, automatic: Bool) {
        if let set = outputTimings[outputKey] { return (set, false) }
        return (LyricsOutputTiming.automatic(outputKey), true)
    }

    /// Moves an output's timing some steps from where it is now, and saves it under its key, 0
    /// included.
    func stepOutputTiming(_ outputKey: String, steps: Int) {
        setOutputTiming(outputKey, LyricsOutputTiming.step(outputTiming(outputKey).ms, steps: steps))
    }

    func setOutputTiming(_ outputKey: String, _ ms: Int) {
        let held = ms.held(to: -LyricsOutputTiming.limitMs...LyricsOutputTiming.limitMs)
        lyricsStore.set(held, forKey: LyricsOutputTiming.keyPrefix + outputKey)
        outputTimings[outputKey] = held
    }

    /// Back to the output's automatic timing.
    func resetOutputTiming(_ outputKey: String) {
        lyricsStore.removeObject(forKey: LyricsOutputTiming.keyPrefix + outputKey)
        outputTimings[outputKey] = nil
    }

    // MARK: Appearance, library, updates

    /// How an album's animated art shows: in place of the cover, filling the player, or not at all.
    var animatedArt: AnimatedArtSetting { player.animatedArt }
    func setAnimatedArt(_ setting: AnimatedArtSetting) { update { $0.animatedArt = setting } }

    func setPlaylistCovers(_ style: PlaylistCoverStyle) {
        playlistArtStore.set(style.storedName, forKey: Keys.playlistCovers)
        playlistCovers = style
    }

    func setFolderIncluded(_ name: String, _ included: Bool) {
        if included { excludedFolders.remove(name) } else { excludedFolders.insert(name) }
        libraryStore.set(excludedFolders.sorted(), forKey: Keys.excludedFolders)
    }

    /// The left-out folders become exactly these.
    func setExcludedFolders(_ names: Set<String>) {
        excludedFolders = names
        libraryStore.set(names.sorted(), forKey: Keys.excludedFolders)
    }

    func setCheckUpdatesAutomatically(_ on: Bool) {
        updatesStore.set(on, forKey: Keys.checkAutomatically)
        checkUpdatesAutomatically = on
    }

    func setEarlyVersions(_ on: Bool) {
        updatesStore.set(on, forKey: Keys.earlyVersions)
        earlyVersions = on
    }

    // MARK: Home

    /// Home's shelves become exactly these, kept as one string under "home_sections".
    func setHomeSections(_ entries: [HomeSectionEntry]) {
        guard entries != homeSections else { return }
        homeStore.set(encodeHomeSections(entries), forKey: homeSectionsKey)
        homeSections = entries
    }

    /// Moves shelves as a list's drag reports it.
    func moveHomeSections(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        setHomeSections(OctoKit.moveHomeSections(homeSections, fromOffsets: offsets, toOffset: destination))
    }

    func setHomeSectionShown(_ section: HomeSection, _ shown: Bool) {
        setHomeSections(toggleHomeSection(homeSections, section, shown: shown))
    }

    /// Every shelf back in the default order and shown. Nothing is kept, so the order follows
    /// the default should it change.
    func resetHomeSections() {
        homeStore.removeObject(forKey: homeSectionsKey)
        homeSections = OctoKit.resetHomeSections()
    }

    /// Whether a shelf is drawn on Home.
    func homeSectionShown(_ section: HomeSection) -> Bool {
        homeSections.first { $0.section == section }?.shown ?? true
    }

    // MARK: ListenBrainz

    func readListenBrainz() -> ListenBrainzPrefs {
        let store = listenBrainzStore
        let sealed = store.bool(forKey: Keys.tokenSealed)
        return ListenBrainzPrefs(
            enabled: store.bool(forKey: Keys.enabled),
            user: sealed ? store.string(forKey: Keys.user) : nil,
            needsAttention: store.bool(forKey: Keys.needsAttention),
            sendPlays: SendPlays.stored(store.string(forKey: Keys.sendPlays), or: .all),
            nowPlaying: store.object(forKey: Keys.nowPlaying) as? Bool ?? true
        )
    }

    /// Reads the ListenBrainz settings again after they were written.
    func refreshListenBrainz() { listenBrainz = readListenBrainz() }

    // MARK: Reading and writing

    enum Keys {
        static let liveBackground = "live_background"
        static let crossfade = "crossfade"
        static let crossfadeSeconds = "crossfade_seconds"
        static let crossfadeCurve = "crossfade_curve"
        static let smartTransitions = "smart_transitions"
        static let filterSweeps = "filter_sweeps"
        static let matchTempo = "match_tempo"
        static let lyricsOnline = "lyrics_online"
        static let speed = "speed"
        static let keepPitch = "keep_pitch"
        static let pitchSemitones = "pitch_semitones"
        static let skipSilence = "skip_silence"
        static let autoplay = "autoplay"
        static let radioDiscovery = "radio_discovery"
        static let radioAdventure = "radio_adventure"
        static let radioVariety = "radio_variety"
        static let radioFavorites = "radio_favorites"
        static let resumeWired = "resume_wired"
        static let resumeBluetooth = "resume_bluetooth"
        static let resumeAlways = "resume_always"
        static let copies = "copies"
        static let ambientStrength = "ambient_strength"
        static let ambientHome = "ambient_home"
        static let ambientLibrary = "ambient_library"
        static let ambientSearch = "ambient_search"
        static let ambientSettings = "ambient_settings"
        static let ambientBar = "ambient_bar"
        static let ambientPageArtwork = "ambient_page_artwork"
        static let streamWifi = "stream_wifi"
        static let streamMobile = "stream_mobile"
        static let startAfter = "start_after"
        static let backgroundMode = "immersive_background"
        static let backgroundBrightnessCap = "immersive_bg_brightness_cap"
        static let backgroundSaturation = "immersive_bg_saturation"
        static let backgroundContrast = "immersive_bg_contrast"
        static let backgroundUseBpm = "immersive_bg_use_bpm"
        static let backgroundFps = "immersive_bg_fps"
        static let backgroundSpeed = "immersive_bg_speed"
        static let reduceMotion = "reduce_motion"
        static let castRenderers = "cast_renderers"
        static let castKeepPlaying = "cast_keep_playing"
        static let libraryOnly = "library_only"
        static let accent = "accent_color"
        static let glassTint = "accent_glass"

        static let cacheSize = "cache_size"
        static let prefetchWifi = "prefetch_wifi"
        static let prefetchMobile = "prefetch_mobile"
        static let downloadQuality = "download_quality"
        static let wifiOnly = "wifi_only"
        static let streamOnWifi = "stream_on_wifi"
        static let keepLiked = "keep_liked"
        static let keptPlaylists = "kept_playlists"

        static let keepScreenOn = "keep_screen_on"
        static let lyricsStyle = "lyrics_style"
        static let keepCompleted = "lyrics_keep_completed"
        static let arc = "lyrics_arc"
        static let bloomFast = "lyrics_bloom_fast"

        static let enabled = "enabled"
        static let user = "user"
        static let tokenSealed = "token_sealed"
        static let needsAttention = "needs_attention"
        static let sendPlays = "send_plays"
        static let nowPlaying = "now_playing"

        static let checkAutomatically = "check_automatically"
        static let install = "install"
        static let earlyVersions = "early_versions"

        static let playlistCovers = "playlist_covers"
        static let excludedFolders = "excluded_folders"
    }

    private static func readPlayer(_ s: UserDefaults) -> PlayerPrefs {
        func bool(_ key: String, _ fallback: Bool) -> Bool { s.object(forKey: key) as? Bool ?? fallback }
        func int(_ key: String, _ fallback: Int) -> Int { s.object(forKey: key) as? Int ?? fallback }
        var p = PlayerPrefs()
        let d = PlayerPrefs()
        p.liveBackground = bool(Keys.liveBackground, d.liveBackground)
        p.background.mode = BackgroundMode.stored(s.string(forKey: Keys.backgroundMode), or: d.background.mode)
        p.background.brightnessCap = int(Keys.backgroundBrightnessCap, d.background.brightnessCap)
        p.background.saturation = int(Keys.backgroundSaturation, d.background.saturation)
        p.background.contrast = (s.object(forKey: Keys.backgroundContrast) as? NSNumber)?.floatValue ?? d.background.contrast
        p.background.useBpm = bool(Keys.backgroundUseBpm, d.background.useBpm)
        p.background.fps = int(Keys.backgroundFps, d.background.fps)
        p.background.speed = int(Keys.backgroundSpeed, d.background.speed)
        p.crossfade = bool(Keys.crossfade, d.crossfade)
        p.crossfadeSeconds = int(Keys.crossfadeSeconds, d.crossfadeSeconds)
        p.crossfadeCurve = FadeCurve.stored(s.string(forKey: Keys.crossfadeCurve), or: d.crossfadeCurve)
        p.smartTransitions = bool(Keys.smartTransitions, d.smartTransitions)
        p.filterSweeps = bool(Keys.filterSweeps, d.filterSweeps)
        p.matchTempo = bool(Keys.matchTempo, d.matchTempo)
        p.lyricsOnline = bool(Keys.lyricsOnline, d.lyricsOnline)
        p.speed = (s.object(forKey: Keys.speed) as? NSNumber)?.floatValue ?? d.speed
        p.keepPitch = bool(Keys.keepPitch, d.keepPitch)
        p.pitchSemitones = int(Keys.pitchSemitones, d.pitchSemitones)
        p.skipSilence = bool(Keys.skipSilence, d.skipSilence)
        p.autoplay = bool(Keys.autoplay, d.autoplay)
        p.radioDiscovery = RadioDiscovery.stored(s.string(forKey: Keys.radioDiscovery), or: d.radioDiscovery)
        p.radioAdventure = RadioAdventure.stored(s.string(forKey: Keys.radioAdventure), or: d.radioAdventure)
        p.radioVariety = RadioVariety.stored(s.string(forKey: Keys.radioVariety), or: d.radioVariety)
        p.radioFavorites = bool(Keys.radioFavorites, d.radioFavorites)
        p.resumeWired = bool(Keys.resumeWired, d.resumeWired)
        p.resumeBluetooth = bool(Keys.resumeBluetooth, d.resumeBluetooth)
        p.resumeAlways = bool(Keys.resumeAlways, d.resumeAlways)
        p.ambient.strength = AmbientStrength.stored(s.string(forKey: Keys.ambientStrength), or: d.ambient.strength)
        p.ambient.home = bool(Keys.ambientHome, true)
        p.ambient.library = bool(Keys.ambientLibrary, true)
        p.ambient.search = bool(Keys.ambientSearch, true)
        p.ambient.settings = bool(Keys.ambientSettings, true)
        p.ambient.bar = bool(Keys.ambientBar, true)
        p.ambient.pageArtwork = bool(Keys.ambientPageArtwork, true)
        p.reduceMotion = bool(Keys.reduceMotion, d.reduceMotion)
        p.castRenderers = bool(Keys.castRenderers, d.castRenderers)
        p.castKeepPlaying = bool(Keys.castKeepPlaying, d.castKeepPlaying)
        p.libraryOnly = bool(Keys.libraryOnly, d.libraryOnly)
        p.accent = AccentChoice.stored(s.string(forKey: Keys.accent), or: d.accent)
        p.glassTint = bool(Keys.glassTint, d.glassTint)
        p.animatedArt = AnimatedArtSetting.from(key: s.string(forKey: AnimatedArtSetting.prefKey))
        return p.sane()
    }

    /// Writes the player settings that differ from `old`, or every one when `old` is nil.
    private func writePlayer(from old: PlayerPrefs?, to new: PlayerPrefs) {
        let s = playerStore
        func put<T: Equatable>(_ path: KeyPath<PlayerPrefs, T>, _ key: String, _ value: (T) -> Any = { $0 }) {
            if old == nil || old![keyPath: path] != new[keyPath: path] { s.set(value(new[keyPath: path]), forKey: key) }
        }
        put(\.liveBackground, Keys.liveBackground)
        if old == nil || old!.background != new.background { writeBackground(new.background) }
        put(\.crossfade, Keys.crossfade)
        put(\.crossfadeSeconds, Keys.crossfadeSeconds)
        put(\.crossfadeCurve, Keys.crossfadeCurve) { $0.storedName }
        put(\.smartTransitions, Keys.smartTransitions)
        put(\.filterSweeps, Keys.filterSweeps)
        put(\.matchTempo, Keys.matchTempo)
        put(\.lyricsOnline, Keys.lyricsOnline)
        put(\.speed, Keys.speed)
        put(\.keepPitch, Keys.keepPitch)
        put(\.pitchSemitones, Keys.pitchSemitones)
        put(\.skipSilence, Keys.skipSilence)
        put(\.autoplay, Keys.autoplay)
        put(\.radioDiscovery, Keys.radioDiscovery) { $0.storedName }
        put(\.radioAdventure, Keys.radioAdventure) { $0.storedName }
        put(\.radioVariety, Keys.radioVariety) { $0.storedName }
        put(\.radioFavorites, Keys.radioFavorites)
        put(\.resumeWired, Keys.resumeWired)
        put(\.resumeBluetooth, Keys.resumeBluetooth)
        put(\.resumeAlways, Keys.resumeAlways)
        put(\.ambient.strength, Keys.ambientStrength) { $0.storedName }
        put(\.ambient.home, Keys.ambientHome)
        put(\.ambient.library, Keys.ambientLibrary)
        put(\.ambient.search, Keys.ambientSearch)
        put(\.ambient.settings, Keys.ambientSettings)
        put(\.ambient.bar, Keys.ambientBar)
        put(\.ambient.pageArtwork, Keys.ambientPageArtwork)
        put(\.reduceMotion, Keys.reduceMotion)
        put(\.castRenderers, Keys.castRenderers)
        put(\.castKeepPlaying, Keys.castKeepPlaying)
        put(\.libraryOnly, Keys.libraryOnly)
        put(\.accent, Keys.accent) { $0.storedName }
        put(\.glassTint, Keys.glassTint)
        put(\.animatedArt, AnimatedArtSetting.prefKey) { $0.storedName }
    }

    private func writeBackground(_ b: BackgroundPrefs) {
        let s = playerStore
        s.set(b.mode.storedName, forKey: Keys.backgroundMode)
        s.set(b.brightnessCap, forKey: Keys.backgroundBrightnessCap)
        s.set(b.saturation, forKey: Keys.backgroundSaturation)
        s.set(b.contrast, forKey: Keys.backgroundContrast)
        s.set(b.useBpm, forKey: Keys.backgroundUseBpm)
        s.set(b.fps, forKey: Keys.backgroundFps)
        s.set(b.speed, forKey: Keys.backgroundSpeed)
    }

    private static func readStream(_ s: UserDefaults) -> StreamPrefs {
        StreamPrefs(
            copies: CopyPreference.stored(s.string(forKey: Keys.copies), or: .phoneFirst),
            wifi: StreamQuality.stored(s.string(forKey: Keys.streamWifi), or: .original),
            mobile: StreamQuality.stored(s.string(forKey: Keys.streamMobile), or: .original),
            startAfter: StartAfter.stored(s.string(forKey: Keys.startAfter), or: .short)
        )
    }

    private static func readOffline(_ s: UserDefaults) -> OfflinePrefs {
        var p = OfflinePrefs()
        p.cacheSize = CacheSize.stored(s.string(forKey: Keys.cacheSize), or: .gb2)
        p.prefetchWifi = (s.object(forKey: Keys.prefetchWifi) as? Int ?? 3).held(to: OfflinePrefs.prefetchRange)
        p.prefetchMobile = (s.object(forKey: Keys.prefetchMobile) as? Int ?? 1).held(to: OfflinePrefs.prefetchRange)
        p.downloadQuality = StreamQuality.stored(s.string(forKey: Keys.downloadQuality), or: .original)
        p.wifiOnly = s.object(forKey: Keys.wifiOnly) as? Bool ?? true
        p.streamOnWifi = s.object(forKey: Keys.streamOnWifi) as? Bool ?? false
        p.keepLiked = s.object(forKey: Keys.keepLiked) as? Bool ?? false
        p.keptPlaylists = (s.stringArray(forKey: Keys.keptPlaylists) ?? []).sorted()
        return p
    }

    private static func readLook(_ s: UserDefaults) -> LyricsLook {
        var look = LyricsLook()
        look.style = LyricsStyle(rawValue: s.string(forKey: Keys.lyricsStyle) ?? "") ?? .flowing
        for dial in LookDial.allCases {
            if let percent = s.object(forKey: dial.key) as? Int { look = look.with(dial, percent: percent) }
        }
        look.keepCompleted = s.object(forKey: Keys.keepCompleted) as? Bool ?? true
        look.arc = s.object(forKey: Keys.arc) as? Bool ?? false
        look.bloomFast = s.object(forKey: Keys.bloomFast) as? Bool ?? true
        return look
    }

    private static func readOutputTimings(_ s: UserDefaults) -> [String: Int] {
        var timings: [String: Int] = [:]
        for (name, value) in s.dictionaryRepresentation() where name.hasPrefix(LyricsOutputTiming.keyPrefix) {
            if let ms = value as? Int { timings[String(name.dropFirst(LyricsOutputTiming.keyPrefix.count))] = ms }
        }
        return timings
    }
}

extension Int {
    /// Held inside a range.
    func held(to range: ClosedRange<Int>) -> Int { Swift.min(Swift.max(self, range.lowerBound), range.upperBound) }
}
