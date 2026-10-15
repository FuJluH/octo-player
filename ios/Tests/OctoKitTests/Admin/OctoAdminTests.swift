import Foundation
import Testing
@testable import OctoKit

@Suite struct OctoAdminSignInTests {
    let home: Set<String> = [rootKey(URL(string: "http://192.168.50.21:5274/")!)!]

    @Test func signsOnlyForAnAddressTheAppTrusts() {
        #expect(mayCarrySignIn(URL(string: "http://192.168.50.21:5274/api/admin/status")!, trusted: home))
        #expect(mayCarrySignIn(URL(string: "http://192.168.50.21:5274/api/admin/lastfm/radio?user=me")!, trusted: home))
    }

    @Test func neverSignsForAnotherHostOrPort() {
        #expect(!mayCarrySignIn(URL(string: "http://10.0.0.5:5274/api/admin/status")!, trusted: home))
        #expect(!mayCarrySignIn(URL(string: "http://192.168.50.21:5275/api/admin/status")!, trusted: home))
        #expect(!mayCarrySignIn(URL(string: "https://192.168.50.21:5274/api/admin/status")!, trusted: home))
        #expect(!mayCarrySignIn(URL(string: "http://192.168.50.21:5274/api/admin/status")!, trusted: []))
    }

    @Test func aDefaultPortIsTheSameRootWrittenOrNot() {
        #expect(rootKey(URL(string: "https://octo.example.com/music")!) == rootKey(URL(string: "https://OCTO.example.com:443/")!))
        #expect(adminRoot(URL(string: "https://octo.example.com:8443/music/rest?x=1")!)?.absoluteString == "https://octo.example.com:8443/")
    }
}

@Suite struct AdminFormatTests {
    let utc = TimeZone(identifier: "UTC")!
    let english = Locale(identifier: "en")
    let now = epochMs("2026-09-26T15:00:00Z")!

    func ago(_ text: String) -> String? { adminAgo(text, nowMs: now, zone: utc, locale: english) }

    @Test func readsTimesWithAndWithoutAZone() {
        let two = epochMs("2026-09-26T14:00:00Z")
        #expect(two == 1_790_431_200_000)
        #expect(epochMs("2026-09-26T16:00:00+02:00") == two)
        #expect(epochMs("2026-09-26T14:00:00.1234567Z") == two.map { $0 + 123 })
        #expect(epochMs("2026-09-26T14:00:00") == two)
        #expect(epochMs(nil) == nil)
        #expect(epochMs("") == nil)
        #expect(epochMs("yesterday") == nil)
        #expect(epochMs("2026-02-30T14:00:00Z") == nil)
    }

    @Test func saysRecentTimesInMinutes() {
        #expect(ago("2026-09-26T14:59:40Z") == "Just now")
        #expect(ago("2026-09-26T14:55:00Z") == "5 min ago")
        #expect(ago("2026-09-26T14:01:00Z") == "59 min ago")
        // A clock a little ahead is still "just now".
        #expect(ago("2026-09-26T15:02:00Z") == "Just now")
    }

    @Test func saysEarlierTodayInHours() {
        #expect(ago("2026-09-26T14:00:00Z") == "1 hr ago")
        #expect(ago("2026-09-26T01:00:00Z") == "14 hr ago")
    }

    @Test func lateLastNightIsHoursAgo() {
        let morning = epochMs("2026-09-26T02:00:00Z")!
        #expect(adminAgo(thenMs: epochMs("2026-09-25T23:00:00Z")!, nowMs: morning, zone: utc, locale: english) == "3 hr ago")
    }

    @Test func thenYesterdayDaysAndDates() {
        #expect(ago("2026-09-25T08:00:00Z") == "Yesterday")
        #expect(ago("2026-09-23T15:00:00Z") == "3 days ago")
        #expect(ago("2026-09-12T10:00:00Z") == "12 Sep")
        #expect(ago("2025-12-30T10:00:00Z") == "30 Dec 2025")
    }

    @Test func anUnreadableTimeSaysNothing() {
        #expect(adminAgo(nil, nowMs: now) == nil)
        #expect(adminAgo("soon", nowMs: now) == nil)
    }

    @Test func learningCountsUpToWhatItNeeds() {
        #expect(learningLine(RadioLearning(plays: 40, needed: 50)) == "Learning your taste: 40 of 50 plays")
        #expect(learningLine(RadioLearning(plays: 0, needed: 1)) == "Learning your taste: 0 of 1 play")
        #expect(learningLine(RadioLearning(plays: 1_234, needed: 5_000)) == "Learning your taste: 1,234 of 5,000 plays")
    }

