import Foundation
import Testing
@testable import OctoKit

/// A text engine for tests: every character a fixed share of the size wide (wide characters a whole
/// size), words wrapped greedily at spaces and between wide characters, lines `lineHeight` apart. A
/// word wider than the line is broken across lines.
struct FakeTypesetter: CoverTypesetter {
    private func charWidth(_ scalar: Unicode.Scalar, _ size: Float) -> Float {
        let v = scalar.value
        let wide = (0x4E00...0x9FFF).contains(v) || (0x3040...0x30FF).contains(v) || isEmojiScalar(v)
        return wide ? size : size * 0.55
    }

    private func width(_ text: String, _ size: Float) -> Float { text.unicodeScalars.reduce(0) { $0 + charWidth($1, size) } }

    func widthOf(_ text: String, _ type: CoverType) -> Float { width(text, type.sizePx) }

    func measure(_ text: String, _ type: CoverType, width boxWidth: Float) -> Measured {
        let space = width(" ", type.sizePx)
        var lines: [Float] = []
        var line: Float = 0
        let char = type.sizePx * 0.55
        let pieces = unbreakableRuns(text).flatMap { run -> [String] in
            let fits = max(1, Int(boxWidth / char))
            if width(run, type.sizePx) <= boxWidth { return [run] }
            // Pieces of at most `fits` UTF-16 units, as the other apps' tests break a word.
            var pieces: [String] = []
            var piece = String.UnicodeScalarView()
            var units = 0
            for scalar in run.unicodeScalars {
                let size = String(scalar).utf16.count
                if units > 0 && units + size > fits {
                    pieces.append(String(piece))
                    piece = String.UnicodeScalarView()
                    units = 0
                }
                piece.append(scalar)
                units += size
            }
            if !piece.isEmpty { pieces.append(String(piece)) }
            return pieces
        }
        for run in pieces {
            let w = width(run, type.sizePx)
            if line > 0 && line + space + w > boxWidth {
                lines.append(line)
                line = w
            } else {
                line = line == 0 ? w : line + space + w
            }
        }
        lines.append(line)
        let shown = min(lines.count, type.maxLines)
        let widest = min(lines.prefix(shown).max() ?? 0, boxWidth)
        return Measured(lines: shown, width: widest, height: Float(shown) * type.sizePx * type.lineHeight, cut: lines.count > type.maxLines)
    }
}

private func rgb(_ r: Int, _ g: Int, _ b: Int) -> UInt32 { 0xFF00_0000 | UInt32(r) << 16 | UInt32(g) << 8 | UInt32(b) }

private func isNear(_ a: Float, _ b: Float, _ within: Float) -> Bool { abs(a - b) <= within }
private func isNear(_ a: Double, _ b: Double, _ within: Double) -> Bool { abs(a - b) <= within }

@Suite struct CoverDesignTests {
    let setter = FakeTypesetter()
    let book = CoverBook.standard
    let library = CoverBackgrounds.standard

    private func spec(_ id: String, _ name: String, palette: CoverPalette? = nil) -> CoverSpec {
        CoverSpec(id: id, name: name, line: playlistCoverLine, footer: "12 songs", palette: palette ?? seededPalette(id))
    }

    private func music(_ argb: UInt32) -> CoverPalette { coverPalette([[CoverSwatch(argb: argb, share: 1)]], seed: "x") }

    @Test func theSharedBookReads() {
        #expect(book.version == 1)
        #expect(book.fonts.footer == "InterDisplay-Medium.ttf")
        #expect(book.layout.footer.weight == 500)
        #expect(book.layout.footer.size == 0.06)
        #expect(book.layout.footer.opacity == 0.85)
        #expect(book.veil.refine == 3)
        #expect(book.veil.yellow.hues == [55, 72, 128, 150])
        #expect(!coverDesignJSON.contains("\"gradients\"") && !coverDesignJSON.contains("\"music\""))
    }

    @Test func everyBackgroundIsInTheBuild() throws {
        #expect(library.backgrounds.count == 48)
        #expect(library.size == 1200)
        let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/Octo/CoverArt")
        for background in library.backgrounds {
            let bytes = try Data(contentsOf: folder.appendingPathComponent(background.file))
            #expect(String(decoding: bytes.prefix(4), as: UTF8.self) == "RIFF")
            #expect(String(decoding: bytes[8..<12], as: UTF8.self) == "WEBP")
            #expect(!background.hues.isEmpty)
        }
        #expect(Set(library.backgrounds.map(\.file)).count == library.backgrounds.count)
    }

