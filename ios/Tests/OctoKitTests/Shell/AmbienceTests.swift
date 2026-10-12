import Foundation
import Testing
@testable import OctoKit

@Suite struct AmbienceTests {
    private let white: UInt32 = 0xFFFF_FFFF
    private let accent: UInt32 = 0xFF97_B1B9

    /// Every color on a 16-step grid of each channel: 4,096 colors, neon included.
    private var everyColor: [UInt32] {
        var out: [UInt32] = []
        for r in stride(from: 0, through: 255, by: 17) {
            for g in stride(from: 0, through: 255, by: 17) {
                for b in stride(from: 0, through: 255, by: 17) {
                    out.append(0xFF00_0000 | UInt32(r) << 16 | UInt32(g) << 8 | UInt32(b))
                }
            }
        }
        return out
    }

    @Test func whiteTextKeepsAaOnTheBrightestGlow() {
        for color in everyColor {
            let field = composite(ambientColor(color), alpha: ambientAlpha(.rich))
            #expect(contrast(white, field) >= 4.5)
        }
    }

    @Test func accentTextKeepsAaOnTheBrightestGlow() {
        for color in everyColor {
            let field = composite(ambientColor(color), alpha: ambientAlpha(.rich))
            #expect(contrast(accent, field) >= 4.5)
        }
    }

    @Test func theClampHoldsLightnessAndSaturation() {
        #expect(ambientColor(white) == 0xFF80_8080)
        #expect(ambientColor(0xFFFF_0000) == 0xFFC6_3939)
        for color in everyColor {
            let clamped = ambientColor(color)
            let channels = [16, 8, 0].map { Float((clamped >> UInt32($0)) & 0xFF) / 255 }
            let high = channels.max()!
            let low = channels.min()!
            let lightness = (high + low) / 2
            let saturation = high == low ? 0 : (high - low) / (1 - abs(2 * lightness - 1))
            #expect(lightness <= Float(ambientMaxLightness) + 0.01)
            #expect(saturation <= Float(ambientMaxSaturation) + 0.02)
        }
    }

    @Test func darkMutedColorsPassUnchanged() {
        let slate: UInt32 = 0xFF20_3040
        let clamped = ambientColor(slate)
        for shift: UInt32 in [16, 8, 0] {
            #expect(abs(Int((slate >> shift) & 0xFF) - Int((clamped >> shift) & 0xFF)) <= 1)
        }
    }

