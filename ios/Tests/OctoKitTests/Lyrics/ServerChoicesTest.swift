import Foundation
import Testing
@testable import OctoKit

/// Counts what a lookup asked, from steps that run at any time.
final class LyricsAsked: @unchecked Sendable {
    private let lock = NSLock()
    private var list: [LyricsSource] = []

    func add(_ source: LyricsSource) {
        lock.lock()
        list.append(source)
        lock.unlock()
    }

    var all: [LyricsSource] {
        lock.lock()
        defer { lock.unlock() }
        return list
    }

    func clear() {
        lock.lock()
        list = []
        lock.unlock()
    }
}

// Lyrics chosen on a server that keeps one choice for every app, beside the lyrics only this
// phone has, and who wins.
@Suite struct ServerChoicesTest {
    let listed = """
    {"subsonic-response":{"status":"ok","version":"1.16.1","type":"octo","lyricsCandidates":{"id":"song-1","choice":"auto","candidate":[
      {"id":"kugou:9f2a.77c1","source":"kugou","title":"Café","artist":"Octo Test","album":"Premier","duration":215,"kind":"word","sameSong":true,"chosen":false,"preview":["Café au lait","日本語の歌"]},
      {"id":"lrclib:4242","source":"lrclib","title":"Café (Live)","artist":"Octo Test","album":null,"duration":null,"kind":"line","sameSong":false,"chosen":false,"preview":["Café au lait"]},
      {"id":"netease:77","source":"netease","title":"Café","artist":"Octo Test","album":"Premier","duration":214,"kind":"plain","sameSong":true,"chosen":false,"preview":[]}]}}}
    """

    func candidates(_ choice: String = LYRICS_AUTO) -> LyricsCandidates {
        var found: LyricsCandidates = try! SubsonicClient.decode(Data(listed.utf8), key: "lyricsCandidates")
        found.choice = choice
        return found
    }

    func timed(_ source: LyricsSource, _ text: String, serverPick: String? = nil) -> Lyrics {
        Lyrics(synced: true, lines: [LyricLine(startMs: 1_000, text: text)], source: source, serverPick: serverPick)
    }

    var songFile: LyricsCandidate { LyricsCandidate(.own(.songFile), .songFile, timed(.songFile, "tag")) }
    var lrcFile: LyricsCandidate { LyricsCandidate(.own(.lyricsFile), .lyricsFile, timed(.lyricsFile, "lrc")) }
    var automatic: Lyrics { timed(.server, "found by the server") }

    let auto = LyricsPick.onServer(LYRICS_AUTO)
    let kugou = LyricsPick.onServer("kugou:9f2a.77c1")
    let lrclib = LyricsPick.onServer("lrclib:4242")
    let netease = LyricsPick.onServer("netease:77")

    @Test func wordTimingsAreAskedForWhenTheServerListsVersionTwo() {
        #expect(serverLyricsCall(["songLyrics:1", "songLyrics:2", "octoLyrics:1"]) == .withWords)
        #expect(serverLyricsCall(["songLyrics:1"]) == .bySongId)
        #expect(serverLyricsCall(["formPost:1"]) == .byName)
    }

    @Test func onlyAServerListingTheExtensionKeepsChoices() {
        #expect(offersLyricsChoices(["songLyrics:2", "octoLyrics:1"]))
        #expect(!offersLyricsChoices(["songLyrics:2", "octoAcquisitions:1"]))
    }

    @Test func theServerCopiesComeWithWhatTheyAre() {
        let found = serverCandidates(candidates(), automatic, [songFile, lrcFile])
        #expect(found.map(\.pick) == [auto, kugou, lrclib, netease, songFile.pick, lrcFile.pick])
        let first = found[1]
        #expect(candidateLabel(first) == "From KuGou")
        #expect(first.kind == .words)
        #expect(first.kind.label == "Word by word")
        #expect(first.album == "Premier")
        #expect(first.durationMs == 215_000)
        #expect(first.preview == ["Café au lait", "日本語の歌"])
        #expect(candidateLabel(found[2]) == "From LRCLIB")
        #expect(found[2].kind == .lines)
        #expect(found[2].album == "")
        #expect(found[2].durationMs == 0)
        #expect(candidateLabel(found[3]) == "From NetEase")
        #expect(found[3].kind == .plain)
        #expect(candidateLabel(found[0]) == "Automatic")
        #expect(candidateLabel(found[4]) == "From the song file")
    }

