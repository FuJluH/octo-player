import Foundation
import Testing
@testable import OctoKit

@Suite struct OctoListGroupsTests {
    /// An id of Octo's own shape: "og" or "or" and 20 letters and digits.
    static func octoId(_ lead: String, _ n: Int) -> String { lead + String(format: "%020d", n) }

    /// A server playlist as getPlaylists lists it.
    func list(_ id: String, _ name: String, owner: String? = "sam", group: String? = nil, octoList: String? = nil,
              readonly: Bool = true) -> Playlist {
        var fields: [String: Any] = ["id": id, "name": name, "readonly": readonly, "songCount": 25]
        if let owner { fields["owner"] = owner }
        if let group { fields["octoGroup"] = group }
        if let octoList { fields["octoList"] = octoList }
        let data = try! JSONSerialization.data(withJSONObject: fields)
        return try! JSONDecoder().decode(Playlist.self, from: data)
    }

    func og(_ n: Int) -> String { Self.octoId("og", n) }

    @Test func eachKindOctoNamesHasItsGroup() {
        let cases: [(String, OctoListGroup?)] = [
            ("forYou", .forYou), ("station", .stations), ("chart", .charts), ("genre", .genres), ("artist", .artists),
            ("country", .countries), ("decade", .years), ("year", .years), ("liked", nil), ("somethingNew", .more),
        ]
        for (word, group) in cases {
            #expect(octoListGroup(list(og(1), "A list", group: word), listener: "sam") == group)
        }
    }

    @Test func theKindDecidesWhateverTheIdLooksLike() {
        #expect(octoListGroup(list("42", "Rock Mix", group: "genre"), listener: "sam") == .genres)
        #expect(octoListGroup(list(Self.octoId("or", 1), "Rock Mix", group: "genre"), listener: "sam") == .genres)
    }

    @Test func anOlderServerMarksOnlyMadeForYouLists() {
        #expect(octoListGroup(list(og(1), "Deep Cuts", octoList: "deepCuts"), listener: "sam") == .forYou)
        #expect(octoListGroup(list(og(2), "Liked Songs", octoList: "liked"), listener: "sam") == nil)
        #expect(octoListGroup(list("7", "New Releases", octoList: "newReleases"), listener: "sam") == .forYou)
    }

    @Test func anOlderServersListsAreKnownByTheirIds() {
        #expect(octoListGroup(list(Self.octoId("or", 3), "Your Radio"), listener: "sam") == .stations)
        #expect(octoListGroup(list(og(4), "1990s Mix"), listener: "sam") == .years)
        #expect(octoListGroup(list(og(5), "1994 Mix"), listener: "sam") == .more)
        #expect(octoListGroup(list(og(6), "Rock Mix"), listener: "sam") == .more)
    }

    @Test func someoneElsesListNeverCounts() {
        #expect(octoListGroup(list(og(1), "Rock Mix", owner: "alex", group: "genre"), listener: "sam") == nil)
        #expect(octoListGroup(list(og(1), "Rock Mix", owner: "SAM", group: "genre"), listener: "sam") == .genres)
        // With no listener known, or no owner named, it counts.
        #expect(octoListGroup(list(og(1), "Rock Mix", owner: "alex", group: "genre"), listener: " ") == .genres)
        #expect(octoListGroup(list(og(1), "Rock Mix", owner: nil, group: "genre"), listener: "sam") == .genres)
    }

    @Test func listsOctoDidNotMakeNeverCount() {
        // A smart playlist and another's public one are read-only too, with ids of another shape.
        #expect(octoListGroup(list("b1c2-smart", "Top rated", readonly: true), listener: "sam") == nil)
        #expect(octoListGroup(list("17", "Road trip", readonly: false), listener: "sam") == nil)
        // Too short, a wrong lead, or a character that is not a letter or digit.
        #expect(octoListGroup(list("og123", "1990s Mix"), listener: "sam") == nil)
        #expect(octoListGroup(list("ox" + String(format: "%020d", 1), "1990s Mix"), listener: "sam") == nil)
        #expect(octoListGroup(list("og-" + String(format: "%019d", 1), "1990s Mix"), listener: "sam") == nil)
    }

    @Test func groupsComeInTheirOrderAndEmptyOnesAreLeftOut() {
        let lists = [
            list(og(1), "Rock Mix", group: "genre"), list(og(2), "Mixed bag", group: "other"), list(og(3), "Top 50", group: "chart"),
            list(og(4), "Deep Cuts", group: "forYou"), list(Self.octoId("or", 5), "Your Radio", group: "station"),
            list(og(6), "2010s Mix", group: "decade"), list(og(7), "Liked Songs", group: "liked"), list("8", "Road trip", readonly: false),
        ]
        let groups = octoListGroups(lists, listener: "sam")
        #expect(groups.map(\.group) == [.forYou, .stations, .charts, .years, .genres, .more])
        #expect(groups.map(\.group.title) == ["Made for you", "Radio", "Charts", "Years", "Genres", "More from Octo"])
        #expect(octoListGroups([], listener: "sam").isEmpty)
    }

    @Test func yearsHaveDecadesFirstThenYearsEachNewestFirst() {
        let lists = [list(og(1), "1994 Mix", group: "year"), list(og(2), "1990s Mix", group: "decade"),
                     list(og(3), "2019 Mix", group: "year"), list(og(4), "2010s Mix", group: "decade")]
        let years = octoListGroups(lists, listener: "sam").first { $0.group == .years }?.lists.map(\.name)
        #expect(years == ["2010s Mix", "1990s Mix", "2019 Mix", "1994 Mix"])
    }

