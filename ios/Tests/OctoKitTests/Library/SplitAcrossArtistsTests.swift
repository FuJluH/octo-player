import Foundation
import Testing
@testable import OctoKit

/// Albums split across album artists: one album filed under each of the artists it is credited
/// to, and the albums of one name that only look like that.
@Suite struct SplitAcrossArtistsTests {
    final class Songs {
        private var next = 0

        /// A song as Navidrome lists it: its credited artists, its album artist and the album id
        /// the server gave its part.
        func song(_ title: String, _ artist: String, _ album: String, _ albumId: String, albumArtist: String? = nil,
                  year: Int? = nil, track: Int? = nil, artists: [String]? = nil, id: String? = nil) -> ServerSong {
            let shownId = id ?? "s\(next)"
            if id == nil { next += 1 }
            let albumBy = albumArtist ?? artist
            return ServerSong(id: shownId, title: title, album: album, albumId: albumId, artist: artist, track: track, year: year,
                              duration: 200, suffix: "flac", displayAlbumArtist: albumBy,
                              artists: (artists ?? [artist]).map { ArtistRef(name: $0) }, albumArtists: [ArtistRef(name: albumBy)])
        }
    }

    let make = Songs()

    private func splits(_ songs: [ServerSong], _ fields: HealthFields<ServerSong> = serverSongHealth) -> [SplitAlbum<ServerSong>] {
        findSplitAlbums(songs, fields)
    }

    /// The library as the live server had it on 2026-10-04: PARTYNEXTDOOR's 15 songs (one of them,
    /// NOKIA, by Drake), Drake's five with no year or track, and Pimmie's interlude, each under its
    /// own album artist.
    let title = "$ome $exy $ongs 4 U"

    private var partynextdoor: [ServerSong] {
        ["CELIBACY", "CN TOWER", "DEEPER", "DIE TRYING", "GLORIOUS", "GREEDY", "LASERS", "MEET YOUR PADRE",
         "MOTH BALLS", "OMW", "SOMEBODY LOVES ME", "SOMETHING ABOUT YOU", "SPIDER-MAN SUPERMAN", "WHEN HE'S GONE"]
            .map { make.song($0, "PARTYNEXTDOOR", title, "08qrDbXNlx9NTxtgugKes1", year: 2025) }
            + [make.song("NOKIA", "Drake", title, "08qrDbXNlx9NTxtgugKes1", albumArtist: "PARTYNEXTDOOR", year: 2025, track: 14, id: "nokia")]
    }

    private var drake: [ServerSong] {
        ["BRIAN STEEL", "CRYING IN CHANEL", "GIMME A HUG", "RAINING IN HOUSTON", "SMALL TOWN FAME"]
            .map { make.song($0, "Drake", title, "3jmLzEVlwtrlq8XfVjei9k") }
    }

    private var pimmie: [ServerSong] { [make.song("PIMMIE'S DILEMMA", "Pimmie", title, "5SHl4krFWPwjViGmMeA0TB")] }

