import Foundation
import Testing
@testable import OctoKit

/// Every case in the library health cases, the file the Octo server runs too against its own
/// port of these checks. The songs are written as a Subsonic server answers them, so they are read
/// here as the app reads a server's songs. A failure names the case, and every failing case is
/// listed, not only the first.
@Suite struct LibraryHealthCasesTests {
    typealias Object = [String: Any]

    private var cases: [Object] {
        let data = Data(libraryHealthCasesJSON.utf8)
        let root = (try? JSONSerialization.jsonObject(with: data)) as? Object
        return root?["cases"] as? [Object] ?? []
    }

    @Test func theFileHasEveryCase() {
        let all = cases
        #expect(all.count == 56)
        #expect(Set(all.compactMap { $0["name"] as? String }).count == all.count)
    }

    @Test func everyCaseReportsWhatTheFileSays() {
        let failures = cases.flatMap(run)
        #expect(failures.isEmpty, "\(failures.count) failing:\n\(failures.joined(separator: "\n"))")
    }

    // MARK: Reading the file

    private static func text(_ value: Any?) -> String? {
        switch value {
        case let text as String: text
        case let number as NSNumber: number.stringValue
        default: nil
        }
    }

    private static func strings(_ value: Any?) -> [String] { (value as? [Any] ?? []).compactMap(text) }

    /// Strings in pairs or threes: [["a3", "year", "1998"], ...].
    private static func rows(_ value: Any?) -> [[String?]] { (value as? [[Any]] ?? []).map { $0.map(text) } }