    @Test func aListWithoutCoversGetsAnyBackgroundAlwaysTheSame() {
        let ids = (0..<400).map { "pl-\($0)" }
        let picked = ids.map { chooseBackground($0, seededPalette($0)).file }
        #expect(picked == ids.map { chooseBackground($0, seededPalette($0)).file })
        var used: [String: Int] = [:]
        for file in picked { used[file, default: 0] += 1 }
        #expect(used.count >= library.backgrounds.count - 2)
        #expect(used.values.allSatisfy { $0 < 400 / library.backgrounds.count * 4 })
    }

    @Test func theMusicPicksABackgroundOfItsColour() {
        for colour in [rgb(200, 30, 40), rgb(30, 60, 200), rgb(40, 160, 70), rgb(240, 200, 30), rgb(150, 40, 190)] {
            let palette = music(colour)
            let picks = Set((0..<60).map { chooseBackground("pl-\($0)", palette) })
            #expect((2...book.background.nearest).contains(picks.count))
            for background in picks {
                let nearest = background.hues.map { hueDistance($0.h, Double(palette.hue)) }.min() ?? 360
                #expect(nearest < 50, "\(background.name) for hue \(palette.hue): \(nearest)")
            }
            #expect(chooseBackground("pl-1", palette) == chooseBackground("pl-1", palette))
        }
    }

    @Test func theWordsSitWhereTheLayoutSays() {
        let words = coverWords(spec("pl-1", "Late"), side: 600, setter: setter)
        #expect(words.count == 3)
        guard words.count == 3 else { return }
        let title = words[0], line = words[1], footer = words[2]
        #expect(title.role == .title)
        #expect(title.left == 48)
        #expect(title.top == 60)
        #expect(title.type.sizePx == 96)
        #expect(isNear(title.height, 96 * 1.08, 0.01))
        #expect(line.role == .line)
        #expect(line.type.weight == 300)
        #expect(line.top == title.top + title.height)
        #expect(footer.role == .footer)
        #expect(footer.type.sizePx == 36)
        #expect(footer.type.weight == 500)
        #expect(isNear(footer.top, 508.8, 0.01))
        #expect(abs(Int(0.85 * 255) - Int(footer.ink >> 24)) <= 1)
    }

    @Test func smallCoversAreArtworkOnly() {
        for side in [16, 32, 48, 71] {
            #expect(coverWords(spec("pl-1", "Late night"), side: side, setter: setter).isEmpty)
            #expect(planCover(spec("pl-1", "Late night"), side: side, setter: setter).veil.isEmpty)
        }
        #expect(!coverWords(spec("pl-1", "Late night"), side: 72, setter: setter).isEmpty)
    }

    @Test func wordsStayInsideTheMarginsAtEverySize() {
        let names = ["Chill", "Dinner with friends", "Everything I have ever loved, in the order I found it", "夜のドライブ", "أغاني الصيف",
                     "🔥🔥🔥", "Supercalifragilisticexpialidocious"]
        for side in [72, 96, 128, 160, 240, 600, 1000, 1200] {
            for name in names {
                let words = coverWords(spec("pl-\(name)", name), side: side, setter: setter)
                for w in words {
                    let box = w.inked
                    let margin = Float(side) * book.layout.margin
                    #expect(box[1] >= 0 && box[3] <= Float(side), "\(name) at \(side): \(w.text) runs off")
                    #expect(box[0] >= margin - 1 && box[2] <= Float(side) - margin + 1, "\(name) at \(side): \(w.text) crosses the margin")
                }
                if let foot = words.first(where: { $0.role == .footer }) {
                    #expect(words.filter { $0.role != .footer }.allSatisfy { $0.top + $0.height <= foot.top })
                }
            }
        }
    }

    @Test func aRightToLeftNameAndItsVeilSitOnTheRight() {
        let plan = planCover(spec("pl-1", "أغاني الصيف"), side: 600, setter: setter)
        #expect(plan.words.allSatisfy { $0.align == .right })
        #expect(isNear(plan.words.first?.inked[2] ?? 0, 600 - 48, 0.5))
        #expect(plan.veil.allSatisfy { $0.box[2] == 600 && $0.box[0] > 0 })
    }

    @Test func theVeilsLimitsAreTheReferences() {
        #expect(isNear(veilLimit(4.5), 1.05 / 4.5 - 0.05, 1e-12))
        #expect(isNear(veilLimit(4.5, inkOpacity: 0.85), 0.141, 0.0015))
    }

    @Test func theRegionsFollowTheWords() {
        let plan = planCover(spec("pl-1", "Late night"), side: 600, setter: setter)
        #expect(plan.veil.count == 2)
        guard plan.veil.count == 2, let foot = plan.words.last else { return }
        let block = plan.words.filter { $0.role != .footer }
        #expect(plan.veil[0].box == [0, 0, (block.map { $0.inked[2] }.max() ?? 0) + 24, (block.map { $0.top + $0.height }.max() ?? 0) + 24])
        #expect(plan.veil[1].box == [0, foot.top - 30, foot.inked[2] + 30, 600])
        #expect(plan.veil[1].maxDrop == 1)
    }

