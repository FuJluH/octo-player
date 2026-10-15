import Foundation

// Library health's fixes: what each finding comes to when it is put right, worked out from the
// songs alone so it can be shown before anything changes, and then done one song at a time
// through the server.

/// The tag names the server reads and writes, as it spells them.
public enum SongTag {
    public static let title = "title"
    public static let artist = "artist"
    public static let album = "album"
    public static let albumArtist = "albumArtist"
    public static let year = "year"
    public static let genre = "genre"
    public static let track = "track"
    public static let disc = "disc"
    public static let isrc = "isrc"

    public static let all = [title, artist, album, albumArtist, year, genre, track, disc, isrc]
}

/// A song's tags as the server names them, for the ones the app can see. Blank is nil.
public func tagValues<T>(_ song: T, _ fields: HealthFields<T>) -> [String: String?] {
    func text(_ value: String?) -> String? { value.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 } }
    func number(_ value: Int?) -> String? { value.flatMap { $0 > 0 ? String($0) : nil } }
    return [
        SongTag.title: text(fields.title(song)),
        SongTag.artist: text(fields.artist(song)),
        SongTag.album: text(fields.album(song)),
        SongTag.albumArtist: fields.seen.contains(.albumArtist) ? text(fields.albumArtist(song)) : nil,
        SongTag.year: number(fields.year(song)),
        SongTag.genre: text(fields.genres(song).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.joined(separator: "; ")),
        SongTag.track: number(fields.track(song)),
        SongTag.disc: number(fields.disc(song)),
        SongTag.isrc: text(fields.isrcs(song).first),
    ]
}

private func value(_ tags: [String: String?], _ tag: String) -> String? { tags[tag] ?? nil }

extension HealthReport {
    /// The report with songs fixed for one check left out of that check only, until the server's
    /// list catches up.
    public func settledFor(_ check: HealthCheck, ids: Set<String>, fields: HealthFields<T>) -> HealthReport<T> {
        if ids.isEmpty { return self }
        let only = without(ids, fields: fields)
        var out = self
        switch check {
        case .duplicates: out.duplicates = only.duplicates
        case .splitAlbums: out.splitAlbums = only.splitAlbums
        case .noLength: out.noLength = only.noLength
        default:
            guard let tag = check.tag else { return self }
            let left = (missing[tag] ?? []).filter { !ids.contains(fields.id($0)) }
            out.missing[tag] = left.isEmpty ? nil : left
        }
        return out
    }
}

/// One tag a fix would write: what the song says now and what it gets.
public struct TagChange: Equatable, Hashable, Sendable {
    public var tag: String
    public var now: String?
    public var value: String
    public var from: String?

    public init(_ tag: String, now: String?, value: String, from: String? = nil) {
        self.tag = tag
        self.now = now
        self.value = value
        self.from = from
    }

    /// "Year: 1998" or, over a value, "Year: 1998, was 1997".
    public var words: String { now.map { "\(fixTagName(tag)): \(value), was \($0)" } ?? "\(fixTagName(tag)): \(value)" }
}

/// One tag two copies disagree on, each copy's value by the copy's id, in the order found.
public struct TagChoice: Equatable, Sendable {
    public var tag: String
    public var values: [(id: String, value: String)]

    public static func == (a: TagChoice, b: TagChoice) -> Bool {
        a.tag == b.tag && a.values.map(\.id) == b.values.map(\.id) && a.values.map(\.value) == b.values.map(\.value)
    }

    public func value(of id: String) -> String? { values.first { $0.id == id }?.value }
}

/// A set of copies put right: one kept, the rest removed, and the tags the kept one lacks taken
/// from the others.
public struct DuplicateFix<T> {
    public var keep: T
    public var remove: [T]
    /// Why that one is kept, in plain words.
    public var why: String
    /// Blank tags on the kept copy another copy can fill.
    public var fills: [TagChange]
    /// Tags the copies say differently, for a person to pick from.
    public var differs: [TagChoice]
    /// Something worth knowing first, like a copy that is the only one on its album.
    public var note: String?
}

private let fillOrder = [SongTag.album, SongTag.albumArtist, SongTag.track, SongTag.disc, SongTag.year, SongTag.genre, SongTag.isrc]

