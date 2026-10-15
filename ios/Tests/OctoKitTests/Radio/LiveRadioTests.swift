import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import OctoKit

@Suite struct LiveRadioTests {
    func station(_ uuid: String, _ name: String? = nil, distance: Double? = nil, clicks: Int = 0, codec: String = "MP3",
                 hls: Bool = false, url: String? = nil) -> LiveStation {
        LiveStation(uuid: uuid, name: name ?? uuid, streamUrl: url ?? "https://radio.example/\(uuid)", codec: codec, hls: hls,
                    distanceMeters: distance, clicks: clicks)
    }

    let austin = LivePlace(latitude: 30.26715, longitude: -97.74306, label: "Austin", state: "TX", countryCode: "US")
    let base = URL(string: "https://de1.api.radio-browser.info")!

    // MARK: Picking a server

    @Test func aServerIsPickedFromTheOnesFound() {
        var random = SystemRandomNumberGenerator()
        let servers = ["at1.api.radio-browser.info", "nl1.api.radio-browser.info"]
        for _ in 0..<20 { #expect(servers.contains(pickRadioServer(servers, random: &random))) }
    }

    @Test func withNoServerFoundTheFallbackIsUsed() {
        var random = SystemRandomNumberGenerator()
        #expect(pickRadioServer([], random: &random) == "de1.api.radio-browser.info")
        #expect(pickRadioServer(["", "  "], random: &random) == "de1.api.radio-browser.info")
    }

    @Test func theServersListNamesOnlyTheCatalogsOwnServersOnce() {
        let json = #"[{"ip":"1.2.3.4","name":"de1.api.radio-browser.info"},{"name":"DE1.api.radio-browser.info"},{"name":"evil.example"},{}]"#
        #expect(radioServerNames(Data(json.utf8)) == ["de1.api.radio-browser.info"])
        #expect(radioServerNames(Data("nope".utf8)).isEmpty)
    }

    @Test func aServerNameStandsForItsHttpsAddress() {
        #expect(radioServerBase("de1.api.radio-browser.info")?.absoluteString == "https://de1.api.radio-browser.info")
        #expect(radioServerBase("http://localhost:8080/")?.absoluteString == "http://localhost:8080")
    }

    @Test func withNoServersFoundTheFallbackIsAsked() async throws {
        let asked = LockedBox<[String]>([])
        let browser = RadioBrowser(userAgent: "Octo/1.0 (iPhone)", servers: { [] }, fetch: { request in
            asked.update { $0.append(request.url?.host ?? "") }
            return (Data("[]".utf8), 200)
        })
        _ = try await browser.near(austin, radiusMeters: 40_000)
        #expect(asked.value.allSatisfy { $0 == "de1.api.radio-browser.info" })
    }

    // MARK: Searches

    @Test func theNearbySearchSendsTheRoundedPlaceOnly() throws {
        let url = try #require(radioNearbyUrl(base, place: austin, radiusMeters: 40_233.6))
        #expect(url.absoluteString == "https://de1.api.radio-browser.info/json/stations/search?geo_lat=30.27&geo_long=-97.74"
                + "&geo_distance=40234&hidebroken=true&order=clickcount&reverse=true&limit=200")
    }