    private func lum(_ p: UInt32) -> Double {
        0.2126 * channelToLinear(Double(p >> 16 & 0xFF) / 255) + 0.7152 * channelToLinear(Double(p >> 8 & 0xFF) / 255)
            + 0.0722 * channelToLinear(Double(p & 0xFF) / 255)
    }

    @Test func theVeilDarkensOnlyWhatIsTooBrightAndKeepsTheColour() {
        let side = 200
        let plan = planCover(spec("pl-1", "Late night"), side: side, setter: setter)
        guard let title = plan.veil.first else {
            Issue.record("no veil")
            return
        }
        for colour in [rgb(120, 170, 255), rgb(255, 140, 190), rgb(90, 220, 200)] {
            let veiled = applyVeil([UInt32](repeating: colour, count: side * side), side: side, regions: plan.veil)
            let inside = veiled[Int(title.box[3] / 2) * side + Int(title.box[2] / 2)]
            #expect(lum(inside) <= title.least * 1.02)
            #expect(hueDistance(toLch(inside).h, toLch(colour).h) < 4)
            #expect(toLch(inside).c > toLch(colour).c * 0.5)
        }
        let dark = [UInt32](repeating: rgb(20, 30, 60), count: side * side)
        #expect(applyVeil(dark, side: side, regions: plan.veil) == dark)
        let light = [UInt32](repeating: rgb(250, 250, 250), count: side * side)
        #expect(applyVeil(light, side: side, regions: []) == light)
    }

    @Test func deepYellowsTurnGoldNeverOlive() {
        let side = 200
        let plan = planCover(spec("pl-1", "Late night"), side: side, setter: setter)
        let yellow = rgb(245, 215, 40)
        let veiled = applyVeil([UInt32](repeating: yellow, count: side * side), side: side, regions: plan.veil)
        let inside = toLch(veiled[20 * side + 20])
        #expect(inside.h < toLch(yellow).h - 10 && inside.h > 50, "hue \(inside.h)")
    }

    @Test func backgroundsComeToSizeAsTheReferenceDoes() {
        let from = 8
        let pixels = (0..<(from * from)).map { i in rgb(i % 256, (i * 7) % 256, (i * 13) % 256) }
        let half = sampleBackground(pixels, from: from, side: 4)
        for y in 0..<4 {
            for x in 0..<4 {
                let q = [pixels[2 * y * from + 2 * x], pixels[2 * y * from + 2 * x + 1], pixels[(2 * y + 1) * from + 2 * x],
                         pixels[(2 * y + 1) * from + 2 * x + 1]]
                let r = (q.reduce(0) { $0 + Int($1 >> 16 & 0xFF) } + 2) / 4
                #expect(r == Int(half[y * 4 + x] >> 16 & 0xFF))
            }
        }
        let flat = sampleBackground([UInt32](repeating: rgb(10, 200, 90), count: 1200 * 1200), from: 1200, side: 176)
        #expect(flat.count == 176 * 176)
        #expect(flat.allSatisfy { $0 == rgb(10, 200, 90) })
        #expect(sampleBackground(pixels, from: from, side: from) == pixels)
        let odd = sampleBackground(pixels, from: from, side: 3)
        #expect(odd.allSatisfy { abs(Int($0 >> 16 & 0xFF) - 32) < 40 })
    }

    @Test func cacheKeysChangeWithEverythingDrawn() throws {
        let base = spec("pl-1", "Late night")
        let key = coverArtKey(base, side: 160)
        #expect(key == coverArtKey(base, side: 160))
        #expect(key != coverArtKey(base, side: 164))
        var other = base
        other.name = "Late nights"
        #expect(key != coverArtKey(other, side: 160))
        other = base
        other.footer = "13 songs"
        #expect(key != coverArtKey(other, side: 160))
        other = base
        other.line = liveListCoverLine
        #expect(key != coverArtKey(other, side: 160))
        other = base
        other.id = "pl-2"
        #expect(key != coverArtKey(other, side: 160))
        var newerBook = book
        newerBook.version = 2
        #expect(key != coverArtKey(base, side: 160, book: newerBook))
        var newerLibrary = library
        newerLibrary.version = 2
        #expect(key != coverArtKey(base, side: 160, library: newerLibrary))
        var redSpec = base
        redSpec.palette = music(rgb(200, 30, 40))
        var blueSpec = base
        blueSpec.palette = music(rgb(30, 60, 200))
        #expect(coverArtKey(redSpec, side: 160) != coverArtKey(blueSpec, side: 160))
        #expect(key.hasPrefix("playlist-art:v\(coverDesignVersion):") && coverDesignVersion >= 2)
    }
}