/// Tags to write, in the order they are filled in, any others after them by name.
public func tagsInOrder(_ tags: [String: String]) -> [(String, String)] {
    func rank(_ tag: String) -> Int { fillOrder.firstIndex(of: tag) ?? fillOrder.count }
    return tags.sorted { a, b in rank(a.key) != rank(b.key) ? rank(a.key) < rank(b.key) : a.key < b.key }.map { ($0.key, $0.value) }
}

/// Tags that belong to an album: taken only from a copy on the same album, or with the album
/// itself when the kept copy has none.
private let albumTags: Set<String> = [SongTag.album, SongTag.albumArtist, SongTag.track, SongTag.disc, SongTag.year]

/// The plan for one set of copies, keeping `keep` (the best copy unless a person picked another).
public func duplicateFix<T>(_ group: DuplicateGroup<T>, _ fields: HealthFields<T>, keep chosen: T? = nil) -> DuplicateFix<T> {
    let keep = chosen ?? group.best
    let others = group.copies.filter { fields.id($0) != fields.id(keep) }
    let mine = tagValues(keep, fields)
    let donors = others.enumerated().sorted { a, b in
        let ta = tagsOf(a.element, fields), tb = tagsOf(b.element, fields)
        return ta != tb ? ta > tb : a.offset < b.offset
    }.map(\.element)
    let myAlbum = SongIdentity.key(value(mine, SongTag.album))
    var fills: [TagChange] = []
    let albumDonor = myAlbum.isEmpty ? donors.first { value(tagValues($0, fields), SongTag.album) != nil } : nil
    for tag in fillOrder where value(mine, tag) == nil {
        let donor = donors.first { donor in
            let theirs = tagValues(donor, fields)
            guard value(theirs, tag) != nil else { return false }
            return !albumTags.contains(tag)
                || (albumDonor.map { fields.id($0) == fields.id(donor) } ?? false)
                || (!myAlbum.isEmpty && SongIdentity.key(value(theirs, SongTag.album)) == myAlbum)
        }
        guard let donor, let found = value(tagValues(donor, fields), tag) else { continue }
        fills.append(TagChange(tag, now: nil, value: found, from: fields.id(donor)))
    }
    let differs = [SongTag.title, SongTag.artist, SongTag.album, SongTag.albumArtist, SongTag.year, SongTag.genre].compactMap { tag -> TagChoice? in
        var values: [(id: String, value: String)] = []
        func put(_ id: String, _ text: String) {
            if let index = values.firstIndex(where: { $0.id == id }) { values[index].value = text } else { values.append((id, text)) }
        }
        if let own = value(mine, tag) { put(fields.id(keep), own) }
        for other in others { if let theirs = value(tagValues(other, fields), tag) { put(fields.id(other), theirs) } }
        return value(mine, tag) != nil && Set(values.map(\.value)).count > 1 ? TagChoice(tag: tag, values: values) : nil
    }
    let lonely = others.first { other in
        let album = SongIdentity.key(fields.album(other))
        return !album.isEmpty && album != myAlbum
    }
    let note = lonely.map { "\(copyName($0, fields)) is on \((fields.album($0) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)), so that album will no longer have this song." }
    return DuplicateFix(keep: keep, remove: others, why: keepWhy(group, keep, fields), fills: fills, differs: differs, note: note)
}

/// Why `keep` is the one kept, in words.
public func keepWhy<T>(_ group: DuplicateGroup<T>, _ keep: T, _ fields: HealthFields<T>) -> String {
    let quality = qualityText(keep, fields)
    if fields.id(keep) != fields.id(group.best) { return "You picked this copy (\(quality)) to keep." }
    switch group.bestReason {
    case .sound: return "Keeps the \(quality) copy, because it sounds best."
    case .tags: return "The copies sound alike, so this keeps the one with the fullest tags (\(quality))."
    case .none: return "The copies sound alike and have the same tags, so this keeps the first (\(quality))."
    }
}

/// "Holocene (MP3, 320 kbps)".
public func copyName<T>(_ song: T, _ fields: HealthFields<T>) -> String { "\(fields.title(song)) (\(qualityText(song, fields)))" }

/// A tag's name for people.
public func fixTagName(_ tag: String) -> String {
    switch tag {
    case SongTag.title: "Title"
    case SongTag.artist: "Artist"
    case SongTag.album: "Album"
    case SongTag.albumArtist: "Album artist"
    case SongTag.year: "Year"
    case SongTag.genre: "Genre"
    case SongTag.track: "Track number"
    case SongTag.disc: "Disc number"
    case SongTag.isrc: "ISRC"
    default: tag.prefix(1).uppercased() + tag.dropFirst()
    }
}

