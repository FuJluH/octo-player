import Foundation
import Testing
@testable import OctoKit

@Suite struct CopiesTest {
    func copy(_ id: String, _ source: String, _ mime: String?, bitrate: Int? = nil, sampleRate: Int? = nil, bitDepth: Int? = nil,
              size: Int? = nil, ms: Int = 240_000) -> SongCopy {
        SongCopy(id: id, sourceId: source, nativeId: id, uri: "content://media/\(id)", mimeType: mime, sizeBytes: size, bitrate: bitrate,
                 sampleRate: sampleRate, bitDepth: bitDepth, durationMs: ms)
    }

    /// A 4-minute phone MP3 of 7.68 MB works out to 256 kbps.
    var phoneMp3: SongCopy { copy("p", "device", "audio/mpeg", size: 7_680_000) }
    var phoneFlac: SongCopy { copy("p", "device", "audio/flac", size: 30_000_000) }
    var serverFlac: SongCopy { copy("s", "server:music.example", "audio/flac", bitrate: 900, sampleRate: 44_100, bitDepth: 16) }
    var serverMp3: SongCopy { copy("s", "server:music.example", "audio/mpeg", bitrate: 320) }

    @Test func phoneFirstPlaysThePhoneCopy() {
        #expect(chooseCopy([serverFlac, phoneMp3], .phoneFirst, serverReachable: true)?.id == "p")
    }

    @Test func phoneFirstStreamsWhenThePhoneFileIsGone() {
        #expect(chooseCopy([phoneMp3, serverFlac], .phoneFirst, serverReachable: true) { $0.id == "p" }?.id == "s")
    }

    @Test func bestQualityStreamsTheBetterServerCopy() {
        #expect(chooseCopy([phoneMp3, serverFlac], .bestQuality, serverReachable: true)?.id == "s")
    }

    @Test func bestQualityPlaysThePhoneCopyWhenTheServerIsOutOfReach() {
        #expect(chooseCopy([phoneMp3, serverFlac], .bestQuality, serverReachable: false)?.id == "p")
    }

    @Test func bestQualityKeepsThePhoneCopyWhenItIsBetter() {
        #expect(chooseCopy([serverMp3, phoneFlac], .bestQuality, serverReachable: true)?.id == "p")
    }

    @Test func aTieGoesToThePhone() {
        let server = copy("s", "server:music.example", "audio/mpeg", bitrate: 256)
        #expect(chooseCopy([server, phoneMp3], .bestQuality, serverReachable: true)?.id == "p")
    }

    @Test func aServerOnlySongIsStillHandedOverWhenOffline() {
        #expect(chooseCopy([serverFlac], .phoneFirst, serverReachable: false)?.id == "s")
    }

    @Test func noCopiesMeansNothingToPlay() {
        #expect(chooseCopy([], .bestQuality, serverReachable: true) == nil)
    }

    @Test func losslessBeatsAHigherBitrate() {
        #expect(compareQuality(serverFlac, copy("a", "device", "audio/mpeg", bitrate: 1_411_000)) == 1)
    }

    @Test func higherSampleRateThenDeeperBitsWin() {
        let hiRes = copy("h", "server:x", "audio/flac", bitrate: 900, sampleRate: 96_000, bitDepth: 16)
        let deep = copy("d", "server:x", "audio/flac", bitrate: 900, sampleRate: 44_100, bitDepth: 24)
        #expect(compareQuality(hiRes, serverFlac) == 1)
        #expect(compareQuality(deep, serverFlac) == 1)
        #expect(compareQuality(hiRes, deep) == 1)
    }

    @Test func unknownFactsAreSkippedForTheBitrate() {
        #expect(compareQuality(copy("p", "device", "audio/flac", size: 90_000_000), serverFlac) == 1)
    }

    @Test func bitrateIsEstimatedFromSizeAndLength() {
        #expect(bitrateOf(phoneMp3) == 256_000)
        #expect(bitrateOf(copy("x", "device", "audio/mpeg")) == nil)
    }

    @Test func serverBitratesInKilobitsAreReadAsSuch() {
        #expect(bitrateOf(serverMp3) == 320_000)
        #expect(bitrateOf(copy("x", "server:x", "audio/mpeg", bitrate: 320_000)) == 320_000)
    }

    @Test func originalAsksForTheFileAsItIs() {
        let request = streamRequest("audio/flac", 900_000, .original)
        #expect(request.params.map { "\($0.0)=\($0.1)" } == ["format=raw"])
        #expect(request.mimeType("audio/flac") == "audio/flac")
    }

