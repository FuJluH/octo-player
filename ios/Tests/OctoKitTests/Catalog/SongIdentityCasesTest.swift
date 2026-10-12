import Foundation
import Testing
@testable import OctoKit

// Every case in the shared song identity file, the file the Octo server runs too. A failure names
// the case by its note, so a rule changed on one side shows up here before the two disagree. Each
// failing case is listed, not only the first.
@Suite struct SongIdentityCasesTest {
    private func cases() -> [String: Any] {
        // swiftlint:disable:next force_cast
        try! JSONSerialization.jsonObject(with: Data(songIdentityCasesJSON.utf8)) as! [String: Any]
    }

    private func section(_ name: String) -> [[String: Any]] {
        (cases()[name] as? [Any] ?? []).map { $0 as? [String: Any] ?? [:] }
    }

    private func text(_ element: Any?) -> String? {
        switch element {
        case nil, is NSNull: return nil
        case let value as String: return value
        case let value as NSNumber: return value.stringValue
        default: return "\(element!)"
        }
    }

    private func strings(_ element: Any?) -> [String] {
        (element as? [Any] ?? []).compactMap { text($0) }
    }

    private func ref(_ side: [String: Any]) -> SongRef {
        SongRef(
            title: text(side["title"]),
            artist: text(side["artist"]),
            seconds: text(side["seconds"]).flatMap { Double($0) },
            // One ISRC as a string, or several as a list. Absent in every case written before it.
            isrcs: {
                switch side["isrc"] {
                case nil: return []
                case let list as [Any]: return strings(list)
                case let one: return [text(one)]
                }
            }()
        )
    }

    private func options(_ testCase: [String: Any]) -> SongMatchOptions {
        guard let options = testCase["options"] as? [String: Any] else { return .Default }
        var result = SongMatchOptions.Default
        if let value = options["lengthToleranceSeconds"] {
            result.lengthToleranceSeconds = value is NSNull ? nil : Int(text(value)!)!
        }
        if let value = options["extrasMustAgree"] {
            result.extrasMustAgree = (value as? NSNumber)?.boolValue ?? (text(value) == "true")
        }
        if let value = options["alsoNeutral"] {
            result.alsoNeutral = Set(strings(value))
        }
        return result
    }

    private func expectNoFailures(_ failures: [String]) {
        #expect(failures.isEmpty, "\(failures.count) failing:\n\(failures.joined(separator: "\n"))")
    }

    @Test func theFileHasEveryCase() {
        #expect(section("compare").count == 231)
        #expect(section("parse").count == 58)
        #expect(section("queries").count == 6)
    }

    @Test func everyComparisonReadsTheSameFromEitherSide() {
        var failures: [String] = []
        for testCase in section("compare") {
            let note = text(testCase["note"]) ?? "?"
            let expect: SongVerdict
            switch text(testCase["expect"]) {
            case "same": expect = .same
            case "version": expect = .sameSongDifferentVersion
            case "different": expect = .different
            case let word: Issue.record("unknown expectation '\(word ?? "")'"); continue
            }
            let a = ref(testCase["a"] as? [String: Any] ?? [:])
            let b = ref(testCase["b"] as? [String: Any] ?? [:])
            let options = options(testCase)
            let runs = [("forward", SongIdentity.same(a, b, options: options)), ("reversed", SongIdentity.same(b, a, options: options))]
            for (label, match) in runs {
                if match.verdict != expect { failures.append("\(note) (\(label)) expected \(expect), got \(match.verdict) (\(match.reason))") }
                if !(0.0...1.0).contains(match.confidence) { failures.append("\(note) (\(label)) confidence \(match.confidence)") }
                if match.reason.isBlankText { failures.append("\(note) (\(label)) gave no reason") }
            }
        }
        expectNoFailures(failures)
    }

    @Test func everyTitleAndCreditParsesAsTheFileSays() {
        var failures: [String] = []
        for testCase in section("parse") {
            let note = text(testCase["note"]) ?? "?"
            let input = testCase["input"] as? [String: Any] ?? [:]
            let title = text(input["title"])
            let artist = text(input["artist"])

            let parsed = SongIdentity.parseTitle(title, artist: artist)
            let wantKey = text(testCase["expectTitleKey"])
            let wantLoose = text(testCase["expectLooseKey"])
            let wantVersions = strings(testCase["expectVersions"])
            if parsed.key != wantKey { failures.append("\(note): title key '\(parsed.key)', expected '\(wantKey ?? "nil")'") }
            if parsed.looseKey != wantLoose { failures.append("\(note): loose key '\(parsed.looseKey)', expected '\(wantLoose ?? "nil")'") }
            if parsed.versions != wantVersions { failures.append("\(note): versions \(parsed.versions), expected \(wantVersions)") }

            let blank = artist == nil || artist!.isBlankText
            let credit = SongIdentity.parseArtists(blank ? parsed.artistFromTitle : artist)
            var artists: [String] = []
            for name in (credit.names + credit.featured + parsed.featured).map(SongIdentity.key) where !artists.contains(name) {
                artists.append(name)
            }
            let wantArtists = strings(testCase["expectArtists"])
            if artists != wantArtists { failures.append("\(note): artists \(artists), expected \(wantArtists)") }
        }
        expectNoFailures(failures)
    }

    @Test func everySearchTriesTheQueriesInOrder() {
        var failures: [String] = []
        for testCase in section("queries") {
            let input = testCase["input"] as? [String: Any] ?? [:]
            let queries = SongIdentity.queryVariants(text(input["title"]), text(input["artist"])).map(\.text)
            let want = strings(testCase["expect"])
            if queries != want { failures.append("\(text(testCase["note"]) ?? "?"): \(queries), expected \(want)") }
        }
        expectNoFailures(failures)
    }
}