@Suite struct CoverGlyphTests {
    let setter = FakeTypesetter()
    let numbers = CoverBook.standard.glyphs!

    @Test func theBookHasTheGlyphs() {
        #expect(numbers.box == 0.36)
        #expect(numbers.heart.from == [0.5, 0.88])
        #expect(numbers.magnifier.radius == 0.3)
        #expect(numbers.copies.side == 0.56)
    }

    @Test func everyGlyphSitsInItsCentredBox() {
        for side in [40, 72, 160, 600] {
            for glyph in [CoverGlyph.heart, .magnifier, .copies] {
                let drawing = glyphDrawing(glyph, side: side, numbers: numbers)
                let left = drawing.box[0], top = drawing.box[1], size = drawing.box[2]
                #expect(isNear(size, Float(side) * 0.36, 0.001))
                #expect(isNear(left, (Float(side) - size) / 2, 0.001))
                #expect(isNear(top, (Float(side) - size) / 2, 0.001))
                #expect(drawing.steps.first?.add == true)
                for step in drawing.steps {
                    let b = step.shape.bounds
                    #expect(b[2] > b[0] && b[3] > b[1], "\(glyph) at \(side)")
                    #expect(b[0] >= left - 0.01 && b[1] >= top - 0.01 && b[2] <= left + size + 0.01 && b[3] <= top + size + 0.01,
                            "\(glyph) at \(side) runs out of its box")
                }
            }
        }
    }

    @Test func theHeartIsMirrored() throws {
        guard case .curves(let x, let y, let cubics) = glyphDrawing(.heart, side: 100, numbers: numbers).steps.first?.shape else {
            Issue.record("not curves")
            return
        }
        let bounds = GlyphShape.curves(x: x, y: y, cubics: cubics).bounds
        #expect(isNear((bounds[0] + bounds[2]) / 2, 50, 0.001))
        #expect(isNear(x, cubics.last?[4] ?? -1, 0.001))
        #expect(isNear(y, cubics.last?[5] ?? -1, 0.001))
    }

    @Test func theCopiesCutAGapAroundTheFrontSquare() {
        let steps = glyphDrawing(.copies, side: 100, numbers: numbers).steps
        #expect(steps.map(\.add) == [true, false, false, true])
        guard case .roundSquare(let gapLeft, _, let gapSide, _) = steps[2].shape,
              case .roundSquare(let frontLeft, _, let frontSide, _) = steps[3].shape else {
            Issue.record("not squares")
            return
        }
        #expect(isNear(gapLeft, frontLeft - 0.06 * 36, 0.001))
        #expect(isNear(gapSide, frontSide + 2 * 0.06 * 36, 0.001))
    }

    @Test func aGlyphCoverHasNoWordsAndAVeilUnderTheGlyph() {
        let spec = CoverSpec(id: "og-liked", name: "Liked Songs", line: playlistCoverLine, footer: "12 songs", palette: seededPalette("og-liked"),
                             glyph: .heart)
        let plan = planCover(spec, side: 600, setter: setter)
        #expect(plan.words.isEmpty)
        #expect(plan.glyph != nil)
        let box = plan.veil.first?.box ?? []
        #expect(plan.veil.count == 1)
        #expect(isNear(box[2] - box[0], 600 * 0.36 * 1.15, 0.01))
        #expect(isNear((box[0] + box[2]) / 2, 300, 0.01))
        #expect(chooseBackground("og-liked", spec.palette) == plan.background)
        var plain = spec
        plain.glyph = nil
        #expect(planCover(plain, side: 600, setter: setter).glyph == nil)
    }

    @Test func theGlyphIsPartOfTheKey() {
        let spec = CoverSpec(id: "p", name: "Review", line: playlistCoverLine, footer: nil, palette: seededPalette("p"))
        var magnifier = spec
        magnifier.glyph = .magnifier
        var copies = spec
        copies.glyph = .copies
        #expect(coverArtKey(spec, side: 160) != coverArtKey(magnifier, side: 160))
        #expect(coverArtKey(copies, side: 160) != coverArtKey(magnifier, side: 160))
    }

    @Test func marksPickTheirGlyph() {
        #expect(playlistGlyph(octoNotice: "review") == .magnifier)
        #expect(playlistGlyph(octoNotice: "duplicates") == .copies)
        #expect(playlistGlyph(octoNotice: nil, octoList: "liked") == .heart)
        #expect(playlistGlyph(octoNotice: nil, octoList: "newReleases") == nil)
        #expect(playlistGlyph(octoNotice: "somethingNewer") == nil)
        #expect(playlistGlyph(octoNotice: nil) == nil)
    }
}