    @Test func aSmallerSizeMakesAnMp3() {
        let request = streamRequest("audio/flac", 900_000, .mp3(kbps: 192))
        #expect(request.params.map { "\($0.0)=\($0.1)" } == ["format=mp3", "maxBitRate=192", "estimateContentLength=true"])
        #expect(request.mimeType("audio/flac") == "audio/mpeg")
    }

    @Test func aLossyFileWithinTheSizePlaysAsItIs() {
        #expect(streamRequest("audio/mp4", 128_000, .mp3(kbps: 192)) == StreamRequest(nil))
        #expect(streamRequest("audio/mp4", 256_000, .mp3(kbps: 192)) == StreamRequest(192))
        #expect(streamRequest("audio/mpeg", nil, .mp3(kbps: 192)) == StreamRequest(192))
    }

    @Test func aFileThePhoneCannotOpenComesAsAnMp3() {
        #expect(phoneRequest("audio/ogg", 160_000, .original) == StreamRequest(320))
        #expect(phoneRequest("audio/ogg", 160_000, .mp3(kbps: 192)) == StreamRequest(192))
        #expect(phoneRequest("audio/flac", 900_000, .original) == StreamRequest(nil))
        #expect(phoneRequest(nil, nil, .original) == StreamRequest(nil))
    }

    @Test func theBadgeReadsTheTranscodedStream() {
        let mime = streamRequest("audio/flac", 900_000, .mp3(kbps: 192)).mimeType("audio/flac")
        #expect(audioQuality(codecMime: nil, fileMime: mime, bitDepth: nil, sampleRate: nil, bitrate: nil)?.full == "MP3")
        let open = audioQuality(codecMime: "audio/mpeg", fileMime: mime, bitDepth: 16, sampleRate: 44_100, bitrate: 192_000)!
        #expect(open.label == "MP3")
        #expect(open.full == "MP3 · 192 kbps")
    }

    var downloaded: SongCopy { downloadedCopy(serverFlac, uri: "file:///music/Octo/song.flac", format: "audio/flac", sizeBytes: 30_000_000) }

    @Test func aDownloadPlaysBeforeTheStream() {
        for preference in CopyPreference.allCases {
            let picked = chooseCopy([serverFlac], download: downloaded, streamInstead: false, preference, serverReachable: true)
            #expect(picked?.uri == "file:///music/Octo/song.flac", "\(preference)")
        }
    }

    @Test func aDownloadPlaysWithNoConnection() {
        let picked = chooseCopy([serverFlac], download: downloaded, streamInstead: true, .phoneFirst, serverReachable: false)
        #expect(picked?.uri == "file:///music/Octo/song.flac")
    }

    @Test func preferringStreamsOnWifiStreamsEvenWhenDownloaded() {
        #expect(chooseCopy([serverFlac], download: downloaded, streamInstead: true, .phoneFirst, serverReachable: true)?.id == "s")
    }

    @Test func aPhoneFileStillComesFirstWhenThereIsOne() {
        #expect(chooseCopy([serverFlac, phoneMp3], download: downloaded, streamInstead: false, .phoneFirst, serverReachable: true)?.id == "p")
        let best = chooseCopy([serverFlac, phoneMp3], download: downloaded, streamInstead: false, .bestQuality, serverReachable: true)
        #expect(best?.id == downloaded.id)
    }

    @Test func withoutADownloadNothingChanges() {
        #expect(chooseCopy([serverFlac, phoneMp3], download: nil, streamInstead: false, .bestQuality, serverReachable: true)?.id == "s")
    }

    @Test func aDownloadIsACopyOnThePhone() {
        #expect(!downloaded.isServerCopy)
        #expect(downloaded.sourceId == downloadSource)
        #expect(downloaded.bitDepth == serverFlac.bitDepth)
        let small = downloadedCopy(serverFlac, uri: "file:///music/Octo/song.mp3", format: "audio/mpeg", sizeBytes: 5_760_000)
        #expect(small.mimeType == "audio/mpeg")
        #expect(small.bitDepth == nil)
        #expect(bitrateOf(small) == 192_000)
    }

    @Test func theTempoComesFromThePlayingCopyOrAnyOther() {
        var phone = phoneMp3
        phone.bpm = 0
        var server = serverFlac
        server.bpm = 128
        #expect(songBpm(phone, [phone, server]) == 128)
        var faster = phone
        faster.bpm = 96
        #expect(songBpm(faster, [phone, server]) == 96)
        #expect(songBpm(nil, [phone, server]) == 128)
        #expect(songBpm(phone, [phone]) == nil)
    }