    @Test func automaticCarriesTheServersLyricsOnlyWhileItFindsThemItself() {
        #expect(serverCandidates(candidates(LYRICS_AUTO), automatic, []).first?.lyrics == automatic)
        #expect(serverCandidates(candidates("kugou:9f2a.77c1"), automatic, []).first?.lyrics == nil)
        #expect(serverCandidates(candidates(LYRICS_NONE), nil, []).first?.lyrics == nil)
    }

    @Test func anUnreachableServerLeavesTheLocalLyrics() {
        #expect(serverCandidates(nil, nil, [songFile]).map(\.pick) == [songFile.pick])
    }

    @Test func copiesWithTheSameFirstLinesAreAllOffered() {
        var same = candidates()
        same.candidate = same.candidate.map { var copy = $0; copy.preview = ["Same"]; return copy }
        let list = candidateList(serverCandidates(same, automatic, []), current: auto, showing: automatic)
        #expect(list.items.map(\.pick) == [auto, kugou, lrclib, netease])
    }

    @Test func thePinnedCopyIsShowingAndComesFirst() {
        let showing = timed(.server, "pinned words", serverPick: "lrclib:4242")
        let current = showingPick("lrclib:4242", showing)
        #expect(current == lrclib)
        let list = candidateList(serverCandidates(candidates("lrclib:4242"), nil, [songFile]), current: current, showing: showing)
        #expect(list.items.map(\.pick) == [lrclib, auto, kugou, netease, songFile.pick])
        #expect(list.showing == 0)
    }

    @Test func theServersOwnFindIsAutomatic() {
        let list = candidateList(serverCandidates(candidates(), automatic, [songFile]), current: showingPick(LYRICS_AUTO, automatic), showing: automatic)
        #expect(list.items[list.showing].pick == auto)
    }

    @Test func aPickOnThisPhoneWinsOverTheServersChoice() {
        let showing = songFile.lyrics
        let current = showingPick("kugou:9f2a.77c1", showing)
        #expect(current == songFile.pick)
        let list = candidateList(serverCandidates(candidates("kugou:9f2a.77c1"), nil, [songFile, lrcFile]), current: current, showing: showing)
        #expect(list.items.first?.pick == songFile.pick)
        #expect(list.showing == 0)
    }

    @Test func anOnlinePickMadeBeforeTheServerOfferedChoicesStillShows() {
        let picked = Lyrics(synced: true, lines: [LyricLine(startMs: 0, text: "picked")], source: .online, onlineId: 99)
        let list = candidateList(serverCandidates(candidates(), automatic, []), current: showingPick(LYRICS_AUTO, picked), showing: picked)
        #expect(list.items.first?.pick == .online(99))
        #expect(list.showing == 0)
    }

    @Test func withoutTheExtensionNothingChanges() {
        let server = LyricsCandidate(.own(.server), .server, automatic)
        #expect(showingPick(nil, automatic) == .own(.server))
        let list = candidateList([songFile, server], current: showingPick(nil, automatic), showing: automatic)
        #expect(list.items.map(\.pick) == [server.pick, songFile.pick])
        #expect(candidateLabel(server) == "From your server")
    }

    @Test func aServerPinClearsThisPhonesPickAndHideAndForgetsTheSavedLyrics() async throws {
        let choices = LyricsChoices(MemoryValues())
        choices.pick("s", .own(.songFile))
        choices.hide("s")
        var sent: [String] = []
        var forgotten = 0
        try await sendServerChoice("s", "kugou:1", choices, send: { sent.append($0) }, forget: { forgotten += 1 })
        #expect(sent == ["kugou:1"])
        #expect(forgotten == 1)
        #expect(choices.current("s") == LyricsChoice())
    }