@Suite struct CoverPaletteTests {
    @Test func theMainColoursOfAPictureComeFirst() {
        let pixels = (0..<400).map { $0 % 4 == 0 ? rgb(230, 110, 40) : rgb(20, 30, 80) }
        let swatches = coverSwatches(pixels, step: 1)
        #expect(swatches.count == 2)
        guard swatches.count == 2 else { return }
        #expect(colourDistance(swatches[0].argb, rgb(20, 30, 80)) < 0.02)
        #expect(isNear(swatches[0].share, 0.75, 0.01))
        #expect(isNear(swatches[1].share, 0.25, 0.01))
    }

    @Test func eachQuarterOfAMosaicIsOneCover() {
        let colours = [rgb(200, 30, 30), rgb(30, 200, 30), rgb(30, 30, 200), rgb(200, 200, 30)]
        let pixels = (0..<400).map { i in colours[(i % 20 < 10 ? 0 : 1) + (i / 20 < 10 ? 0 : 2)] }
        let quarters = quarterSwatches(pixels, width: 20)
        #expect(quarters.count == 4)
        for (q, swatches) in quarters.enumerated() { #expect(colourDistance(swatches.first?.argb ?? 0, colours[q]) < 0.02) }
    }

    @Test func theColoursComeFromTheMusic() {
        let palette = coverPalette([[CoverSwatch(argb: rgb(200, 30, 40), share: 0.8)], [CoverSwatch(argb: rgb(30, 60, 200), share: 0.6)]], seed: "pl-1")
        #expect(palette.fromMusic)
        #expect(hueDistance(Double(palette.hue), toLch(rgb(200, 30, 40)).h) < 2)
        #expect(isNear(palette.lightness, toLch(rgb(200, 30, 40)).l, 0.002))
    }

    @Test func aVividDetailBeatsALargeGreyButNotALargeColour() {
        let grey = CoverSwatch(argb: rgb(120, 120, 120), share: 0.9)
        let speck = CoverSwatch(argb: rgb(0, 160, 255), share: 0.05)
        #expect(hueDistance(Double(coverPalette([[grey, speck]], seed: "x").hue), toLch(rgb(0, 160, 255)).h) < 2)
        let green = CoverSwatch(argb: rgb(40, 140, 60), share: 0.9)
        #expect(hueDistance(Double(coverPalette([[green, speck]], seed: "x").hue), toLch(rgb(40, 140, 60)).h) < 2)
    }

    @Test func noCoversOrGreyOnesGiveTheListsOwnPalette() {
        let none = coverPalette([], seed: "pl-7")
        #expect(!none.fromMusic)
        #expect(none == seededPalette("pl-7"))
        let grey = coverPalette([[CoverSwatch(argb: rgb(128, 128, 128), share: 1)], [CoverSwatch(argb: rgb(10, 10, 10), share: 1)]], seed: "pl-7")
        #expect(grey == seededPalette("pl-7"))
        #expect(seededPalette("pl-7").key != seededPalette("pl-8").key)
    }

    @Test func aPaletteReadsBackFromItsKey() {
        let palette = coverPalette([[CoverSwatch(argb: rgb(200, 90, 30), share: 1)]], seed: "a")
        #expect(CoverPalette.fromKey(palette.key) == palette)
        #expect(CoverPalette.fromKey("nonsense") == nil)
    }

    @Test func theHashIsTheSameEverywhere() {
        #expect(coverHash("pl-1") == 0x5280_D386_DB28_089B)
    }

    @Test func colourSpaceRoundTrips() {
        for argb in [rgb(255, 0, 0), rgb(12, 200, 90), rgb(30, 30, 30), rgb(250, 240, 220)] {
            #expect(colourDistance(argb, toLch(argb).argb) < 0.005)
        }
        #expect(isNear(toLch(lchToArgb(0.5, 0.5, 140)).l, 0.5, 0.01))
    }
}

@Suite struct CoverTextTests {
    let setter = FakeTypesetter()
    let look = CoverType(sizePx: 0, weight: 600, tracking: 0, lineHeight: 1.08, maxLines: 1)

    @Test func writingIsToldApart() {
        #expect(coverScript("Late night") == .latin)
        #expect(coverScript("Музыка для работы") == .latin)
        #expect(coverScript("夜のドライブ") == .wide)
        #expect(coverScript("أغاني الصيف") == .tall)
        #expect(coverScript("שירים לנסיעה") == .tall)
        #expect(coverScript("🔥🔥🔥") == .emoji)
        #expect(coverScript("2026") == .latin)
    }

