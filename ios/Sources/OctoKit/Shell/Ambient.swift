import Foundation

extension AmbientPrefs {
    /// Prefs with each part given, the rest at their defaults.
    public init(strength: AmbientStrength = .subtle, home: Bool = true, library: Bool = true, search: Bool = true,
                settings: Bool = true, bar: Bool = true, pageArtwork: Bool = true) {
        self.init()
        self.strength = strength
        self.home = home
        self.library = library
        self.search = search
        self.settings = settings
        self.bar = bar
        self.pageArtwork = pageArtwork
    }
}

/// How much of the color shows over the app's near-black background.
public func ambientAlpha(_ strength: AmbientStrength) -> Double { strength.glowAlpha }

/// How much of the color tints the bar's glass: about half the page's, so the glass stays glass.
public func barTintAlpha(_ strength: AmbientStrength) -> Double { strength.barTintAlpha }

/// Artwork colors are held to this lightness and saturation before they glow.
public let ambientMaxLightness = 0.5
public let ambientMaxSaturation = 0.55

/// The page background the glow sits on, as `0xAARRGGBB`.
public let ambientBase: UInt32 = 0xFF0C0C0D

/// An artwork color made safe to glow: the same hue, no brighter and no more saturated than
/// the limits above.
public func ambientColor(_ argb: UInt32) -> UInt32 {
    let hsl = toHsl(argb)
    return fromHsl(hsl.hue, min(hsl.saturation, Float(ambientMaxSaturation)), min(hsl.lightness, Float(ambientMaxLightness)))
}

/// A color laid over another at some opacity, as the screen draws it.
public func composite(_ argb: UInt32, alpha: Double, over: UInt32 = ambientBase) -> UInt32 {
    func channel(_ shift: UInt32) -> UInt32 {
        let top = Double((argb >> shift) & 0xFF)
        let bottom = Double((over >> shift) & 0xFF)
        return UInt32(max(0, min(255, (bottom + (top - bottom) * alpha).rounded(.toNearestOrAwayFromZero))))
    }
    return 0xFF00_0000 | channel(16) << 16 | channel(8) << 8 | channel(0)
}

