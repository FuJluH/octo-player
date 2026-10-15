import Foundation
import Testing
@testable import OctoKit

@Suite struct HlsFollowTests {
    let base = URL(string: "https://radio.example/live/index.m3u8")!

    func media(_ first: Int, count: Int, target: Double = 6, ended: Bool = false) -> HlsMedia {
        HlsMedia(targetSeconds: target, segments: (0..<count).map { HlsSegment(sequence: first + $0, uri: base, seconds: target) },
                 ended: ended, encrypted: false, fragmentedMp4: false)
    }

    func fetched(_ step: HlsStep) -> [Int] {
        if case .fetch(let segments, _) = step { return segments.map(\.sequence) }
        return []
    }

    @Test func aGrowingPlaylistIsFollowedAndReadAgainAfterATargetTime() {
        var follower = HlsFollower()
        let first = follower.step(media(10, count: 5), now: 0)
        #expect(first == .fetch(media(10, count: 5).segments.suffix(3).map { $0 }, reloadSeconds: 6))
        for segment in media(12, count: 3).segments { follower.fetched(segment) }
        // Nothing new yet: read again after half a target time.
        #expect(follower.step(media(10, count: 5), now: 6_000) == .fetch([], reloadSeconds: 3))
        #expect(fetched(follower.step(media(11, count: 5), now: 9_000)) == [15])
    }

    @Test func aPlaylistThatStopsGrowingStalls() {
        var follower = HlsFollower()
        for segment in media(1, count: 3).segments {
            _ = follower.step(media(1, count: 3), now: 0)
            follower.fetched(segment)
        }
        #expect(follower.step(media(1, count: 3), now: 17_999) == .fetch([], reloadSeconds: 3))
        #expect(follower.step(media(1, count: 3), now: 18_000) == .stalled)
        // Still stalled on every reading until it grows again.
        #expect(follower.step(media(1, count: 3), now: 20_000) == .stalled)
        #expect(fetched(follower.step(media(2, count: 3), now: 21_000)) == [4])
    }

    @Test func anEmptyLivePlaylistStallsTooAndAnEndedOneFinishes() {
        var follower = HlsFollower()
        #expect(follower.step(media(0, count: 0), now: 1_000) == .fetch([], reloadSeconds: 3))
        #expect(follower.step(media(0, count: 0), now: 19_000) == .stalled)
        var done = HlsFollower()
        let all = media(0, count: 2, ended: true)
        #expect(fetched(done.step(all, now: 0)) == [0, 1])
        for segment in all.segments { done.fetched(segment) }
        #expect(done.step(all, now: 1) == .finished)
    }

    @Test func aNumberingResetRejoinsAtTheLiveEdge() {
        var follower = HlsFollower()
        for segment in media(500, count: 3).segments { follower.fetched(segment) }
        #expect(fetched(follower.step(media(0, count: 6), now: 0)) == [3, 4, 5])
        #expect(follower.last == nil)
    }