    @Test func strengthMapsToAFaintAlpha() {
        #expect(ambientAlpha(.off) == 0)
        let subtle = ambientAlpha(.subtle)
        let rich = ambientAlpha(.rich)
        #expect((0.10...0.25).contains(subtle))
        #expect((0.10...0.25).contains(rich))
        #expect(rich > subtle)
        for strength in AmbientStrength.allCases { #expect(barTintAlpha(strength) <= ambientAlpha(strength)) }
        #expect(barTintAlpha(.off) == 0)
    }

    @Test func everyPageBelongsToAnArea() {
        let areas: [(AmbientPage, AmbientArea)] = [
            (.home, .home), (.charts, .home), (.search, .search), (.library, .library), (.albums, .library),
            (.artists, .library), (.songs, .library), (.genres, .library), (.genre, .library), (.folders, .library),
            (.playlists, .library), (.playlist, .library), (.liked, .library), (.downloads, .library),
            (.favorites, .library), (.album, .library), (.artist, .library), (.onlineAlbum, .library),
            (.onlineArtist, .library), (.settings, .settings), (.settingsPage, .settings), (.sound, .settings),
            (.signIn, .settings), (.editConnection, .settings), (.serverForm, .settings), (.octoAdmin, .settings),
            (.importList, .settings), (.family, .settings), (.familyJoin, .settings), (.shares, .settings),
            (.radioStations, .settings),
        ]
        for (page, area) in areas { #expect(areaOf(page) == area) }
        #expect(areaOf(nil) == nil)
        for page: AmbientPage in [.liveList, .liveListEdit, .history, .libraryHealth, .healthCheck, .healthTrash] {
            #expect(areaOf(page) == nil)
        }
    }

    private func source(_ page: AmbientPage?, _ prefs: AmbientPrefs? = AmbientPrefs(), artwork: String? = nil,
                        playing: Bool = true) -> AmbientSource {
        ambientSource(prefs: prefs, page: page, pageArtwork: artwork, hasTrack: playing, playingArtwork: "song-cover")
    }

    @Test func pagesGlowWithTheSongOnNow() {
        #expect(source(.home) == .playing("song-cover"))
        #expect(source(.search) == .playing("song-cover"))
        #expect(source(.playlist) == .playing("song-cover"))
        #expect(source(.sound) == .playing("song-cover"))
    }

    @Test func albumAndArtistPagesGlowWithTheirOwnArtwork() {
        #expect(source(.album, artwork: "album-cover") == .page("album-cover"))
        #expect(source(.onlineArtist, artwork: "artist-photo") == .page("artist-photo"))
        #expect(source(.album, artwork: "album-cover", playing: false) == .page("album-cover"))
        let songOnly = AmbientPrefs(pageArtwork: false)
        #expect(source(.album, songOnly, artwork: "album-cover") == .playing("song-cover"))
        #expect(source(.album, artwork: nil) == .playing("song-cover"))
        #expect(source(.playlist, artwork: "album-cover") == .playing("song-cover"))
    }

    @Test func areasSwitchedOffStayPlain() {
        let prefs = AmbientPrefs(home: false, library: false, search: false, settings: false)
        for page: AmbientPage in [.home, .search, .library, .album, .settings] {
            #expect(source(page, prefs, artwork: "album-cover") == AmbientSource.none)
        }
        let onlySearch = AmbientPrefs(home: false, library: false, settings: false)
        #expect(source(.search, onlySearch) == .playing("song-cover"))
        #expect(source(.home, onlySearch) == AmbientSource.none)
    }

    @Test func offUnreadAndSilenceStayPlain() {
        let off = AmbientPrefs(strength: .off)
        #expect(source(.home, off) == AmbientSource.none)
        #expect(source(.album, off, artwork: "album-cover") == AmbientSource.none)
        #expect(!off.tintsBar)
        #expect(source(.home, nil) == AmbientSource.none)
        #expect(source(.home, playing: false) == AmbientSource.none)
        #expect(source(.history) == AmbientSource.none)
    }

    @Test func theBarTintHasItsOwnSwitch() {
        #expect(AmbientPrefs().tintsBar)
        #expect(!AmbientPrefs(bar: false).tintsBar)
        #expect(AmbientPrefs(home: false, library: false, search: false, settings: false).tintsBar)
    }

    @Test func defaultsAreSubtleEverywhere() {
        let prefs = AmbientPrefs()
        #expect(prefs.strength == .subtle)
        for area in AmbientArea.allCases { #expect(prefs.shows(area)) }
        #expect(prefs.pageArtwork)
    }

    @Test func savedSettingsReadBackAndAnUnknownStrengthIsTheDefault() throws {
        let prefs = AmbientPrefs(strength: .rich, search: false, bar: false, pageArtwork: false)
        let data = try JSONEncoder().encode(prefs)
        #expect(try JSONDecoder().decode(AmbientPrefs.self, from: data) == prefs)
        let text = String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\"Rich\"", with: "\"Blinding\"")
        #expect(try JSONDecoder().decode(AmbientPrefs.self, from: Data(text.utf8)).strength == .subtle)
        #expect(try JSONDecoder().decode(AmbientPrefs.self, from: Data("{}".utf8)) == AmbientPrefs())
    }

    @Test func theBarFilmIsATraceOfTheSongOverTheDimFilm() {
        #expect(barFilm(prefs: nil, hasTrack: true, firstMeshColor: 0xFF0000) == OctoPalette.glazeFilm)
        #expect(barFilm(prefs: AmbientPrefs(), hasTrack: false, firstMeshColor: 0xFF0000) == OctoPalette.glazeFilm)
        #expect(barFilm(prefs: AmbientPrefs(bar: false), hasTrack: true, firstMeshColor: 0xFF0000) == OctoPalette.glazeFilm)
        let film = barFilm(prefs: AmbientPrefs(strength: .rich), hasTrack: true, firstMeshColor: 0xFF0000)
        #expect(abs(film.alpha - (0.10 + 0.16 * 0.9)) < 1e-9)
        #expect(film.red > film.green)
    }
}

@Suite struct ArtworkColorsTests {
    @Test func aPictureOfOneColorGivesThatColor() {
        let teal: UInt32 = 0xFF20_8090
        let palette = ArtworkSwatches(pixels: Array(repeating: teal, count: 112 * 112))
        #expect(palette.swatches.count == 1)
        #expect(palette.dominant?.population == 112 * 112)
        let colors = ArtworkColors.from(palette)
        #expect(colors != nil)
        #expect(colors?.mesh.count == 4)
        #expect(colors?.mesh[3] == 0x0A0B0F)
    }

    @Test func blackWhiteAndSkinAreLeftOut() {
        let pixels: [UInt32] = Array(repeating: 0xFF00_0000, count: 100) + Array(repeating: 0xFFFF_FFFF, count: 100)
        #expect(ArtworkSwatches(pixels: pixels).swatches.isEmpty)
        #expect(ArtworkColors.from(pixels: pixels) == nil)
    }

    @Test func manyColorsAreCutDownToSixteen() {
        var pixels: [UInt32] = []
        for r in stride(from: 0, to: 256, by: 16) {
            for g in stride(from: 0, to: 256, by: 16) {
                for b in stride(from: 0, to: 256, by: 32) {
                    pixels.append(0xFF00_0000 | UInt32(r) << 16 | UInt32(g) << 8 | UInt32(b))
                }
            }
        }
        let palette = ArtworkSwatches(pixels: pixels, maximumColors: 16)
        #expect(palette.swatches.count <= 16)
        #expect(palette.swatches.count > 4)
        #expect(palette.dominant != nil)
        let picked = [palette.vibrant, palette.darkVibrant, palette.lightVibrant, palette.muted, palette.darkMuted, palette.lightMuted]
            .compactMap { $0?.rgb }
        #expect(Set(picked).count == picked.count)
    }

    @Test func aBrightRedReadsAsVibrant() {
        let red = Array(repeating: UInt32(0xFFE0_1010), count: 500)
        let navy = Array(repeating: UInt32(0xFF10_1850), count: 200)
        let palette = ArtworkSwatches(pixels: red + navy)
        #expect(palette.vibrant?.rgb == palette.dominant?.rgb)
        #expect(palette.darkVibrant != nil || palette.darkMuted != nil)
    }

    @Test func theSampleIsAboutTwelveThousandPixels() {
        #expect(paletteSampleSize(width: 128, height: 128) == (112, 112))
        #expect(paletteSampleSize(width: 100, height: 100) == (100, 100))
    }

    @Test func lightnessShiftsKeepTheHue() {
        let shifted = shiftLightness(0x336699, 0.16)
        let a = paletteHsl(0x336699)
        let b = paletteHsl(shifted)
        #expect(abs(a.hue - b.hue) < 2)
        #expect(abs(b.lightness - a.lightness - 0.16) < 0.01)
        #expect(blendToward(0xFFFFFF, 0x000000, 0.7) == 0x4C4C4C)
    }
}

@Suite struct MeshFieldTests {
    private let colors: [(Double, Double, Double)] = [(1, 0, 0), (0, 1, 0), (0, 0, 1), (0, 0, 0)]

    @Test func eachCornerLeansToItsOwnPool() {
        let pools = MeshField.pools(0)
        let topLeft = MeshField.color(x: 20, y: 18, width: 100, height: 100, time: 0, pools: pools, colors: colors)
        #expect(topLeft.0 > topLeft.1 && topLeft.0 > topLeft.2)
        let bottomLeft = MeshField.color(x: 24, y: 78, width: 100, height: 100, time: 0, pools: pools, colors: colors)
        #expect(bottomLeft.2 > bottomLeft.0)
    }

    @Test func theGrainIsTiny() {
        for i in 0..<100 { #expect(abs(MeshField.grain(Double(i) * 3.1, Double(i) * 7.7)) <= 0.004) }
    }

    @Test func aRenderFillsEveryPixel() {
        let bytes = MeshField.render(columns: 4, rows: 3, width: 40, height: 30, time: 1, colors: colors)
        #expect(bytes.count == 48)
        #expect(stride(from: 3, to: 48, by: 4).allSatisfy { bytes[$0] == 255 })
    }
}

@Suite struct PathDataTests {
    @Test func absoluteAndRelativeCommandsEndInTheSamePlace() {
        let absolute = PathData.steps("M10,10 L20,10 L20,20 Z")
        let relative = PathData.steps("m10 10 l10 0 l0 10 z")
        #expect(absolute == relative)
        #expect(absolute == [.move(10, 10), .line(20, 10), .line(20, 20), .close])
    }

    @Test func pairsAfterAMoveAreLines() {
        #expect(PathData.steps("M0 0 10 0 10 10") == [.move(0, 0), .line(10, 0), .line(10, 10)])
    }

    @Test func horizontalAndVerticalLinesKeepTheOtherAxis() {
        #expect(PathData.steps("M5,5H15V25h-10v-20") == [.move(5, 5), .line(15, 5), .line(15, 25), .line(5, 25), .line(5, 5)])
    }

    @Test func anArcIsCubicCurvesEndingAtItsEnd() {
        let steps = PathData.steps("M0,8A8,8,0,0,1,16,8")
        #expect(steps.count >= 3)
        guard case let .cubic(_, _, _, _, x, y) = steps.last! else {
            Issue.record("not a curve")
            return
        }
        #expect(abs(x - 16) < 1e-9 && abs(y - 8) < 1e-9)
        // The half circle goes through the top, 8 above the line.
        guard case let .cubic(_, _, _, _, mx, my) = steps[1] else { return }
        #expect(abs(mx - 8) < 1e-6 && abs(my) < 1e-6)
    }

    @Test func arcFlagsMayRunIntoTheNumbers() {
        let packed = PathData.steps("M0 8a8 8 0 0116 0")
        let spaced = PathData.steps("M0 8a8 8 0 0 1 16 0")
        #expect(packed == spaced)
    }

    @Test func numbersMayRunTogether() {
        #expect(PathData.steps("M.5.5L-1-1") == [.move(0.5, 0.5), .line(-1, -1)])
        #expect(PathData.steps("M1e1,2E0") == [.move(10, 2)])
    }

    @Test func smoothCurvesMirrorTheLastControlPoint() {
        let steps = PathData.steps("M0,0 C0,10 10,10 10,0 S20,-10 20,0")
        #expect(steps.count == 3)
        #expect(steps[2] == .cubic(10, -10, 20, -10, 20, 0))
    }
}
