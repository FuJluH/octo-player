import Foundation
import Testing
@testable import OctoKit

/// Real metadata blocks, as stations sent them on 2026-10-13.
@Suite struct OnAirTests {
    let kiisSong = "StreamTitle='Ariana Grande - text=\"Petal\" song_spot=\"M\" MediaBaseId=\"3246947\" itunesTrackId=\"0\" "
        + "amgTrackId=\"-1\" amgArtistId=\"0\" TAID=\"0\" TPID=\"421089822\" cartcutId=\"0447960001\" "
        + "amgArtworkURL=\"https://i.iheart.com/v3/catalog/track/421089822?ops=fit(200,200),format(%22jpeg%22)\" "
        + "length=\"00:02:59\" unsID=\"-1\" spotInstanceId=\"-1\"';"
    let kiisSpot = "StreamTitle='LA's #1 Hit Music Station - text=\"102.7 KIIS FM\" song_spot=\"T\" MediaBaseId=\"0\" "
        + "itunesTrackId=\"0\" amgTrackId=\"0\" amgArtistId=\"0\" TAID=\"0\" TPID=\"0\" cartcutId=\"0\" amgArtworkURL=\"\" "
        + "length=\"00:00:00\" unsID=\"0\" spotInstanceId=\"-1\"';"
    let kiisLushLife = "StreamTitle='Zara Larsson - text=\"Lush Life\" song_spot=\"M\" MediaBaseId=\"2123647\" itunesTrackId=\"0\" "
        + "amgTrackId=\"-1\" amgArtistId=\"0\" TAID=\"883390\" TPID=\"45849925\" cartcutId=\"0886408001\" "
        + "amgArtworkURL=\"http://image.iheart.com/ihr-ingestion-pipeline-production-sbmg/A10301A00036327915_20190402040656160/45785635.20126.jpg\" "
        + "length=\"00:03:18\" unsID=\"-1\" spotInstanceId=\"-1\"';"

    func read(_ block: String, _ station: String) -> OnAir {
        let fields = icyFields(block)
        return onAir(fields["StreamTitle"], streamUrl: icyArtworkField(fields), station: station)
    }