    private static func decode<T: Decodable>(_ type: T.Type, _ value: Any) -> T? {
        guard let data = try? JSONSerialization.data(withJSONObject: value) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func tag(_ name: String) -> HealthTag? {
        switch name {
        case "Genre": .genre
        case "Year": .year
        case "AlbumArtist": .albumArtist
        case "TrackNumber": .trackNumber
        case "Cover": .cover
        default: nil
        }
    }

    private static func name(_ tag: HealthTag) -> String {
        switch tag {
        case .genre: "Genre"
        case .year: "Year"
        case .albumArtist: "AlbumArtist"
        case .trackNumber: "TrackNumber"
        case .cover: "Cover"
        }
    }

    private static func name(_ basis: DuplicateBasis) -> String { basis == .tags ? "Tags" : "TitleAndLength" }

    private static func name(_ reason: BestReason) -> String {
        switch reason {
        case .sound: "Sound"
        case .tags: "Tags"
        case .none: "None"
        }
    }

    private static func name(_ basis: SplitBasis) -> String {
        switch basis {
        case .sharedArtist: "SharedArtist"
        case .sameRelease: "SameRelease"
        case .sameReleaseGroup: "SameReleaseGroup"
        case .sameBarcode: "SameBarcode"
        case .sameLabelAndYear: "SameLabelAndYear"
        }
    }

    private static func name(_ kind: AlbumDifference) -> String {
        switch kind {
        case .title: "Title"
        case .albumArtist: "AlbumArtist"
        case .year: "Year"
        case .other: "Other"
        }
    }

    /// The server's song fields with what a case adds: release facts by album id, the server's
    /// album list, places by song id, and the tags the reader keeps.
    private func fields(_ test: Object) -> HealthFields<ServerSong> {
        let albums = (test["albums"] as? [Any]).flatMap { Self.decode([HealthAlbumFacts].self, $0) }
        let base = albums.map(serverAlbumHealth) ?? serverSongHealth
        var fields = base
        let facts = test["facts"] as? Object
        let places = test["places"] as? Object
        func fact(_ kind: String, _ song: ServerSong) -> String? {
            Self.text((facts?[kind] as? Object)?[song.albumId ?? ""])
        }
        if facts != nil {
            fields.releaseId = { fact("releases", $0) }
            fields.labels = { song in fact("labels", song).map { [$0] } ?? [] }
        }
        fields.releaseGroupId = { fact("releaseGroups", $0) }
        fields.barcode = { fact("barcodes", $0) }
        fields.place = { Self.text(places?[$0.id]) ?? "" }
        if let seen = test["seen"] { fields.seen = Set(Self.strings(seen).compactMap(Self.tag)) }
        return fields
    }

    /// What went wrong in one case.
    private final class Failures {
        let name: String
        var found: [String] = []

        init(_ name: String) { self.name = name }

        func check<V: Equatable>(_ what: String, _ expected: V, _ actual: V) {
            if expected != actual { found.append("\(name): \(what) expected \(expected), got \(actual)") }
        }

        /// The same number of things, before each is checked.
        func sameCount(_ what: String, _ expected: Int, _ actual: Int) -> Bool {
            check("\(what) count", expected, actual)
            return expected == actual
        }
    }

    // MARK: Running a case

    private func run(_ test: Object) -> [String] {
        let failed = Failures(Self.text(test["name"]) ?? "?")
        let songs = (test["songs"] as? [Any] ?? []).compactMap { Self.decode(ServerSong.self, $0) }
        let fields = fields(test)
        let report = checkLibrary(songs, fields)
        let expect = test["expect"] as? Object ?? [:]

        if let sets = expect["duplicates"] as? [Object], failed.sameCount("duplicates", sets.count, report.duplicates.count) {
            for (i, set) in sets.enumerated() { checkSet(failed, "duplicates[\(i)]", set, report.duplicates[i], fields) }
        }
        if let splits = expect["splitAlbums"] as? [Object], failed.sameCount("splitAlbums", splits.count, report.splitAlbums.count) {
            for (i, split) in splits.enumerated() { checkSplit(failed, "splitAlbums[\(i)]", split, report.splitAlbums[i], fields) }
        }
        if let missing = expect["missing"] as? Object {
            for (name, titles) in missing {
                let found = Self.tag(name).flatMap { report.missing[$0] } ?? []
                failed.check("missing \(name)", Self.strings(titles), found.map(\.title))
            }
        }
        if let absent = expect["missingAbsent"] {
            for name in Self.strings(absent) {
                failed.check("missing \(name) present", false, Self.tag(name).map { report.missing[$0] != nil } ?? false)
            }
        }
        if let keys = expect["missingKeys"] {
            let shown = HealthTag.allCases.filter { report.missing[$0] != nil }.map(Self.name)
            failed.check("missing tags", Set(Self.strings(keys)), Set(shown))
        }
        if let songsOf = expect["songsOf"] as? Object {
            for (check, titles) in songsOf {
                let found = HealthCheck(rawValue: check).map { report.songs($0).map(\.title) } ?? []
                failed.check("songs of \(check)", Self.strings(titles), found)
            }
        }
        if let noLength = expect["noLength"] { failed.check("noLength", Self.strings(noLength), report.noLength.map(\.title)) }
        if let findings = expect["findings"] { failed.check("findings", Self.strings(findings), report.findings.map(\.rawValue)) }
        if let counts = expect["counts"] as? Object {
            for (check, count) in counts {
                failed.check("count of \(check)", (count as? Int) ?? -1, HealthCheck(rawValue: check).map(report.count) ?? -2)
            }
        }
        if let overview = expect["overview"] { failed.check("overview", Self.text(overview), report.overview) }
        if let without = expect["without"] as? Object {
            let after = report.without(Set(Self.strings(without["ids"])), fields: fields)
            failed.check("duplicates after removing", (without["duplicates"] as? Int) ?? -1, after.duplicates.count)
            for (check, ids) in without["songsOf"] as? Object ?? [:] {
                let found = HealthCheck(rawValue: check).map { after.songs($0).map(\.id) } ?? []
                failed.check("songs of \(check) after removing", Self.strings(ids), found)
            }
        }
        if let fix = expect["fix"] as? Object, failed.sameCount("duplicates to fix", 1, report.duplicates.count) {
            checkFix(failed, fix, report.duplicates[0], fields)
        }
        if let fills = expect["fillsFromAlbum"] as? Object, let tag = Self.text(fills["tag"]).flatMap(Self.tag) {
            let wanting: [ServerSong]
            if let ids = fills["missing"] {
                let wanted = Set(Self.strings(ids))
                wanting = songs.filter { wanted.contains($0.id) }
            } else {
                wanting = report.missing[tag] ?? []
            }
            let found = fillsFromAlbum(wanting, all: songs, tag: tag, fields)
            failed.check("fills from album", Self.rows(fills["fills"]), found.map { [$0.0.id, $0.1.tag, $0.1.value] as [String?] })
        }
        return failed.found
    }

    private func checkSet(_ failed: Failures, _ at: String, _ expect: Object, _ set: DuplicateGroup<ServerSong>,
                          _ fields: HealthFields<ServerSong>) {
        if let copies = expect["copies"] { failed.check("\(at) copies", Self.strings(copies), set.copies.map(\.id)) }
        if let size = expect["size"] as? Int { failed.check("\(at) size", size, set.copies.count) }
        if let basis = expect["basis"] { failed.check("\(at) basis", Self.text(basis), Self.name(set.basis)) }
        if let best = expect["best"] { failed.check("\(at) best", Self.text(best), Self.name(set.bestReason)) }
        if let heading = expect["heading"] { failed.check("\(at) heading", Self.text(heading), set.heading(fields)) }
        if let summary = expect["summary"] { failed.check("\(at) summary", Self.text(summary), set.summary(fields)) }
    }

    private func checkSplit(_ failed: Failures, _ at: String, _ expect: Object, _ album: SplitAlbum<ServerSong>,
                            _ fields: HealthFields<ServerSong>) {
        if let parts = expect["parts"] { failed.check("\(at) parts", Self.strings(parts), album.parts.map(\.albumId)) }
        if let sizes = expect["sizes"] as? [Int] { failed.check("\(at) sizes", sizes, album.parts.map(\.songs.count)) }
        if let artist = expect["artist"] { failed.check("\(at) artist", Self.text(artist), album.artist) }
        if let heading = expect["heading"] { failed.check("\(at) heading", Self.text(heading), album.heading) }
        if let summary = expect["summary"] { failed.check("\(at) summary", Self.text(summary), album.summary) }
        if let reasons = expect["reasons"] as? [Object], failed.sameCount("\(at) reasons", reasons.count, album.reasons.count) {
            for (i, want) in reasons.enumerated() {
                let got = album.reasons[i]
                failed.check("\(at) reasons[\(i)] basis", Self.text(want["basis"]), Self.name(got.basis))
                if let artist = want["artist"] { failed.check("\(at) reasons[\(i)] artist", Self.text(artist), got.artist) }
                if let other = want["other"] { failed.check("\(at) reasons[\(i)] other", Self.text(other), got.other) }
                if let song = want["song"] { failed.check("\(at) reasons[\(i)] song", Self.text(song), got.song) }
            }
        }
        if let words = expect["reasonWords"] { failed.check("\(at) reason words", Self.strings(words), album.reasons.map(\.words)) }
        if let differences = expect["differences"] as? [Object],
           failed.sameCount("\(at) differences", differences.count, album.differences.count) {
            for (i, want) in differences.enumerated() {
                failed.check("\(at) differences[\(i)] kind", Self.text(want["kind"]), Self.name(album.differences[i].kind))
                failed.check("\(at) differences[\(i)] values", Self.strings(want["values"]), album.differences[i].values)
            }
        }
        let join = albumJoin(album)
        if let moving = expect["joinMoving"] {
            failed.check("\(at) join moves", Self.strings(moving).sorted(), join.moving.map(\.id).sorted())
        }
        if let lead = expect["joinLeadAlbum"] {
            failed.check("\(at) join lead album", Self.text(lead), join.lead.albumId)
            for step in join.steps(fields) {
                failed.check("\(at) join step action", "joinAlbum", step.action)
                failed.check("\(at) join step like", join.lead.id, step.with.first { $0.0 == "like" }?.1 ?? "")
            }
        }
        if let words = expect["joinWords"] { failed.check("\(at) join words", Self.text(words), join.words) }
    }

    private func checkFix(_ failed: Failures, _ expect: Object, _ set: DuplicateGroup<ServerSong>, _ fields: HealthFields<ServerSong>) {
        let pick = Self.text(expect["pick"]).flatMap { picked in set.copies.first { $0.id == picked } }
        let fix = duplicateFix(set, fields, keep: pick ?? set.best)
        if let keep = expect["keep"] { failed.check("fix keeps", Self.text(keep), fix.keep.id) }
        if let remove = expect["remove"] { failed.check("fix removes", Self.strings(remove), fix.remove.map(\.id)) }
        if let why = expect["why"] { failed.check("fix why", Self.text(why), fix.why) }
        if let fills = expect["fills"] as? Object {
            let wanted = fills.mapValues { Self.text($0) ?? "" }
            failed.check("fix fills", wanted, Dictionary(fix.fills.map { ($0.tag, $0.value) }, uniquingKeysWith: { a, _ in a }))
        }
        if let from = expect["fillsFrom"] {
            for change in fix.fills {
                failed.check("fix fill \(change.tag) from", Self.text(from), change.from)
                failed.check("fix fill \(change.tag) now", nil as String?, change.now)
            }
        }
        if expect.keys.contains("note") { failed.check("fix note", Self.text(expect["note"]), fix.note) }
        if let differs = expect["differs"] as? [Object], failed.sameCount("fix differs", differs.count, fix.differs.count) {
            for (i, want) in differs.enumerated() {
                failed.check("fix differs[\(i)] tag", Self.text(want["tag"]), fix.differs[i].tag)
                failed.check("fix differs[\(i)] values", Self.rows(want["values"]), fix.differs[i].values.map { [$0.id, $0.value] as [String?] })
            }
        }
    }
}