    @Test func rightToLeftGoesByTheFirstLetter() {
        #expect(isRightToLeft("أغاني الصيف"))
        #expect(isRightToLeft("2026 שירים"))
        #expect(!isRightToLeft("Summer أغاني"))
        #expect(!isRightToLeft("🔥"))
    }

    @Test func wideCharactersEachStandAlone() {
        #expect(unbreakableRuns("Late  night") == ["Late", "night"])
        #expect(unbreakableRuns("夜のドライブ") == ["夜", "の", "ド", "ラ", "イ", "ブ"])
        #expect(unbreakableRuns("Tokyo 夜") == ["Tokyo", "夜"])
    }

    @Test func theLargestSizeThatFitsIsChosen() {
        let fit = fitCoverText("Late night", width: 200, height: 1000, maxLines: 1, minPx: 10, maxPx: 80, look: look, setter: setter)
        #expect(fit.type.sizePx == 36)
        #expect(!fit.measured.cut)
    }

    @Test func textAlwaysStaysInItsBox() {
        let names = ["Chill", "Late night drives", "Everything I have ever loved, in the order I found it", "東京の夜に聴きたい曲たち、雨の日のためのプレイリスト",
                     "Supercalifragilisticexpialidocious", "🔥🔥🔥"]
        for side in [32, 72, 96, 160, 300, 1000] {
            for name in names {
                let width = Float(side) * 0.84, height = Float(side) * 0.6
                let fit = fitCoverText(name, width: width, height: height, maxLines: 3, minPx: 9, maxPx: Float(side) * 0.16, look: look,
                                       setter: setter)
                #expect(fit.measured.height <= height || fit.type.sizePx == 9, "\(name) at \(side)")
                #expect(fit.measured.lines <= 3)
                if !fit.measured.cut { #expect(unbreakableRuns(name).allSatisfy { setter.widthOf($0, fit.type) <= width }, "\(name) at \(side): \(fit)") }
            }
        }
    }

    @Test func aWordTooLongIsCutOnOneLineNotBroken() {
        let fit = fitCoverText("Supercalifragilisticexpialidocious", width: 100, height: 200, maxLines: 3, minPx: 12, maxPx: 30, look: look,
                               setter: setter)
        #expect(fit.type.maxLines == 1)
        #expect(fit.measured.cut)
    }

    @Test func scriptsWithMarksGetRoomBetweenLines() {
        #expect(coverLineHeight(.latin, 1.08) == 1.08)
        #expect(coverLineHeight(.tall, 1.08) == 1.4)
        #expect(coverLineHeight(.wide, 1.08) == 1.15)
    }
}

@Suite struct CoverTitleTests {
    let setter = FakeTypesetter()

    @Test func aMixNamedMixReadsAsTwoLinesWhateverItsKind() {
        #expect(coverTitle("Discovery Mix", line: stationCoverLine) == CoverTitle(title: "Discovery", line: "Mix"))
        #expect(coverTitle("Bad Bunny Radio", line: stationCoverLine) == CoverTitle(title: "Bad Bunny", line: "Station"))
        #expect(coverTitle("Your Mix", line: stationCoverLine) == CoverTitle(title: "Your Mix", line: nil))
        #expect(coverTitle("Top 50 Chart", line: playlistCoverLine) == CoverTitle(title: "Top 50", line: "Chart"))
        #expect(coverTitle("Rock Radio", line: stationCoverLine) == CoverTitle(title: "Rock", line: "Station"))
        #expect(coverTitle("Discovery MIX", line: playlistCoverLine) == CoverTitle(title: "Discovery", line: "Mix"))
    }