    @Test func automaticClearsThisPhonesPickToo() async throws {
        let choices = LyricsChoices(MemoryValues())
        choices.pick("s", .online(4))
        try await sendServerChoice("s", LYRICS_AUTO, choices, send: { _ in }, forget: {})
        #expect(choices.current("s") == LyricsChoice())
    }

    @Test func hidingOnTheServerHidesHereAndKeepsThePickForLater() async throws {
        let choices = LyricsChoices(MemoryValues())
        choices.pick("s", .own(.lyricsFile))
        try await sendServerChoice("s", LYRICS_NONE, choices, send: { _ in }, forget: {})
        #expect(choices.current("s") == LyricsChoice(.own(.lyricsFile), hidden: true))
        try await sendServerChoice("s", LYRICS_AUTO, choices, send: { _ in }, forget: {}, showAgain: true)
        #expect(choices.current("s") == LyricsChoice(.own(.lyricsFile), hidden: false))
    }

    @Test func aChoiceTheServerRefusesChangesNothingHere() async {
        let choices = LyricsChoices(MemoryValues())
        choices.pick("s", .online(4))
        var forgotten = false
        var refused = false
        do {
            try await sendServerChoice("s", "kugou:1", choices, send: { _ in throw LyricsOffline() }, forget: { forgotten = true })
        } catch {
            refused = error is LyricsOffline
        }
        #expect(refused)
        #expect(!forgotten)
        #expect(choices.current("s") == LyricsChoice(.online(4)))
    }

    @Test func aSavedAnswerIsStaleWhenTheServersChoiceMoved() {
        func saved(_ lyrics: Lyrics?, pick: String? = nil) -> CachedLyrics {
            CachedLyrics(savedAt: 1_000, lyrics: lyrics, askedOnline: true, lookupVersion: ONLINE_LOOKUP_VERSION, pick: pick)
        }
        let serverAuto = saved(timed(.server, "auto"))
        let serverPinned = saved(timed(.server, "pinned", serverPick: "kugou:1"))
        #expect(!servedStale(nil, "kugou:1"))
        #expect(!servedStale(serverAuto, LYRICS_AUTO))
        #expect(!servedStale(serverPinned, "kugou:1"))
        #expect(servedStale(serverAuto, "kugou:1"))
        #expect(servedStale(serverPinned, "lrclib:2"))
        #expect(servedStale(serverPinned, LYRICS_AUTO))
        #expect(servedStale(serverAuto, LYRICS_NONE))
        #expect(servedStale(saved(nil), "kugou:1"))
        #expect(servedStale(saved(timed(.songFile, "tag")), "kugou:1"))
        #expect(!servedStale(saved(timed(.songFile, "tag")), LYRICS_AUTO))
        #expect(!servedStale(saved(timed(.songFile, "tag"), pick: "own:SongFile"), "kugou:1"))
    }

    @Test func theServersAnswerIsFinalWhenItKeepsChoices() async throws {
        let asked = LyricsAsked()
        let tag = timed(.songFile, "tag")
        let fromOnline = timed(.online, "online")
        func steps(_ server: @escaping @Sendable () async throws -> Lyrics?, decides: Bool) -> [LyricsStep] {
            lyricsSteps(
                server: { asked.add(.server); return try await server() },
                serverDecides: decides,
                songFile: { asked.add(.songFile); return tag },
                lyricsFile: nil,
                online: { asked.add(.online); return fromOnline }
            )
        }
        let plain = Lyrics(synced: false, lines: [LyricLine(text: "plain")], source: .server)

        #expect(try await searchInOrder(steps({ plain }, decides: true)).lyrics == plain)
        #expect(asked.all == [.server])

        asked.clear()
        #expect(try await searchInOrder(steps({ nil }, decides: true)).lyrics?.source == .songFile)
        #expect(asked.all == [.server, .songFile])
        asked.clear()
        let none = try await searchInOrder(lyricsSteps(server: { nil }, serverDecides: true, songFile: nil, lyricsFile: nil,
                                                       online: { asked.add(.online); return nil }))
        #expect(none.lyrics == nil)
        #expect(asked.all.isEmpty)

        asked.clear()
        let search = try await searchInOrder(lyricsSteps(server: { throw LyricsOffline() }, serverDecides: true, songFile: nil, lyricsFile: nil,
                                                         online: { asked.add(.online); return fromOnline }))
        #expect(search.lyrics?.source == .online)
        #expect(asked.all == [.online])
        #expect(!search.complete)

        asked.clear()
        #expect(try await searchInOrder(steps({ plain }, decides: false)).lyrics?.source == .songFile)
    }

