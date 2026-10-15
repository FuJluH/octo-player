import Foundation
import Testing
@testable import OctoKit

@Suite struct StationSourceTest {
    let mix = QueueSource.station(id: "or1234", name: "Your Radio")

    @Test func aStationIsHeadedByItsName() {
        #expect(queueSourceTitle(mix) == "Next from Your Radio")
        #expect(queueSourceTitle(.station(id: "or1", name: "")) == "Up next")
    }

    @Test func aStationIsSavedWithItsIdAndName() {
        #expect(mix.encoded == "station:or1234:Your Radio")
        #expect(queueSourceOf("station:or1234:Your Radio") == mix)
    }

    @Test func aStationSurvivesBeingSavedWithColonsInItsName() {
        for source in [mix, .station(id: "or9", name: "Radio: a:b"), .station(id: "or9", name: ""), .station(id: "or9", name: ":")] {
            #expect(queueSourceOf(source.encoded) == source)
        }
    }

    @Test func aStationWithNoIdReadsBackAsAListWithNoName() {
        #expect(queueSourceOf("station::Your Radio") == .none)
        #expect(queueSourceOf("station:") == .none)
    }

    @Test func everyOtherSavedWordReadsBackAsBefore() {
        #expect(queueSourceOf("you") == .you)
        #expect(queueSourceOf("autoplay") == .autoplay)
        #expect(queueSourceOf("list") == .none)
        #expect(queueSourceOf("list:") == .none)
        #expect(queueSourceOf("list:OK Computer") == .played("OK Computer"))
        #expect(queueSourceOf("list:station:or1:x") == .played("station:or1:x"))
        #expect(queueSourceOf("stations") == .none)
    }

    @Test func onlyOctosStationsPlayAsStations() {
        #expect(serverListSource(id: "or1234", name: "Your Radio") == .station(id: "or1234", name: "Your Radio"))
        #expect(serverListSource(id: "og5678", name: "Deep Cuts") == .played("Deep Cuts"))
        #expect(serverListSource(id: "og5678", name: "") == .none)
        #expect(serverListSource(id: "or:12", name: "Odd") == .played("Odd"))
        #expect(serverListSource(id: "or1234", name: "Your Radio", octoGroup: "station") == .station(id: "or1234", name: "Your Radio"))
        #expect(serverListSource(id: "or1234", name: "Rock Mix", octoGroup: "genre") == .played("Rock Mix"))
    }

    @Test func stationSongsAreOfferedByTheExtension() {
        #expect(offersStationSongs(["octoStations:1"]))
        #expect(offersStationSongs(["songLyrics:1", "octoStations:2"]))
        #expect(!offersStationSongs(["octoTopSongs:1", "octoStationsX:1"]))
        #expect(!offersStationSongs([]))
    }
}

@Suite struct StationTopUpTest {
    let mix = QueueSource.station(id: "or1", name: "Your Radio")
    let discovery = QueueSource.station(id: "or2", name: "Discovery Radio")

    func run(_ count: Int) -> [QueueSource] { Array(repeating: mix, count: count) }

    @Test func aStationRunningLowIsToppedUp() {
        #expect(stationToTopUp(run(50), current: 30) == mix)
        #expect(stationToTopUp(run(50), current: 49) == mix)
        #expect(stationToTopUp(run(3), current: 0) == mix)
    }

    @Test func aStationWithEnoughToComeIsLeftAlone() {
        #expect(stationToTopUp(run(50), current: 29) == nil)
        #expect(stationToTopUp(run(50), current: 0) == nil)
    }

    @Test func songsTheListenerQueuedAfterTheStationLeaveItGoing() {
        #expect(stationToTopUp(run(10) + [.you], current: 9) == mix)
        #expect(stationToTopUp(run(10) + [.you, .you], current: 8) == mix)
        // Only the listener's songs from the one playing on: no station to keep going.
        #expect(stationToTopUp(run(10) + [.you], current: 10) == nil)
    }