    @Test func onlyASensibleStoredTempoReachesTheAnalysis() {
        #expect(tagBpm(128) == 128)
        #expect(tagBpm(0) == nil)
        #expect(tagBpm(-5) == nil)
        #expect(tagBpm(nil) == nil)
    }
}

@Suite struct StreamRefTest {
    let flac = StreamRef(sourceId: "server:music.example", serverId: "tr-42", mimeType: "audio/flac", bitrate: 900_000)
    let mp3 = StreamRef(sourceId: "server:music.example", serverId: "tr-7", mimeType: "audio/mpeg", bitrate: 256_000)

    @Test func aSongReadsBackAsItWasWritten() {
        #expect(parseStreamUri(streamUri(flac)) == flac)
        let pinned = flac.pin(StreamRequest(192))
        #expect(parseStreamUri(streamUri(pinned)) == pinned)
        let raw = flac.pin(StreamRequest(nil))
        #expect(parseStreamUri(streamUri(raw)) == raw)
    }

    @Test func oddIdsAndServersSurviveTheAddress() {
        let odd = StreamRef(sourceId: "server:host:4533", serverId: "a/b c+d&e=f", mimeType: "audio/x-flac", bitrate: nil)
        #expect(parseStreamUri(streamUri(odd)) == odd)
        let bare = StreamRef(sourceId: nil, serverId: "123", mimeType: nil, bitrate: nil)
        #expect(parseStreamUri(streamUri(bare)) == bare)
    }

    @Test func anythingElseIsNotAServerSong() {
        #expect(parseStreamUri("content://media/external/audio/media/12") == nil)
        #expect(parseStreamUri("file:///storage/Music/Octo/song.flac") == nil)
        #expect(parseStreamUri("https://music.example/rest/stream?id=1") == nil)
        #expect(parseStreamUri("octo-stream://album/1") == nil)
        #expect(parseStreamUri("not a uri at all") == nil)
    }

    @Test func theKeyNamesTheSongNeverTheSignedAddress() {
        let key = streamCacheKey("server:music.example", flac, StreamRequest(nil))
        #expect(key == "server:music.example|tr-42|audio/flac|raw")
        #expect(streamCacheKey("server:music.example", flac, StreamRequest(192)) == "server:music.example|tr-42|audio/flac|192")
        #expect(streamCacheKey("server:music.example", parseStreamUri(streamUri(flac))!, StreamRequest(nil)) == key)
        #expect(!(key.contains("salt") || key.contains("token") || key.contains("http")))
    }

    @Test func eachServerTypeAndRequestIsItsOwnCopy() {
        let raw = StreamRequest(nil)
        let base = streamCacheKey("server:a", flac, raw)
        #expect(base != streamCacheKey("server:b", flac, raw))
        var other = flac
        other.mimeType = "audio/mpeg"
        #expect(base != streamCacheKey("server:a", other, raw))
        #expect(base != streamCacheKey("server:a", flac, StreamRequest(320)))
        var otherSong = flac
        otherSong.serverId = "tr-43"
        #expect(base != streamCacheKey("server:a", otherSong, raw))
    }

    @Test func variantsRunFromTheFileAsItIsDownToTheSmallestMp3() {
        #expect(requestVariants(flac) == [StreamRequest(nil), StreamRequest(320), StreamRequest(256), StreamRequest(192), StreamRequest(128)])
        #expect(requestVariants(mp3) == [StreamRequest(nil), StreamRequest(192), StreamRequest(128)])
    }

    @Test func theConnectionsSizeIsAskedForWhenNothingIsSaved() {
        #expect(chooseRequest("server:a", flac, .mp3(kbps: 192), fullySaved: { _ in false }) == StreamRequest(192))
        #expect(chooseRequest("server:a", flac, .original, fullySaved: { _ in false }) == StreamRequest(nil))
    }

    @Test func aWholeSavedCopyInAnotherSizePlaysInstead() {
        let saved: Set = [streamCacheKey("server:a", flac, StreamRequest(nil))]
        #expect(chooseRequest("server:a", flac, .mp3(kbps: 128), fullySaved: { saved.contains($0) }) == StreamRequest(nil))
    }