    @Test func possessivesStayWhole() {
        for name in ["Your Mix", "My Mix", "Our Radio"] { #expect(coverTitle(name, line: playlistCoverLine) == CoverTitle(title: name, line: nil)) }
        #expect(coverTitle("your chart", line: playlistCoverLine) == CoverTitle(title: "your chart", line: "Playlist"))
    }

    @Test func newAndTrendingAreNotKindWords() {
        #expect(coverTitle("Something New", line: playlistCoverLine) == CoverTitle(title: "Something New", line: "Playlist"))
        #expect(coverTitle("Trending", line: playlistCoverLine) == CoverTitle(title: "Trending", line: "Playlist"))
    }

    @Test func aNameTooShortOrAWordOnlyEndingSoStaysWhole() {
        #expect(coverTitle("A Mix", line: playlistCoverLine) == CoverTitle(title: "A Mix", line: nil))
        #expect(coverTitle("Mix", line: playlistCoverLine) == CoverTitle(title: "Mix", line: nil))
        #expect(coverTitle("Gym Mixtape", line: playlistCoverLine) == CoverTitle(title: "Gym Mixtape", line: "Playlist"))
        #expect(coverTitle("Road Trip Playlist", line: playlistCoverLine) == CoverTitle(title: "Road Trip Playlist", line: nil))
    }

    @Test func theCoverSaysChart() {
        #expect(coverTitle("Popular right now", line: chartCoverLine, coverTitle: "Popular") == CoverTitle(title: "Popular", line: "Chart"))
        #expect(coverTitle("Top Mix right now", line: chartCoverLine, coverTitle: "Top Mix") == CoverTitle(title: "Top Mix", line: nil))
    }

    @Test func theCoverSetsTheShortWordsAndKeepsTheListsOwnBackground() {
        let palette = seededPalette("og-pop")
        let spec = CoverSpec(id: "og-pop", name: "Popular right now", line: chartCoverLine, footer: nil, palette: palette, coverTitle: "Popular")
        #expect(coverWords(spec, side: 600, setter: setter).map(\.text) == ["Popular", "Chart"])
        #expect(planCover(spec, side: 600, setter: setter).background == chooseBackground("og-pop", palette))
        let mix = coverWords(CoverSpec(id: "og-d", name: "Discovery Mix", line: stationCoverLine, footer: nil, palette: palette), side: 600,
                             setter: setter)
        #expect(mix.map(\.text) == ["Discovery", "Mix"])
    }

    @Test func theCoverTitleIsPartOfTheKey() {
        let plain = CoverSpec(id: "og-pop", name: "Popular right now", line: chartCoverLine, footer: nil, palette: seededPalette("og-pop"))
        var titled = plain
        titled.coverTitle = "Popular"
        #expect(coverArtKey(plain, side: 160) != coverArtKey(titled, side: 160))
    }
}

@Suite struct CoverVarietyTests {
    /// The server's sheet of 24 lists and the colour of each one's music (hue, chroma, lightness;
    /// hue -1 for none). The list's name is the hash input, as on the server.
    let lists: [(String, Int, Double, Double)] = [
        ("Daft Punk Radio", 261, 0.043, 0.722), ("Billie Eilish Radio", 63, 0.061, 0.575),
        ("Tame Impala Radio", 318, 0.041, 0.453), ("Radiohead Radio", 47, 0.159, 0.657),
        ("Kendrick Lamar Radio", 4, 0.068, 0.41), ("Your Mix", 241, 0.039, 0.732),
        ("Discovery Mix", 30, 0.225, 0.581), ("Bad Bunny Radio", 30, 0.225, 0.581),
        ("Jazz & Blues Mix", 225, 0.14, 0.62), ("Metal Mix", 40, 0.163, 0.601),
        ("1970s Mix", 75, 0.14, 0.62), ("Rock Mix", 26, 0.14, 0.62),
        ("Hip-Hop Mix", 61, 0.14, 0.62), ("1990s Mix", 134, 0.14, 0.62),
        ("2020s Mix", 168, 0.14, 0.62), ("Electronic Radio", 250, 0.14, 0.62),
        ("Polka Mix", -1, 0, 0), ("Red Hot Chili Peppers Radio", -1, 0, 0),
        ("The Most Unreasonably Long Playlist Name Anyone Ever Typed Into A Music Server Radio", -1, 0, 0),
        ("宇多田ヒカル Radio", -1, 0, 0), ("블랙핑크 BLACKPINK Radio", 5, 0.041, 0.336),
        ("فيروز Radio", 69, 0.065, 0.682), ("Late Night 🌙 Chill Mix", 206, 0.14, 0.62),
        ("Ünïcödé Café Mix", -1, 0, 0),
    ]

    private func paletteOf(_ list: (String, Int, Double, Double)) -> CoverPalette {
        list.1 < 0 ? seededPalette(list.0) : .of(hue: Double(list.1), chroma: list.2, lightness: list.3, fromMusic: true)
    }

    @Test func aSheetOfListsHasNoCopies() {
        #expect(lists.count == 24)
        let picks = lists.map { "\(chooseBackground($0.0, paletteOf($0)).file)|\(coverOrientation($0.0))" }
        var pairs: [String: Int] = [:]
        for pick in picks { pairs[pick, default: 0] += 1 }
        #expect(pairs.values.allSatisfy { $0 == 1 }, "the same background turned the same way")
        var backgrounds: [String: Int] = [:]
        for list in lists { backgrounds[chooseBackground(list.0, paletteOf(list)).file, default: 0] += 1 }
        #expect(backgrounds.values.allSatisfy { $0 <= 3 }, "one background too often")
        let dull = lists[0]
        #expect(chooseBackground(dull.0, seededPalette(dull.0)) == chooseBackground(dull.0, paletteOf(dull)))
        #expect(CoverBook.standard.background.lowChromaAsGrey > 0.043)
    }

