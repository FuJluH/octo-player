import Foundation
import Observation

// Replacing a library song's copy with one picked in Find songs: the question before, the row while
// it runs, and the line once it ends, with Undo. The app runs the calls and draws; the words and
// what each answer means are here.

/// The two questions a pick can come back with on a server that asks first.
public enum AskKind: Sendable, Equatable {
    /// A better copy of the right song: the usual "Replace your copy?".
    case ready
    /// A copy that needs the person's word, in the server's own sentence.
    case confirm
}

/// The confirm's title, its two buttons.
public let replaceTitle = "Replace your copy?"
public let replaceAnywayText = "Replace anyway"
public let keepMineText = "Keep mine"

/// What is asked when the server sends no words of its own.
public let replaceAnywayFallback = "This copy is not better than yours. Replace yours anyway?"

/// The usual question for a better copy, by its first facts.
public func replaceQuestion(_ copy: FoundCandidate, locale: Locale = .current) -> String {
    "Replace your copy with \(candidateFacts(copy, locale: locale).prefix(2).joined(separator: ", "))?"
}

/// One side of the comparison in a line: "Yours: FLAC, 7:00, live recording". Missing parts are
/// left out, and a side with none is nil.
public func compareLine(_ label: String, _ side: PickSide?) -> String? {
    let parts = [
        side?.quality.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 },
        side?.length.flatMap { $0 > 0 ? downloadClockText($0) : nil },
        side?.take.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 },
    ].compactMap { $0 }
    return parts.isEmpty ? nil : "\(label): \(parts.joined(separator: ", "))"
}

/// Both lines of a comparison, the library's first.
public func compareLines(_ compare: PickCompare?) -> [String] {
    [compareLine("Yours", compare?.yours), compareLine("This copy", compare?.copy)].compactMap { $0 }
}

/// The tag beside a copy's kind that says how it stands against the library's copy, and what a
/// screen reader says for it.
public func vsYoursTag(_ copy: FoundCandidate) -> String? {
    copy.vsYoursText.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 }
}

public func vsYoursSpoken(_ copy: FoundCandidate) -> String? { vsYoursTag(copy).map { "Compared with your copy: \($0)" } }

/// The line a Find songs search shows over its copies when the library's copy looks like another
/// take of the song.
public func takeLine(_ take: String?) -> String? {
    take.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 }
}

/// A pick waiting for an answer. `words` is the whole question: the server's sentence for Confirm,
/// the usual question for Ready. `songId` is the library song it would replace, and `title` names
/// it.
public struct PickQuestion: Sendable, Equatable {
    public var search: String
    public var copy: FoundCandidate
    public var words: String
    public var kind: AskKind
    public var compare: PickCompare?
    public var songId: String?
    public var title: String

    public init(search: String, copy: FoundCandidate, words: String, kind: AskKind = .confirm, compare: PickCompare? = nil,
                songId: String? = nil, title: String = "") {
        self.search = search
        self.copy = copy
        self.words = words
        self.kind = kind
        self.compare = compare
        self.songId = songId
        self.title = title
    }
}

/// The take the server calls the plain song, which the line after names.
private let plainSongTake = "the plain song"

/// A library song being replaced by a picked copy. `copyKey` and `search` name the copy's row on
/// the list it was picked from.
public struct Replacing: Sendable, Equatable {
    public var songId: String
    public var title: String
    public var search: String
    public var copyKey: String
    public var plainSong: Bool
    /// When the server last changed an older job for the song, as it was listed when this one
    /// started; only a later end is this one's.
    public var before: String?
    /// Seen on the server's list while still under way.
    public var seen: Bool

    public init(songId: String, title: String, search: String, copyKey: String, plainSong: Bool, before: String? = nil, seen: Bool = false) {
        self.songId = songId
        self.title = title
        self.search = search
        self.copyKey = copyKey
        self.plainSong = plainSong
        self.before = before
        self.seen = seen
    }

    public static func of(_ question: PickQuestion) -> Replacing? {
        guard let songId = question.songId else { return nil }
        let take = question.compare?.copy?.take?.trimmingCharacters(in: .whitespacesAndNewlines)
        return Replacing(songId: songId, title: question.title, search: question.search, copyKey: OctoKit.copyKey(question.copy),
                         plainSong: take?.caseInsensitiveCompare(plainSongTake) == .orderedSame)
    }
}

