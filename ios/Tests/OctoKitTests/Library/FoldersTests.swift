import Foundation
import Testing
@testable import OctoKit

@Suite struct FolderTreeTests {
    private struct Item { let title: String; let path: String }

    private func tree(_ items: Item...) -> FolderNode<Item> {
        buildFolderTree(items, pathOf: { pathNames($0.path) }, songOrder: { $0.title < $1.title })
    }

    @Test func pathNamesIgnoreSlashesAtEitherEnd() {
        #expect(pathNames("Music/Kavinsky/Nightcall/") == ["Music", "Kavinsky", "Nightcall"])
        #expect(pathNames("/Music//") == ["Music"])
        #expect(pathNames(nil).isEmpty)
        #expect(pathNames("").isEmpty)
    }

    @Test func buildsNestedFoldersWithSongsAtEachLevel() throws {
        let root = tree(Item(title: "b", path: "Music/Kavinsky/OutRun/"), Item(title: "a", path: "Music/Kavinsky/OutRun/"),
                        Item(title: "single", path: "Music/Kavinsky/"), Item(title: "teardrop", path: "Music/Massive Attack/Mezzanine/"))
        let music = try #require(root.at(["Music"]))
        #expect(music.folders.map(\.name) == ["Kavinsky", "Massive Attack"])
        let kavinsky = try #require(music.at(["Kavinsky"]))
        #expect(kavinsky.folders.map(\.name) == ["OutRun"])
        #expect(kavinsky.songs.map(\.title) == ["single"])
        #expect(kavinsky.at(["OutRun"])?.songs.map(\.title) == ["a", "b"])
        #expect(root.at(["Music", "Nobody"]) == nil)
    }

    @Test func countsEverySongUnderAFolder() {
        let root = tree(Item(title: "a", path: "Music/A/1/"), Item(title: "b", path: "Music/A/1/"), Item(title: "c", path: "Music/A/"),
                        Item(title: "d", path: "Music/B/"))
        #expect(root.songCount == 4)
        #expect(root.at(["Music", "A"])?.songCount == 3)
        #expect(root.at(["Music", "A", "1"])?.songCount == 2)
    }

    @Test func allSongsFollowTheShownOrderFoldersFirst() {
        let root = tree(Item(title: "own", path: "Music/A/"), Item(title: "deep", path: "Music/A/Z/"), Item(title: "inner", path: "Music/A/B/"))
        #expect(root.at(["Music", "A"])?.allSongs().map(\.title) == ["inner", "deep", "own"])
    }

    @Test func collapsesDownToWhereTheMusicIs() {
        let collapsed = tree(Item(title: "a", path: "Music/Rock/A/"), Item(title: "b", path: "Music/Rock/B/")).collapsed()
        #expect(collapsed.skipped == ["Music", "Rock"])
        #expect(collapsed.name == "Rock")
        #expect(collapsed.root.folders.map(\.name) == ["A", "B"])
    }

    @Test func collapsingStopsAtAFolderWithItsOwnSongs() {
        let collapsed = tree(Item(title: "a", path: "Music/"), Item(title: "b", path: "Music/Inner/")).collapsed()
        #expect(collapsed.name == "Music")
        #expect(collapsed.root.songs.map(\.title) == ["a"])
    }

    @Test func nothingIsSkippedWhenTheTopAlreadySplits() {
        let collapsed = tree(Item(title: "a", path: "Music/"), Item(title: "b", path: "Download/")).collapsed()
        #expect(collapsed.skipped.isEmpty)
        #expect(collapsed.name == "")
        #expect(collapsed.root.folders.map(\.name) == ["Download", "Music"])
    }

    @Test func anEmptyTreeCollapsesToItself() {
        let collapsed = tree().collapsed()
        #expect(collapsed.root.songCount == 0)
        #expect(collapsed.name == "")
    }

    @Test func foldersSortTheWayPeopleCount() {
        let root = tree(Item(title: "a", path: "Disc 10/"), Item(title: "b", path: "Disc 2/"), Item(title: "c", path: "disc 1/"),
                        Item(title: "d", path: "Abba/"))
        #expect(root.folders.map(\.name) == ["Abba", "disc 1", "Disc 2", "Disc 10"])
    }

    @Test func naturalOrderHandlesLeadingZerosAndTies() {
        let names = ["Track 010", "Track 9", "track 9", "Track 9b", "Track"]
        #expect(names.sorted { naturalOrder($0, $1) < 0 } == ["Track", "Track 9", "track 9", "Track 9b", "Track 010"])
    }
}

@Suite struct FolderSongsTests {
    private let folders: [String: FolderContents<String>] = [
        "artist": FolderContents(folders: ["album1", "album2"], songs: ["artist-loose"]),
        "album1": FolderContents(folders: [], songs: ["a1", "a2", "a3"]),
        "album2": FolderContents(folders: ["bonus"], songs: ["b1", "b2"]),
        "bonus": FolderContents(folders: [], songs: ["x1"]),
    ]

    private final class Opened: @unchecked Sendable { var ids: [String] = [] }

    private func gather(_ start: FolderContents<String>, limit: Int, maxFolders: Int, opened: Opened = Opened()) async -> Gathered<String> {
        await gatherSongs(start, limit: limit, maxFolders: maxFolders) { id in
            opened.ids.append(id)
            return folders[id]!
        }
    }

    @Test func gathersEverythingInTheShownOrder() async {
        let got = await gather(folders["artist"]!, limit: 100, maxFolders: 100)
        #expect(got.songs == ["a1", "a2", "a3", "x1", "b1", "b2", "artist-loose"])
        #expect(!got.limitReached)
    }

    @Test func stopsAtTheSongLimitAndSaysSo() async {
        let opened = Opened()
        let got = await gather(folders["artist"]!, limit: 4, maxFolders: 100, opened: opened)
        #expect(got.songs == ["a1", "a2", "a3", "x1"])
        #expect(got.limitReached)
        #expect(opened.ids == ["album1", "album2", "bonus"])
    }

    @Test func exactlyTheLimitWithNothingLeftIsNotCut() async {
        let got = await gather(folders["album1"]!, limit: 3, maxFolders: 100)
        #expect(got.songs.count == 3)
        #expect(!got.limitReached)
    }

    @Test func stopsAfterTheFolderLimit() async {
        let opened = Opened()
        let got = await gather(folders["artist"]!, limit: 100, maxFolders: 1, opened: opened)
        #expect(got.songs == ["a1", "a2", "a3"])
        #expect(got.limitReached)
        #expect(opened.ids == ["album1"])
    }

    @Test func aFolderListedTwiceIsOpenedOnce() async {
        let opened = Opened()
        let got = await gather(FolderContents(folders: ["album1", "album1"], songs: []), limit: 100, maxFolders: 100, opened: opened)
        #expect(got.songs == ["a1", "a2", "a3"])
        #expect(opened.ids == ["album1"])
    }

    @Test func anEmptyFolderGathersNothing() async {
        let got = await gather(FolderContents(folders: [], songs: []), limit: 10, maxFolders: 10)
        #expect(got.songs.isEmpty)
        #expect(!got.limitReached)
    }

    @Test func namesTheServerPeopleWouldKnow() {
        #expect(serverName(isOcto: true, type: "navidrome", host: "music.example") == "Octo")
        #expect(serverName(isOcto: false, type: "navidrome", host: "music.example") == "Navidrome")
        #expect(serverName(isOcto: false, type: " ", host: "music.example") == "music.example")
        #expect(serverName(isOcto: false, type: nil, host: "music.example") == "music.example")
    }
}
