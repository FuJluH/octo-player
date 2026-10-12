import Foundation

// Library health's fixes on the phone, planned from what the checks found. The checks run on the
// library as the phone shows it, which joins copies from several places; every step carries the id
// of the song's copy on the signed-in Octo server, and a song with no copy there gets none.

/// How many songs one bulk look-up takes at most, so it stays short.
public let lookupBatchSize = 25

/// Why an Undo, or a fix that waited its turn, was not sent: it was for a server no longer signed
/// in to.
public let fixOtherServer = "That change was made on another server, so it cannot be undone from here."

/// Whether a server lists Octo's library actions at all. Removing a song is there from the first
/// version, so any version counts.
public func listsLibraryActions(_ extensions: some Sequence<String>) -> Bool {
    extensions.contains { $0 == fileActionsExtension || $0.hasPrefix("\(fileActionsExtension):") }
}

/// Each library song's copy on the server `sourceId`, by library song: the copy with the lowest id
/// there when the server has two.
public func serverSongIds(_ copies: [SourceTrack], sourceId: String?) -> [String: String] {
    guard let sourceId else { return [:] }
    var out: [String: String] = [:]
    for copy in copies where copy.sourceId == sourceId && !copy.mergedId.isEmpty {
        if let held = out[copy.mergedId], held <= copy.nativeId { continue }
        out[copy.mergedId] = copy.nativeId
    }
    return out
}

/// The steps that delete library songs from the server's disk: every copy each one has there, so
/// none is left behind in the library.
public func deleteSteps(_ trackIds: [String], copies: [SourceTrack], sourceId: String?) -> [FixStep] {
    guard let sourceId else { return [] }
    var onServer: [String: [SourceTrack]] = [:]
    for copy in copies where copy.sourceId == sourceId { onServer[copy.mergedId, default: []].append(copy) }
    var seen = Set<String>()
    return trackIds.filter { seen.insert($0).inserted }.flatMap { id in
        (onServer[id] ?? []).sorted { $0.nativeId < $1.nativeId }.map { FixStep.remove(id: $0.nativeId, title: $0.title) }
    }
}

extension Array where Element == FixStep {
    /// Steps planned on library songs, sent to the server's songs: each step's song, and an album
    /// join's `like`, by its id there. A step for a song with no copy on that server is left out.
    public func onServer(_ ids: [String: String]) -> [FixStep] {
        compactMap { step in
            guard let id = ids[step.id] else { return nil }
            if case .joinAlbum(_, _, let like) = step {
                guard let lead = ids[like] else { return nil }
                return step.on(id, like: lead)
            }
            return step.on(id)
        }
    }
}

extension FileActions {
    /// Whether the server can do a step now.
    public func canRun(_ step: FixStep) -> Bool {
        switch step {
        case .remove: canRemove
        case .restore: canRestore
        case .retag, .undo: canEdit
        case .joinAlbum: canJoinAlbums
        case .addCover: canAddCover
        }
    }
}

/// Whether every step can be done now, as for an Undo.
public func canRunAll(_ actions: FileActions?, _ steps: [FixStep]) -> Bool {
    guard let actions, !steps.isEmpty else { return false }
    return steps.allSatisfy(actions.canRun)
}

/// What Library health offers to do, from what the server lets this user do. A server with no
/// library actions, or a user who is not an admin, gets none, and the pages stay something to read.
public struct HealthOffers: Equatable, Sendable {
    /// Keep the best copy of a song and send the others to the trash.
    public var fixDuplicates = false
    /// Write tags: the kept copy's blanks, a song's album's year, a look-up.
    public var edit = false
    public var join = false
    public var lookUp = false
    public var covers = false
    public var upgrade = false
    public var restore = false
    public var remove = false

    public init(fixDuplicates: Bool = false, edit: Bool = false, join: Bool = false, lookUp: Bool = false, covers: Bool = false,
                upgrade: Bool = false, restore: Bool = false, remove: Bool = false) {
        self.fixDuplicates = fixDuplicates
        self.edit = edit
        self.join = join
        self.lookUp = lookUp
        self.covers = covers
        self.upgrade = upgrade
        self.restore = restore
        self.remove = remove
    }