    @Test func iHeartNamesTheSongItsArtistAndArtwork() {
        let air = read(kiisSong, "102.7 KIIS FM")
        #expect(air.title == "Petal")
        #expect(air.artist == "Ariana Grande")
        #expect(air.artwork == "https://i.iheart.com/v3/catalog/track/421089822?ops=fit(600,600),format(%22jpeg%22)")
        #expect(read(kiisLushLife, "102.7 KIIS FM") == OnAir("Lush Life", "Zara Larsson",
                                                             "http://image.iheart.com/ihr-ingestion-pipeline-production-sbmg/A10301A00036327915_20190402040656160/45785635.20126.jpg"))
    }

    @Test func anIHeartSpotThatIsNotMusicNamesNoSongButGivesTheTagline() {
        let air = read(kiisSpot, "102.7 KIIS FM")
        #expect(!air.named)
        #expect(air.artwork == "")
        #expect(air.tagline == "LA's #1 Hit Music Station")
    }

    @Test func aQuoteInsideAValueStaysInIt() {
        #expect(icyFields("StreamTitle='LA's #1 Hit Music Station - text=\"102.7 KIIS FM\"';")["StreamTitle"]
                == "LA's #1 Hit Music Station - text=\"102.7 KIIS FM\"")
        #expect(read("StreamTitle='AEROSMITH - I DON'T WANNA MISS A THING';", "538") == OnAir("I DON'T WANNA MISS A THING", "AEROSMITH"))
        #expect(read("StreamTitle='Riccardo Garzoni - Dick's Boogie';", "Swiss Jazz") == OnAir("Dick's Boogie", "Riccardo Garzoni"))
        // A block cut before its closing quote keeps what it has.
        #expect(icyFields("StreamTitle='It's on")["StreamTitle"] == "It's on")
        #expect(icyFields("StreamTitle='Dick's Boogie'")["StreamTitle"] == "Dick's Boogie")
    }

    @Test func aPlainTitleSplitsAtTheFirstDash() {
        #expect(read("StreamTitle='Portugal. The Man - Angoon';StreamUrl='http://img.radioparadise.com/covers/l/24684.jpg';", "Radio Paradise")
                == OnAir("Angoon", "Portugal. The Man", "http://img.radioparadise.com/covers/l/24684.jpg"))
        #expect(read("StreamTitle='Flo The Duchess - Dance Machine';", "NPO Radio2") == OnAir("Dance Machine", "Flo The Duchess"))
        #expect(read("StreamTitle='HUGEL & SOLTO  - Jamaican (Bam Bam)';", "538 Party") == OnAir("Jamaican (Bam Bam)", "HUGEL & SOLTO"))
        #expect(read("StreamTitle='Ice Cube - We Be Clubbin` (Clean Radio Edit) ';StreamUrl='';StreamArtwork='';", "181.FM Old School")
                == OnAir("We Be Clubbin` (Clean Radio Edit)", "Ice Cube"))
        #expect(onAir("Artist - Song - Part 2") == OnAir("Song - Part 2", "Artist"))
        #expect(read("StreamTitle='Kenny Loggins - Welcome To Heartlight';", "ANTENNE BAYERN") == OnAir("Welcome To Heartlight", "Kenny Loggins"))
        #expect(read("StreamTitle='KYGO & MAX MCNOWN - TAKE ME BACK';", "Radio 538") == OnAir("TAKE ME BACK", "KYGO & MAX MCNOWN"))
    }

    @Test func anImageStreamUrlIsTheArtwork() {
        let soma = read("StreamTitle='Reef Project - True Clown';StreamUrl='https://somafm.com/logos/512/groovesalad512.jpg';", "Groove Salad")
        #expect(soma == OnAir("True Clown", "Reef Project", "https://somafm.com/logos/512/groovesalad512.jpg"))
        // A web page is not artwork.
        #expect(read("StreamTitle='A - B';StreamUrl='https://station.example/now';", "X").artwork == "")
        #expect(read("StreamTitle='A - B';StreamArtwork='https://cdn.example/cover.png';", "X").artwork == "https://cdn.example/cover.png")
    }

    @Test func aTitleAloneIsATitle() {
        #expect(onAir("Interlude", station: "Some FM") == OnAir("Interlude"))
        #expect(onAir("Petal", station: "") == OnAir("Petal"))
        #expect(!onAir("Advertisement").named)
    }

    @Test func nothingIsNamedByEmptyPunctuationTheStationAdsOrCartCodes() {
        #expect(!onAir("").named)
        #expect(!onAir("   ").named)
        #expect(!onAir(nil as String?).named)
        #expect(!onAir(" - ").named)
        #expect(!onAir("NPO Radio2", station: "NPO Radio2").named)
        #expect(!onAir("npo radio 2", station: "NPO Radio 2").named)
        // KROQ between songs.
        #expect(!read("StreamTitle='- Advertisement';", "KROQ").named)
        // 181.FM's playout cart number.
        #expect(!read("StreamTitle='GWMR0446000';StreamUrl='';StreamArtwork='';", "181.FM").named)
        // A song whose name is in capitals is still a song.
        #expect(onAir("ABBA - SOS").named)
        #expect(onAir("U2").named)
    }

    @Test func iHeartTitleAndArtistKeys() {
        #expect(onAir("title=\"Blinding Lights\" artist=\"The Weeknd\" url=\"x\"", station: "Some FM") == OnAir("Blinding Lights", "The Weeknd"))
        // A text that is only the station's name is no song.
        #expect(!onAir("text=\"102.7 KIIS FM\" song_spot=\"M\"", station: "102.7 KIIS FM").named)
    }

    @Test func iHeartArtworkIsAskedForAtThePlayersSize() {
        #expect(sharperArtwork("https://i.iheart.com/v3/catalog/track/1?ops=fit(200,200),format(%22jpeg%22)")
                == "https://i.iheart.com/v3/catalog/track/1?ops=fit(600,600),format(%22jpeg%22)")
        #expect(sharperArtwork("https://i.iheart.com/x?ops=fit(1000,1000)") == "https://i.iheart.com/x?ops=fit(1000,1000)")
        #expect(sharperArtwork("https://cdn.example/fit(200,200).jpg") == "https://cdn.example/fit(200,200).jpg")
        #expect(sharperArtwork("http://image.iheart.com/a/b.jpg") == "http://image.iheart.com/a/b.jpg")
    }

    @Test func fieldsReadEveryKeyOnce() {
        let fields = icyFields("StreamTitle='A - B';StreamUrl='';StreamArtwork='';\u{0}\u{0}")
        #expect(fields == ["StreamTitle": "A - B", "StreamUrl": "", "StreamArtwork": ""])
        #expect(icyFields("") == [:])
        #expect(icyArtworkField(fields) == nil)
    }
}