    @Test func theLastStationFromTheOnePlayingIsTheOneToppedUp() {
        #expect(stationToTopUp(run(8) + [discovery, .you], current: 7) == discovery)
        #expect(stationToTopUp([discovery] + run(4), current: 1) == mix)
        // A station that played before the current song is not topped up.
        #expect(stationToTopUp([mix, .you, .you], current: 1) == nil)
    }

    @Test func aQueueWithNoStationIsNeverToppedUp() {
        #expect(stationToTopUp([.you, .autoplay, .played("OK Computer")], current: 2) == nil)
        #expect(stationToTopUp([.played("Deep Cuts")], current: 0) == nil)
    }

    @Test func aPlaceOutsideTheQueueTopsUpNothing() {
        #expect(stationToTopUp(run(3), current: -1) == nil)
        #expect(stationToTopUp(run(3), current: 3) == nil)
        #expect(stationToTopUp([], current: 0) == nil)
    }
}

@Suite struct StationTopUpInPlayOrderTest {
    let radio = QueueSource.station(id: "or1", name: "Your Radio")

    /// 50 of the station's songs, the one playing `rank` places into the play order.
    func queue(at rank: Int, shuffle: Bool, repeatMode: RepeatMode = .off) -> PlayQueue {
        let items = (0..<50).map { QueueItem(trackId: "s\($0)", uri: "", title: "s\($0)", source: radio) }
        var q = PlayQueue()
        var random = SeededRandom(state: 11)
        q.setItems(items, startIndex: 0, using: &random)
        let start = shuffle ? q.order[rank] : rank
        var again = SeededRandom(state: 11)
        q.setItems(items, startIndex: start, using: &again)
        q.shuffle = shuffle
        q.repeatMode = repeatMode
        return q
    }

    @Test func shuffledTheSongsLeftAreCountedInPlayOrder() throws {
        let low = queue(at: 30, shuffle: true)
        let found = try #require(stationTopUp(low))
        #expect(found.station == radio)
        #expect(found.tail == low.items[low.order[49]].entryId)
        #expect(stationTopUp(queue(at: 29, shuffle: true)) == nil)
    }

    @Test func inQueueOrderTheLastEntryIsTheTail() throws {
        let low = queue(at: 30, shuffle: false)
        #expect(try #require(stationTopUp(low)).tail == low.items[49].entryId)
        #expect(stationTopUp(queue(at: 29, shuffle: false)) == nil)
    }

    @Test func aRepeatingQueueIsNeverToppedUp() {
        #expect(stationTopUp(queue(at: 49, shuffle: false, repeatMode: .all)) == nil)
        #expect(stationTopUp(queue(at: 49, shuffle: true, repeatMode: .one)) == nil)
        #expect(stationTopUp(PlayQueue()) == nil)
    }
}

@Suite struct StationSongsQueuedTest {
    let mix = QueueSource.station(id: "or1", name: "Your Radio")

    func item(_ id: String, _ source: QueueSource) -> QueueItem { QueueItem(trackId: id, uri: "", title: id, source: source) }

    @Test func onlyThatStationsSongsAreTold() {
        let items = [item("a", mix), item("x", .you), item("b", mix), item("d", .station(id: "or2", name: "Discovery Radio")),
                     item("c", .station(id: "or1", name: "Your Radio")), item("e", .autoplay)]
        #expect(stationSongsQueued(items, station: mix) == ["a", "b", "c"])
    }

    @Test func theLastHundredAreToldInQueueOrder() {
        let items = (0..<130).map { item("s\($0)", mix) }
        let told = stationSongsQueued(items, station: mix)
        #expect(told.count == stationAfter)
        #expect(told.first == "s30")
        #expect(told.last == "s129")
        #expect(told == (30..<130).map { "s\($0)" })
    }