    /// Whether a check's page has its button for every finding.
    public func fixesAll(_ check: HealthCheck) -> Bool {
        switch check {
        case .duplicates: fixDuplicates
        case .splitAlbums: join
        case .noCover: covers
        case .noLength: upgrade
        case .noYear, .noGenre, .noAlbumArtist: edit
        case .noTrackNumber: lookUp
        }
    }

    /// Whether each song of a check can be looked up by itself.
    public func looksUp(_ check: HealthCheck) -> Bool { lookUp && check.tag != nil && check != .noCover }
}

public func healthOffers(_ actions: FileActions?) -> HealthOffers {
    guard let actions else { return HealthOffers() }
    return HealthOffers(
        fixDuplicates: actions.canRemove, edit: actions.canEdit, join: actions.canJoinAlbums,
        // A look-up is only worth showing when what it finds can be written.
        lookUp: actions.canLookUp && actions.canEdit,
        covers: actions.canAddCover, upgrade: actions.canUpgrade, restore: actions.canRestore, remove: actions.canRemove)
}

extension PhoneHealth {
    /// The plan for the set of copies at `index`, keeping `keep` (the best copy unless a person
    /// picked another). Nil for a set that is not on the signed-in server's disk.
    public func duplicatePlan(_ index: Int, source: String?, keep: SourceTrack? = nil) -> DuplicateFix<SourceTrack>? {
        guard copyGroups.indices.contains(index), let source else { return nil }
        let group = copyGroups[index]
        guard group.best.sourceId == source else { return nil }
        let kept = keep.flatMap { k in group.copies.first { $0.id == k.id } } ?? group.best
        return duplicateFix(group, serverCopyHealth, keep: kept)
    }

    /// The source's copy that one library song of a set stands for.
    public func copyIn(_ index: Int, trackId: String) -> SourceTrack? {
        guard copyGroups.indices.contains(index) else { return nil }
        return copyGroups[index].copies.first { $0.mergedId == trackId }
    }

    /// Every set on the signed-in server, each with the steps "Fix all" takes: its fills, never a
    /// differing value, and the others removed.
    public func fixAllDuplicates(source: String?, edit: Bool) -> [(DuplicateFix<SourceTrack>, [FixStep])] {
        copyGroups.indices.compactMap { index in
            guard let plan = duplicatePlan(index, source: source) else { return nil }
            return (plan, plan.serverSteps(plan.fills, edit: edit))
        }
    }

    /// The join for the split album at `index`, led by the first song of its largest part the
    /// server has, with its steps. Nil when the server has nothing of it to move.
    public func joinPlan(_ index: Int, serverIds: [String: String]) -> (AlbumJoin<LibraryTrack>, [FixStep])? {
        guard report.splitAlbums.indices.contains(index) else { return nil }
        let album = report.splitAlbums[index]
        guard let lead = album.parts[0].songs.first(where: { serverIds[$0.id] != nil }) else { return nil }
        var join = albumJoin(album)
        join.lead = lead
        let steps = join.steps(fields).onServer(serverIds)
        return steps.isEmpty ? nil : (join, steps)
    }

    /// Every split album the server can join, one after another.
    public func joinAll(serverIds: [String: String]) -> [FixStep] {
        report.splitAlbums.indices.flatMap { joinPlan($0, serverIds: serverIds)?.1 ?? [] }
    }

    /// A check's missing tag filled where the rest of the album agrees, one step per song the
    /// server has.
    public func fillSteps(_ check: HealthCheck, serverIds: [String: String]) -> [FixStep] {
        guard let tag = check.tag else { return [] }
        return fillsFromAlbum(report.missing[tag] ?? [], all: tracks, tag: tag, fields)
            .map { FixStep.retag(id: $0.0.id, title: $0.0.title, tags: [$0.1.tag: $0.1.value]) }
            .onServer(serverIds)
    }

    /// A cover looked for, for each song without one the server has.
    public func coverSteps(serverIds: [String: String]) -> [FixStep] {
        (report.missing[.cover] ?? []).map { FixStep.addCover(id: $0.id, title: $0.title) }.onServer(serverIds)
    }