/// A split album put right: every song of the other parts takes the album tags of the first part.
public struct AlbumJoin<T> {
    public var album: SplitAlbum<T>
    public var lead: T
    public var moving: [T]

    public var words: String {
        let count = countText(moving.count, "song", "songs")
        let kept = album.parts[0].songs.count
        let named = kept < (album.parts.map(\.songs.count).max() ?? 0)
        let why = named ? ", since its album artist names every part's artist" : ""
        let head = "Moves \(count) onto \(album.title.trimmingCharacters(in: .whitespacesAndNewlines)), the part with \(countText(kept, "song", "songs"))\(why)."
        let artist = album.artist.trimmingCharacters(in: .whitespacesAndNewlines)
        let differs = !album.reasons.isEmpty || album.differences.contains { $0.kind == .albumArtist }
        return differs && !artist.isEmpty ? "\(head) Their album artist becomes \(artist)." : head
    }
}

public func albumJoin<T>(_ album: SplitAlbum<T>) -> AlbumJoin<T> {
    AlbumJoin(album: album, lead: album.parts[0].songs[0], moving: album.parts.dropFirst().flatMap(\.songs))
}

/// A tag a song lacks that the rest of its album agrees on, so it can be filled in without
/// looking anything up.
public func fillsFromAlbum<T>(_ missing: [T], all: [T], tag: HealthTag, _ fields: HealthFields<T>) -> [(T, TagChange)] {
    let name: String
    switch tag {
    case .year: name = SongTag.year
    case .genre: name = SongTag.genre
    case .albumArtist: name = SongTag.albumArtist
    default: return []
    }
    var byAlbum: [String: [T]] = [:]
    for song in all { byAlbum[fields.albumId(song) ?? "", default: []].append(song) }
    return missing.compactMap { song in
        guard let albumId = fields.albumId(song), !albumId.isEmpty else { return nil }
        let siblings = (byAlbum[albumId] ?? []).filter { fields.id($0) != fields.id(song) }
        var values: [String] = []
        for sibling in siblings { if let text = value(tagValues(sibling, fields), name), !values.contains(text) { values.append(text) } }
        var found: String? = values.count == 1 ? values[0] : nil
        if found == nil, tag == .albumArtist, values.isEmpty {
            var artists: [String] = []
            for one in siblings + [song] {
                if let artist = fields.artist(one), !artist.trimmingCharacters(in: .whitespaces).isEmpty, !artists.contains(artist) { artists.append(artist) }
            }
            found = artists.count == 1 ? artists[0] : nil
        }
        return found.map { (song, TagChange(name, now: nil, value: $0)) }
    }
}

// MARK: Looking tags up

/// What a lookup found for one song: its tags now and the ones a download would get, with how
/// sure the match is and where from.
public struct SongLookup: Decodable, Sendable {
    public var id: String
    public var state: String
    public var detail: String?
    public var current: [String: String?]
    public var suggested: [String: String?]
    public var confidence: String?
    public var source: String?
    public var release: String?

