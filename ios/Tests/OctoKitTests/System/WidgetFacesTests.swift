import Foundation
import Testing
@testable import OctoSystem

/// The Now playing widget's shapes and words, and the commands its buttons carry.
@Suite struct WidgetFacesTests {
    let song = WidgetPlayback(title: "Hold On, We're Going Home", artist: "Drake", isPlaying: true)

    @Test func sizeFollowsWidthFirstThenHeight() {
        #expect(WidgetSize(width: 110, height: 40) == .small)
        #expect(WidgetSize(width: 180, height: 40) == .small)
        // Tall but narrow stays small: three buttons need the width.
        #expect(WidgetSize(width: 150, height: 170) == .small)
        #expect(WidgetSize(width: 250, height: 40) == .medium)
        #expect(WidgetSize(width: 320, height: 99) == .medium)
        #expect(WidgetSize(width: 250, height: 110) == .large)
        #expect(WidgetSize(width: 400, height: 300) == .large)
    }

    @Test func sizeThresholdsAreWhereEachShapeStarts() {
        #expect(WidgetSize(width: WidgetSize.mediumMinWidth, height: WidgetSize.smallMinHeight) == .medium)
        #expect(WidgetSize(width: WidgetSize.mediumMinWidth, height: WidgetSize.largeMinHeight) == .large)
        // No size reported yet counts as the smallest.
        #expect(WidgetSize(width: 0, height: 0) == .small)
    }

    @Test func iPhoneWidgetSlotsTakeTheirShapes() {
        // The small slot is square and narrower than three buttons need; medium and large are
        // wide and tall enough for everything.
        #expect(WidgetSize(width: 170, height: 170) == .small)
        #expect(WidgetSize(width: 364, height: 170) == .large)
        #expect(WidgetSize(width: 364, height: 382) == .large)
    }

    @Test func smallShowsTheTitleAndPlayOrPauseOnly() {
        let face = nowPlayingFace(song, .small)
        #expect(face.title == "Hold On, We're Going Home")
        #expect(face.artist == nil)
        #expect(face.titleLines == 1)
        #expect(face.playing)
        #expect(!face.showSkips)
        #expect(!face.empty)
    }

    @Test func mediumAddsTheArtistAndTheSkipButtons() {
        let face = nowPlayingFace(song, .medium)
        #expect(face.artist == "Drake")
        #expect(face.titleLines == 1)
        #expect(face.showSkips)
    }

    @Test func largeGivesTheTitleASecondLine() {
        let face = nowPlayingFace(song, .large)
        #expect(face.artist == "Drake")
        #expect(face.titleLines == 2)
        #expect(face.showSkips)
    }

    @Test func pausedShowsPlay() {
        var paused = song
        paused.isPlaying = false
        #expect(!nowPlayingFace(paused, .medium).playing)
    }

    @Test func nothingLoadedShowsNothingPlayingAndOnlyPlayAtEverySize() {
        for size in WidgetSize.allCases {
            let face = nowPlayingFace(nil, size)
            #expect(face.title == WidgetWords.nothingPlaying)
            #expect(face.artist == nil)
            #expect(!face.playing)
            #expect(!face.showSkips)
            #expect(face.empty)
        }
    }

    @Test func aSongWithNoTitleOrArtistStillReadsWell() {
        let face = nowPlayingFace(WidgetPlayback(title: "  ", artist: "", isPlaying: false), .large)
        #expect(face.title == WidgetWords.unknownSong)
        #expect(face.artist == nil)
        #expect(!face.empty)
    }

    @Test func textIsTrimmedAndRunsOfSpacesBecomeOne() {
        #expect(widgetClip("  Take \n  Care ") == "Take Care")
        #expect(widgetClip(nil) == nil)
        #expect(widgetClip(" \t ") == nil)
    }

    @Test func longTextIsCutWithAnEllipsisWithinTheLimit() throws {
        let cut = try #require(widgetClip(String(repeating: "a", count: 200)))
        #expect(cut.count == widgetTextLimit)
        #expect(cut.hasSuffix("…"))
        let exact = String(repeating: "b", count: widgetTextLimit)
        #expect(widgetClip(exact) == exact)
    }

    @Test func cuttingDoesNotLeaveASpaceBeforeTheEllipsis() {
        #expect(widgetClip("abc  defgh", limit: 5) == "abc…")
    }

    @Test func commandsSurviveTheTripThroughALink() {
        let all = WidgetCommand.all
        #expect(all.count == 8)
        for command in all {
            #expect(WidgetCommand(encoded: command.encoded) == command)
            #expect(OctoLink(OctoLink.command(command).url) == .command(command))
        }
        // Every button gets its own link.
        #expect(Set(all.map { OctoLink.command($0).url }).count == all.count)
        #expect(WidgetCommand(encoded: nil) == nil)
        #expect(WidgetCommand(encoded: "quick:Nope") == nil)
        #expect(WidgetCommand(encoded: "stop") == nil)
    }

    @Test func commandsKeepTheirWords() {
        #expect(WidgetCommand.play.encoded == "play")
        #expect(WidgetCommand.pause.encoded == "pause")
        #expect(WidgetCommand.next.encoded == "next")
        #expect(WidgetCommand.previous.encoded == "previous")
        #expect(WidgetCommand.quick(.liked).encoded == "quick:Liked")
        #expect(WidgetCommand.quick(.recentlyAdded).encoded == "quick:RecentlyAdded")
        #expect(WidgetCommand.quick(.albumMix).encoded == "quick:AlbumMix")
        #expect(WidgetCommand.quick(.resume).encoded == "quick:Resume")
    }

    @Test func linksOpenTheAppThePlayerOrACommand() throws {
        #expect(OctoLink.open.url.absoluteString == "octo://open")
        #expect(OctoLink.player.url.absoluteString == "octo://player")
        #expect(OctoLink.command(.quick(.liked)).url.absoluteString == "octo://widget?command=quick:Liked")
        #expect(OctoLink(try #require(URL(string: "OCTO://Player"))) == .player)
        #expect(OctoLink(try #require(URL(string: "octo://widget?command=next"))) == .command(.next))
        #expect(OctoLink(try #require(URL(string: "octo://widget"))) == nil)
        #expect(OctoLink(try #require(URL(string: "octo://import"))) == nil)
        #expect(OctoLink(try #require(URL(string: "octo://join?server=x"))) == nil)
        #expect(OctoLink(try #require(URL(string: "https://player"))) == nil)
    }

    @Test func quickPlayKeepsItsOrderNamesAndLists() {
        #expect(QuickPick.allCases == [.liked, .recentlyAdded, .albumMix, .resume])
        #expect(QuickPick.allCases.map(\.label) == ["Liked songs", "Recently added", "Album mix", "Resume"])
        #expect(QuickPick.recentAlbums == 10)
        #expect(QuickPick.mixAlbums == 8)
    }
}