    @Test func theMenuSaysWhereLyricsAreFrom() {
        var worded = Lyrics(synced: true, lines: [LyricLine(startMs: 0, text: "Café", words: [LyricWord(startMs: 0, endMs: 500, text: "Café", from: 0, to: 4)])], source: .server)
        #expect(worded.sourceLine() == "From your server, word by word")
        worded.serverPick = "kugou:9f2a.77c1"
        #expect(worded.sourceLine() == "From KuGou, word by word")
        #expect(timed(.online, "x").sourceLine() == "From LRCLIB")
        #expect(timed(.server, "x", serverPick: "lrclib:4242").sourceLine() == "From LRCLIB")
        #expect(timed(.server, "x").sourceLine() == "From your server")
        #expect(timed(.songFile, "x").sourceLine() == "From the song file")
    }

    @Test func aSearchByHandIsATitleOrArtistAndTitle() {
        #expect(splitLyricsSearch(" Octo Test - Café ") == ("Café", "Octo Test"))
        #expect(splitLyricsSearch("Stand by Me") == ("Stand by Me", nil))
        #expect(splitLyricsSearch("- Café") == ("- Café", nil))
    }

    @Test func aServerChoiceIsNeverMistakenForAnotherPick() {
        #expect(decodePick(kugou.encoded) == kugou)
        #expect(decodePick(auto.encoded) == auto)
        #expect(decodePick("server:") == nil)
    }

    @Test func sourceNamesReadAsTheListenerKnowsThem() {
        #expect(lyricsSourceName("kugou") == "KuGou")
        #expect(lyricsSourceName(" LRCLIB ") == "LRCLIB")
        #expect(lyricsSourceName("lyricsovh") == "Lyrics.ovh")
        #expect(lyricsSourceName("pinned") == "your server")
        #expect(lyricsSourceName("musixmatch") == "Musixmatch")
    }
}

@Suite struct LyricsSearchTest {
    func synced(_ source: LyricsSource) -> Lyrics { Lyrics(synced: true, lines: [LyricLine(startMs: 0, text: source.rawValue)], source: source) }
    func plain(_ source: LyricsSource) -> Lyrics { Lyrics(synced: false, lines: [LyricLine(text: source.rawValue)], source: source) }

    func steps(_ answers: [(LyricsSource, @Sendable () throws -> Lyrics?)], _ asked: LyricsAsked) -> [LyricsStep] {
        answers.map { source, answer in LyricsStep(source) { asked.add(source); return try answer() } }
    }

    @Test func aSourceCutOffByItsOwnTimeLimitMakesTheSearchIncomplete() async throws {
        let slow = LyricsStep(.online) {
            // Its own time limit ends the wait inside it; the search around it carries on.
            let wait = Task<Lyrics?, Error> {
                try await Task.sleep(for: .seconds(60))
                return nil
            }
            Task {
                try? await Task.sleep(for: .milliseconds(20))
                wait.cancel()
            }
            return try await wait.value
        }
        let search = try await searchInOrder(steps([(.server, { nil }), (.songFile, { nil })], LyricsAsked()) + [slow])
        #expect(search.lyrics == nil)
        #expect(!search.complete)
    }

    @Test func theServerWinsWhenItHasSyncedLyrics() async throws {
        let asked = LyricsAsked()
        let server = synced(.server), file = synced(.songFile), online = synced(.online)
        let search = try await searchInOrder(steps([(.server, { server }), (.songFile, { file }), (.online, { online })], asked))
        #expect(search.lyrics?.source == .server)
        #expect(asked.all == [.server])
        #expect(!search.askedOnline)
    }