/// How a replacement ended: the copy took the place of the library's, or the library's copy was
/// kept, with the server's words why.
public enum ReplaceEnd: Sendable, Equatable {
    /// Undo puts back by the song's id, which swaps the old copy in and leaves the newer one in
    /// Recently removed.
    case replaced(Replacing)
    case kept(Replacing, detail: String?)

    public var replacing: Replacing {
        switch self {
        case .replaced(let replacing), .kept(let replacing, _): replacing
        }
    }

    public var words: String {
        switch self {
        case .replaced(let replacing): replacedLine(plainSong: replacing.plainSong)
        case .kept(_, let detail): keptLine(detail)
        }
    }
}

public let replacingText = "Replacing..."
public let detailsInDownloads = "Details are in Downloads."

public func replacedLine(plainSong: Bool) -> String {
    plainSong ? "Replaced with the plain song" : "Replaced with the copy you picked"
}

/// The server's words for a replacement that did not happen, which already end "Your copy was
/// kept.", and where to read more.
public func keptLine(_ detail: String?) -> String {
    let said: String
    if let detail = detail?.trimmingCharacters(in: .whitespacesAndNewlines), let last = detail.last {
        said = ".!?".contains(last) ? detail : detail + "."
    } else {
        said = "The copy you picked did not replace yours. Your copy was kept."
    }
    return "\(said) \(detailsInDownloads)"
}

/// The row under way for a replacement, when the sheet has one: the higher quality copy asked for
/// the song, or its download.
public func replacingRow(_ replacing: Replacing, _ rows: [DownloadRow]) -> DownloadRow? {
    rows.first { $0.findId == replacing.songId && !$0.finished }
}

/// What a replacing copy's row says: "Replacing... Downloading 42%", with the step the downloads
/// pill would show for it.
public func replacingWords(_ row: DownloadRow?) -> String { row.map { "\(replacingText) \(stepWords($0))" } ?? replacingText }

/// The replacements under way on one server, by library song, followed through the server's list
/// of higher quality copies, which lists a forced pick under the song's id too.
@MainActor
@Observable
public final class Replacements {
    public private(set) var now: [String: Replacing] = [:]

    public init() {}

    /// Follows one from now; `upgrades` is the server's list as last read, whose older jobs for the
    /// song are not this one's end.
    public func start(_ replacing: Replacing, upgrades: [Upgrade]) {
        let latest = upgrades.filter { $0.id == replacing.songId }.map { $0.updatedAt ?? "" }.max()
        var started = replacing
        started.before = latest.flatMap { $0.isEmpty ? nil : $0 }
        now[replacing.songId] = started
    }

    /// The one replacing the copy `copyKey` on the list `search`, if any.
    public func of(search: String?, copyKey: String) -> Replacing? {
        now.values.first { $0.search == search && $0.copyKey == copyKey }
    }

    /// Whether this library song is being replaced.
    public func replacing(_ songId: String?) -> Bool { songId.map { now[$0] != nil } ?? false }

    /// Reads the server's list, and answers the replacements that ended there, which are let go. An
    /// end no later than the newest job listed when one started is that older job's, unless this
    /// one was seen under way first.
    public func update(_ upgrades: [Upgrade]) -> [ReplaceEnd] {
        var ends: [ReplaceEnd] = []
        var next: [String: Replacing] = [:]
        for (id, replacing) in now {
            let entries = upgrades.filter { $0.id == id }
            if entries.contains(where: { $0.stage.pending }) {
                var seen = replacing
                seen.seen = true
                next[id] = seen
                continue
            }
            guard let last = entries.max(by: { ($0.updatedAt ?? "") < ($1.updatedAt ?? "") }) else {
                next[id] = replacing
                continue
            }
            let fresh = replacing.seen || replacing.before == nil || later(last.updatedAt, than: replacing.before ?? "")
            var end: ReplaceEnd?
            if fresh {
                switch last.stage {
                case .upgraded: end = .replaced(replacing)
                case .notFound, .failed, .skipped, .rehearsed: end = .kept(replacing, detail: last.detail)
                default: end = nil
                }
            }
            if let end { ends.append(end) } else { next[id] = replacing }
        }
        if next != now { now = next }
        return ends
    }

    public func clear() { now = [:] }
}

/// Whether the server's time `at` comes after `than`, read as instants, or as text when either is
/// not one.
private func later(_ at: String?, than: String) -> Bool {
    if let a = at.flatMap(parseServerInstant), let b = parseServerInstant(than) { return a > b }
    return (at ?? "") > than
}