    @Test func playlistNumbersNeverTrap() throws {
        let text = "#EXTM3U\n#EXT-X-TARGETDURATION:1e20\n#EXT-X-MEDIA-SEQUENCE:9223372036854775807\n#EXTINF:inf,\na.ts\n#EXTINF:10,\nb.ts\n"
        guard case .media(let held) = try #require(parseHlsPlaylist(text, base: base)) else {
            Issue.record("not a media playlist")
            return
        }
        #expect(held.targetSeconds == 60)
        #expect(held.segments.map(\.sequence) == [hlsSequenceCap, hlsSequenceCap + 1])
        #expect(held.segments[0].seconds == 0)
        var follower = HlsFollower()
        #expect(fetched(follower.step(held, now: 0)) == [hlsSequenceCap, hlsSequenceCap + 1])
        let tiny = "#EXTM3U\n#EXT-X-TARGETDURATION:0\n#EXTINF:1,\na.ts\n"
        guard case .media(let short) = try #require(parseHlsPlaylist(tiny, base: base)) else { return }
        #expect(short.targetSeconds == 1)
        let nan = "#EXTM3U\n#EXT-X-TARGETDURATION:nan\n#EXTINF:1,\na.ts\n"
        guard case .media(let unknown) = try #require(parseHlsPlaylist(nan, base: base)) else { return }
        #expect(unknown.targetSeconds == 6)
    }

    @Test func plainPlaylistsNameWholeStreams() {
        let streams = [URL(string: "https://radio.example/stream.mp3")!, URL(string: "https://backup.example/stream.mp3")!]
        #expect(parseHlsPlaylist("#EXTM3U\n#EXTINF:-1,Radio\nhttps://radio.example/stream.mp3\n", base: base) == .plain([streams[0]]))
        #expect(parseHlsPlaylist("#EXTM3U\nhttps://radio.example/stream.mp3\nhttps://backup.example/stream.mp3\n", base: base)
                == .plain(streams))
        #expect(parseHlsPlaylist("https://radio.example/stream.mp3\r\n", base: base) == .plain([streams[0]]))
        #expect(parseHlsPlaylist("#EXTM3U\n#EXT-X-TARGETDURATION:10\n#EXTINF:-1,\nlive.ts\n", base: base)
                == .plain([URL(string: "https://radio.example/live/live.ts")!]))
        #expect(parseHlsPlaylist("#EXTM3U\n", base: base) == nil)
    }

    @Test func aPlaylistIsSeenByItsFirstBytes() {
        #expect(startsLikePlaylist(Data("#EXTM3U\n#EXT-X-VERSION:3".utf8)))
        #expect(startsLikePlaylist(Data([0xEF, 0xBB, 0xBF]) + Data("\n #EXTM3U".utf8)))
        #expect(!startsLikePlaylist(Data([0xFF, 0xFB, 0x90, 0x64])))
        #expect(isHlsPlaylistType("Application/vnd.apple.mpegURL") && !isHlsPlaylistType("audio/mpeg") && !isHlsPlaylistType(nil))
    }

    @Test func aFormatChangeIsSeen() {
        let aac44Stereo = Data([0xFF, 0xF1, 0x50, 0x80, 0x01, 0x7F, 0xFC])
        let aac48Stereo = Data([0xFF, 0xF1, 0x4C, 0x80, 0x01, 0x7F, 0xFC])
        let aacFrameLater = Data([0x00, 0x12]) + aac44Stereo
        #expect(hlsSoundFormat(aac44Stereo, kind: .aac) != nil)
        #expect(hlsSoundFormat(aac44Stereo, kind: .aac) == hlsSoundFormat(aacFrameLater, kind: .aac))
        #expect(hlsSoundFormat(aac44Stereo, kind: .aac) != hlsSoundFormat(aac48Stereo, kind: .aac))
        let mp3 = Data([0xFF, 0xFB, 0x90, 0x64])
        #expect(hlsSoundFormat(mp3, kind: .mpeg) != nil && hlsSoundFormat(mp3, kind: .mpeg) != hlsSoundFormat(aac44Stereo, kind: .aac))
        #expect(hlsSoundFormat(Data([1, 2, 3, 4, 5]), kind: .aac) == nil)
    }
}

@Suite struct LiveReconnectTests {
    @Test func waitsGrowThenItFails() {
        var plan = LiveReconnect()
        #expect(plan.lost() == .again(after: 1))
        #expect(plan.lost() == .again(after: 2))
        #expect(plan.lost(status: 503) == .again(after: 4))
        #expect(plan.lost() == .again(after: 8))
        #expect(plan.lost() == .fail)
    }

    @Test func aGoodStretchStartsTheWaitsOver() {
        var plan = LiveReconnect()
        _ = plan.lost()
        _ = plan.lost()
        plan.connected()
        plan.heard(LiveReconnect.goodStretch - 1)
        #expect(plan.tries == 2)
        plan.heard(1)
        #expect(plan.tries == 0)
        #expect(plan.lost() == .again(after: 1))
        // A short burst on a new connection does not.
        plan.connected()
        plan.heard(1_000)
        #expect(plan.lost() == .again(after: 2))
        plan.recovered()
        #expect(plan.lost() == .again(after: 1))
    }

    @Test func aRefusalFailsAtOnce() {
        var plan = LiveReconnect()
        #expect(plan.lost(status: 404) == .fail)
        #expect(plan.lost(status: 403) == .fail)
        #expect(plan.lost(status: 429) == .again(after: 1))
        #expect(plan.lost(status: 408) == .again(after: 2))
    }
}

@Suite struct PlaceResolverTests {
    let austin = OctoPlace(code: "78701", name: "Austin", state: "TX", country: "US", latitude: 30.27, longitude: -97.74)