    @Test func theWantedSizeWinsWhenItIsSavedToo() {
        let saved: Set = [streamCacheKey("server:a", flac, StreamRequest(nil)), streamCacheKey("server:a", flac, StreamRequest(128))]
        #expect(chooseRequest("server:a", flac, .mp3(kbps: 128), fullySaved: { saved.contains($0) }) == StreamRequest(128))
    }

    @Test func aSongStartedInOneSizeKeepsItWhenTheConnectionChanges() {
        let started: Set = [streamCacheKey("server:a", flac, StreamRequest(nil))]
        #expect(chooseRequest("server:a", flac, .mp3(kbps: 192), fullySaved: { _ in false }, partlySaved: { started.contains($0) }) == StreamRequest(nil))
    }

    @Test func aPinnedRequestIsNeverChanged() {
        let pinned = flac.pin(StreamRequest(256))
        #expect(chooseRequest("server:a", pinned, .original, fullySaved: { _ in true }) == StreamRequest(256))
        #expect(pinned.request(.original) == StreamRequest(256))
        #expect(flac.request(.mp3(kbps: 128)) == StreamRequest(128))
    }
}

/// Which quality a stream asks for: the phone's own on Wi-Fi or mobile data, unless a family
/// account leaves it to the server.
@Suite struct StreamQualityForTest {
    let prefs = StreamPrefs(wifi: .mp3(kbps: 320), mobile: .mp3(kbps: 128))

    @Test func withoutAFamilyTheConnectionDecides() {
        #expect(streamQualityFor(appPicks: true, onMobile: false, prefs: prefs) == .mp3(kbps: 320))
        #expect(streamQualityFor(appPicks: true, onMobile: true, prefs: prefs) == .mp3(kbps: 128))
    }

    @Test func aPhoneThatFollowsItsAccountAsksForTheFileAsItIs() {
        #expect(streamQualityFor(appPicks: false, onMobile: false, prefs: prefs) == .original)
        #expect(streamQualityFor(appPicks: false, onMobile: true, prefs: prefs) == .original)
    }

    @Test func aPhoneLeftToTheAppUsesItsOwnSettings() {
        let picks = AccountQualityWords.appPicksQuality(familyOn: true, follows: .app)
        #expect(streamQualityFor(appPicks: picks, onMobile: false, prefs: prefs) == .mp3(kbps: 320))
        #expect(streamQualityFor(appPicks: picks, onMobile: true, prefs: prefs) == .mp3(kbps: 128))
    }

    @Test func theAppPicksQualityOnlyWithoutAFamilyOrWhenLeftToIt() {
        #expect(AccountQualityWords.appPicksQuality(familyOn: false, follows: nil))
        #expect(AccountQualityWords.appPicksQuality(familyOn: false, follows: .account))
        #expect(AccountQualityWords.appPicksQuality(familyOn: true, follows: .app))
        #expect(!AccountQualityWords.appPicksQuality(familyOn: true, follows: .account))
        #expect(!AccountQualityWords.appPicksQuality(familyOn: true, follows: nil))
        // Following the account, the phone asks for the file as it is.
        #expect(streamQualityFor(appPicks: false, onMobile: true, prefs: StreamPrefs(wifi: .mp3(kbps: 96), mobile: .mp3(kbps: 96))) == .original)
    }

    @Test func originalIsTheDefaultOnWifiAndMobileData() {
        let prefs = StreamPrefs()
        #expect(prefs.wifi == .original)
        #expect(prefs.mobile == .original)
        #expect(StreamQuality.choices.first == .original)
        #expect(StreamQuality.stored("Kbps256", or: .original) == .mp3(kbps: 256))
        #expect(StreamQuality.stored("Huge", or: .original) == .original)
        #expect(StreamQuality.choices.map(\.storedName) == ["Original", "Kbps320", "Kbps256", "Kbps192", "Kbps128"])
    }

    @Test func originalSendsNoTranscodeAsk() {
        #expect(streamRequest("audio/flac", 900_000, .original).params.map(\.0) == ["format"])
        #expect(streamRequest("audio/flac", 900_000, .original).mimeType("audio/flac") == "audio/flac")
    }
}

@Suite struct QualityTest {
    @Test func theOutputsRateShowsOnlyWhenItDiffers() {
        let hiRes = audioQuality(codecMime: "audio/flac", fileMime: nil, bitDepth: 24, sampleRate: 96_000, bitrate: 0)!
        #expect(hiRes.playingAt(48_000).full == "FLAC · 24-bit · 96 kHz · plays at 48 kHz")
        #expect(hiRes.playingAt(96_000).full == "FLAC · 24-bit · 96 kHz")
        #expect(hiRes.playingAt(nil).full == "FLAC · 24-bit · 96 kHz")
    }

