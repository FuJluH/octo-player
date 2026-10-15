import Foundation
import Testing
@testable import OctoKit

/// The words both apps show about kept servers.
@Suite struct ServerListTests {
    @Test func aServerIsCalledByItsNameElseItsHost() {
        #expect(serverName(label: " Home ", address: "https://music.example.com/") == "Home")
        #expect(serverName(label: "", address: "https://music.example.com:4533/") == "music.example.com")
        #expect(serverName(label: "", address: "not an address/") == "not an address")
        let address = URL(string: "https://music.example.com/")!
        #expect(StoredServer(label: "  Home  ", address: address, username: "me").name == "Home")
        #expect(StoredServer(label: "   ", address: address, username: "me").name == "music.example.com")
    }

    @Test func theRowSaysWhoAndWhere() {
        #expect(accountLine(username: "winters", address: "https://music.example.com/") == "winters at music.example.com")
        #expect(accountLine(username: "", address: "http://music.example.com:4533/") == "music.example.com:4533")
    }

    @Test func theStatusLineSaysHowTheServerAnswered() {
        #expect(statusLine(serverType: "octo", serverVersion: "0.9.3", signedOut: false, check: nil) == "Octo 0.9.3")
        #expect(statusLine(serverType: "octo", serverVersion: "0.9.3", signedOut: false, check: ServerCheck(.answers, 38))
            == "Octo 0.9.3 · Answered in 38 ms")
        #expect(statusLine(serverType: "octo", serverVersion: "0.9.3", signedOut: false, check: ServerCheck(.answers, 38), inUse: true)
            == "Octo 0.9.3")
        #expect(statusLine(serverType: "octo", serverVersion: "0.9.3", signedOut: false, check: ServerCheck(.unreachable))
            == "Octo 0.9.3 · Out of reach right now")
        #expect(statusLine(serverType: "octo", serverVersion: "0.9.3", signedOut: false, check: ServerCheck(.wrongPassword))
            == "Octo 0.9.3 · Didn't take the saved password")
        #expect(statusLine(serverType: "octo", serverVersion: "0.9.3", signedOut: true, check: ServerCheck(.answers, 38))
            == "Signed out. Sign in again to use it.")
        #expect(statusLine(serverType: nil, serverVersion: nil, signedOut: false, check: nil, switching: true) == "Switching to it now")
        #expect(ServerCheck(.unreachable).isWarning)
        #expect(!ServerCheck(.answers).isWarning)
    }

    @Test func aNewIdIsTheAccountsKeyUnlessTaken() {
        let first = serverAccountKey("winters", "https://music.test/")
        #expect(freshServerId(username: "winters", address: "https://music.test/", taken: []) == first)
        #expect(freshServerId(username: "winters", address: "https://music.test/", taken: [first]) == "\(first)-2")
        #expect(freshServerId(username: "winters", address: "https://music.test/", taken: [first, "\(first)-2"]) == "\(first)-3")
    }

    @Test func theAccountKeyIsStable() {
        #expect(serverAccountKey("brandon", "https://music.example") == serverAccountKey("brandon", "https://music.example"))
        #expect(serverAccountKey("a", "b").count == 16)
        #expect(serverAccountKey("a", "b") != serverAccountKey("a", "c"))
        // SHA-256 of "abc" starts ba7816bf8f01cfea.
        #expect(serverAccountKey("winters", "https://music.test/") == Hashes.hex(Hashes.sha256(Array("winters@https://music.test/".utf8)).prefix(8)))
    }


    @Test func anAddressIsWrittenWithASlashAfterABareHost() {
        #expect(ServerAddress.written(URL(string: "https://music.test")!) == "https://music.test/")
        #expect(ServerAddress.written(URL(string: "https://music.test/octo")!) == "https://music.test/octo")
        #expect(ServerAddress.normalized("music.test/rest").map(ServerAddress.shown) == "http://music.test")
        #expect(ServerAddress.normalized("HTTPS://WWW.Example.com/a?b=1#c").map(ServerAddress.shown) == "https://www.example.com/a")
        #expect(ServerAddress.normalized("://") == nil)
    }

    private struct Kept: Equatable {
        var id: String
        var username: String
        var address: String
        var label = ""
        var signedOut = false
    }

    private func settle(_ listed: [Kept], _ legacy: Kept?) -> (list: [Kept], inUse: Kept?) {
        settleServers(listed, legacy: legacy, id: \.id, same: { a, b in a.username == b.username && a.address == b.address }) { old, match in
            guard let match else { return old }
            var kept = old
            kept.id = match.id
            kept.label = old.label.isEmpty ? match.label : old.label
            kept.signedOut = false
            return kept
        }
    }

    @Test func theOneServerOfAnOlderAppBecomesAListOfOneInUse() {
        let legacy = Kept(id: "k", username: "winters", address: "https://music.test/")
        let (list, inUse) = settle([], legacy)
        #expect(list == [legacy])
        #expect(inUse == legacy)
    }

    @Test func theListStandsAloneWhenNoServerIsInUse() {
        let home = Kept(id: "h", username: "winters", address: "https://home.test/")
        let (list, inUse) = settle([home, home], nil)
        #expect(list == [home])
        #expect(inUse == nil)
    }

    @Test func theServerInUseIsBroughtUpToDateInItsPlace() {
        let home = Kept(id: "h", username: "winters", address: "https://home.test/", label: "Home", signedOut: true)
        let work = Kept(id: "w", username: "brandon", address: "https://work.test/")
        let (list, inUse) = settle([home, work], Kept(id: "other", username: "winters", address: "https://home.test/"))
        #expect(list.map(\.id) == ["h", "w"])
        #expect(inUse?.label == "Home")
        #expect(inUse?.signedOut == false)
    }
}