    @Test func sourcesAreAskedInOrderUntilOneHasLyrics() async throws {
        let asked = LyricsAsked()
        let lrc = synced(.lyricsFile), online = synced(.online)
        let search = try await searchInOrder(steps([(.server, { nil }), (.songFile, { nil }), (.lyricsFile, { lrc }), (.online, { online })], asked))
        #expect(search.lyrics?.source == .lyricsFile)
        #expect(asked.all == [.server, .songFile, .lyricsFile])
    }

    @Test func syncedLyricsFurtherDownBeatPlainOnesFirst() async throws {
        let server = plain(.server), file = synced(.songFile)
        #expect(try await searchInOrder(steps([(.server, { server }), (.songFile, { file })], LyricsAsked())).lyrics?.source == .songFile)
    }

    @Test func theFirstPlainLyricsWinWhenNoneAreSynced() async throws {
        let file = plain(.songFile), lrc = plain(.lyricsFile)
        let search = try await searchInOrder(steps([(.server, { nil }), (.songFile, { file }), (.lyricsFile, { lrc }), (.online, { nil })], LyricsAsked()))
        #expect(search.lyrics?.source == .songFile)
        #expect(search.complete)
        #expect(search.askedOnline)
    }

    @Test func emptyLyricsCountAsNone() async throws {
        let empty = Lyrics(synced: true, lines: [LyricLine(text: "")], source: .server), file = plain(.songFile)
        #expect(try await searchInOrder(steps([(.server, { empty }), (.songFile, { file })], LyricsAsked())).lyrics?.source == .songFile)
    }

    @Test func aFailingSourceIsSkippedAndTheSearchIsNotComplete() async throws {
        let search = try await searchInOrder(steps([(.server, { throw LyricsOffline() }), (.songFile, { nil })], LyricsAsked()))
        #expect(search.lyrics == nil)
        #expect(!search.complete)
    }

    @Test func aStoppedSearchStops() async {
        let search = Task { try await searchInOrder([LyricsStep(.server) { try await Task.sleep(for: .seconds(30)); return nil }]) }
        search.cancel()
        let result = await search.result
        #expect(throws: CancellationError.self) { try result.get() }
    }

    @Test func aNoneFromAServerThatLooksLyricsUpItselfIsUnsure() async throws {
        let unsure = try await searchInOrder(lyricsSteps(server: { nil }, serverDecides: true, songFile: nil, lyricsFile: nil, online: nil))
        #expect(unsure.lyrics == nil)
        #expect(unsure.complete)
        #expect(unsure.unsure)
        let sure = try await searchInOrder(lyricsSteps(server: { nil }, serverDecides: false, songFile: nil, lyricsFile: nil, online: nil))
        #expect(!sure.unsure)
    }
}

// Octo's lyrics copies and the choice between them that holds for the whole server.
@Suite struct LyricsPinsTest {
    let library = StubLibrary()

    var client: SubsonicClient {
        SubsonicClient(baseURL: library.base, credentials: Credentials(username: "winters", password: "secret"),
                       device: DeviceIdentity(id: "d", name: "Phone"), appVersion: "1", session: library.session)
    }

    let listed = #"{"subsonic-response":{"status":"ok","version":"1.16.1","type":"octo","lyricsCandidates":{"id":"ext-deezer-song-3135556","choice":"kugou:9f2a.77c1","candidate":[{"id":"kugou:9f2a.77c1","source":"kugou","title":"Café","artist":"Octo Test","album":"Premier","duration":215,"kind":"word","sameSong":true,"chosen":true,"preview":["Café au lait","日本語の歌"]},{"id":"lrclib:4242","source":"lrclib","title":"Café (Live)","artist":"Octo Test","album":null,"duration":null,"kind":"line","sameSong":false,"chosen":false,"preview":["Café au lait"]},{"id":"lyricsovh:octo%20test/caf%C3%A9","source":"lyricsovh","title":"Café","artist":"Octo Test","album":null,"duration":null,"kind":"plain","sameSong":true,"chosen":false,"preview":[]}]}}}"#