    enum CodingKeys: String, CodingKey { case id, state, detail, current, suggested, confidence, source, release }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.string(.id) ?? ""
        state = c.string(.state) ?? ""
        detail = c.string(.detail)
        current = (try? c.decodeIfPresent([String: String?].self, forKey: .current)) ?? [:]
        suggested = (try? c.decodeIfPresent([String: String?].self, forKey: .suggested)) ?? [:]
        confidence = c.string(.confidence)
        source = c.string(.source)
        release = c.string(.release)
    }

    public init(state: String = "found", current: [String: String?] = [:], suggested: [String: String?] = [:],
                confidence: String? = nil, source: String? = nil, release: String? = nil, detail: String? = nil) {
        id = ""
        self.state = state
        self.current = current
        self.suggested = suggested
        self.confidence = confidence
        self.source = source
        self.release = release
        self.detail = detail
    }

    public var found: Bool { state == "found" }

    /// Strong or Medium: what a download would have written without asking.
    public var sure: Bool {
        confidence?.caseInsensitiveCompare("Strong") == .orderedSame || confidence?.caseInsensitiveCompare("Medium") == .orderedSame
    }

    /// What it would change, each picked or not to begin with. A blank tag is picked to be filled;
    /// one the file has only when the match is sure and the tag is not the song's name.
    public func changes() -> [(TagChange, Bool)] {
        SongTag.all.compactMap { tag in
            guard let found = suggested[tag] ?? nil, !found.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            let now = (current[tag] ?? nil).flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
            if let now, now.trimmingCharacters(in: .whitespacesAndNewlines) == found.trimmingCharacters(in: .whitespacesAndNewlines) { return nil }
            let named = tag == SongTag.title || tag == SongTag.artist || tag == SongTag.album
            return (TagChange(tag, now: now, value: found, from: source), now == nil || (sure && !named))
        }
    }

    /// Where a lookup came from: "A sure match from the song's fingerprint, on Mezzanine."
    public var origin: String {
        let how: String = switch confidence?.lowercased() {
        case "strong": "A sure match"
        case "medium": "A likely match"
        case nil: "Found"
        default: "A doubtful match"
        }
        let from = source.map { " from \(Self.sourceName($0))" } ?? ""
        let on = release.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : ", on \($0)" } ?? ""
        return "\(how)\(from)\(on)."
    }

    private static func sourceName(_ source: String) -> String {
        switch source.lowercased() {
        case "fingerprint": "the song's fingerprint"
        case "database": "MusicBrainz"
        case "catalog": "the catalog"
        case "filetags": "the file's own tags"
        default: source
        }
    }
}

/// One song in the server's trash.
public struct TrashedSong: Decodable, Sendable, Hashable, Identifiable {
    public var id: String
    public var title: String
    public var artist: String
    public var album: String
    public var removedBy: String?
    public var removedAt: String?
    /// When the server deletes it for good; nil keeps it until someone clears the trash.
    public var goneAt: String?
    /// "removed" (also when left out) or "replaced": a file another copy took the place of, with
    /// the file in the trash (`was`) and the one in the library now (`now`).
    public var kind: String?
    public var was: String?
    public var now: String?

    enum CodingKeys: String, CodingKey { case id, title, artist, album, removedBy, removedAt, goneAt, kind, was, now }

    public init(id: String = "", title: String = "", artist: String = "", album: String = "", removedBy: String? = nil,
                removedAt: String? = nil, goneAt: String? = nil, kind: String? = nil, was: String? = nil, now: String? = nil) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.removedBy = removedBy
        self.removedAt = removedAt
        self.goneAt = goneAt
        self.kind = kind
        self.was = was
        self.now = now
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.string(.id) ?? ""
        title = c.string(.title) ?? ""
        artist = c.string(.artist) ?? ""
        album = c.string(.album) ?? ""
        removedBy = c.string(.removedBy)
        removedAt = c.string(.removedAt)
        goneAt = c.string(.goneAt)
        kind = c.string(.kind)
        was = c.string(.was)
        now = c.string(.now)
    }

    /// A file another copy took the place of; putting it back swaps the two.
    public var replaced: Bool { kind == "replaced" }

    /// The step that puts it back.
    public var restoreStep: FixStep { .restore(id: id, title: title, replaced: replaced) }
}

public struct LibraryTrash: Decodable, Sendable {
    public var keepDays: Int
    public var songs: [TrashedSong]

    enum CodingKeys: String, CodingKey { case keepDays, songs }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        keepDays = c.int(.keepDays) ?? 0
        songs = (try? c.decodeIfPresent([TrashedSong].self, forKey: .songs)) ?? []
    }
}

extension SubsonicClient {
    /// The tags a download of the song would get, beside what its file says now. Writes nothing.
    public func lookUpTags(_ id: String) async throws -> SongLookup {
        try await get("libraryAction", [("id", id), ("action", "lookup")], key: "libraryAction")
    }

    /// The songs in the server's trash, newest first.
    public func libraryTrash() async throws -> LibraryTrash {
        try await get("getLibraryTrash", key: "libraryTrash")
    }
}

// MARK: Running fixes

/// One thing done to one song through the server, by the song's id there.
public enum FixStep: Hashable, Sendable {
    /// `copy`: one copy of a song the library keeps another of.
    case remove(id: String, title: String, copy: Bool = false)
    case retag(id: String, title: String, tags: [String: String])
    case joinAlbum(id: String, title: String, like: String)
    case addCover(id: String, title: String)
    /// `replaced`: putting it back swaps it with the file that replaced it.
    case restore(id: String, title: String, replaced: Bool = false)
    case undo(id: String, title: String)