/// The words about a server both apps show.
@Suite struct ServerStatsTests {
    let utc = TimeZone(identifier: "UTC")!
    let now: Int64 = 1_790_683_200_000 // 2026-09-29 12:00 UTC
    let minute: Int64 = 60_000

    func ms(_ text: String) -> Int64 { epochMs(text)! }

    @Test func theKindAndVersionReadAsOneName() {
        #expect(serverKind("octo", "0.9.3") == "Octo 0.9.3")
        #expect(serverKind("navidrome", nil) == "Navidrome")
        #expect(serverKind(nil, " ") == "Subsonic server")
    }

    @Test func whatItOffersIsSaidWithoutItsMachinery() {
        #expect(serverOffers(lyrics: true, adds: true) == "Offers synced lyrics and adding songs you find online to your library.")
        #expect(serverOffers(lyrics: true, adds: false) == "Offers synced lyrics.")
        #expect(serverOffers(lyrics: false, adds: false) == nil)
        #expect(offersOf(["songLyrics:1", "octoAcquisitions:1", "formPost:1"])
            == "Offers synced lyrics and adding songs you find online to your library.")
        #expect(offersOf(["octoLyrics:1"]) == "Offers synced lyrics.")
        #expect(offersOf(["formPost:1"]) == nil)
    }

    @Test func countsReadAsAListLeavingOutWhatIsNotKnown() {
        #expect(libraryCounts(songs: 12_040, albums: 960, artists: 1, playlists: 12) == "12,040 songs, 960 albums, 1 artist and 12 playlists")
        #expect(libraryCounts(songs: 3, albums: nil, artists: nil, playlists: 1) == "3 songs and 1 playlist")
        #expect(libraryCounts(songs: 1, albums: nil, artists: nil, playlists: nil) == "1 song")
        #expect(libraryCounts(songs: nil, albums: nil, artists: nil, playlists: nil) == nil)
    }

    @Test func answerTimesAreInMillisecondsThenSeconds() {
        #expect(answerWords(42) == "Answered in 42 ms")
        #expect(answerWords(1_260) == "Answered in 1.3 s")
    }

    @Test func aScanInProgressSaysHowFarItIs() {
        #expect(scanWords(ServerScanStatus(scanning: true, count: 1_204), nowMs: now, zone: utc) == "Reading its folders now, 1,204 files so far.")
        #expect(scanWords(ServerScanStatus(scanning: true), nowMs: now, zone: utc) == "Reading its folders now.")
    }

    @Test func theLastScanSaysWhen() {
        let last: ServerScanStatus = decoded(#"{"scanning":false,"count":0,"lastScan":"2026-09-29T09:00:00Z"}"#)
        #expect(scanWords(last, nowMs: now, zone: utc) == "Last read its folders 3 hours ago.")
        #expect(scanWords(ServerScanStatus(), nowMs: now, zone: utc) == nil)
        #expect(scanWords(nil, nowMs: now, zone: utc) == nil)
    }

    @Test func timesAgoReadLikeSpeech() {
        #expect(agoWords(thenMs: now - 20_000, nowMs: now, zone: utc) == "just now")
        #expect(agoWords(thenMs: now - minute, nowMs: now, zone: utc) == "a minute ago")
        #expect(agoWords(thenMs: now - 45 * minute, nowMs: now, zone: utc) == "45 minutes ago")
        #expect(agoWords(thenMs: now - 61 * minute, nowMs: now, zone: utc) == "an hour ago")
        #expect(agoWords(thenMs: now - 30 * 60 * minute, nowMs: now, zone: utc) == "yesterday")
        #expect(agoWords(thenMs: now - 4 * 24 * 60 * minute, nowMs: now, zone: utc) == "4 days ago")
        #expect(agoWords(thenMs: ms("2026-09-12T08:00:00Z"), nowMs: now, zone: utc) == "on 12 September")
        #expect(agoWords(thenMs: ms("2025-03-03T08:00:00Z"), nowMs: now, zone: utc) == "on 3 March 2025")
        #expect(agoWords(thenMs: now + 5 * minute, nowMs: now, zone: utc) == "just now")
    }

    @Test func homeIsUsedOnlyWhenEverythingSaysSo() {
        #expect(choosePlace(hasHome: true, onLocalNetwork: true, homeAnswered: true) == .home)
        #expect(choosePlace(hasHome: true, onLocalNetwork: false, homeAnswered: true) == .away)
        #expect(choosePlace(hasHome: false, onLocalNetwork: true, homeAnswered: true) == .away)
        #expect(choosePlace(hasHome: true, onLocalNetwork: true, homeAnswered: false) == .away)
    }

    @Test func octoIsKnownByItsProbeItsNameOrItsExtensions() {
        #expect(isOctoServer(probed: true, serverType: "navidrome", extensions: []))
        #expect(isOctoServer(probed: false, serverType: "Octo", extensions: []))
        #expect(isOctoServer(probed: false, serverType: nil, extensions: ["octoFamily:1"]))
        #expect(!isOctoServer(probed: false, serverType: "navidrome", extensions: ["songLyrics:1"]))
    }
}