    @Test func aQueueWithoutTheStationTellsNothing() {
        #expect(stationSongsQueued([item("a", .you)], station: mix).isEmpty)
        #expect(stationSongsQueued([], station: mix).isEmpty)
    }
}

@Suite struct StationSongsCallTest {
    static let answer = """
    {"subsonic-response":{"status":"ok","version":"1.16.1","type":"octo","openSubsonic":true,
     "stationSongs":{"id":"or1234","name":"Your Radio","entry":[
      {"id":"s1","title":"Nikes","artist":"Frank Ocean","duration":314},
      {"id":77,"title":"Ivy","artist":"Frank Ocean","duration":"249","isExternal":true}]}}}
    """

    @Test func theAnswerHasTheStationAndItsSongs() throws {
        let songs: StationSongs = try SubsonicClient.decode(Data(Self.answer.utf8), key: "stationSongs")
        #expect(songs.id == "or1234")
        #expect(songs.name == "Your Radio")
        #expect(songs.entry.map(\.id) == ["s1", "77"])
        #expect(songs.entry[1].duration == 249)
        #expect(songs.entry[1].isExternal)
    }

    @Test func aStationWithNothingMoreHasNoSongs() throws {
        let json = #"{"subsonic-response":{"status":"ok","version":"1.16.1","stationSongs":{"id":"or1","name":"Your Radio"}}}"#
        let songs: StationSongs = try SubsonicClient.decode(Data(json.utf8), key: "stationSongs")
        #expect(songs.entry.isEmpty)
    }

    @Test func theCallNamesTheStationAndEverySongAlreadyQueued() async throws {
        let server = FakeServer()
        server.enqueue(Self.answer)
        let songs = try await server.client().stationSongs(id: "or1234", after: ["s1", "s2", "s3"])
        #expect(songs.entry.count == 2)
        let request = try #require(server.requests.first)
        #expect(request.method == "GET")
        #expect(request.endpoint == "getStationSongs")
        #expect(request.query["id"] == "or1234")
        #expect(request.query["count"] == "\(stationBatch)")
        #expect(request.values("after") == ["s1", "s2", "s3"])
    }

    @Test func aStationGoneFromTheServerIsNotFound() async {
        let server = FakeServer()
        server.error(70, "Station not found")
        await #expect(throws: OctoError.self) { try await server.client().stationSongs(id: "or1", after: []) }
    }

    @Test func theRulesMatchTheOtherApps() {
        #expect(stationTopUpAt == 20)
        #expect(stationBatch == 25)
        #expect(stationAfter == 100)
    }
}

@Suite struct StationTapTest {
    @Test func anAddedInternetStationPlaysItsStream() {
        let added = Station(id: "7", name: "KEXP", artwork: nil, streamUrl: " https://kexp.example/live ")
        #expect(stationTap(added) == .playStream("https://kexp.example/live"))
        #expect(!stationHasPlayButton(added))
    }

    @Test func homeShowsOctosStationsAsRadioAndAddedStationsAsLiveRadio() {
        let radio = Station(id: "or1234", name: "Your Radio", artwork: nil)
        let kexp = Station(id: "7", name: "KEXP", artwork: nil, streamUrl: "https://kexp.example/live")
        let discovery = Station(id: "or5678", name: "Discovery Radio", artwork: nil)
        #expect(octoRadio([radio, kexp, discovery]) == [radio, discovery])
        #expect(internetRadio([radio, kexp, discovery]) == [kexp])
    }

    @Test func octosStationsAndMadeForYouListsOpenTheirSongs() {
        let mix = Station(id: "or1234", name: "Your Radio", artwork: nil)
        let deepCuts = Station(id: "og5678", name: "Deep Cuts", artwork: nil, songCount: 40)
        let blank = Station(id: "or9", name: "Blank", artwork: nil, streamUrl: "  ")
        for station in [mix, deepCuts, blank] {
            #expect(stationTap(station) == .openList)
            #expect(stationHasPlayButton(station))
        }
    }
}