    public var id: String {
        switch self {
        case .remove(let id, _, _), .retag(let id, _, _), .joinAlbum(let id, _, _), .addCover(let id, _), .restore(let id, _, _),
             .undo(let id, _): id
        }
    }

    public var title: String {
        switch self {
        case .remove(_, let title, _), .retag(_, let title, _), .joinAlbum(_, let title, _), .addCover(_, let title),
             .restore(_, let title, _), .undo(_, let title): title
        }
    }

    public var action: String {
        switch self {
        case .remove: "remove"
        case .retag: "retag"
        case .joinAlbum: "joinAlbum"
        case .addCover: "cover"
        case .restore: "restore"
        case .undo: "undo"
        }
    }

    public var with: [(String, String)] {
        switch self {
        case .retag(_, _, let tags): tagsInOrder(tags)
        case .joinAlbum(_, _, let like): [("like", like)]
        case .remove(_, _, let copy): copy ? [("copy", "true")] : []
        default: []
        }
    }

    /// The step that puts this one back, once it is done.
    public var undoStep: FixStep? {
        switch self {
        case .remove(let id, let title, _): .restore(id: id, title: title)
        case .retag(let id, let title, _), .joinAlbum(let id, let title, _), .addCover(let id, let title): .undo(id: id, title: title)
        case .restore(let id, let title, let replaced): replaced ? .restore(id: id, title: title, replaced: true) : .remove(id: id, title: title)
        case .undo: nil
        }
    }

    /// The same step for another id: the song's copy on the server.
    public func on(_ id: String, like: String? = nil) -> FixStep {
        switch self {
        case .remove(_, let title, let copy): .remove(id: id, title: title, copy: copy)
        case .retag(_, let title, let tags): .retag(id: id, title: title, tags: tags)
        case .joinAlbum(_, let title, let old): .joinAlbum(id: id, title: title, like: like ?? old)
        case .addCover(_, let title): .addCover(id: id, title: title)
        case .restore(_, let title, let replaced): .restore(id: id, title: title, replaced: replaced)
        case .undo(_, let title): .undo(id: id, title: title)
        }
    }
}

extension DuplicateFix {
    /// The steps that fix a set of copies: fill the kept one's blank tags, then remove the others.
    public func steps(_ fields: HealthFields<T>, fills: [TagChange]? = nil) -> [FixStep] {
        let changes = fills ?? self.fills
        var out: [FixStep] = []
        if !changes.isEmpty {
            var tags: [String: String] = [:]
            for change in changes { tags[change.tag] = change.value }
            out.append(.retag(id: fields.id(keep), title: fields.title(keep), tags: tags))
        }
        out += remove.map { .remove(id: fields.id($0), title: fields.title($0), copy: true) }
        return out
    }
}

extension AlbumJoin {
    public func steps(_ fields: HealthFields<T>) -> [FixStep] {
        moving.map { .joinAlbum(id: fields.id($0), title: fields.title($0), like: fields.id(lead)) }
    }
}

/// How one file action went, as the server tells it.
public enum FileActionState: Sendable {
    case applied, queued, rehearsed, skipped, unresolved, failed, unknown

    public init(_ text: String?) {
        switch text?.trimmingCharacters(in: .whitespaces).lowercased() {
        case "applied": self = .applied
        case "queued": self = .queued
        case "rehearsed": self = .rehearsed
        case "skipped": self = .skipped
        case "unresolved": self = .unresolved
        case "failed": self = .failed
        default: self = .unknown
        }
    }
}

/// How a run of steps went.
public struct FixOutcome: Sendable {
    public var done: [FixStep] = []
    /// Steps that changed nothing because nothing needed changing.
    public var unchanged: [FixStep] = []
    /// Steps that could not be done, with the server's words.
    public var failed: [(FixStep, String)] = []
    /// The server only rehearsed.
    public var rehearsed = false
    public var stopped = false
    /// The server's own words for steps done, when it gave any.
    public var said: [FixStep: String] = [:]