    @Test func theTurnIsFromTheIdAndCoversAllEight() {
        let turns = (0..<400).map { coverOrientation("pl-\($0)") }
        #expect(turns == (0..<400).map { coverOrientation("pl-\($0)") })
        #expect(Set(turns) == Set(0..<8))
        #expect(coverPick("pl-1") == 0x098F_28EE_76F6_47CE)
        #expect(Int((coverPick("pl-1") >> 11) % 8) == coverOrientation("pl-1"))
        #expect((6...8).contains(CoverBook.standard.background.nearest))
    }

    @Test func numberedListsLookApart() {
        for ids in [(1...12).map { "\($0)" }, (1...12).map { "p\($0)" }] {
            let none = ids.map { "\(chooseBackground($0, seededPalette($0)).file)|\(coverOrientation($0))" }
            #expect(Set(none).count == ids.count, "\(ids)")
            #expect(Set(ids.map { coverOrientation($0) }).count >= 5)
            let warm = coverPalette([[CoverSwatch(argb: 0xFFE0_701F, share: 1)]], seed: "x")
            let picks = ids.map { "\(chooseBackground($0, warm).file)|\(coverOrientation($0))" }
            #expect(Set(picks).count >= ids.count - 2, "\(ids) warm")
        }
    }

    @Test func aBackgroundTurnsAndMirrorsAsTheRuleSays() {
        let p: [UInt32] = [0, 1, 2, 3]
        #expect(orientBackground(p, side: 2, v: 0) == p)
        #expect(orientBackground(p, side: 2, v: 1) == [2, 0, 3, 1])
        #expect(orientBackground(p, side: 2, v: 2) == [3, 2, 1, 0])
        #expect(orientBackground(p, side: 2, v: 3) == [1, 3, 0, 2])
        #expect(orientBackground(p, side: 2, v: 4) == [1, 0, 3, 2])
        #expect(orientBackground(p, side: 2, v: 5) == [0, 2, 1, 3])
        let q: [UInt32] = (0..<9).map { UInt32($0) }
        var r = q
        for _ in 0..<4 { r = orientBackground(r, side: 3, v: 1) }
        #expect(r == q)
    }
}

@Suite struct PlaylistCoversTests {
    @Test func aCoverIsDrawnAtTheNextSizeUpInFineSteps() {
        #expect(coverSide(32) == 32)
        #expect(coverSide(33) == 36)
        #expect(coverSide(128) == 128)
        #expect(coverSide(129) == 144)
        #expect(coverSide(513) == 576)
        for px in 16...2048 {
            let side = coverSide(px)
            #expect(side >= px)
            if px >= 32 { #expect(Double(side) <= Double(px) * 1.125 + 1, "\(px) drawn at \(side)") }
        }
    }

    @Test func theFootLineSaysWhoseItIsOrHowBig() {
        #expect(playlistCoverFooter(12, owner: "winters", you: "winters") == "12 songs")
        #expect(playlistCoverFooter(1, owner: nil, you: "winters") == "1 song")
        #expect(playlistCoverFooter(2500, owner: "Winters", you: "winters") == "2,500 songs")
        #expect(playlistCoverFooter(12, owner: "sam", you: "winters") == "By sam")
        #expect(playlistCoverFooter(0, owner: "winters", you: "winters") == nil)
    }

    @Test func coloursComeFromOneCoverPerAlbum() {
        let songs: [(album: String?, cover: String?)] = [("a1", "c1"), ("a1", "c1"), ("a2", nil), ("a3", "c3"), ("a4", "c4"), ("a5", "c5"), ("a6", "c6")]
        #expect(coverSources(songs) == ["c1", "c3", "c4", "c5"])
    }

    @Test func paletteKeysFollowTheirCovers() {
        let key = coverPaletteKey("music.example", ["c1", "c2"])
        #expect(key != coverPaletteKey("music.example", ["c2", "c1"]))
        #expect(key != coverPaletteKey("other.example", ["c1", "c2"]))
        #expect(key.contains("v\(coverPaletteVersion)"))
    }

    @Test func fileNamesAreShortAndSafe() {
        let name = coverFileName("playlist-art:v1:1.2:pl/ü:1.2.3.4m:160:x", "png")
        #expect(name.range(of: "^[0-9a-f]{32}\\.png$", options: .regularExpression) != nil)
        #expect(name == coverFileName("playlist-art:v1:1.2:pl/ü:1.2.3.4m:160:x", "png"))
    }
}