    @Test func learnedOnceItHasEnough() {
        #expect(learningLine(RadioLearning(plays: 212, needed: 50)) == "Learned from 212 plays")
        #expect(learningLine(RadioLearning(plays: 50, needed: 50)) == "Learned from 50 plays")
        #expect(learningLine(RadioLearning(plays: 1, needed: 0)) == "Learned from 1 play")
    }

    @Test func healthPicksItsDot() {
        #expect(healthDot(AdminHealth(ok: true)) == .ok)
        #expect(healthDot(AdminHealth(ok: true, warning: true)) == .warning)
        #expect(healthDot(AdminHealth(ok: false)) == .down)
        #expect(healthDot(AdminHealth(ok: false, warning: true)) == .down)
        // Something never set up is not a failure.
        #expect(healthDot(AdminHealth(ok: false, configured: false)) == .notSetUp)
    }

    @Test func servicesHaveFriendlyNames() {
        #expect(serviceName("slskd") == "Soulseek")
        #expect(serviceName("ytDlpShim") == "Streaming helper")
        #expect(serviceName("lastfm") == "Last.fm")
        #expect(serviceName("somethingNew") == "somethingNew")
    }

    @Test func refreshErrorsStayReadable() {
        #expect(refreshProblem(nil) == nil)
        #expect(refreshProblem("  ") == nil)
        #expect(refreshProblem("No plays yet") == "The last refresh did not finish: No plays yet")
        #expect(refreshProblem(#"{"error":"boom"}"#) == "The last refresh did not finish.")
        #expect(refreshProblem("System.Net.HttpRequestException: timed out") == "The last refresh did not finish.")
        #expect(refreshProblem("failed\n   at Octo.Radio.Refresh()") == "The last refresh did not finish.")
    }