@Suite struct LivePlayerTests {
    let kiis = LiveStation(
        uuid: "u-kiis",
        name: "102.7 KIIS FM",
        streamUrl: "https://stream.revma.ihrhls.com/zc185",
        favicon: "https://i.iheart.com/v3/re/assets.brands/2ebe?ops=new(),fit(100,100)",
        codec: "AAC",
        bitrate: 128,
        country: "The United States Of America",
        countryCode: "US",
        state: "California",
        tags: ["pop", "top 40"],
        homepage: "https://kiisfm.iheart.com/")

    @Test func aStationsDetailsRideInItsId() {
        let id = kiis.radioId()
        #expect(radioOf(id)?.stream == kiis.streamUrl)
        #expect(radioOf(id)?.name == kiis.name)
        #expect(!radioIsHls(id))
        let details = radioDetailsOf(id)
        #expect(details.logo == kiis.favicon)
        #expect(details.codec == "AAC")
        #expect(details.bitrate == 128)
        #expect(details.state == "California")
        #expect(details.tags == ["pop", "top 40"])
        #expect(details.uuid == "u-kiis")
        #expect(details.homepage == "https://kiisfm.iheart.com/")
        var hlsStation = kiis
        hlsStation.hls = true
        let hls = hlsStation.radioId()
        #expect(radioIsHls(hls))
        #expect(radioDetailsOf(hls).logo == kiis.favicon)
        #expect(radioSong(hls)?.contentType == hlsPlaylistTypes[0])
        #expect(radioSong(id)?.contentType == nil)
    }

    @Test func aCatalogStationComesBackFromItsIdForKeeping() throws {
        let back = try #require(liveStationOf(kiis.radioId()))
        #expect(back.uuid == kiis.uuid && back.name == kiis.name && back.streamUrl == kiis.streamUrl)
        #expect(back.favicon == kiis.favicon && back.codec == "AAC" && back.bitrate == 128 && back.tags == kiis.tags)
        #expect(back.state == "California" && back.countryCode == "US" && !back.hls)
        #expect(back.homepage == "https://kiisfm.iheart.com/")
        // The server's own stations and old ids are not the catalog's.
        #expect(liveStationOf(radioId("http://h/s", "Mine")) == nil)
        #expect(liveStationOf("song-1") == nil)
    }

    @Test func oldIdsReadWithNoDetails() {
        #expect(radioDetailsOf(radioId("http://host/live", "Name")) == RadioDetails())
        #expect(radioDetailsOf(radioId("http://host/live", "Name", hls: true)) == RadioDetails())
        #expect(radioIsHls(radioId("http://host/live", "Name", hls: true)))
        #expect(radioDetailsOf("find:abc") == RadioDetails())
        // No details makes the id it always was.
        #expect(radioId("http://host/live", "Name") == radioId("http://host/live", "Name", details: RadioDetails()))
        #expect(radioId("http://host/live", "Name") == "radio:http%3A%2F%2Fhost%2Flive:Name")
        #expect(radioOf("radio:http%3A%2F%2Fhost%2Flive:Name")?.name == "Name")
    }

    @Test func detailsWithEveryOddCharacterRoundTrip() {
        let details = RadioDetails(logo: "https://x/a.png?a=1&b=2:3", homepage: "https://x/?q=a&b", tags: ["r&b", "hip-hop"])
        let id = radioId("http://h/s", "A: B & C", details: details)
        #expect(radioDetailsOf(id) == details)
        #expect(radioOf(id)?.stream == "http://h/s")
        #expect(radioOf(id)?.name == "A: B & C")
    }

    @Test func aServerStationsCoverRidesInItsId() {
        let id = radioId(streamUrl: "http://h/s", name: "Mine", details: RadioDetails(coverArt: "ra-12", homepage: "https://mine.example"))
        #expect(radioSong(id)?.coverArt == "ra-12")
        #expect(radioDetailsOf(id).homepage == "https://mine.example")
    }