    @Test func madeForYouAndChartsKeepTheServersOrderAndTheRestGoByName() {
        let lists = [list(og(1), "Rediscover", group: "forYou"), list(og(2), "Deep Cuts", group: "forYou"),
                     list(og(3), "Top 50", group: "chart"), list(og(4), "Best New Songs", group: "chart"),
                     list(og(5), "rock Mix", group: "genre"), list(og(6), "Ambient Mix", group: "genre"), list(og(7), "Jazz Mix", group: "genre")]
        let groups = octoListGroups(lists, listener: "sam")
        #expect(groups.first { $0.group == .forYou }?.lists.map(\.name) == ["Rediscover", "Deep Cuts"])
        #expect(groups.first { $0.group == .charts }?.lists.map(\.name) == ["Top 50", "Best New Songs"])
        #expect(groups.first { $0.group == .genres }?.lists.map(\.name) == ["Ambient Mix", "Jazz Mix", "rock Mix"])
    }

    @Test func homeShowsEachMixGroupOnItsShelf() {
        let lists = [list(og(1), "Rock Mix", group: "genre"), list(og(2), "1990s Mix", group: "decade"),
                     list(og(3), "Prince Mix", group: "artist"), list(og(4), "France Mix", group: "country"),
                     list(og(5), "Deep Cuts", group: "forYou")]
        let shelves = homeMixes(lists, listener: "sam", sourceId: "server:1")
        #expect(shelves[.genreMixes]?.map(\.name) == ["Rock Mix"])
        #expect(shelves[.yearMixes]?.map(\.name) == ["1990s Mix"])
        #expect(shelves[.artistMixes]?.map(\.name) == ["Prince Mix"])
        #expect(shelves[.countryMixes]?.map(\.name) == ["France Mix"])
        #expect(shelves.count == 4)
        #expect(shelves[.genreMixes]?.first?.octoGroup == "genre")
        #expect(shelves[.genreMixes]?.first?.songCount == 25)
        // A mix is a fixed list: it plays under its name and is never kept going.
        let rock = try! #require(shelves[.genreMixes]?.first)
        #expect(serverListSource(id: rock.id, name: rock.name, octoGroup: rock.octoGroup) == .played("Rock Mix"))
    }

    @Test func theListenersOwnListIsNeverClaimedByItsId() {
        // Another server's own ids can have Octo's shape; a list the listener can change is theirs.
        #expect(octoListGroup(list(og(9), "1990s Mix", readonly: false), listener: "sam") == nil)
        #expect(octoListGroup(list(Self.octoId("or", 9), "Road trip", readonly: false), listener: "sam") == nil)
        #expect(octoListGroups([list(og(9), "Road trip", readonly: false)], listener: "sam").isEmpty)
    }

    @Test func aServerThatMarksItsListsIsNeverGuessedAt() {
        let marked = list(og(1), "Rock Mix", group: "genre")
        let unmarked = list(og(2), "1990s Mix")
        let groups = octoListGroups([marked, unmarked], listener: "sam")
        #expect(groups.map(\.group) == [.genres])
        #expect(groups.flatMap(\.lists).map(\.id) == [marked.id])
        #expect(octoListGroup(unmarked, listener: "sam", guess: false) == nil)
        // Made for you lists marked the older way still count.
        #expect(octoListGroup(list(og(3), "Deep Cuts", octoList: "deepCuts"), listener: "sam", guess: false) == .forYou)
    }

    @Test func octosListsOpenAsTheServerHasThem() {
        #expect(opensAsServerList(list("42", "Rock Mix", group: "genre"), runsOcto: true, listener: "sam"))
        #expect(opensAsServerList(list(og(1), "Deep Cuts"), runsOcto: true, listener: "sam"))
        #expect(opensAsServerList(list(og(1), "Deep Cuts", owner: nil), runsOcto: true, listener: "sam"))
        #expect(!opensAsServerList(list("42", "Road trip", readonly: false), runsOcto: true, listener: "sam"))
    }

    @Test func onlyTheListenersListsOnOctoOpenAsTheServerHasThem() {
        #expect(!opensAsServerList(list(og(1), "Deep Cuts"), runsOcto: false, listener: "sam"))
        #expect(!opensAsServerList(list("42", "Rock Mix", group: "genre"), runsOcto: false, listener: "sam"))
        #expect(!opensAsServerList(list(og(1), "Rock Mix", owner: "alex", group: "genre"), runsOcto: true, listener: "sam"))
        #expect(!opensAsServerList(list(og(9), "Road trip", readonly: false), runsOcto: true, listener: "sam"))
    }

    @Test func theKindIsReadFromTheServersAnswer() throws {
        let json = #"{"subsonic-response":{"status":"ok","version":"1.16.1","playlists":{"playlist":["#
            + #"{"id":"og00000000000000000001","name":"Rock Mix","owner":"sam","songCount":50,"readonly":true,"octoGroup":"genre"},"#
            + #"{"id":"17","name":"Road trip","owner":"sam","songCount":12}]}}}"#
        let body: PlaylistsBody = try SubsonicClient.decode(Data(json.utf8), key: "playlists")
        #expect(body.playlist.map(\.octoGroup) == ["genre", nil])
    }
}