    @Test func cdQualityFlacIsLossless() {
        let quality = audioQuality(codecMime: "audio/flac", fileMime: "audio/flac", bitDepth: 16, sampleRate: 44_100, bitrate: nil)!
        #expect(quality.label == "Lossless")
        #expect(quality.full == "FLAC · 16-bit · 44.1 kHz")
    }

    @Test func above48KilohertzIsHiRes() {
        let quality = audioQuality(codecMime: "audio/flac", fileMime: "audio/flac", bitDepth: 24, sampleRate: 96_000, bitrate: nil)!
        #expect(quality.label == "Hi-Res")
        #expect(quality.full == "FLAC · 24-bit · 96 kHz")
    }

    @Test func twentyFourBitAt48IsStillLossless() {
        let quality = audioQuality(codecMime: "audio/flac", fileMime: "audio/flac", bitDepth: 24, sampleRate: 48_000, bitrate: nil)!
        #expect(quality.label == "Lossless")
        #expect(quality.full == "FLAC · 24-bit · 48 kHz")
    }

    @Test func lossyShowsItsCodecAndBitrate() {
        let quality = audioQuality(codecMime: "audio/mpeg", fileMime: "audio/mpeg", bitDepth: nil, sampleRate: 44_100, bitrate: 320_000)!
        #expect(quality.label == "MP3")
        #expect(quality.full == "MP3 · 320 kbps")
    }

    @Test func lossyWithoutBitrateShowsSampleRate() {
        let quality = audioQuality(codecMime: "audio/opus", fileMime: "audio/ogg", bitDepth: nil, sampleRate: 48_000, bitrate: nil)!
        #expect(quality.label == "Opus")
        #expect(quality.full == "Opus · 48 kHz")
    }

    @Test func beforeTheDecoderReportsTheFileTypeIsUsed() {
        let quality = audioQuality(codecMime: nil, fileMime: "audio/flac", bitDepth: nil, sampleRate: nil, bitrate: nil)!
        #expect(quality.label == "Lossless")
        #expect(quality.full == "FLAC")
    }

    @Test func unknownTypeHasNoBadge() {
        #expect(audioQuality(codecMime: nil, fileMime: "audio/x-unknown", bitDepth: nil, sampleRate: nil, bitrate: nil) == nil)
    }

    @Test func thePlayersMeasureWinsOnceItHasOne() {
        #expect(songLengthMs(listedMs: 296_000, playerMs: 291_000) == 291_000)
        #expect(songLengthMs(listedMs: 296_000, playerMs: nil) == 296_000)
        #expect(songLengthMs(listedMs: 0, playerMs: nil) == 0)
        #expect(songLengthMs(listedMs: 296_000, playerMs: 0) == 296_000)
    }

    @Test func aCorrectedListingReachesEveryRowOfTheSong() {
        let lengths = RealLengths()
        lengths.learn("find:a", listedMs: 296_000, playerMs: 291_000)
        #expect(songLengthMs(listedMs: lengths.lengthMs("find:a", listedMs: 296_000), playerMs: nil) == 291_000)
        #expect(songLengthMs(listedMs: lengths.lengthMs("t-1", listedMs: 200_000), playerMs: nil) == 200_000)
    }
}

@Suite struct ItemIdsTest {
    @Test func aStationRoundTrips() {
        let id = radioId("https://stream.example:8443/fip.mp3?type=http&x=1", "FIP: Jazz & more")
        #expect(isRadio(id))
        let back = radioOf(id)
        #expect(back?.stream == "https://stream.example:8443/fip.mp3?type=http&x=1")
        #expect(back?.name == "FIP: Jazz & more")
    }

    @Test func colonsAreEncodedSoThePartsSplitCleanly() {
        let id = radioId("http://a:b@host:8000/live", "One: Two")
        #expect(id.dropFirst(radioPrefix.count).split(separator: ":", omittingEmptySubsequences: false).count == 2)
    }

    @Test func theNameMayBeEmpty() {
        let back = radioOf(radioId(" http://host/live "))
        #expect(back?.stream == "http://host/live")
        #expect(back?.name == "")
    }

    @Test func otherIdsAreNotStations() {
        #expect(!isRadio("find:abc"))
        #expect(!isRadio("device:12"))
        #expect(radioOf("device:12") == nil)
        #expect(radioOf("radio::name") == nil)
    }