    @Test func theLineupStepsThroughTheListAndStopsAtTheEnds() throws {
        let ids = ["radio:a:A", "radio:b:B", "radio:c:C"]
        let first = try #require(liveLineup(ids, current: 0))
        #expect(first.shows)
        #expect(!first.hasPrevious)
        #expect(first.previous == nil)
        #expect(first.next == 1)
        let last = try #require(liveLineup(ids, current: 2))
        #expect(last.previous == 1)
        #expect(!last.hasNext)
        #expect(last.next == nil)
        let middle = try #require(liveLineup(ids, current: 1))
        #expect(middle.previous == 0)
        #expect(middle.next == 2)
    }

    @Test func aStationAloneHasNoBackOrNext() throws {
        let one = try #require(liveLineup(["radio:a:A"], current: 0))
        #expect(!one.shows)
        #expect(one.next == nil)
        #expect(one.previous == nil)
        // A station among songs stands alone.
        let mixed = try #require(liveLineup(["song1", "radio:a:A", "song2"], current: 1))
        #expect(!mixed.shows)
        #expect(liveLineup(["song1"], current: 0) == nil)
        #expect(liveLineup([], current: 0) == nil)
    }

    @Test func aListBecomesALineupWithEachStreamOnce() {
        var dupe = kiis
        dupe.uuid = "dupe"
        dupe.streamUrl = "http://stream.revma.ihrhls.com/zc185/"
        var other = kiis
        other.uuid = "b"
        other.streamUrl = "https://b/live"
        let stations = [kiis, dupe, other]
        let (ids, index) = lineupOf(stations, tapped: 2, stream: \.streamUrl, id: { $0.radioId() })
        #expect(ids.count == 2)
        #expect(index == 1)
        #expect(lineupOf(stations, tapped: 1, stream: \.streamUrl, id: { $0.radioId() }).index == 0)
    }

    @Test func theLinesUnderTheTitle() {
        let details = kiis.radioDetails()
        #expect(liveSubtitle(OnAir("Petal", "Ariana Grande"), station: "102.7 KIIS FM", details: details) == "Ariana Grande · 102.7 KIIS FM")
        #expect(liveSubtitle(OnAir("Petal"), station: "102.7 KIIS FM", details: details) == "102.7 KIIS FM")
        #expect(liveSubtitle(OnAir(tagline: "LA's #1 Hit Music Station"), station: "102.7 KIIS FM", details: details) == "LA's #1 Hit Music Station")
        #expect(liveSubtitle(.nothing, station: "102.7 KIIS FM", details: details) == "California, The United States Of America · Pop")
        #expect(liveSubtitle(.nothing, station: "X", details: RadioDetails(countryCode: "NL")) == "NL")
        #expect(liveSubtitle(.nothing, station: "X", details: RadioDetails()) == liveRadioLine)
        #expect(liveTitle(OnAir("Petal", "Ariana Grande"), station: "102.7 KIIS FM", streamUrl: "u") == "Petal")
        #expect(liveTitle(.nothing, station: "102.7 KIIS FM", streamUrl: "u") == "102.7 KIIS FM")
        #expect(liveTitle(.nothing, station: "", streamUrl: "http://h/s") == "http://h/s")
    }