    @Test func libraryNamesEachProblem() {
        #expect(libraryProblems(LibraryStatus(writable: true, rescanAuthenticated: true)).isEmpty)
        #expect(libraryProblems(LibraryStatus(writable: false, rescanAuthenticated: false))
            == ["Octo cannot write to this folder", "Octo cannot ask Navidrome to rescan"])
    }

    @Test func downloadLineSkipsWhatIsMissing() {
        #expect(downloadLine(DownloadRecord(artist: "Radiohead", format: "flac")) == "Radiohead · FLAC")
        #expect(downloadLine(DownloadRecord(artist: "Radiohead")) == "Radiohead")
        #expect(downloadLine(DownloadRecord(format: "mp3")) == "MP3")
    }

    @Test func theStatusKeepsTheServicesInTheOrderWritten() throws {
        let body = #"{"octo":{"ok":true,"detail":"Running"},"services":{"slskd":{"ok":false,"detail":"No answer"},"navidrome":{"ok":true,"detail":"0.58.0"},"lidarr":{"configured":false},"lastfm":{"ok":true,"warning":true,"detail":"Key \"old\""}},"extra":[1,{"a":"}"}]}"#
        let status = try AdminStatus.read(Data(body.utf8))
        #expect(status.octo == AdminHealth(ok: true, detail: "Running"))
        #expect(status.services.map(\.key) == ["slskd", "navidrome", "lidarr", "lastfm"])
        #expect(status.services[2].health == AdminHealth(configured: false))
        #expect(status.services[3].health.detail == #"Key "old""#)
    }

    @Test func missingAndNullFieldsFallBackToDefaults() throws {
        let status = try AdminStatus.read(Data(#"{"octo":null}"#.utf8))
        #expect(status == AdminStatus())
        let radio = try RadioState.read(Data(#"{"enabled":true,"learning":{"plays":null},"stations":[{"name":"Mix"}]}"#.utf8))
        #expect(radio.enabled)
        #expect(radio.learning == RadioLearning())
        #expect(radio.stations == [AdminStation(name: "Mix")])
        #expect(try LibraryStatus.read(Data("{}".utf8)) == LibraryStatus())
        #expect(try DownloadRecord.list(Data(#"{"downloads":[{"title":"Angel","sizeBytes":12}]}"#.utf8)) == [DownloadRecord(title: "Angel", sizeBytes: 12)])
    }
}

final class AdminStore: AdminAddressStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String]
    init(_ values: [String: String] = [:]) { self.values = values }
    func string(_ key: String) -> String? { lock.withLock { values[key] } }
    func set(_ value: String?, _ key: String) { lock.withLock { values[key] = value } }
    var all: [String: String] { lock.withLock { values } }
}

/// Octo's admin pages as a server answers them: the status page, the sections, and a refresh.
func adminRoutes(_ server: FakeServer, statusOk: Bool = true, refreshing: @escaping @Sendable () -> Bool = { false }) {
    server.route { request in
        func json(_ text: String, _ status: Int = 200) -> FakeServer.Reply { FakeServer.Reply(status: status, body: Data(text.utf8)) }
        switch request.path {
        case "/api/admin/status":
            return statusOk ? json(#"{"octo":{"ok":true},"services":{"navidrome":{"ok":true}}}"#) : json("not here", 404)
        case "/api/admin/downloads": return json(#"{"downloads":[{"title":"Angel","artist":"Massive Attack","format":"flac"}]}"#)
        case "/api/admin/lastfm/radio":
            return json(#"{"enabled":true,"learning":{"plays":10,"needed":50,"refreshing":\#(refreshing())},"stations":[{"name":"Mix","trackCount":25}]}"#)
        case "/api/admin/library-status": return json(#"{"effectiveDownloadPath":"/music","writable":true,"rescanAuthenticated":true}"#)
        case "/api/admin/lastfm/radio/refresh": return json("{}")
        case "/rest/getInternetRadioStations": return nil
        default: return json("missing", 404)
        }
    }
}

@MainActor
@Suite struct OctoAdminModelTests {
    let server = FakeServer()

    func signIn(_ server: FakeServer, kept: Int = 1, id: String = "winters@home") -> AdminSignIn {
        AdminSignIn(server: id, client: server.client(), primary: server.base, keptServers: kept)
    }

    @Test func findsThePagesAtTheAddressInUseAndSignsCallsThere() async {
        adminRoutes(server)
        let store = AdminStore()
        let signIn = signIn(server)
        let model = OctoAdminModel(admin: OctoAdmin(store: store), signIn: { signIn })
        model.open()
        #expect(model.place == .looking)
        #expect(await until("found") { model.downloads.value != nil && model.library.value != nil && model.radio.value != nil && model.status.value != nil })
        #expect(model.place == .found(URL(string: "https://\(server.host)/")!))
        #expect(model.status.value?.services.map(\.key) == ["navidrome"])
        #expect(model.radio.value?.stations.first?.trackCount == 25)
        #expect(store.all == ["address@winters@home": "https://\(server.host)/"])
        let probe = server.requests.first { $0.path == "/api/admin/status" && $0.query["u"] == nil }
        #expect(probe != nil)
        let radio = server.requests.first { $0.path == "/api/admin/lastfm/radio" }
        #expect(radio?.query["user"] == "winters")
        #expect(radio?.query["u"] == "winters")
        #expect(radio?.query["t"] != nil)
        #expect(radio?.query["f"] == nil)
        #expect(model.pageUrl?.absoluteString == "https://\(server.host)/admin/")
    }

    @Test func awayWhenNothingAnswers() async {
        adminRoutes(server, statusOk: false)
        let signIn = signIn(server)
        let model = OctoAdminModel(admin: OctoAdmin(store: AdminStore()), signIn: { signIn })
        model.open()
        #expect(await until("away") { model.place == .away })
        #expect(model.pageUrl == nil)
        let notSignedIn = OctoAdminModel(admin: OctoAdmin(store: AdminStore()), signIn: { nil })
        notSignedIn.open()
        #expect(await until("away") { notSignedIn.place == .away })
    }

    @Test func aSavedAddressFromElsewhereIsTriedButNeverSentTheSignIn() async {
        adminRoutes(server, statusOk: false)
        let elsewhere = FakeServer()
        adminRoutes(elsewhere)
        let store = AdminStore(["address": elsewhere.base.absoluteString])
        let signIn = signIn(server)
        let model = OctoAdminModel(admin: OctoAdmin(store: store), signIn: { signIn })
        model.open()
        #expect(await until("found") { model.downloads.value != nil })
        #expect(model.place == .found(URL(string: "https://\(elsewhere.host)/")!))
        #expect(elsewhere.requests.allSatisfy { $0.query["u"] == nil && $0.query["t"] == nil })
        #expect(store.all == ["address@winters@home": "https://\(elsewhere.host)/"])
    }

    @Test func theOlderSingleAddressCountsOnlyWhileOneServerIsKept() async {
        adminRoutes(server, statusOk: false)
        let elsewhere = FakeServer()
        adminRoutes(elsewhere)
        let signIn = signIn(server, kept: 2)
        let model = OctoAdminModel(admin: OctoAdmin(store: AdminStore(["address": elsewhere.base.absoluteString])), signIn: { signIn })
        model.open()
        #expect(await until("away") { model.place == .away })
        #expect(elsewhere.requests.isEmpty)
    }

    @Test func theStationsAddressIsTriedLastAndTrustedWithTheSignIn() async {
        let home = FakeServer()
        adminRoutes(home)
        server.route { request in
            if request.endpoint == "getInternetRadioStations" {
                let body = FakeServer.okBody(#""internetRadioStations":{"internetRadioStation":[{"id":"1","name":"Mix","streamUrl":"https://\#(home.host)/radio/mix.mp3"}]}"#)
                return FakeServer.Reply(status: 200, body: Data(body.utf8))
            }
            return FakeServer.Reply(status: 404, body: Data())
        }
        let signIn = signIn(server)
        let model = OctoAdminModel(admin: OctoAdmin(store: AdminStore()), signIn: { signIn })
        model.open()
        #expect(await until("found") { model.library.value != nil })
        #expect(model.place == .found(URL(string: "https://\(home.host)/")!))
        #expect(home.requests.first { $0.path == "/api/admin/library-status" }?.query["u"] == "winters")
    }

    @Test func eachSectionFailsOnItsOwnWithoutSayingWhy() async {
        server.route { request in
            switch request.path {
            case "/api/admin/status": FakeServer.Reply(status: 200, body: Data(#"{"octo":{"ok":true}}"#.utf8))
            case "/api/admin/downloads": FakeServer.Reply(status: 403, body: Data())
            case "/api/admin/library-status": FakeServer.Reply(status: 200, body: Data("not json".utf8))
            default: FakeServer.Reply(status: 500, body: Data())
            }
        }
        let signIn = signIn(server)
        let model = OctoAdminModel(admin: OctoAdmin(store: AdminStore()), signIn: { signIn })
        model.open()
        // Every section checked below has settled, the status too, before any is looked at.
        #expect(await until("settled") {
            model.status != .loading && model.downloads != .loading && model.library != .loading && model.radio != .loading
        })
        #expect(model.status.value != nil)
        #expect(model.downloads == .failed("Couldn't load recent downloads just now. Pull down to try again."))
        #expect(model.library == .failed("Couldn't load the library folder just now. Pull down to try again."))
        #expect(model.radio == .failed("Couldn't load the stations just now. Pull down to try again."))
    }

    @Test func aPullKeepsWhatIsShownAndEndsItsIndicator() async {
        adminRoutes(server)
        let signIn = signIn(server)
        let model = OctoAdminModel(admin: OctoAdmin(store: AdminStore()), signIn: { signIn })
        model.open()
        #expect(await until("found") { model.downloads.value != nil })
        let before = server.requestCount
        let pull = Task { await model.refresh() }
        await Task.yield()
        #expect(model.refreshing)
        #expect(model.downloads.value != nil)
        await pull.value
        #expect(!model.refreshing)
        #expect(server.requestCount > before)
    }

    @Test func aStationRefreshFollowsUpUntilOctoIsDone() async {
        let busy = Busy(3)
        adminRoutes(server, refreshing: { busy.next() })
        let signIn = signIn(server)
        let model = OctoAdminModel(admin: OctoAdmin(store: AdminStore()), signIn: { signIn }, refreshWaitMs: 20, refreshChecks: 5)
        model.open()
        #expect(await until("found") { model.radio.value != nil })
        let reads = server.requests.filter { $0.path == "/api/admin/lastfm/radio" }.count
        model.refreshStations()
        #expect(model.refreshingStations)
        #expect(await until("done") { !model.refreshingStations })
        let refresh = server.requests.first { $0.path == "/api/admin/lastfm/radio/refresh" }
        #expect(refresh?.method == "POST")
        #expect(refresh?.headers["X-Octo-Admin"] == "1")
        #expect(refresh?.text == #"{"user":"winters"}"#)
        #expect(server.requests.filter { $0.path == "/api/admin/lastfm/radio" }.count - reads == 2)
        #expect(model.stationsProblem == nil)
    }

    @Test func aRefreshOctoRefusesSaysSo() async {
        server.route { request in
            switch request.path {
            case "/api/admin/status": FakeServer.Reply(status: 200, body: Data(#"{"octo":{}}"#.utf8))
            case "/api/admin/lastfm/radio/refresh": FakeServer.Reply(status: 500, body: Data())
            default: FakeServer.Reply(status: 200, body: Data("{}".utf8))
            }
        }
        let signIn = signIn(server)
        let model = OctoAdminModel(admin: OctoAdmin(store: AdminStore()), signIn: { signIn }, refreshWaitMs: 20)
        model.open()
        #expect(await until("found") { model.radio.value != nil })
        model.refreshStations()
        #expect(await until("problem") { model.stationsProblem != nil })
        #expect(model.stationsProblem == "Octo could not start a refresh just now.")
        #expect(!model.refreshingStations)
    }
}

/// Answers true for the first reads after the refresh starts, then false.
final class Busy: @unchecked Sendable {
    private let lock = NSLock()
    private var reads = 0
    private let first: Int
    init(_ first: Int) { self.first = first }
    /// The first read is the screen's own, before any refresh.
    func next() -> Bool {
        lock.withLock {
            reads += 1
            return reads > 1 && reads < first
        }
    }
}