@Suite struct ServerFormatTests {
    let hour: Int64 = 60 * 60 * 1_000
    var day: Int64 { 24 * hour }
    let english = Locale(identifier: "en_US")

    @Test func scanWords() {
        #expect(scanLabel(.idle) == "Scan library now")
        #expect(scanLabel(.scanning(count: 1234)) == "Scanning, 1,234 songs")
        #expect(scanLabel(.scanning(count: 0)) == "Scanning")
        #expect(scanLabel(.finished) == "Scan finished")
        #expect(scanLabel(.failed(message: "Only an admin can scan")) == "Only an admin can scan")
    }

    @Test func expiryWords() {
        let now = 10 * day
        #expect(expiryLabel(expiresAtMs: nil, nowMs: now) == "Never expires")
        #expect(expiryLabel(expiresAtMs: now - 1, nowMs: now) == "Expired")
        #expect(expiryLabel(expiresAtMs: now + hour / 2, nowMs: now) == "Expires within the hour")
        #expect(expiryLabel(expiresAtMs: now + 5 * hour, nowMs: now) == "Expires in 5 hours")
        #expect(expiryLabel(expiresAtMs: now + day, nowMs: now) == "Expires in 1 day")
        #expect(expiryLabel(expiresAtMs: now + 7 * day - hour, nowMs: now) == "Expires in 7 days")
    }