    /// What a check's button for everything would do, shown before it runs: one line per set,
    /// album or song, and the steps it takes. Songs with no copy on the server, and anything it
    /// cannot do, are left out.
    public func fixAllPreview(_ check: HealthCheck, offers: HealthOffers, source: String?, serverIds: [String: String]) -> FixPreview {
        guard offers.fixesAll(check) else { return FixPreview() }
        switch check {
        case .duplicates:
            let plans = fixAllDuplicates(source: source, edit: offers.edit)
            let lines = plans.map { plan, steps -> (String, String?) in
                let fills = steps.flatMap { step -> [String] in
                    guard case .retag(_, _, let tags) = step else { return [] }
                    return tagsInOrder(tags).map { TagChange($0.0, now: nil, value: $0.1).words }
                }
                let removes = "Removes " + plan.remove.map { copyName($0, serverCopyHealth) }.joined(separator: ", ") + "."
                let detail = fills.isEmpty ? removes : "\(removes) Fills in \(fills.joined(separator: ", "))."
                return ("Keeps \(copyName(plan.keep, serverCopyHealth))", detail)
            }
            return FixPreview(count: plans.count, lines: lines, steps: plans.flatMap(\.1))
        case .splitAlbums:
            let joins = report.splitAlbums.indices.compactMap { index in
                joinPlan(index, serverIds: serverIds).map { (report.splitAlbums[index], $0) }
            }
            return FixPreview(count: joins.count, lines: joins.map { ($0.0.heading, $0.1.0.words) }, steps: joins.flatMap(\.1.1))
        case .noCover:
            let steps = coverSteps(serverIds: serverIds)
            return FixPreview(count: steps.count, lines: steps.map { ($0.title, nil) }, steps: steps)
        case .noYear, .noGenre, .noAlbumArtist:
            let steps = fillSteps(check, serverIds: serverIds)
            let lines = steps.map { step -> (String, String?) in
                guard case .retag(_, _, let tags) = step else { return (step.title, nil) }
                return (step.title, tagsInOrder(tags).map { TagChange($0.0, now: nil, value: $0.1).words }
                    .joined(separator: ", "))
            }
            return FixPreview(count: steps.count, lines: lines, steps: steps)
        case .noTrackNumber, .noLength:
            // Looked up first, then reviewed; and asked through Find higher quality.
            return FixPreview()
        }
    }
}

extension DuplicateFix where T == SourceTrack {
    /// The tags a person picked from the copies' differing values, by tag: the copy whose value is
    /// kept. One picked from the kept copy changes nothing.
    public func picked(_ choices: [String: String]) -> [TagChange] {
        differs.compactMap { choice in
            guard let from = choices[choice.tag], let value = choice.value(of: from) else { return nil }
            let now = choice.value(of: keep.nativeId)
            return value == now ? nil : TagChange(choice.tag, now: now, value: value, from: from)
        }
    }

    /// The steps for one set: fill the kept copy's tags when the server can write them, then send
    /// the others to the trash.
    public func serverSteps(_ changes: [TagChange], edit: Bool) -> [FixStep] {
        steps(serverCopyHealth, fills: edit ? changes : [])
    }
}

/// The songs one bulk look-up takes: the first the server has, at most a batch, each with its id
/// there.
public func lookupBatch(_ songs: [LibraryTrack], serverIds: [String: String], limit: Int = lookupBatchSize) -> [(LibraryTrack, String)] {
    var seen = Set<String>()
    var out: [(LibraryTrack, String)] = []
    for song in songs {
        guard out.count < limit, let id = serverIds[song.id], seen.insert(id).inserted else { continue }
        out.append((song, id))
    }
    return out
}

/// The step that writes the changes picked for one song, if any.
public func retagStep(_ serverId: String, title: String, changes: [TagChange]) -> FixStep? {
    guard !changes.isEmpty else { return nil }
    var tags: [String: String] = [:]
    for change in changes { tags[change.tag] = change.value }
    return .retag(id: serverId, title: title, tags: tags)
}

/// What a check's button for everything would do, shown before it runs.
public struct FixPreview: @unchecked Sendable {
    public var count = 0
    public var lines: [(String, String?)] = []
    public var steps: [FixStep] = []

    public init(count: Int = 0, lines: [(String, String?)] = [], steps: [FixStep] = []) {
        self.count = count
        self.lines = lines
        self.steps = steps
    }
}
