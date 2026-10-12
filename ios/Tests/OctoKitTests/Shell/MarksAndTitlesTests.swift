import Foundation
import Testing
@testable import OctoKit

@Suite struct NotInLibraryTests {
    @Test func onlyASongFoundOnlineAndNotYetInTheLibraryIsMarked() {
        #expect(isOutsideLibrary(songId: "e1", isExternal: true, adopted: []))
        #expect(!isOutsideLibrary(songId: "t-42", isExternal: false, adopted: []))
        #expect(!isOutsideLibrary(songId: "e1", isExternal: true, adopted: ["e1"]))
        #expect(isOutsideLibrary(songId: "e2", isExternal: true, adopted: ["e1"]))
        #expect(!isOutsideLibrary(songId: nil, isExternal: true, adopted: []))
    }

    @Test func onlyFinishedDownloadsCountAsInTheLibrary() {
        let phases: [String: DownloadPhase] = ["a": .done, "b": .queued, "c": .downloading(0.5), "d": .adding,
                                               "e": .failed("gone"), "f": DownloadPhase.none]
        #expect(adoptedFinds(phases) == ["a"])
        #expect(isOutsideLibrary(songId: "c", isExternal: true, adopted: adoptedFinds(phases)))
    }

    @Test func theMarkScalesWithTheArtworkWithinItsBounds() {
        #expect(abs(notInLibraryMarkSize(150) - 18.75) < 0.01)
        #expect(abs(notInLibraryMarkSize(120) - 15) < 0.01)
        #expect(notInLibraryMarkSize(44) == 12)
        #expect(notInLibraryMarkSize(36) == 12)
        #expect(notInLibraryMarkSize(240) == 20)
        #expect(notInLibraryMarkSize(400) == 20)
    }

    @Test func onASquareCoverTheMarkSitsJustInFromTheCorner() {
        #expect(abs(notInLibraryMarkInset(150, mark: 18.75, round: false) - 6) < 0.01)
        #expect(abs(notInLibraryMarkInset(44, mark: 12, round: false) - 3) < 0.01)
    }

    @Test func onARoundPictureTheWholeMarkStaysInsideTheCircle() {
        for art in [36.0, 48, 96, 160] {
            let mark = notInLibraryMarkSize(art)
            let inset = notInLibraryMarkInset(art, mark: mark, round: true)
            let radius = art / 2
            let center = art - inset - mark / 2
            let fromMiddle = 2.0.squareRoot() * (center - radius)
            #expect(fromMiddle + mark / 2 <= radius + 1e-9)
            #expect(center > radius)
            #expect(inset > 0)
        }
    }

    @Test func aScreenReaderHearsWhatIsNotInTheLibrary() {
        #expect(artworkDescription(nil, outside: false) == nil)
        #expect(artworkDescription(nil, outside: true) == "Not in your library")
        #expect(artworkDescription("Cover", outside: true) == "Cover, not in your library")
        #expect(artworkDescription("Cover", outside: false) == "Cover")
    }
}

@Suite struct TitlesTests {
    @Test func aNameJoinedWithUnderscoresMayWrapAfterThem() {
        #expect(breakableText("a_ b __") == "a_ b __")
        #expect(breakableText("Radiohead_OK") == "Radiohead_\u{200B}OK")
        #expect(breakableText("Radiohead_OK_Computer").filter { $0 == "\u{200B}" }.count == 2)
    }

    @Test func aWordThatFitsKeepsItsSize() {
        #expect(fitScale(widest: 300, width: 300) == 1)
    }

    @Test func aWordTooWideIsSetJustSmallEnoughToFit() {
        let scale = fitScale(widest: 600, width: 300)
        #expect(scale < 0.5)
        #expect(scale > 0.45)
        #expect(600 * scale <= 300)
    }

    @Test func theButtonsShareTheLineWhenTheWholeTitleFits() {
        #expect(actionsBeside(titleWidth: 100, actionsWidth: 200, gap: 12, width: 312))
        #expect(!actionsBeside(titleWidth: 101, actionsWidth: 200, gap: 12, width: 312))
        #expect(actionsBeside(titleWidth: 5_000, actionsWidth: 200, gap: 12, width: nil))
    }
}