    public init(done: [FixStep] = [], unchanged: [FixStep] = [], failed: [(FixStep, String)] = [], rehearsed: Bool = false,
                stopped: Bool = false, said: [FixStep: String] = [:]) {
        self.done = done
        self.unchanged = unchanged
        self.failed = failed
        self.rehearsed = rehearsed
        self.stopped = stopped
        self.said = said
    }

    public var removed: Set<String> {
        Set(done.compactMap { if case .remove(let id, _, _) = $0 { id } else { nil } })
    }

    /// What puts every done step back, the last first.
    public var undo: [FixStep] { done.reversed().compactMap(\.undoStep) }

    /// One line for the window: what was done, and what was not.
    public func summary() -> String {
        let all = done + failed.map(\.0)
        if !rehearsed, all.count == 1, case .restore(_, _, true) = all[0] {
            if let words = said[all[0]] { return words }
            if failed.count == 1 { return failed[0].1 }
        }
        if rehearsed { return "The server only rehearsed this, because its library actions are in dry run. Nothing changed." }
        var parts: [String] = []
        func count(_ test: (FixStep) -> Bool) -> Int { done.filter(test).count }
        let removes = count { if case .remove = $0 { true } else { false } }
        let retags = count { if case .retag = $0 { true } else { false } }
        let joins = count { if case .joinAlbum = $0 { true } else { false } }
        let covers = count { if case .addCover = $0 { true } else { false } }
        let restores = count { if case .restore = $0 { true } else { false } }
        let undos = count { if case .undo = $0 { true } else { false } }
        if removes > 0 { parts.append("removed \(countText(removes, "song", "songs"))") }
        if retags > 0 { parts.append("changed the tags of \(countText(retags, "song", "songs"))") }
        if joins > 0 { parts.append("moved \(countText(joins, "song", "songs")) onto their album") }
        if covers > 0 { parts.append("added \(countText(covers, "cover", "covers"))") }
        if restores > 0 { parts.append("put back \(countText(restores, "song", "songs"))") }
        if undos > 0 { parts.append("undid the changes to \(countText(undos, "song", "songs"))") }
        let head: String
        if parts.isEmpty {
            head = unchanged.isEmpty ? "Nothing was done." : "Nothing needed changing."
        } else {
            let joined = parts.joined(separator: ", ")
            head = joined.prefix(1).uppercased() + joined.dropFirst() + "."
        }
        let stop = stopped ? " Stopped before the end." : ""
        let miss: String = switch failed.count {
        case 0: ""
        case 1: " \(failed[0].0.title): \(failed[0].1)"
        default: " \(countText(failed.count, "song", "songs")) could not be done, like \(failed[0].0.title): \(failed[0].1)"
        }
        return "\(head)\(stop)\(miss)"
    }
}

private let nothingToDo = ["nothing to change", "already", "picture of its own", "has a picture"]

/// Runs steps one after another through `send`, which asks the server and answers as it did;
/// a thrown error is that step's failure, in `failure`'s words. `progress` hears how many are
/// done; `stop` ends the run between steps.
public func runFix(_ steps: [FixStep], isolation: isolated (any Actor)? = #isolation,
                   send: (FixStep) async throws -> FileActionResult,
                   progress: (Int, Int) -> Void = { _, _ in },
                   stop: () -> Bool = { false },
                   failure: (Error) -> String = { $0.localizedDescription }) async -> FixOutcome {
    var outcome = FixOutcome()
    progress(0, steps.count)
    for (index, step) in steps.enumerated() {
        if stop() {
            outcome.stopped = true
            break
        }
        do {
            let answer = try await send(step)
            let words = answer.detail.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 } ?? "the server said \(answer.state)"
            switch FileActionState(answer.state) {
            case .applied:
                outcome.done.append(step)
                if let detail = answer.detail, !detail.trimmingCharacters(in: .whitespaces).isEmpty { outcome.said[step] = detail }
            case .rehearsed:
                outcome.rehearsed = true
            case .skipped:
                let detail = answer.detail?.lowercased() ?? ""
                if nothingToDo.contains(where: detail.contains) { outcome.unchanged.append(step) } else { outcome.failed.append((step, words)) }
            default:
                outcome.failed.append((step, words))
            }
        } catch is CancellationError {
            outcome.stopped = true
            break
        } catch {
            outcome.failed.append((step, failure(error)))
        }
        progress(index + 1, steps.count)
    }
    return outcome
}