    @Test func candidatesAreReadWithTheChoice() async throws {
        library.answer(listed)
        let found = try await client.lyricsCandidates("ext-deezer-song-3135556")
        let url = library.takeRequest()
        #expect(url.path.hasSuffix("/rest/getLyricsCandidates"))
        #expect(queryParameter(url, "id") == "ext-deezer-song-3135556")
        #expect(queryParameter(url, "title") == nil)
        #expect(queryParameter(url, "artist") == nil)
        #expect(queryParameter(url, "u") == "winters")
        #expect(found.choice == "kugou:9f2a.77c1")
        #expect(found.candidate.count == 3)
        #expect(found.candidate[0].duration == 215)
        #expect(found.candidate[0].chosen)
        #expect(found.candidate[1].album == nil)
        #expect(found.candidate[1].duration == nil)
        #expect(found.candidate[2].preview.isEmpty)
    }

    @Test func aSearchByHandSendsTitleAndArtist() async throws {
        library.answer(listed)
        _ = try await client.lyricsCandidates("song-1", title: " Café ", artist: "Octo Test")
        let url = library.takeRequest()
        #expect(queryParameter(url, "title") == "Café")
        #expect(queryParameter(url, "artist") == "Octo Test")
    }

    @Test func blankSearchWordsAreLeftOut() {
        let params = lyricsCandidatesParams("1", "a", " ")
        #expect(params.map(\.0) == ["id", "title"])
        #expect(params.map(\.1) == ["1", "a"])
    }

    @Test func aChoiceIsSentAndItsAnswerRead() async throws {
        library.answer(#"{"subsonic-response":{"status":"ok","version":"1.16.1","type":"octo","lyricsChoice":{"id":"ext-deezer-song-3135556","choice":"lrclib:4242"}}}"#)
        #expect(try await client.setLyricsChoice("ext-deezer-song-3135556", candidate: "lrclib:4242") == "lrclib:4242")
        let url = library.takeRequest()
        #expect(url.path.hasSuffix("/rest/setLyricsChoice"))
        #expect(queryParameter(url, "candidate") == "lrclib:4242")
    }

    @Test func hidingAndAutomaticAreChoicesToo() async throws {
        library.answer(#"{"subsonic-response":{"status":"ok","lyricsChoice":{"id":"s","choice":"none"}}}"#)
        #expect(try await client.setLyricsChoice("s", candidate: LYRICS_NONE) == LYRICS_NONE)
        library.answer(#"{"subsonic-response":{"status":"ok","lyricsChoice":{"id":"s","choice":"auto"}}}"#)
        #expect(try await client.setLyricsChoice("s", candidate: LYRICS_AUTO) == LYRICS_AUTO)
    }

    @Test func lookupsSwitchedOffAreAServerError() async {
        library.answer(#"{"subsonic-response":{"status":"failed","version":"1.16.1","type":"octo","error":{"code":0,"message":"Lyrics lookups are off on this server"}}}"#)
        await #expect(throws: OctoError.server(code: 0, message: "Lyrics lookups are off on this server")) {
            _ = try await client.lyricsCandidates("song-1")
        }
    }

    @Test func wordTimingsAreAskedForByName() async throws {
        library.answer(#"{"subsonic-response":{"status":"ok","lyricsList":{"structuredLyrics":[]}}}"#)
        _ = try await client.lyricsBySongId("song-1", enhanced: true)
        #expect(queryParameter(library.takeRequest(), "enhanced") == "true")
        library.answer(#"{"subsonic-response":{"status":"ok","lyricsList":{"structuredLyrics":[]}}}"#)
        _ = try await client.lyricsBySongId("song-1", enhanced: false)
        #expect(queryParameter(library.takeRequest(), "enhanced") == nil)
    }

    @Test func theOlderCallAnswersPlainText() async throws {
        library.answer(#"{"subsonic-response":{"status":"ok","lyrics":{"artist":"a","title":"t","value":"Hello"}}}"#)
        #expect(try await client.lyrics(artist: "a", title: "t") == "Hello")
        library.answer(#"{"subsonic-response":{"status":"ok","lyrics":{"value":"  "}}}"#)
        #expect(try await client.lyrics(artist: "a", title: "t") == nil)
    }
}
