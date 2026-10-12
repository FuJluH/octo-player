import Foundation
import Testing
@testable import OctoKit

/// Octo's imports as the apps call them: the overview, one list, the actions, files and text,
/// and the loopback page that catches Spotify's answer on the device.
@Suite struct ImportsTests {
    let server = FakeServer()
    var client: SubsonicClient { server.client(username: "winters", password: "secret") }

    @Test func readsTheOverview() async throws {
        server.ok(#""imports":{"spotify":{"configured":true,"connected":true,"account":"Brandon","redirectUri":"http://127.0.0.1/callback","octoFinishes":false,"endsUtc":"2027-04-01T00:00:00Z"},"reading":{"busy":true,"step":"Reading your liked songs"},"lists":[{"id":"spotify-liked","name":"Liked Songs","source":"spotifyLiked","total":10,"have":6,"missing":2,"queued":1,"downloading":1,"keepPlaylist":false,"getMissing":true,"canRefresh":true,"newField":1}],"trickle":{"state":"waitingForSoulseek","perHour":20,"queued":1,"current":{"key":"spotify:a","title":"Angel","artist":"Massive Attack","state":"downloading","progress":0.4}},"libraryProblem":null}"#)
        let overview = try await client.imports()
        #expect(server.requests[0].path == "/rest/getImports")
        #expect(overview.spotify.connected)
        #expect(overview.reading.step == "Reading your liked songs")
        let liked = try #require(overview.lists.first)
        #expect(liked.origin == .spotifyLiked)
        #expect(abs(liked.fraction - 0.6) < 0.001)
        #expect(liked.coming == 2)
        #expect(overview.trickle.stage == .waitingForSoulseek)
        #expect(overview.trickle.current?.stage == .downloading)
        #expect(overview.moving)
    }

    @Test func readsOneListsSongs() async throws {
        server.ok(#""import":{"list":{"id":"file-1","name":"Gym","source":"file"},"tracks":[{"key":"song:a","title":"A","artist":"B","state":"notFound","detail":"No source had it"},{"key":"song:c","title":"C","artist":"D","state":"have","libraryId":"nd-1"},{"key":"song:e","title":"E","artist":"F","state":"brandNew"}]}"#)
        let detail = try await client.importList("file-1")
        #expect(server.requests[0].query["id"] == "file-1")
        #expect(detail.tracks.map(\.stage) == [.notFound, .have, .unknown])
        #expect(detail.tracks[0].stage.askable)
        #expect(!detail.tracks[1].stage.askable)
    }

    @Test func anActionSendsItsParametersAndEverySongKey() async throws {
        server.ok(#""importAction":{"ok":true,"message":"Queued 2 songs.","count":2}"#)
        let result = try await client.importAction(ImportActions.songs, [("id", "file-1")], keys: ["song:a", "spotify:b"])
        let request = server.requests[0]
        #expect(request.path == "/rest/importAction")
        #expect(request.query["action"] == "songs")
        #expect(request.values("key") == ["song:a", "spotify:b"])
        #expect(result.ok)
        #expect(result.count == 2)
        server.ok(#""importAction":{"ok":false,"message":"Add your Spotify app's Client ID first."}"#)
        let refused = try await client.importAction(ImportActions.connect, [("redirect", "http://127.0.0.1:5000/callback")])
        #expect(!refused.ok)
        #expect(refused.url == nil)
    }

    @Test func listsAndApprovalReadWhateverTheServerSends() async throws {
        server.ok(#""imports":{"lists":[{"id":"t1","name":"Gym","source":"textList"},{"id":"f1","name":"Road","source":"file"}]}"#)
        #expect(try await client.imports().lists.map(\.origin) == [.unknown, .file])
        server.ok(#""imports":{"lists":[],"approval":{"needed":true,"by":"Sam","later":1}}"#)
        #expect(try await client.imports().approval == ImportApproval(needed: true, by: "Sam"))
        server.ok(#""imports":{"lists":[],"approval":{"needed":true}}"#)
        #expect(try await client.imports().approval == ImportApproval(needed: true, by: nil))
        server.ok(#""imports":{"lists":[],"approval":null}"#)
        #expect(try await client.imports().approval == nil)
    }

    @Test func readsTheServices() async throws {
        server.ok(#""importServices":{"services":[{"id":"spotify","name":"Spotify","exportUrl":"https://www.tunemymusic.com/transfer/spotify-to-file","tile":"Spotify"},{"id":"apple-music","name":"Apple Music","exportUrl":"https://www.tunemymusic.com/transfer/apple-music-to-file","tile":"Apple Music","later":1}],"spotifyConnect":true}"#)
        let services = try await client.importServices()
        #expect(services.spotifyConnect)
        #expect(services.services.map(\.id) == ["spotify", "apple-music"])
        #expect(services.services[1].tile == "Apple Music")
        server.ok(#""other":{}"#)
        #expect(try await client.importServices() == ImportServices())
    }

    @Test func aFileIsSentAsAMultipartPost() async throws {
        server.ok(#""importAction":{"ok":true,"message":"Read 2 lists, 340 songs.","count":2}"#)
        let result = try await client.importFile(name: "My Spotify Library.csv", bytes: Data("Track name,Artist name\nAngel,Massive Attack\n".utf8))
        let request = server.requests[0]
        #expect(request.method == "POST")
        #expect(request.path == "/rest/importFile")
        #expect(request.query["name"] == "My Spotify Library.csv")
        #expect(request.query["u"] == "winters")
        #expect(request.headers["Content-Type"]?.hasPrefix("multipart/form-data") == true)
        #expect(request.text.contains(#"name="file"; filename="My Spotify Library.csv""#))
        #expect(request.text.contains("Content-Type: text/csv"))
        #expect(request.text.contains("Angel,Massive Attack"))
        #expect(result.ok)
        #expect(result.message == "Read 2 lists, 340 songs.")
    }

    @Test func textIsSentInAFormBody() async throws {
        server.ok(#""importAction":{"ok":true,"message":"Read 1 list, 2 songs."}"#)
        _ = try await client.importText(name: "Pasted list", text: "Massive Attack - Angel\nMGMT - Kids")
        let request = server.requests[0]
        #expect(request.method == "POST")
        #expect(request.query["text"] == nil)
        var form: [String: String] = [:]
        for pair in request.text.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            form[parts[0]] = parts[1].removingPercentEncoding
        }
        #expect(form["name"] == "Pasted list")
        #expect(form["text"] == "Massive Attack - Angel\nMGMT - Kids")
    }

    @Test func theFileTypeFollowsTheName() {
        #expect(importFileType("a.CSV") == "text/csv")
        #expect(importFileType("a.txt") == "text/plain")
        #expect(importFileType("export.zip") == "application/zip")
        #expect(importFileType("x.json") == "application/json")
        #expect(importFileType("noending") == "application/octet-stream")
    }

    @Test func onlyAPortlessLoopbackRedirectCanBeCaughtOnTheDevice() {
        #expect(LoopbackRules.usable("http://127.0.0.1/callback")?.path == "/callback")
        #expect(LoopbackRules.usable("http://[::1]/cb")?.path == "/cb")
        #expect(LoopbackRules.usable("http://127.0.0.1")?.path == "/")
        #expect(LoopbackRules.usable("http://127.0.0.1:8888/callback") == nil)
        #expect(LoopbackRules.usable("https://octo.example.com/imports/spotify/callback") == nil)
        #expect(LoopbackRules.usable("http://localhost/callback") == nil)
        #expect(LoopbackRules.usable("not a uri") == nil)
    }

    @Test func theBrowsersReturnIsCaughtAndAnyOtherAddressIsNot() {
        #expect(LoopbackRules.parse("/callback?error=access_denied&state=s1", path: "/callback") == LoopbackAnswer(code: nil, state: "s1", error: "access_denied"))
        #expect(LoopbackRules.parse("/callback?code=AQB%2Fx&state=s1", path: "/callback") == LoopbackAnswer(code: "AQB/x", state: "s1", error: nil))
        #expect(LoopbackRules.parse("/callback", path: "/callback") == nil)
        #expect(LoopbackRules.parse("/other?code=x", path: "/callback") == nil)
        let (answer, page) = LoopbackRules.respond(to: "GET /callback?code=c&state=s HTTP/1.1", path: "/callback")
        #expect(answer?.code == "c")
        #expect(String(decoding: page, as: UTF8.self).contains("go back to Octo"))
        let (none, missing) = LoopbackRules.respond(to: "GET /favicon.ico HTTP/1.1", path: "/callback")
        #expect(none == nil)
        #expect(String(decoding: missing, as: UTF8.self).hasPrefix("HTTP/1.1 404"))
    }
}

/// A catcher for tests that answers as the browser would.
final class FakeCatcher: LoopbackCatcher, @unchecked Sendable {
    let redirectUri = "http://127.0.0.1:5123/callback"
    let answer: LoopbackAnswer?
    init(_ answer: LoopbackAnswer?) { self.answer = answer }
    func await(timeoutMs: Int) async -> LoopbackAnswer? { answer }
    func close() {}
}

final class Opened: @unchecked Sendable {
    private let lock = NSLock()
    private var urls: [String] = []
    func add(_ url: String) { lock.withLock { urls.append(url) } }
    var all: [String] { lock.withLock { urls } }
}

/// What both apps say about an import, and the Spotify sign-in they share.
@Suite struct SpotifyImportTests {
    let server = FakeServer()
    var client: SubsonicClient { server.client() }

    @Test func aListSaysWhereItIsFromAndWhatTheLibraryHas() {
        let list = ImportListSummary(source: "spotifyPlaylist", by: "Spotify", total: 10, have: 6, missing: 2, queued: 1, downloading: 1, notFound: 1)
        #expect(list.originLine == "Spotify · by Spotify")
        #expect(list.countsLine == "6 of 10 · 2 missing · 2 coming · 1 not found")
        #expect(ImportListSummary(source: "file").originLine == "File")
        #expect(trackStateLabel(.done) == "Fetched")
        #expect(ImportListSummary(name: "Road trip").removeLine == "Octo forgets Road trip. Songs already in your library stay.")
        #expect(ImportListSummary(name: "Road trip", getMissing: true, playlistId: "pl-1").removeLine
            == "Octo forgets Road trip and stops getting its missing songs. Songs already in your library stay, and so does its playlist.")
    }

    @Test func theTrickleSaysWhatItWaitsFor() {
        let utc = TimeZone(identifier: "UTC")!
        let running = TrickleStatus(state: "running", nextUtc: "2026-10-04T14:05:00Z", perHour: 20, queued: 3, done: 2)
        #expect(running.title == "Waiting for the next turn")
        #expect(running.line(zone: utc) == "Up to 20 songs an hour. Next song at 14:05. 3 waiting, 2 fetched.")
        #expect(TrickleStatus(state: "waitingForSoulseek").title == "Waiting for Soulseek")
        #expect(TrickleStatus(state: "off").line(zone: utc) == "Songs an hour is 0 on the server, so nothing starts.")
        #expect(TrickleStatus(state: "idle").title == "Nothing to fetch")
    }

    @Test func theAccountLineSaysWhatToDoFirst() {
        #expect(SpotifyStatus().line().contains("Client ID"))
        #expect(SpotifyStatus(configured: true, connected: true, account: "Brandon").title == "Connected as Brandon")
        #expect(SpotifyStatus(configured: true, connected: true, endsUtc: "2027-04-01T00:00:00Z").line(zone: TimeZone(identifier: "UTC")!).contains("2027"))
        #expect(SpotifyStatus(configured: true, problem: "Expired").title == "Sign in again")
    }

    @Test func theAppCatchesSpotifysAnswerOnTheDeviceAndTheServerFinishes() async throws {
        server.ok(#""imports":{"spotify":{"configured":true,"redirectUri":"http://127.0.0.1/callback"}}"#)
        server.ok(#""importAction":{"ok":true,"message":"Opened Spotify.","url":"https://accounts.spotify.com/authorize?x=1"}"#)
        server.ok(#""importAction":{"ok":true,"message":"Connected to Spotify as Brandon."}"#)
        let opened = Opened()
        let result = try await signInToSpotify(client, open: { opened.add($0) },
                                               catcher: { _, _ in FakeCatcher(LoopbackAnswer(code: "the-code", state: "s1", error: nil)) })
        #expect(opened.all == ["https://accounts.spotify.com/authorize?x=1"])
        #expect(result.ok)
        #expect(result.message == "Connected to Spotify as Brandon.")
        #expect(server.requests[1].query["redirect"] == "http://127.0.0.1:5123/callback")
        let finish = server.requests[2]
        #expect(finish.query["action"] == "finish")
        #expect(finish.query["code"] == "the-code")
        #expect(finish.query["state"] == "s1")
    }

    @Test func refusalsAndTimeoutsSaySo() async throws {
        for (answer, words) in [(LoopbackAnswer(code: nil, state: nil, error: "access_denied"), "Spotify says access was not allowed."),
                                (LoopbackAnswer(code: nil, state: nil, error: "boom"), "Spotify sent back an error: boom")] {
            server.ok(#""imports":{"spotify":{"configured":true,"redirectUri":"http://127.0.0.1/callback"}}"#)
            server.ok(#""importAction":{"ok":true,"url":"https://accounts.spotify.com/a"}"#)
            #expect(try await signInToSpotify(client, open: { _ in }, catcher: { _, _ in FakeCatcher(answer) }).message == words)
        }
        server.ok(#""imports":{"spotify":{"configured":true,"redirectUri":"http://127.0.0.1/callback"}}"#)
        server.ok(#""importAction":{"ok":true,"url":"https://accounts.spotify.com/a"}"#)
        #expect(try await signInToSpotify(client, open: { _ in }, catcher: { _, _ in FakeCatcher(nil) }).message
            == "Spotify did not answer. Connect again when you are ready.")
    }

    @Test func aServerWithoutAClientIdIsNotAskedToConnect() async throws {
        server.ok(#""imports":{"spotify":{"configured":false,"redirectUri":"http://127.0.0.1/callback"}}"#)
        let result = try await signInToSpotify(client, open: { _ in Issue.record("nothing to open") }, catcher: { _, _ in nil })
        #expect(!result.ok)
        #expect(result.message.contains("Client ID"))
        #expect(server.requestCount == 1)
    }

    @Test func aRedirectWithAPortCannotBeCaughtHere() async throws {
        server.ok(#""imports":{"spotify":{"configured":true,"redirectUri":"http://127.0.0.1:8888/callback"}}"#)
        let result = try await signInToSpotify(client, open: { _ in }, catcher: { _, _ in FakeCatcher(nil) })
        #expect(!result.ok)
        #expect(result.message.contains("http://127.0.0.1/callback"))
    }

    @Test func aServerOnHttpsFinishesItself() async throws {
        server.ok(#""imports":{"spotify":{"configured":true,"octoFinishes":true,"redirectUri":"https://octo.example.com/imports/spotify/callback"}}"#)
        server.ok(#""importAction":{"ok":true,"message":"Opened Spotify.","url":"https://accounts.spotify.com/authorize?y=2"}"#)
        let opened = Opened()
        let result = try await signInToSpotify(client, open: { opened.add($0) }, catcher: { _, _ in nil })
        #expect(result.ok)
        #expect(result.message == "Allow Octo in your browser. This page notices on its own when that is done.")
        #expect(opened.all == ["https://accounts.spotify.com/authorize?y=2"])
        #expect(server.requests[1].query["redirect"] == nil)
    }
}

/// "Get my music": which export pages open, the steps from a tile tapped to the lists read, and
/// what a family member whose downloads are approved first reads once their lists are in.
@MainActor
@Suite struct GetMyMusicTests {
    let spotify = ImportServiceLink(id: "spotify", name: "Spotify", exportUrl: "https://www.tunemymusic.com/transfer/spotify-to-file", tile: "Spotify")
    let apple = ImportServiceLink(id: "apple-music", name: "Apple Music", exportUrl: "https://www.tunemymusic.com/transfer/apple-music-to-file", tile: "Apple Music")

    @Test func onlyTuneMyMusicOverHttpsOpens() {
        #expect(tuneMyMusicUrl("https://www.tunemymusic.com/transfer/spotify-to-file") == "https://www.tunemymusic.com/transfer/spotify-to-file")
        #expect(tuneMyMusicUrl(" https://tunemymusic.com/transfer/tidal-to-file ") == "https://tunemymusic.com/transfer/tidal-to-file")
        #expect(tuneMyMusicUrl("HTTPS://WWW.TuneMyMusic.com") == "https://www.tunemymusic.com/")
        for refused in ["http://www.tunemymusic.com/transfer/spotify-to-file", "https://tunemymusic.com.evil.example/transfer",
                        "https://evil.example/tunemymusic.com", "https://app.tunemymusic.com/transfer", "https://tunemymusic.com@evil.example/",
                        "https://user:pass@tunemymusic.com/", "https://www.tunemymusic.com:8443/transfer", "javascript:alert(1)",
                        "intent://tunemymusic.com#Intent;end", "file:///sdcard/Download/x.csv", "", "not a link"] {
            #expect(tuneMyMusicUrl(refused) == nil, "\(refused)")
        }
    }

    @Test func theWaitSaysWhichTileToTap() {
        #expect(waitingLine(apple) == "Tap the Apple Music tile, sign in, choose your playlists or Liked songs, then Export to file as CSV.")
        #expect(waitingTitle(apple) == "Waiting for your Apple Music file")
        #expect(waitingTitle(nil) == "Waiting for your file")
        #expect(isImportFileName("My Library.CSV"))
        #expect(isImportFileName("export.zip"))
        #expect(!isImportFileName("song.mp3"))
    }

    func octo(_ fake: FamilyFake, versions: String = "[1,2]", spotifyConnect: Bool = false, approval: String? = nil) {
        let spotify = spotify
        let apple = apple
        fake.answer("getOpenSubsonicExtensions") { _ in #""openSubsonicExtensions":[{"name":"octoImports","versions":\#(versions)}]"# }
        fake.answer("getImports") { _ in #""imports":{"lists":[],"trickle":{"state":"idle"}\#(approval.map { ",\"approval\":\($0)" } ?? "")}"# }
        fake.answer("getImportServices") { _ in
            #""importServices":{"services":[{"id":"spotify","name":"Spotify","exportUrl":"\#(spotify.exportUrl)","tile":"Spotify"},{"id":"apple-music","name":"Apple Music","exportUrl":"\#(apple.exportUrl)","tile":"Apple Music"},{"id":"bad","name":"Bad","exportUrl":"https://evil.example.com/transfer","tile":"Bad"}],"spotifyConnect":\#(spotifyConnect)}"#
        }
    }

    final class Pages: @unchecked Sendable { var urls: [String] = [] }

    func model(_ fake: FamilyFake, _ pages: Pages = Pages()) -> ImportModel {
        let client = fake.client()
        let model = ImportModel(client: { client }, openUrl: { pages.urls.append($0) }, busyPollMs: 30, idlePollMs: 30)
        model.watch()
        return model
    }

    @Test func aServerWithoutVersion2ShowsNoServices() async {
        let fake = FamilyFake()
        octo(fake, versions: "[1]")
        let model = model(fake)
        #expect(await until("overview") { model.overview != nil })
        await settle(150)
        #expect(model.services == nil)
        #expect(fake.called("getImportServices").isEmpty)
        model.stop()
    }

    @Test func aTileOpensItsExportPageAndWaitsForTheFile() async {
        let fake = FamilyFake()
        octo(fake)
        let pages = Pages()
        let model = model(fake, pages)
        #expect(await until("services") { model.services != nil })
        #expect(model.services?.services.map(\.id) == ["spotify", "apple-music", "bad"])
        model.choose(apple)
        #expect(pages.urls == [apple.exportUrl])
        #expect(model.step == .waiting(apple))
        model.backToServices()
        #expect(model.step == .choose)
        if let bad = model.services?.services.last { model.choose(bad) }
        #expect(pages.urls.count == 1)
        #expect(model.step == .choose)
        #expect(model.said == ImportText.notTuneMyMusic)
        model.stop()
    }

    @Test func spotifyOffersTheSignInFirstWhenTheServerHasIt() async {
        let fake = FamilyFake()
        octo(fake, spotifyConnect: true)
        let pages = Pages()
        let model = model(fake, pages)
        #expect(await until("services") { model.services != nil })
        model.choose(spotify)
        #expect(model.step == .spotifyWays(spotify))
        #expect(pages.urls.isEmpty)
        model.openExport(spotify)
        #expect(model.step == .waiting(spotify))
        model.stop()
    }

    @Test func aFileSentShowsTheServersWords() async {
        let fake = FamilyFake()
        octo(fake)
        fake.answer("importFile") { _ in #""importAction":{"ok":true,"message":"Read 2 lists, 340 songs."}"# }
        let model = model(fake)
        #expect(await until("services") { model.services != nil })
        model.choose(apple)
        model.sendFile(name: "My Library.csv", bytes: Data("Track name,Artist name\nAngel,Massive Attack\n".utf8))
        #expect(await until("sent") { if case .sent = model.step { true } else { false } })
        #expect(model.step == .sent(message: "Read 2 lists, 340 songs.", approval: nil))
        #expect(fake.called("importFile").first?.method == "POST")
        model.stop()
    }

    @Test func aRefusedFileKeepsTheWaitOpenWithTheServersWords() async {
        let fake = FamilyFake()
        octo(fake)
        fake.answer("importFile") { _ in #""importAction":{"ok":false,"message":"No songs found. Each line should read Artist - Title."}"# }
        let model = model(fake)
        #expect(await until("services") { model.services != nil })
        model.choose(apple)
        model.sendFile(name: "notes.txt", bytes: Data("hello".utf8))
        #expect(await until("said") { model.said != nil })
        #expect(model.said == "No songs found. Each line should read Artist - Title.")
        #expect(model.step == .waiting(apple))
        model.stop()
    }

    @Test func aFileOctoCannotReadIsNotSent() async {
        let fake = FamilyFake()
        octo(fake)
        let model = model(fake)
        #expect(await until("services") { model.services != nil })
        model.useAFile()
        model.sendFile(name: "song.mp3", bytes: Data([1, 2, 3]))
        #expect(model.said == ImportText.notAListFile)
        model.sendFile(name: "empty.csv", bytes: Data())
        #expect(model.said == ImportText.fileEmpty)
        #expect(model.step == .waiting(nil))
        #expect(fake.called("importFile").isEmpty)
        model.stop()
    }

    @Test func aPastedListIsSentAsText() async {
        let fake = FamilyFake()
        octo(fake)
        fake.answer("importText") { _ in #""importAction":{"ok":true,"message":"Read 1 list, 2 songs."}"# }
        let model = model(fake)
        #expect(await until("services") { model.services != nil })
        model.sendText("Massive Attack - Angel\nMGMT - Kids")
        #expect(await until("sent") { if case .sent = model.step { true } else { false } })
        #expect(fake.called("importText").first?.text.contains("name=Pasted") == true)
        model.stop()
    }

    @Test func anotherServerStartsTheVisitOver() async {
        let fake = FamilyFake()
        octo(fake)
        let model = model(fake)
        #expect(await until("services") { model.services != nil })
        model.choose(apple)
        model.forget()
        #expect(model.step == .choose)
        #expect(model.services == nil)
    }

    @Test func theApprovalLineNamesTheOwnerWhenItCan() {
        #expect(approvalLine("Sam") == "Your lists are in. Sam approves downloads before Octo fetches the missing songs.")
        #expect(approvalLine(nil) == "Your lists are in. The owner approves downloads before Octo fetches the missing songs.")
        #expect(approvalLine("  ") == "Your lists are in. The owner approves downloads before Octo fetches the missing songs.")
        #expect(ImportOverview(approval: ImportApproval(needed: false, by: "Sam")).approvalLine == nil)
        #expect(ImportOverview().approvalLine == nil)
    }

    @Test func aMemberWhoseDownloadsWaitIsToldWhoApprovesThem() async {
        let fake = FamilyFake()
        octo(fake, approval: #"{"needed":true,"by":"Sam"}"#)
        fake.answer("importFile") { _ in #""importAction":{"ok":true,"message":"Read 1 list, 12 songs."}"# }
        let model = model(fake)
        #expect(await until("services") { model.services != nil })
        model.choose(apple)
        model.sendFile(name: "Apple.csv", bytes: Data("Track name,Artist name\nAngel,Massive Attack\n".utf8))
        #expect(await until("sent") { if case .sent = model.step { true } else { false } })
        #expect(model.step == .sent(message: "Read 1 list, 12 songs.", approval: "Your lists are in. Sam approves downloads before Octo fetches the missing songs."))
        #expect(fake.called("getFamily").isEmpty)
        model.stop()
    }
}

@Suite struct ImportShareTests {
    @Test func sharedTextIsTheListItself() {
        #expect(sharedText("Massive Attack - Angel\nMGMT - Kids", subject: " Road trip ") == .text("Massive Attack - Angel\nMGMT - Kids", name: "Road trip"))
        #expect(sharedText("Massive Attack - Angel", subject: "  ") == .text("Massive Attack - Angel", name: nil))
        #expect(sharedText("   ", subject: nil) == nil)
        #expect(sharedText(nil, subject: nil) == nil)
    }

    @Test func aFileIsNamedSoTheServerKnowsHowToReadIt() {
        #expect(importFileName("My Spotify Library.csv", type: "text/plain") == "My Spotify Library.csv")
        #expect(importFileName("export.zip", type: nil) == "export.zip")
        #expect(importFileName("Liked", type: "text/csv") == "Liked.csv")
        #expect(importFileName("Liked", type: "text/comma-separated-values") == "Liked.csv")
        #expect(importFileName("notes.txt.txt", type: "text/plain") == "notes.txt.txt")
        #expect(importFileName(nil, type: "text/plain") == "Shared list.txt")
        #expect(importFileName("  ", type: "application/json") == "Shared list.json")
        #expect(importFileName("song.mp3", type: nil) == "song.mp3.txt")
    }

    @Test func thePickerOffersEveryKindTheServerReads() {
        #expect(importPickTypes == ["text/plain", "text/csv", "text/comma-separated-values", "application/zip", "application/json"])
    }
}