    func resolver(_ lookup: PlaceLookup, server: @escaping PlaceResolver.ServerAsk = { _ in nil },
                  phone: LockedBox<[String]> = LockedBox([])) -> PlaceResolver {
        PlaceResolver(lookup: lookup, server: server,
                      phoneTyped: { query in
                          phone.update { $0.append("typed \(query.params.map(\.1).joined(separator: " "))") }
                          return LivePlace(latitude: 52.523, longitude: 13.411, label: "", state: "Berlin", countryCode: "DE")
                      },
                      phoneNear: { place in
                          phone.update { $0.append("near \(place.latitude) \(place.longitude)") }
                          return LivePlace(latitude: place.latitude, longitude: place.longitude, label: "Austin, TX", state: "Texas",
                                           countryCode: "US")
                      })
    }

    @Test func theLookupFollowsTheServer() {
        #expect(PlaceLookup(extensions: ["octoPlaces:1"], reachable: true) == .server)
        #expect(PlaceLookup(extensions: ["octoPlaces:1"], reachable: false) == .serverUnreachable)
        #expect(PlaceLookup(extensions: ["octoFamily:1"], reachable: true) == .phone)
        #expect(PlaceLookup(extensions: [], reachable: false) == .phone)
    }

    @Test func aListedServerIsAskedAndThePhoneNever() async throws {
        let asked = LockedBox<[PlaceQuery]>([])
        let phone = LockedBox<[String]>([])
        let austin = austin
        let places = resolver(.server, server: { query in
            asked.update { $0.append(query) }
            return austin
        }, phone: phone)
        let typed = try await places.typed("78701", country: "US")
        #expect(typed == LivePlace(latitude: 30.27, longitude: -97.74, label: "Austin, TX", state: "Texas", countryCode: "US"))
        let here = await places.near(latitude: 30.26715, longitude: -97.74306)
        #expect(here.latitude == 30.27 && here.longitude == -97.74 && here.state == "Texas" && here.countryCode == "US")
        // Only the rounded coordinates are sent.
        #expect(asked.value == [.code("78701", country: "US"), .near(latitude: 30.27, longitude: -97.74)])
        #expect(asked.value.last?.params.map(\.1) == ["30.27", "-97.74"])
        #expect(phone.value.isEmpty)
    }

    @Test func aPlaceTheServerDoesNotKnowIsNotFound() async {
        let places = resolver(.server)
        await #expect(throws: PlaceProblem.notFound) { try await places.typed("Nowhere", country: "US") }
        // A location it cannot name is searched by radius alone.
        let here = await places.near(latitude: 30.26715, longitude: -97.74306)
        #expect(here == LivePlace(latitude: 30.27, longitude: -97.74, label: "Your location"))
    }

    @Test func aServerThatFailsIsUnreachableAndThePhoneIsNotAsked() async {
        let phone = LockedBox<[String]>([])
        let failing = resolver(.server, server: { _ in throw OctoError.http(502) }, phone: phone)
        await #expect(throws: PlaceProblem.serverUnreachable) { try await failing.typed("78701", country: "US") }
        #expect(await failing.near(latitude: 30.26715, longitude: -97.74306).state == "")
        let away = resolver(.serverUnreachable, server: { _ in
            Issue.record("asked a server that cannot be reached")
            return nil
        }, phone: phone)
        await #expect(throws: PlaceProblem.serverUnreachable) { try await away.typed("Austin, TX", country: "US") }
        #expect(await away.near(latitude: 30.26715, longitude: -97.74306) == LivePlace(latitude: 30.27, longitude: -97.74, label: "Your location"))
        #expect(phone.value.isEmpty)
    }

    @Test func withoutTheServerThePhoneIsAskedWithTheRoundedPlace() async throws {
        let phone = LockedBox<[String]>([])
        let places = resolver(.phone, server: { _ in
            Issue.record("asked a server without the look-up")
            return nil
        }, phone: phone)
        let typed = try await places.typed("Berlin", country: "DE")
        #expect(typed == LivePlace(latitude: 52.52, longitude: 13.41, label: "Berlin", state: "Berlin", countryCode: "DE"))
        let here = await places.near(latitude: 30.26715, longitude: -97.74306)
        #expect(here.label == "Austin, TX" && here.state == "Texas")
        #expect(phone.value == ["typed Berlin  DE", "near 30.27 -97.74"])
    }
}