    @Test func aFileRoundTrips() {
        let uri = "content://com.example.files/document/primary%3AMusic%2FA%20song.flac"
        let id = openedFileId(uri, "A song: live", "The Band")
        #expect(isOpenedFile(id))
        #expect(openedFileOf(id) == OpenedFile(uri: uri, title: "A song: live", artist: "The Band"))
    }

    @Test func fileColonsAreEncodedSoThePartsSplitCleanly() {
        let id = openedFileId("file:///sdcard/Music/x.mp3", "One: Two", "Three: Four")
        #expect(id.dropFirst(openedFilePrefix.count).split(separator: ":", omittingEmptySubsequences: false).count == 3)
    }

    @Test func theTitleAndArtistMayBeEmpty() {
        #expect(openedFileOf(openedFileId(" content://a/b ")) == OpenedFile(uri: "content://a/b", title: "", artist: ""))
    }

    @Test func otherIdsAreNotFiles() {
        #expect(!isOpenedFile("radio:http%3A%2F%2Fhost:"))
        #expect(!isOpenedFile("device:12"))
        #expect(openedFileOf("find:abc") == nil)
        #expect(openedFileOf("file::title:artist") == nil)
    }

    @Test func theChosenSongIsFoundByItsPlace() {
        #expect(chosenStart(["a", "b", "a"], 2) == 2)
        #expect(chosenStart([nil, "a", nil, "b"], 3) == 1)
        #expect(chosenStart(["a", nil, "b"], 1) == 0)
        #expect(chosenStart(["a", "b"], 5) == 0)
    }

    @Test func aFindPlaysAsTheLibrarySongItBecame() {
        let library: Set = ["server:octo:dAti9", "server:octo:cEi8R"]
        #expect(playsAs(findId: "find:huntin", adoptedId: "server:octo:cEi8R", library: library) == "server:octo:cEi8R")
        #expect(playsAs(findId: "find:huntin", adoptedId: "", library: library) == "find:huntin")
        #expect(playsAs(findId: "find:huntin", adoptedId: "server:octo:gone", library: library) == "find:huntin")
    }
}

@Suite struct CarIdsTest {
    func roundTrip(_ node: CarNode) { #expect(parseCarId(carId(node)) == node) }

    @Test func everyNodeReadsBackAsItself() {
        for node in [CarNode.root, .recent, .playlists, .albums, .artists, .liked, .mostPlayed,
                     .album("device:album:12"), .artist("device:artist:4"), .playlist("3f2a-uuid")] {
            roundTrip(node)
        }
    }

    @Test func aSongKeepsTheListItWasFoundIn() {
        roundTrip(.song(trackId: "device:4054", list: .album("device:album:12")))
        roundTrip(.song(trackId: "device:4054", list: .playlist("3f2a-uuid")))
        roundTrip(.song(trackId: "device:4054", list: .liked))
        roundTrip(.song(trackId: "device:4054", list: .mostPlayed))
        roundTrip(.song(trackId: "device:4054", list: nil))
    }

    @Test func theAppsOwnSongIdsAreNotCarIds() { #expect(parseCarId("device:4054") == nil) }

    @Test func playingStartsAtTheChosenSongOrTheTop() {
        let list = ["a", "b", "c"]
        #expect(startIndex(list, "b") == 1)
        #expect(startIndex(list, "gone") == 0)
        #expect(startIndex(list, nil) == 0)
    }
}

@Suite struct NotificationHeartTest {
    let liked: Set = ["t1"]

    @Test func aLibrarySongShowsItsHeart() {
        #expect(notificationHeart("t1", liked: liked, downloads: [:]) == .like(liked: true))
        #expect(notificationHeart("t2", liked: liked, downloads: [:]) == .like(liked: false))
    }

    @Test func aSongFoundOnlineOffersADownloadUntilOneIsAskedFor() {
        #expect(notificationHeart("find:9", liked: liked, downloads: [:]) == .download)
        #expect(notificationHeart("find:9", liked: liked, downloads: ["find:9": .requested]) == .none)
        #expect(notificationHeart("find:9", liked: liked, downloads: ["find:9": .done]) == .none)
    }

    @Test func aStationOrNothingPlayingShowsNeither() {
        #expect(notificationHeart("radio:x", liked: liked, downloads: [:]) == .none)
        #expect(notificationHeart(nil, liked: liked, downloads: [:]) == .none)
    }
}