    @Test func whatTheLivePlayerShows() throws {
        let shown = try #require(liveShown(kiis.radioId(),
                                           streamTitle: "Ariana Grande - text=\"Petal\" song_spot=\"M\" amgArtworkURL=\"https://i.iheart.com/v3/catalog/track/421089822\""))
        #expect(shown.title == "Petal")
        #expect(shown.subtitle == "Ariana Grande · 102.7 KIIS FM")
        #expect(shown.cover == "https://i.iheart.com/v3/catalog/track/421089822")
        let between = try #require(liveShown(kiis.radioId(),
                                             streamTitle: "LA's #1 Hit Music Station - text=\"102.7 KIIS FM\" song_spot=\"T\" amgArtworkURL=\"\""))
        #expect(between.title == "102.7 KIIS FM")
        #expect(between.subtitle == "LA's #1 Hit Music Station")
        #expect(between.cover == kiis.favicon)
        #expect(liveShown(radioId("http://h/s", "Plain"), streamTitle: nil)?.cover == "")
        #expect(liveShown("song-1", streamTitle: "A - B") == nil)
        // The whole real block, as the reader hands it on.
        let meta = try #require(icyMeta(Data(OnAirTests().kiisSong.utf8)))
        let read = try #require(liveShown(kiis.radioId(), meta))
        #expect(read.title == "Petal")
        #expect(read.onAir.artist == "Ariana Grande")
        // A station that stops naming a song shows its own name again.
        #expect(liveShown(kiis.radioId(), IcyMeta(title: ""))?.title == "102.7 KIIS FM")
    }

    @Test func theCodecPill() {
        #expect(liveCodecLine(RadioDetails(codec: "aac", bitrate: 128)) == "AAC 128 kbps")
        #expect(liveCodecLine(RadioDetails(codec: "MP3")) == "MP3")
        #expect(liveCodecLine(RadioDetails(codec: "UNKNOWN")) == "")
        #expect(liveCodecLine(RadioDetails(bitrate: 64)) == "64 kbps")
    }

    @Test func howLongTheListenerHasBeenOn() {
        #expect(listenedFor(0) == "0:00")
        #expect(listenedFor(42_900) == "0:42")
        #expect(listenedFor((12 * 60 + 4) * 1_000) == "12:04")
        #expect(listenedFor((3_600 + 2 * 60 + 3) * 1_000) == "1:02:03")
        #expect(listenedFor(-5) == "0:00")
    }

    func lib(_ id: String, _ title: String, _ artist: String) -> HeartCandidate { HeartCandidate(id: id, title: title, artist: artist, inLibrary: true) }
    func outside(_ id: String, _ title: String, _ artist: String) -> HeartCandidate {
        HeartCandidate(id: id, title: title, artist: artist, inLibrary: false)
    }

    @Test func theHeartFindsTheSongOnAir() {
        let petal = OnAir("Petal", "Ariana Grande")
        #expect(heartMatch(petal, [lib("1", "Petal", "Ariana Grande")])?.id == "1")
        #expect(heartMatch(petal, [lib("1", "petal", "ARIANA GRANDE")])?.id == "1")
        #expect(heartQuery(petal) == "Ariana Grande Petal")
        // A library song wins over the same song from outside.
        #expect(heartMatch(petal, [outside("out", "Petal", "Ariana Grande"), lib("lib", "Petal", "Ariana Grande")])?.id == "lib")
        // Only outside: that one.
        #expect(heartMatch(petal, [outside("out", "Petal", "Ariana Grande")])?.id == "out")
    }

    @Test func featuredArtistsAndPunctuationDoNotStopAMatch() {
        #expect(heartMatch(OnAir("TAKE ME BACK", "KYGO & MAX MCNOWN"), [lib("k", "Take Me Back", "Kygo & Max McNown")])?.id == "k")
        #expect(heartMatch(OnAir("Take Me Back", "KYGO & MAX MCNOWN"), [lib("k", "Take Me Back", "Kygo & Max McNown")])?.id == "k")
        #expect(heartMatch(OnAir("Die With A Smile (feat. Bruno Mars)", "Lady Gaga"), [lib("g", "Die With A Smile", "Lady Gaga, Bruno Mars")])?.id == "g")
        #expect(heartMatch(OnAir("Lush Life", "Zara Larsson feat. Nobody"), [lib("z", "Lush Life", "Zara Larsson")])?.id == "z")
        #expect(heartMatch(OnAir("We Be Clubbin'", "Ice Cube"), [lib("w", "We Be Clubbin", "Ice Cube")])?.id == "w")
        #expect(heartMatch(OnAir("Angoon", "Portugal. The Man"), [lib("p", "Angoon", "Portugal The Man")])?.id == "p")
    }

    @Test func nearMissesNeverMatch() {
        let petal = OnAir("Petal", "Ariana Grande")
        #expect(heartMatch(petal, [lib("r", "Petal (Remix)", "Ariana Grande")]) == nil)
        #expect(heartMatch(petal, [lib("l", "Petal (Live)", "Ariana Grande")]) == nil)
        #expect(heartMatch(petal, [lib("o", "Petal", "Ariana Greenblatt")]) == nil)
        #expect(heartMatch(petal, [lib("t", "Petals", "Ariana Grande")]) == nil)
        #expect(heartMatch(petal, [lib("x", "Positions", "Ariana Grande")]) == nil)
        #expect(heartMatch(OnAir("Lush Life", "Zara Larsson"), [lib("c", "Lush Life", "Some Cover Band")]) == nil)
        // No artist named: a title alone is never enough.
        #expect(heartMatch(OnAir("Petal"), [lib("1", "Petal", "Ariana Grande")]) == nil)
        #expect(heartMatch(.nothing, [lib("1", "Petal", "Ariana Grande")]) == nil)
        #expect(heartMatch(petal, []) == nil)
        // The near miss is passed over for the song itself.
        #expect(heartMatch(petal, [lib("r", "Petal (Remix)", "Ariana Grande"), outside("o", "Petal", "Ariana Grande")])?.id == "o")
    }

    @Test func aSongOnAirIsLookedUpUnderItsArtistAndTitle() {
        #expect(liveLookupKey(OnAir("Petal", "Ariana Grande")) == liveLookupKey(OnAir("petal ", "ARIANA  GRANDE")))
        #expect(liveLookupKey(OnAir("Petal", "Ariana Grande")) != liveLookupKey(OnAir("Petal", "Ariana Greenblatt")))
        #expect(liveLookupKey(.nothing) == "")
        #expect(liveLookupKey(OnAir(tagline: "LA's #1 Hit Music Station")) == "")
    }

    @Test func theLookupCacheAnswersARepeatAndForgetsTheOldest() {
        var cache = LiveLookupCache<String>(capacity: 2)
        cache.keep(.found("1"), for: "a")
        cache.keep(.notFound, for: "b")
        if case .found(let id) = cache["a"] { #expect(id == "1") } else { Issue.record("a was not kept") }
        if case .notFound = cache["b"] {} else { Issue.record("b's empty answer was not kept") }
        cache.keep(.found("3"), for: "c")
        #expect(cache["a"] == nil)
        #expect(cache.count == 2)
        cache.keep(.found("x"), for: "")
        #expect(cache.count == 2)
    }

    @Test func theCoverOrderIsOctoThenArtworkThenLogoThenServer() throws {
        let shown = try #require(liveShown(kiis.radioId(),
                                           streamTitle: "Ariana Grande - text=\"Petal\" song_spot=\"M\" amgArtworkURL=\"https://i.iheart.com/a.jpg\""))
        #expect(liveCoverSources(octo: ("al-1", false), shown: shown, serverCover: nil)
                == [.octo(coverArt: "al-1", online: false), .artwork("https://i.iheart.com/a.jpg"), .logo(kiis.favicon)])
        #expect(liveCoverSources(octo: nil, shown: shown, serverCover: "ra-1") == [.artwork("https://i.iheart.com/a.jpg"), .logo(kiis.favicon), .server("ra-1")])
        let plain = try #require(liveShown(radioId("http://h/s", "Plain"), streamTitle: nil))
        #expect(liveCoverSources(octo: nil, shown: plain, serverCover: nil).isEmpty)
    }

    @Test func aLiveStationsLockScreenHasNoSeekingAndStepsThroughItsList() {
        let ids = ["radio:a:A", "radio:b:B", "radio:c:C"]
        let first = RemoteButtons.of(ids, current: 0)
        #expect(first.live)
        #expect(!first.showsDuration)
        #expect(!first.seek && !first.changePosition && !first.skipInterval)
        #expect(first.next && !first.previous)
        let last = RemoteButtons.of(ids, current: 2)
        #expect(!last.next && last.previous)
        let middle = RemoteButtons.of(ids, current: 1)
        #expect(middle.next && middle.previous)
        let alone = RemoteButtons.of(["radio:a:A"], current: 0)
        #expect(alone.live && !alone.next && !alone.previous)
        // Stop, never Pause: Pause and Play/Pause are off, Stop is on and lets go of the stream.
        #expect(!first.pause && !first.togglePlayPause && first.stop && first.stopDoes == .stopStream)
        #expect(!alone.pause && !alone.togglePlayPause && alone.stop && alone.stopDoes == .stopStream)
        let song = RemoteButtons.of(["s1", "s2"], current: 0)
        #expect(song.pause && song.togglePlayPause && song.stop && song.stopDoes == .close)
        // A station among songs is still live: Stop, not Pause.
        let mixed = RemoteButtons.of(["s1", "radio:a:A"], current: 1)
        #expect(mixed.live && !mixed.pause && mixed.stopDoes == .stopStream && !mixed.next && !mixed.previous)
        #expect(!song.live && song.showsDuration && song.seek && song.changePosition && song.next && song.previous)
    }
}