/// Relative luminance, as WCAG defines it.
public func luminance(_ argb: UInt32) -> Double {
    func linear(_ shift: UInt32) -> Double {
        let c = Double((argb >> shift) & 0xFF) / 255
        return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * linear(16) + 0.7152 * linear(8) + 0.0722 * linear(0)
}

/// The WCAG contrast ratio between two colors, from 1 to 21.
public func contrast(_ a: UInt32, _ b: UInt32) -> Double {
    let la = luminance(a)
    let lb = luminance(b)
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
}

/// A color as hue (degrees), saturation and lightness, the last two from 0 to 1.
public func toHsl(_ argb: UInt32) -> (hue: Float, saturation: Float, lightness: Float) {
    let r = Float((argb >> 16) & 0xFF) / 255
    let g = Float((argb >> 8) & 0xFF) / 255
    let b = Float(argb & 0xFF) / 255
    let high = max(r, max(g, b))
    let low = min(r, min(g, b))
    let lightness = (high + low) / 2
    let spread = high - low
    if spread == 0 { return (0, 0, lightness) }
    let saturation = spread / (1 - abs(2 * lightness - 1))
    let sector: Float
    if high == r {
        sector = positiveMod((g - b) / spread, 6)
    } else if high == g {
        sector = (b - r) / spread + 2
    } else {
        sector = (r - g) / spread + 4
    }
    return (sector * 60, min(1, max(0, saturation)), lightness)
}

/// A color from hue (degrees), saturation and lightness.
public func fromHsl(_ hue: Float, _ saturation: Float, _ lightness: Float) -> UInt32 {
    let chroma = (1 - abs(2 * lightness - 1)) * saturation
    let x = chroma * (1 - abs(positiveMod(hue / 60, 2) - 1))
    let m = lightness - chroma / 2
    let rgb: (Float, Float, Float)
    switch min(5, max(0, Int(hue / 60))) {
    case 0: rgb = (chroma, x, 0)
    case 1: rgb = (x, chroma, 0)
    case 2: rgb = (0, chroma, x)
    case 3: rgb = (0, x, chroma)
    case 4: rgb = (x, 0, chroma)
    default: rgb = (chroma, 0, x)
    }
    func byte(_ v: Float) -> UInt32 { UInt32(max(0, min(255, ((v + m) * 255).rounded(.toNearestOrAwayFromZero)))) }
    return 0xFF00_0000 | byte(rgb.0) << 16 | byte(rgb.1) << 8 | byte(rgb.2)
}

/// The remainder that is never negative, as Kotlin's `mod` gives it.
private func positiveMod(_ a: Float, _ b: Float) -> Float {
    let r = a.truncatingRemainder(dividingBy: b)
    return r < 0 ? r + b : r
}

/// Every kind of page, as the glow sees it.
public enum AmbientPage: Sendable, Equatable {
    case home, charts, search, liveRadio
    case library, albums, artists, songs, genres, genre, folders, playlists, playlist, liked, downloads, favorites
    case album, artist, onlineAlbum, onlineArtist
    case settings, settingsPage, sound, signIn, editConnection, serverForm, octoAdmin, importList, family, familyJoin
    case shares, radioStations
    case liveList, liveListEdit, history, libraryHealth, healthCheck, healthTrash
}

/// The part of the app a page belongs to. Album, artist, playlist and genre pages are library
/// pages wherever they were opened from. A page not listed gets no glow.
public func areaOf(_ page: AmbientPage?) -> AmbientArea? {
    switch page {
    case .home, .charts, .liveRadio: .home
    case .search: .search
    case .library, .albums, .artists, .songs, .genres, .folders, .playlists, .liked, .downloads, .favorites,
         .album, .artist, .onlineAlbum, .onlineArtist, .genre, .playlist:
        .library
    case .settings, .sound, .signIn, .editConnection, .serverForm, .octoAdmin, .importList, .family, .familyJoin,
         .shares, .radioStations, .settingsPage:
        .settings
    default: nil
    }
}

/// Pages that show one album or artist, and so have artwork of their own.
public func hasOwnArtwork(_ page: AmbientPage?) -> Bool {
    page == .album || page == .artist || page == .onlineAlbum || page == .onlineArtist
}

/// Which colors a page glows with.
public enum AmbientSource: Sendable, Equatable {
    /// The plain background.
    case none
    /// The artwork of the song on now.
    case playing(String?)
    /// The artwork of the album or artist the page shows.
    case page(String)
}

/// What the page on top glows with. Settings not read yet count as off, so a glow turned off
/// never flashes up at launch.
public func ambientSource(prefs: AmbientPrefs?, page: AmbientPage?, pageArtwork: String?, hasTrack: Bool,
                          playingArtwork: String?) -> AmbientSource {
    guard let prefs, let area = areaOf(page), prefs.shows(area) else { return .none }
    if prefs.pageArtwork && hasOwnArtwork(page), let pageArtwork { return .page(pageArtwork) }
    return hasTrack ? .playing(playingArtwork) : .none
}

/// The bar's glass film: a trace of the song's first color, made safe to glow, at the bar
/// tint's opacity, laid over the glass's usual dim film.
public func barFilm(_ firstMeshColor: UInt32, strength: AmbientStrength) -> RGBA {
    let tint = RGBA(argb: ambientColor(firstMeshColor)).opacity(barTintAlpha(strength))
    return compositeOver(tint, OctoPalette.glazeFilm)
}

/// The film the bar wears: the plain one unless the bar tint is on and a song is loaded.
public func barFilm(prefs: AmbientPrefs?, hasTrack: Bool, firstMeshColor: UInt32?) -> RGBA {
    guard let prefs, prefs.tintsBar, hasTrack, let firstMeshColor else { return OctoPalette.glazeFilm }
    return barFilm(firstMeshColor, strength: prefs.strength)
}

/// One translucent color over another, as a single color.
public func compositeOver(_ top: RGBA, _ bottom: RGBA) -> RGBA {
    let alpha = top.alpha + bottom.alpha * (1 - top.alpha)
    guard alpha > 0 else { return .clear }
    func channel(_ a: Double, _ b: Double) -> Double { (a * top.alpha + b * bottom.alpha * (1 - top.alpha)) / alpha }
    return RGBA(red: channel(top.red, bottom.red), green: channel(top.green, bottom.green),
                blue: channel(top.blue, bottom.blue), alpha: alpha)
}

/// The glow's timing.
public enum AmbientTiming {
    /// Color and strength changes cross over this long, in milliseconds.
    public static let crossMs = 800
    /// The glow drifts at this share of the player's pace.
    public static let pace = 0.2
    /// And redraws this often, in milliseconds.
    public static let frameMs = 100
    /// Below this strength nothing is drawn.
    public static let threshold = 0.002
}