    @Test func aCollaborationAlbumFiledUnderEachArtistIsOneAlbum() throws {
        let all = splits(partynextdoor + drake + pimmie)
        #expect(all.count == 1)
        let found = try #require(all.first)
        #expect(found.parts.map(\.albumId) == ["08qrDbXNlx9NTxtgugKes1", "3jmLzEVlwtrlq8XfVjei9k"])
        #expect(found.parts.map(\.songs.count) == [15, 5])
        #expect(found.artist == "PARTYNEXTDOOR")
        #expect(found.reasons == [SplitReason(.sharedArtist, artist: "Drake", other: "PARTYNEXTDOOR", song: "NOKIA")])
        #expect(found.heading == "\(title) by PARTYNEXTDOOR, shown as 2 albums")
        #expect(found.summary == "One album filed under two artists: the part by PARTYNEXTDOOR has NOKIA by Drake. "
            + "The album artist differs: PARTYNEXTDOOR, Drake. The year differs: 2025, none.")
    }

    @Test func joiningItGivesDrakesSongsTheLargerPartsAlbumArtist() throws {
        let drakeSongs = drake
        let join = albumJoin(try #require(splits(partynextdoor + drakeSongs).first))
        #expect(Set(join.moving.map(\.id)) == Set(drakeSongs.map(\.id)))
        #expect(join.lead.albumId == "08qrDbXNlx9NTxtgugKes1")
        #expect(join.steps(serverSongHealth).allSatisfy { step in
            if case .joinAlbum(_, _, let like) = step { return like == join.lead.id }
            return false
        })
        #expect(join.words == "Moves 5 songs onto \(title), the part with 15 songs. Their album artist becomes PARTYNEXTDOOR.")
    }

    @Test func aPartWithNothingTyingItToTheOthersIsLeftAlone() {
        #expect(splits(partynextdoor + pimmie).isEmpty)
    }

    @Test func aCreditNamingBothArtistsLeadsTheJoin() throws {
        let both = ["Big Rings", "Diamonds Dancing"].map {
            make.song($0, "Drake & Future", "What a Time to Be Alive", "both", year: 2015, artists: ["Drake", "Future"])
        }
        let future = ["Digital Dash", "Live From the Gutter", "Jumpman", "Scholarships", "30 for 30 Freestyle"]
            .map { make.song($0, "Future", "What a Time to Be Alive", "future", year: 2015) }
        let found = try #require(splits(both + future).first)
        let join = albumJoin(found)
        #expect(found.parts.map(\.albumId) == ["both", "future"])
        #expect(found.reasons == [SplitReason(.sharedArtist, artist: "Future", other: "Drake & Future")])
        #expect(found.reasons.first?.words == "One album filed under two artists: the part by Drake & Future names Future too.")
        #expect(join.words == "Moves 5 songs onto What a Time to Be Alive, the part with 2 songs, since its album artist names every part's artist. "
            + "Their album artist becomes Drake & Future.")
    }

    // MARK: Albums of one name that are not one album

    @Test func aTitleManyArtistsUseIsNeverJoinedOnACreditAlone() {
        let found = splits([
            make.song("Bohemian Rhapsody", "Queen", "Greatest Hits", "queen"),
            make.song("Under Pressure", "Queen & David Bowie", "Greatest Hits", "queen", albumArtist: "Queen", artists: ["Queen", "David Bowie"]),
            make.song("Heroes", "David Bowie", "Greatest Hits", "bowie"),
            make.song("Under Pressure", "Queen & David Bowie", "Greatest Hits", "bowie", albumArtist: "David Bowie", artists: ["Queen", "David Bowie"]),
            make.song("One More Time", "Daft Punk", "Live", "daft"),
            make.song("Harder Better Faster Stronger", "Daft Punk", "Live", "daft"),
            make.song("Get Lucky", "Daft Punk feat. Pharrell Williams", "Live", "pharrell", albumArtist: "Pharrell Williams",
                      artists: ["Daft Punk", "Pharrell Williams"]),
            make.song("Untitled 01", "Kendrick Lamar", "Untitled", "kendrick"),
            make.song("Untitled 02", "Kendrick Lamar & SZA", "Untitled", "sza", albumArtist: "SZA", artists: ["Kendrick Lamar", "SZA"]),
        ])
        #expect(found.isEmpty)
    }

    @Test func anAlbumNamedAfterItsArtistIsNeverJoinedOnACreditAlone() {
        let found = splits([
            make.song("Enter Sandman", "Metallica", "Metallica", "black"),
            make.song("Nothing Else Matters", "Metallica", "Metallica", "black"),
            make.song("Nothing Else Matters", "Apocalyptica & Metallica", "Metallica", "tribute", albumArtist: "Apocalyptica",
                      artists: ["Apocalyptica", "Metallica"]),
        ])
        #expect(found.isEmpty)
    }

    @Test func aCreditDoesNotJoinAlbumsOfOneNameFromDifferentYears() {
        let found = splits([
            make.song("A Case of You", "Joni Mitchell", "Blue", "joni", year: 1971),
            make.song("River", "Joni Mitchell", "Blue", "joni", year: 1971),
            make.song("Blue", "LeAnn Rimes", "Blue", "leann", year: 1996),
            make.song("River", "LeAnn Rimes & Joni Mitchell", "Blue", "leann", albumArtist: "LeAnn Rimes", year: 1996,
                      artists: ["LeAnn Rimes", "Joni Mitchell"]),
        ])
        #expect(found.isEmpty)
    }

    @Test func albumsOfOneNameByArtistsWithNothingInCommonStayApart() {
        let found = splits([
            make.song("A Case of You", "Joni Mitchell", "Blue", "joni"),
            make.song("Semi-Charmed Life", "Third Eye Blind", "Blue", "third-eye-blind"),
            make.song("Blue", "LeAnn Rimes", "Blue", "leann"),
        ])
        #expect(found.isEmpty)
    }

    @Test func aDeluxeEditionByAnotherCreditIsAnotherAlbum() {
        let found = splits([
            make.song("God's Plan", "Drake", "Scorpion", "standard", year: 2018),
            make.song("Nonstop", "Drake", "Scorpion", "standard", year: 2018),
            make.song("In My Feelings", "Drake & City Girls", "Scorpion (Deluxe)", "deluxe", albumArtist: "City Girls", year: 2018,
                      artists: ["Drake", "City Girls"]),
        ])
        #expect(found.isEmpty)
    }

    // MARK: Codes and labels the parts share

    /// The songs' fields with release facts by album id.
    private func facts(releases: [String: String] = [:], groups: [String: String] = [:], barcodes: [String: String] = [:],
                       labels: [String: String] = [:]) -> HealthFields<ServerSong> {
        var fields = serverSongHealth
        fields.releaseId = { $0.albumId.flatMap { releases[$0] } }
        fields.releaseGroupId = { $0.albumId.flatMap { groups[$0] } }
        fields.barcode = { $0.albumId.flatMap { barcodes[$0] } }
        fields.labels = { song in song.albumId.flatMap { labels[$0] }.map { [$0] } ?? [] }
        return fields
    }

    /// A soundtrack filed under its composer on one part and its performer on the other: nothing
    /// in the credits ties them.
    private var score: [ServerSong] {
        [make.song("Time", "Hans Zimmer", "Inception", "zimmer", year: 2010),
         make.song("Dream Is Collapsing", "Hans Zimmer", "Inception", "zimmer", year: 2010),
         make.song("Old Souls", "Lorne Balfe", "Inception", "balfe", year: 2010)]
    }

    @Test func theSameReleaseOrReleaseGroupJoinsParts() throws {
        let byRelease = try #require(splits(score, facts(releases: ["zimmer": "A1B2C3D4-0000-4000-8000-000000000001",
                                                                    "balfe": "a1b2c3d4-0000-4000-8000-000000000001"])).first)
        let byGroup = try #require(splits(score, facts(groups: ["zimmer": "5b5f2a1e-1111-4111-8111-111111111111",
                                                                "balfe": "5b5f2a1e-1111-4111-8111-111111111111"])).first)
        #expect(byRelease.parts.map(\.albumId) == ["zimmer", "balfe"])
        #expect(byRelease.reasons.first?.words == "The parts are tagged as the same MusicBrainz release.")
        #expect(byGroup.reasons.first?.words == "The parts are tagged as the same MusicBrainz release group.")
    }

    @Test func aBarcodeWrittenAsUpcOrEanJoinsParts() {
        let found = splits(score, facts(barcodes: ["zimmer": "093624966126", "balfe": "0093624966126"]))
        #expect(found.first?.reasons.first?.words == "The parts carry the same barcode, 93624966126.")
    }

    @Test func theSameLabelJoinsPartsOnlyInTheSameYear() {
        let labels = ["zimmer": "Reprise Records", "balfe": "Reprise Records"]
        let found = splits(score, facts(labels: labels))
        let unknownYear = splits(score.map { song in
            var copy = song
            if song.albumId == "balfe" { copy.year = nil }
            return copy
        }, facts(labels: labels))
        let otherLabel = splits(score, facts(labels: ["zimmer": "Reprise Records", "balfe": "WaterTower Music"]))
        #expect(found.first?.reasons.first?.words == "The parts came out on the same label in the same year: Reprise Records, 2010.")
        #expect(unknownYear.isEmpty)
        #expect(otherLabel.isEmpty)
    }

    @Test func aCodeNeverJoinsPartsFromDifferentYears() {
        let years = score.map { song in
            var copy = song
            if song.albumId == "balfe" { copy.year = 2020 }
            return copy
        }
        #expect(splits(years, facts(groups: ["zimmer": "g", "balfe": "g"])).isEmpty)
    }

    @Test func theServersAlbumListGivesTheReleaseAndLabel() throws {
        let albums = [HealthAlbumFacts(id: "zimmer", musicBrainzId: "r1", labels: ["Reprise Records"]),
                      HealthAlbumFacts(id: "balfe", musicBrainzId: "r1")]
        let songs = score
        let found = try #require(checkLibrary(songs, serverAlbumHealth(albums)).splitAlbums.first)
        #expect(found.reasons.first?.basis == .sameRelease)
        #expect(serverAlbumHealth(albums).labels(songs[0]) == ["Reprise Records"])
    }

    @Test func partsByOneAlbumArtistNeedNoReason() throws {
        let found = try #require(splits([
            make.song("Angel", "Massive Attack", "Mezzanine", "a", year: 1998),
            make.song("Teardrop", "Massive Attack", "Mezzanine", "b", year: 1998),
        ]).first)
        #expect(found.reasons.isEmpty)
        #expect(found.summary == "Something else in the tags differs, often a release date or an album id on only some songs.")
    }
}