    @Test func shareLines() {
        let now: Int64 = 1_790_416_800_000
        let share: ServerShare = decoded(#"{"id":"sh1","url":"","description":"","expires":"2026-09-29T10:00:00Z","visitCount":12,"entry":[{"id":"s1","title":"Nightcall"},{"id":"s2","title":"Odd Look"}]}"#)
        #expect(shareTitle(share) == "Nightcall")
        #expect(shareDetails(share, nowMs: now) == "2 songs • Expires in 3 days • 12 visits")
        let bare: ServerShare = decoded(#"{"id":"sh2"}"#)
        #expect(shareTitle(bare) == "Shared link")
        #expect(shareDetails(bare, nowMs: now) == "Never expires • No visits")
        let busy: ServerShare = decoded(#"{"id":"sh3","visitCount":1234}"#)
        #expect(shareDetails(busy, nowMs: now) == "Never expires • 1,234 visits")
    }

    @Test func minutesAgoWords() {
        #expect(minutesAgo(0) == "Just now")
        #expect(minutesAgo(1) == "1 minute ago")
        #expect(minutesAgo(45) == "45 minutes ago")
        #expect(minutesAgo(90) == "1 hour ago")
        #expect(minutesAgo(200) == "3 hours ago")
    }

    @Test func streamAddresses() {
        #expect(isStreamAddress("https://stream.example/fip.mp3"))
        #expect(isStreamAddress(" http://192.168.50.21:8000/live "))
        #expect(!isStreamAddress("stream.example/fip.mp3"))
        #expect(!isStreamAddress(""))
        #expect(StationDraft(nil, "FIP", "https://stream.example/fip.mp3", "").ready)
        #expect(!StationDraft(nil, " ", "https://stream.example/fip.mp3", "").ready)
        #expect(!StationDraft(nil, "FIP", "https://stream.example/fip.mp3", "not a page").ready)
    }

    @Test func aListenerReadsAsSongThenWho() {
        let song: ServerNowPlaying = decoded(#"{"id":"s","title":"Song","artist":"","username":"sam","minutesAgo":3,"playerName":"Feishin"}"#)
        #expect(listenerTitle(song) == "Song")
        #expect(listenerLine(song) == "sam · Feishin · 3 minutes ago")
    }

    @Test func aStationSaysWhoseItIsOrWhereItStreams() {
        let added: ServerStationDetails = decoded(#"{"id":"r1","name":"FIP","coverArt":"ra-r1"}"#)
        #expect(stationLine(added, readOnly: true) == "Made by the server")
        let streamed: ServerStationDetails = decoded(#"{"id":"r","streamUrl":"https://stream.example:8000/live"}"#)
        #expect(stationLine(streamed, readOnly: false) == "stream.example")
        let odd: ServerStationDetails = decoded(#"{"id":"r","streamUrl":"rtsp-ish"}"#)
        #expect(stationLine(odd, readOnly: false) == "rtsp-ish")
    }

    @Test func whatASaveSends() {
        #expect(queueSaveParams(["a", "b"], currentIndex: 1, positionMs: -5, indexBased: true).map { "\($0.0)=\($0.1)" }
            == ["id=a", "id=b", "currentIndex=1", "position=0"])
        #expect(queueSaveParams(["a", "b"], currentIndex: 1, positionMs: 9, indexBased: false).map { "\($0.0)=\($0.1)" }
            == ["id=a", "id=b", "current=b", "position=9"])
        #expect(queueSaveParams([], currentIndex: 0, positionMs: 9, indexBased: false).isEmpty)
    }
}

@Suite struct QueueItemIdTests {
    @Test func aStationRoundTrips() {
        let id = radioId(streamUrl: "https://stream.example:8443/fip.mp3?type=http&x=1", name: "FIP: Jazz & more")
        #expect(isRadio(id))
        #expect(radioOf(id)?.stream == "https://stream.example:8443/fip.mp3?type=http&x=1")
        #expect(radioOf(id)?.name == "FIP: Jazz & more")
        #expect(radioSong(id)?.title == "FIP: Jazz & more")
        #expect(radioSong(id)?.artist == "Radio")
    }

    @Test func colonsAreEncodedSoThePartsSplitCleanly() {
        let id = radioId(streamUrl: "http://a:b@host:8000/live", name: "One: Two")
        #expect(id.dropFirst(radioPrefix.count).split(separator: ":", omittingEmptySubsequences: false).count == 2)
        #expect(radioId(streamUrl: "http://h/x y", name: "A B").hasSuffix(":A+B"))
    }

    @Test func theNameMayBeEmpty() {
        let id = radioId(streamUrl: " http://host/live ")
        #expect(radioOf(id)?.stream == "http://host/live")
        #expect(radioOf(id)?.name == "")
        #expect(radioSong(id)?.title == "http://host/live")
    }

    @Test func otherIdsAreNotStations() {
        #expect(!isRadio("find:abc"))
        #expect(radioOf("device:12") == nil)
        #expect(radioOf("radio::name") == nil)
    }

    @Test func aFileRoundTrips() {
        let uri = "content://com.example.files/document/primary%3AMusic%2FA%20song.flac"
        let id = openedFileId(uri: uri, title: "A song: live", artist: "The Band")
        #expect(isOpenedFile(id))
        #expect(openedFileOf(id) == OpenedFile(uri: uri, title: "A song: live", artist: "The Band"))
    }

    @Test func fileColonsAreEncoded() {
        let id = openedFileId(uri: "file:///sdcard/Music/x.mp3", title: "One: Two", artist: "Three: Four")
        #expect(id.dropFirst(openedFilePrefix.count).split(separator: ":", omittingEmptySubsequences: false).count == 3)
        #expect(openedFileOf(openedFileId(uri: " content://a/b ")) == OpenedFile(uri: "content://a/b", title: "", artist: ""))
        #expect(!isOpenedFile("radio:http%3A%2F%2Fhost:"))
        #expect(openedFileOf("find:abc") == nil)
        #expect(openedFileOf("file::title:artist") == nil)
        #expect(openedFileSong(openedFileId(uri: "file:///Music/Song.mp3"))?.title == "Song.mp3")
    }

    @Test func aNameLosesItsType() {
        #expect(titleFromName("A song.mp3") == "A song")
        #expect(titleFromName("v1.2 mix.flac") == "v1.2 mix")
        #expect(titleFromName("plain") == "plain")
        #expect(titleFromName(".mp3") == nil)
        #expect(titleFromName(nil) == nil)
    }
}

/// A value read from JSON, as a server would send it.
func decoded<T: Decodable>(_ json: String) -> T {
    do {
        return try JSONDecoder().decode(T.self, from: Data(json.utf8))
    } catch {
        fatalError("\(T.self) did not read: \(error)")
    }
}