    @Test func theRegionalSearchUsesTheCountryAndTheStatesFullName() throws {
        let url = try #require(radioRegionalUrl(base, place: austin))
        #expect(url.absoluteString == "https://de1.api.radio-browser.info/json/stations/search?countrycode=US&state=Texas"
                + "&hidebroken=true&order=clickcount&reverse=true&limit=200")
        var abroad = austin
        abroad.countryCode = "de"
        abroad.state = "Nordrhein-Westfalen"
        #expect(radioRegionalUrl(base, place: abroad)?.absoluteString.contains("countrycode=DE&state=Nordrhein-Westfalen") == true)
        abroad.state = ""
        #expect(radioRegionalUrl(base, place: abroad)?.absoluteString.contains("countrycode=DE&hidebroken") == true)
        abroad.countryCode = ""
        #expect(radioRegionalUrl(base, place: abroad) == nil)
    }

    @Test func aStartIsToldByTheStationsId() {
        #expect(radioClickUrl(base, uuid: "96 2a")?.absoluteString == "https://de1.api.radio-browser.info/json/url/96%202a")
    }

    @Test func theSearchesAndTheStartNameTheApp() async throws {
        let agents = LockedBox<[String]>([])
        let browser = RadioBrowser(userAgent: "Octo/1.7 (iPhone)", servers: { ["at1.api.radio-browser.info"] }, fetch: { request in
            agents.update { $0.append(request.value(forHTTPHeaderField: "User-Agent") ?? "") }
            return (Data("[]".utf8), 200)
        })
        _ = try await browser.near(austin, radiusMeters: 40_000)
        await browser.started("abc")
        #expect(agents.value == ["Octo/1.7 (iPhone)", "Octo/1.7 (iPhone)", "Octo/1.7 (iPhone)"])
    }

    // MARK: Rows, merging and order

    @Test func catalogRowsBecomeStations() throws {
        let json = #"""
        [{"stationuuid":"a","name":" KUT ","url":"http://x/a.pls","url_resolved":"https://x/a.mp3","favicon":"https://x/a.png",
          "codec":"MP3","bitrate":128,"hls":0,"country":"The United States Of America","countrycode":"us","state":"Texas",
          "tags":"news, npr,news,,talk","geo_lat":30.28,"geo_long":-97.73,"geo_distance":1234.5,"clickcount":77,"lastcheckok":1},
         {"stationuuid":"b","name":"","url":"https://x/b","url_resolved":"","codec":"AAC","bitrate":"64","hls":1,"geo_lat":null,
          "clickcount":3,"lastcheckok":1},
         {"stationuuid":"c","name":"Broken","url":"https://x/c","lastcheckok":0},
         {"stationuuid":"","name":"No id","url":"https://x/d"}]
        """#
        let found = try catalogStations(Data(json.utf8), from: austin.rounded)
        #expect(found.count == 2)
        let a = found[0]
        #expect(a.name == "KUT" && a.streamUrl == "https://x/a.mp3" && a.countryCode == "US" && a.tags == ["news", "npr", "talk"])
        #expect(a.distanceMeters == 1234.5 && a.clicks == 77 && a.formatLine == "MP3 128k" && !a.hls)
        let b = found[1]
        #expect(b.name == "https://x/b" && b.streamUrl == "https://x/b" && b.bitrate == 64 && b.hls && b.distanceMeters == nil)
        #expect(a.homepage == "" && b.homepage == "")
    }

    @Test func aStationsWebsiteIsKeptOnlyWhenItIsAWebAddress() throws {
        let json = #"""
        [{"stationuuid":"a","url":"https://x/a","homepage":" https://kut.org/ "},
         {"stationuuid":"b","url":"https://x/b","homepage":"HTTP://town.example"},
         {"stationuuid":"c","url":"https://x/c","homepage":"kut.org"},
         {"stationuuid":"d","url":"https://x/d","homepage":"javascript:alert(1)"}]
        """#
        let found = try catalogStations(Data(json.utf8), from: nil)
        #expect(found.map(\.homepage) == ["https://kut.org/", "HTTP://town.example", "", ""])
    }

    @Test func aKeptStationsWebsiteIsKeptAndOldOnesReadWithout() {
        var a = station("a")
        a.homepage = "https://kut.org/"
        let kept = KeptStations().keep(a)
        #expect(KeptStations.decoded(kept.encoded()).stations.first?.homepage == "https://kut.org/")
        let old = KeptStations.decoded(#"{"stations":[{"uuid":"a","name":"A","streamUrl":"https://x/a","favicon":"","tags":[]}]}"#)
        #expect(old.stations.first?.homepage == "")
    }

    @Test func aNearbyRowWithoutItsDistanceGetsOne() throws {
        let json = #"[{"stationuuid":"a","url":"https://x/a","geo_lat":30.27,"geo_long":-97.84}]"#
        let found = try catalogStations(Data(json.utf8), from: austin.rounded)
        let meters = try #require(found.first?.distanceMeters)
        #expect(abs(meters - 9_610) < 50)
    }

    @Test func mergingKeepsEachStationOnceNearestFirst() {
        let near = [station("far", distance: 9_000), station("near", distance: 100), station("same", distance: 500)]
        let regional = [station("same", distance: nil, clicks: 999), station("unplaced", clicks: 5),
                        station("elsewhere", distance: 900_000), station("inside", distance: 2_000)]
        let merged = sortStations(mergeStations(near: near, regional: regional), by: .distance)
        #expect(merged.map(\.uuid) == ["near", "same", "far", "unplaced"])
    }

    @Test func regionalRowsTheCatalogPlacesAreDropped() throws {
        let json = #"""
        [{"stationuuid":"placed","url":"https://x/a","geo_lat":31.76,"geo_long":-106.49},
         {"stationuuid":"unplaced","url":"https://x/b","geo_lat":null,"geo_long":null},
         {"stationuuid":"zero","url":"https://x/c","geo_lat":0,"geo_long":0},
         {"stationuuid":"offEarth","url":"https://x/d","geo_lat":95,"geo_long":10}]
        """#
        let found = try regionalStations(Data(json.utf8))
        #expect(found.map(\.uuid) == ["unplaced", "zero", "offEarth"])
        #expect(found.allSatisfy { $0.distanceMeters == nil })
    }

    @Test func numbersFromTheCatalogNeverTrap() throws {
        let json = #"""
        [{"stationuuid":"a","url":"https://x/a","bitrate":1e20,"clickcount":-1e300,"hls":1e19,"lastcheckok":1e20,
          "geo_distance":1e300,"geo_lat":"Infinity","geo_long":"nan"},
         {"stationuuid":"b","url":"https://x/b","bitrate":"99999999999999999999","geo_distance":"Infinity"},
         {"stationuuid":"c","url":"https://x/c","geo_distance":-5}]
        """#
        let found = try catalogStations(Data(json.utf8), from: austin.rounded)
        #expect(found.count == 3)
        #expect(found[0].bitrate == 1_000_000_000 && found[0].clicks == -1_000_000_000 && !found[0].hls)
        #expect(found.allSatisfy { $0.distanceMeters == nil })
        #expect(found[1].bitrate == 0)
        #expect(liveDistanceText(.infinity, miles: true) == "")
        #expect(liveDistanceText(1e300, miles: false) == "")
        #expect(liveDistanceText(earthHalfCircumferenceMeters, miles: false) == "20040 km")
        #expect(clampedWhole(.nan) == 0 && clampedWhole(1e30) == 1_000_000_000)
        #expect(liveCacheKey(austin, radiusMeters: .infinity).contains(",0,"))
    }

    @Test func unplacedStationsComeLastMostPlayedFirst() {
        let sorted = sortStations([station("u1", clicks: 1), station("p", distance: 5), station("u2", clicks: 9),
                                   station("u3", "a", clicks: 9)], by: .distance)
        #expect(sorted.map(\.uuid) == ["p", "u3", "u2", "u1"])
    }

    @Test func popularityOrdersByStartsThenName() {
        let sorted = sortStations([station("x", "Beta", distance: 1, clicks: 5), station("y", "alpha", distance: 900, clicks: 5),
                                   station("z", distance: 2, clicks: 50)], by: .popular)
        #expect(sorted.map(\.uuid) == ["z", "y", "x"])
    }

    // MARK: Keeping answers

    @Test func answersAreKeptByTheRoundedPlaceAndRadius() async throws {
        let calls = LockedBox(0)
        let clock = LockedBox<Int64>(1_000_000)
        let browser = RadioBrowser(userAgent: "Octo", servers: { ["at1.api.radio-browser.info"] }, fetch: { _ in
            calls.update { $0 += 1 }
            return (Data(#"[{"stationuuid":"a","url":"https://x/a","codec":"MP3","geo_distance":10}]"#.utf8), 200)
        }, now: { clock.value })
        _ = try await browser.near(austin, radiusMeters: 40_000)
        #expect(calls.value == 2)
        var nearby = austin
        nearby.latitude += 0.001
        nearby.longitude -= 0.001
        _ = try await browser.near(nearby, radiusMeters: 40_000)
        #expect(calls.value == 2)
        _ = try await browser.near(austin, radiusMeters: 80_000)
        #expect(calls.value == 4)
        clock.update { $0 += liveCacheMs }
        _ = try await browser.near(austin, radiusMeters: 40_000)
        #expect(calls.value == 6)
    }

    @Test func theCacheKeyIsTheRoundedPlace() {
        var a = austin
        a.latitude = 30.2649
        #expect(liveCacheKey(a, radiusMeters: 40_000.2) == "30.26,-97.74,40000,TX,US")
        a.latitude = 30.2651
        #expect(liveCacheKey(a, radiusMeters: 40_000) == "30.27,-97.74,40000,TX,US")
    }

    @Test func aFailedRegionalSearchIsNotKept() async throws {
        let calls = LockedBox<[String]>([])
        let regionalFails = LockedBox(true)
        let browser = RadioBrowser(userAgent: "Octo", servers: { ["at1.api.radio-browser.info"] }, fetch: { request in
            let regional = request.url?.query?.contains("countrycode") == true
            calls.update { $0.append(regional ? "regional" : "near") }
            if regional && regionalFails.value { return (Data(), 500) }
            if regional { return (Data(#"[{"stationuuid":"r","url":"https://x/r","codec":"MP3"}]"#.utf8), 200) }
            return (Data(#"[{"stationuuid":"n","url":"https://x/n","codec":"MP3","geo_distance":10}]"#.utf8), 200)
        })
        // The nearby stations still show, but the answer is not kept.
        #expect(try await browser.near(austin, radiusMeters: 40_000).map(\.uuid) == ["n"])
        regionalFails.update { $0 = false }
        #expect(try await browser.near(austin, radiusMeters: 40_000).map(\.uuid) == ["n", "r"])
        _ = try await browser.near(austin, radiusMeters: 40_000)
        #expect(calls.value == ["near", "regional", "near", "regional"])
    }

    @Test func anUnreadableAnswerLetsTheServerGo() async throws {
        let picks = LockedBox(0)
        let bad = LockedBox(true)
        let browser = RadioBrowser(userAgent: "Octo", servers: {
            picks.update { $0 += 1 }
            return ["at1.api.radio-browser.info"]
        }, fetch: { _ in (Data((bad.value ? "<html>" : "[]").utf8), 200) })
        await #expect(throws: RadioBrowserError.self) { try await browser.near(austin, radiusMeters: 40_000) }
        bad.update { $0 = false }
        _ = try await browser.near(austin, radiusMeters: 40_000)
        #expect(picks.value == 2)
    }

    @Test func aFailedSearchIsNotKept() async throws {
        let fail = LockedBox(true)
        let browser = RadioBrowser(userAgent: "Octo", servers: { ["at1.api.radio-browser.info"] }, fetch: { _ in
            if fail.value { return (Data(), 503) }
            return (Data("[]".utf8), 200)
        })
        await #expect(throws: RadioBrowserError.self) { try await browser.near(austin, radiusMeters: 40_000) }
        fail.update { $0 = false }
        #expect(try await browser.near(austin, radiusMeters: 40_000).isEmpty)
    }

    // MARK: What plays

    @Test func onlyMp3AndAacPlay() {
        let all = [station("mp3"), station("aac", codec: "AAC"), station("aacp", codec: "aac+"), station("ogg", codec: "OGG"),
                   station("flac", codec: "FLAC"), station("unknown", codec: "UNKNOWN"), station("video", codec: "AAC,H.264")]
        let (shown, hidden) = playableStations(all, hlsPlays: true)
        #expect(shown.map(\.uuid) == ["mp3", "aac", "aacp"])
        #expect(hidden == 4)
    }

    @Test func hlsStationsPlayOnlyWhereHlsIsRead() {
        let all = [station("flag", codec: "AAC", hls: true), station("path", url: "https://x/live/index.m3u8?t=1"), station("plain")]
        #expect(playableStations(all, hlsPlays: false).stations.map(\.uuid) == ["plain"])
        #expect(playableStations(all, hlsPlays: true).hidden == 0)
    }

    @Test func theHiddenNoteCountsThem() {
        #expect(hiddenStationsNote(0) == nil)
        #expect(hiddenStationsNote(1) == "1 station here uses a format this app cannot play")
        #expect(hiddenStationsNote(4) == "4 stations here use a format this app cannot play")
    }

    // MARK: Places and radius

    @Test func onlyTwoDecimalsLeaveThePhone() {
        let at = austin.rounded
        #expect(at.latitude == 30.27 && at.longitude == -97.74)
    }

    @Test func theRadiusIsInTheListenersUnits() {
        #expect(LiveRadius.choices(miles: true).map(\.label) == ["10 mi", "25 mi", "50 mi", "100 mi"])
        #expect(LiveRadius.choices(miles: false).map(\.label) == ["15 km", "40 km", "80 km", "160 km"])
        #expect(LiveRadius.at(9, miles: true).amount == 25)
        #expect(abs(LiveRadius.at(1, miles: true).meters - 40_233.6) < 0.01)
        #expect(liveDistanceText(3_862, miles: true) == "2.4 mi")
        #expect(liveDistanceText(25_000, miles: false) == "25 km")
    }

    @Test func searchWordsAboutRadioAreSeen() {
        #expect(looksLikeRadioSearch("jazz radio"))
        #expect(looksLikeRadioSearch("KUT FM"))
        #expect(looksLikeRadioSearch("news stations"))
        #expect(!looksLikeRadioSearch("Radiohead"))
        #expect(!looksLikeRadioSearch("fmlyhood"))
    }

    // MARK: Kept stations

    @Test func keptStationsRoundTrip() {
        var a = station("a", distance: 12, clicks: 4)
        a.tags = ["jazz"]
        a.favicon = "https://x/a.png"
        a.state = "Texas"
        let kept = KeptStations().keep(a).keep(station("b")).keep(station("a", "A again"))
        #expect(kept.stations.map(\.uuid) == ["a", "b"])
        #expect(kept.stations[0].name == "A again" && kept.stations[0].distanceMeters == nil)
        #expect(KeptStations.decoded(kept.encoded()) == kept)
        #expect(KeptStations.decoded("not json") == KeptStations())
        #expect(KeptStations.decoded(nil) == KeptStations())
        #expect(kept.drop("a").stations.map(\.uuid) == ["b"])
        #expect(kept.has("b") && !kept.has("z"))
    }

    @Test func keptStationsReadWhatTheOtherAppsWrite() {
        // A station written by another app may leave out fields at their defaults.
        let kept = KeptStations.decoded(#"{"stations":[{"uuid":"a","name":"A","streamUrl":"https://x/a","extra":1}]}"#)
        #expect(kept.stations == [LiveStation(uuid: "a", name: "A", streamUrl: "https://x/a")])
    }

    @Test func keptStationsGoThroughABackupAndBack() {
        var backup = Backup()
        var a = station("a", codec: "AAC+")
        a.tags = ["rock", "indie"]
        a.bitrate = 96
        a.hls = true
        backup.keptStations = [a, station("b")]
        #expect(BackupFile.encode(backup).contains(#""keptStations": ["#))
        guard case .read(let back) = BackupFile.decode(BackupFile.encode(backup)) else {
            Issue.record("not read back")
            return
        }
        #expect(back.keptStations == backup.keptStations)
        #expect(BackupPlanner.describe(back).contains("2 kept radio stations"))
        guard case .read(let none) = BackupFile.decode(#"{"kind":"octo-settings"}"#) else { return }
        #expect(none.keptStations.isEmpty)
        #expect(BackupFile.decode(#"{"kind":"octo-settings","keptStations":[{"name":"no id"}]}"#) == .notABackup)
    }
}

/// A value tests share with the closures they hand out.
final class LockedBox<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: T

    init(_ value: T) { stored = value }

    var value: T { lock.withLock { stored } }

    func update(_ change: (inout T) -> Void) { lock.withLock { change(&stored) } }
}
