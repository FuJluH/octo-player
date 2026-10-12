import Foundation

// Octo's radio: songs like the seeds, from the library and from what the server suggests,
// played the way a good station plays them.
//
// Each song is a list of weighted features: its genres (a genre that is rare in this library
// says more), each genre in the song's era, its year, and who made it. How alike a song is to the
// seeds is the cosine of the two lists, but only when they share a genre: a shared year or artist
// lifts a song that already fits and never pulls in one that does not. The server's suggestions
// add a bonus by their rank. Picks are drawn at random with the better matches favored, then
// spaced so an album, a title or an artist does not come back too soon. Songs from outside the
// library land at random, at the share the listener chose (see RadioTuning).

private let genreWeight = 1.0
private let eraWeight = 1.0
private let yearWeight = 0.5
private let artistWeight = 0.6
private let composerWeight = 0.4
private let yearSpread = 7

/// A server suggestion's bonus: the top one counts about as much as a close match from the
/// library, and the bonus fades down its list.
private let suggestedWeight = 0.5
private let rankDepth = 20.0

/// Songs played this recently wait until nothing else will do.
let recentDays = 8

/// Nudges: a song not marked as a favorite, one played a lot, and one played in the last couple
/// of weeks each give up a tenth.
private let freshDays = 15
private let manyPlays = 4
private let nudge = 0.9

/// An artist with a song rated one star gives up half.
private let dislikedArtist = 0.5

/// How far a radio may drift from its share of outside songs, in songs, before the next pick puts
/// it right.
private let shareSlack = 1.5

/// The most songs of the rarer kind in a row.
private let rarerRun = 2

/// What a favorite counts for when the listener asks for favorites more often.
private let favoriteBoost = 1.15

/// A big library is sampled, and only the best matches are drawn from.
private let candidateCap = 4000
private let keepAtLeast = 200
private let keepPerPick = 8

private let dayMs = 86_400_000

/// What the radio is asked for.
public struct RadioInput {
    /// What the radio is like. The first is what it started from.
    public var seeds: [RadioSong]
    /// Every song in the library.
    public var library: [RadioSong]
    /// The server's songs like the seeds, best first.
    public var suggested: [RadioSong]
    /// What played or is queued just before, oldest first; the spacing carries on from these.
    public var before: [RadioSong]
    /// Never picked, like the queue. The first seed is never picked either.
    public var exclude: Set<String>
    public var now: Int
    public var tuning: RadioTuning
    /// Which of the songs in `before` came from outside the library, oldest first. Nil works it
    /// out from the library.
    public var beforeOutside: [Bool]?

    public init(seeds: [RadioSong], library: [RadioSong], suggested: [RadioSong] = [], before: [RadioSong] = [],
                exclude: Set<String> = [], now: Int, tuning: RadioTuning = RadioTuning(), beforeOutside: [Bool]? = nil) {
        self.seeds = seeds
        self.library = library
        self.suggested = suggested
        self.before = before
        self.exclude = exclude
        self.now = now
        self.tuning = tuning
        self.beforeOutside = beforeOutside
    }
}

private final class Scored {
    let song: RadioSong
    let score: Double
    init(_ song: RadioSong, _ score: Double) {
        self.song = song
        self.score = score
    }
}

/// Up to `count` songs like the seeds, in play order. Empty when nothing is alike at all (the
/// seeds have no genre and the server suggested nothing).
public func radioMix(_ input: RadioInput, count: Int, random: inout OctoRandom) -> [RadioSong] {
    guard count > 0, let firstSeed = input.seeds.first else { return [] }
    let everything = input.library + input.suggested
    let rarity = genreRarity(everything)
    var seedFeatures: [String: Double] = [:]
    for seed in input.seeds { features(seed, rarity, &seedFeatures) }
    let seedNorm = seedFeatures.keys.sorted().reduce(0.0) { $0 + seedFeatures[$1]! * seedFeatures[$1]! }.squareRoot()
    let seedGenres = Set(input.seeds.flatMap(\.genreKeys))
    let seedArtists = Set(input.seeds.flatMap(\.artistKeys))
    let disliked = Set(everything.filter { $0.rating == 1 }.flatMap(\.artistKeys))
    var rank: [String: Int] = [:]
    for (index, song) in input.suggested.enumerated() where rank[song.id] == nil { rank[song.id] = index }
    let skip = input.exclude.union([firstSeed.id])
    let owned = Set(input.library.map(\.id))

    // Library songs that could fit: sharing a genre or an artist with the seeds.
    var fromLibrary = input.library.filter { song in
        song.genreKeys.contains(where: seedGenres.contains) || song.artistKeys.contains(where: seedArtists.contains)
    }
    if fromLibrary.count > candidateCap { fromLibrary = Array(random.shuffled(fromLibrary).prefix(candidateCap)) }
    var seen = Set<String>()
    var candidates: [Scored] = []
    for song in input.suggested + fromLibrary where seen.insert(song.id).inserted {
        if skip.contains(song.id) || song.rating == 1 || isRadioFiller(song.title, durationMs: song.durationMs, genres: song.genres) { continue }
        var own: [String: Double] = [:]
        features(song, rarity, &own)
        var score = likeness(own, seedFeatures, seedNorm)
        if let at = rank[song.id] { score += suggestedWeight / (1 + Double(at) / rankDepth) }
        let nudgedScore = nudged(song, score, input.now, disliked, input.tuning.favorites)
        if nudgedScore > 0 { candidates.append(Scored(song, nudgedScore)) }
    }
    let scored = stableSortedByScore(candidates)
    // Songs the library has and songs it does not are drawn from apart, so the new ones keep
    // their share. Only the library's are trimmed.
    let fromOwned = scored.filter { owned.contains($0.song.id) }
    let found = scored.filter { !owned.contains($0.song.id) }
    // Only my library: songs from outside it never play, not even to fill.
    let fromNew = input.tuning.discovery == .libraryOnly ? [] : found
    let heardAfter = input.now - recentDays * dayMs
    let heardLately = { (s: Scored) in (s.song.lastPlayedAt ?? Int.min) >= heardAfter }
    let keep = max(keepAtLeast, Int(Double(count * keepPerPick) * input.tuning.adventure.keep))
    let fresh = fromOwned.filter { !heardLately($0) }
    let lately = fromOwned.filter(heardLately)
    let known = Array(fresh.prefix(keep))
    let spare = Array(lately.prefix(keep))
    let titleGap = radioSpacing(input.library.count)
    let gap = max(2, Int((Double(titleGap) * input.tuning.variety.scale).rounded(.toNearestOrAwayFromZero)))
    let beforeOutside = input.beforeOutside ?? input.before.map { !owned.contains($0.id) }
    return pick(known: known, discovered: fromNew.filter { !heardLately($0) }, spare: spare + fromNew.filter(heardLately),
                before: input.before, count: count, spacing: (gap, titleGap), asked: input.tuning.discovery.share,
                reach: input.tuning.adventure.reach, leadRun: runOf(beforeOutside), random: &random)
}

/// Best score first, keeping the order of equal scores.
private func stableSortedByScore(_ items: [Scored]) -> [Scored] {
    let indexed: [(offset: Int, element: Scored)] = Array(items.enumerated())
    let sorted = indexed.sorted { a, b in
        if a.element.score != b.element.score { return a.element.score > b.element.score }
        return a.offset < b.offset
    }
    return sorted.map(\.element)
}

/// The run of one kind at the end of `outside` (oldest first): above 0 for songs from outside the
/// library, below 0 for the library's.
func runOf(_ outside: [Bool]) -> Int {
    guard let last = outside.last else { return 0 }
    let length = outside.reversed().prefix { $0 == last }.count
    return last ? length : -length
}

/// The share of the picks that can go to songs from outside the library: the share asked for, as
/// far as there are songs of each kind to fill it.
func pacedShare(_ share: Double, outside: Int, library: Int, slots: Int) -> Double {
    if slots <= 0 || outside + library == 0 { return share }
    if outside + library < slots { return Double(outside) / Double(outside + library) }
    let most = min(max(Double(outside) / Double(slots), 0), 1)
    let least = min(max(1.0 - Double(library) / Double(slots), 0), 1)
    return min(max(share, least), most)
}

/// How many picks apart an album or a title must be; an artist must be half as far. Grows with
/// the library: 8 for a small one, up to 30.
public func radioSpacing(_ librarySize: Int) -> Int { min(max(Int(6.7 + Double(librarySize) / 6000.0), 8), 30) }

/// Whether the next pick goes to a song from outside the library. A draw at the share, so outside
/// songs land anywhere instead of every third song; pulled back once the radio is more than
/// `shareSlack` songs off its share; and never more than `rarerRun` of the rarer kind in a row.
func outsideDue(_ share: Double, picked: Int, outside: Int, run: Int, random: inout OctoRandom) -> Bool {
    if share <= 0 { return false }
    if share >= 1 { return true }
    let target = share * Double(picked + 1)
    if target - Double(outside) > shareSlack { return true }
    if Double(outside + 1) - target > shareSlack { return false }
    if share < 0.5 && run >= rarerRun { return false }
    if share > 0.5 && run <= -rarerRun { return true }
    return random.nextDouble() < share
}

/// Picks in play order from two sorted lists: `known` (the library's) and `discovered`
/// (suggestions the library does not have), keeping about `asked` of the picks for the second
/// while it lasts, placed at random. A draw may land as far down a list as `reach` of its total
/// weight.
private func pick(known: [Scored], discovered: [Scored], spare: [Scored], before: [RadioSong], count: Int,
                  spacing: (gap: Int, title: Int), asked: Double, reach: Double, leadRun: Int,
                  random: inout OctoRandom) -> [RadioSong] {
    let all = known + discovered
    let albums = Set(all.compactMap(\.song.album)).count
    let artists = Set(all.flatMap(\.song.artistKeys)).count
    var played = before
    var picked: [RadioSong] = []
    var taken = Set<String>()
    var held: [Scored] = []
    var heldIds = Set<String>()
    let knownTotal = known.reduce(0) { $0 + $1.score }
    let discoveredTotal = discovered.reduce(0) { $0 + $1.score }
    let discoveredIds = Set(discovered.map { ObjectIdentifier($0) })
    var newPicks = 0
    var run = leadRun
    let share = asked <= 0 ? 0 : pacedShare(asked, outside: discovered.count, library: known.count, slots: count)

    func draw(_ list: [Scored], _ total: Double) -> Scored? {
        guard !list.isEmpty else { return nil }
        let threshold = random.nextDouble() * total * reach
        var start = 0
        var sum = list[0].score
        while start < list.count - 1 && sum < threshold {
            start += 1
            sum += list[start].score
        }
        for step in list.indices {
            let candidate = list[(start + step) % list.count]
            if taken.contains(candidate.song.id) { continue }
            if tooSoon(candidate.song, played, spacing, albums, artists, &random) {
                if heldIds.insert(candidate.song.id).inserted { held.append(candidate) }
                continue
            }
            return candidate
        }
        return nil
    }

    var tries = 0
    while picked.count < count && taken.count < all.count && tries < count * 100 {
        tries += 1
        let newDue = outsideDue(share, picked: picked.count, outside: newPicks, run: run, random: &random)
            && discovered.contains { !taken.contains($0.song.id) }
        let chosen = newDue ? (draw(discovered, discoveredTotal) ?? draw(known, knownTotal))
            : (draw(known, knownTotal) ?? draw(discovered, discoveredTotal))
        guard let chosen else { continue }
        taken.insert(chosen.song.id)
        picked.append(chosen.song)
        played.append(chosen.song)
        if discoveredIds.contains(ObjectIdentifier(chosen)) {
            newPicks += 1
            run = max(run, 0) + 1
        } else {
            run = min(run, 0) - 1
        }
    }
    // Not enough with the spacing: the best of what it held back, then songs heard lately, never
    // the same artist twice in a row unless nothing else is left.
    var restSeen = Set<String>()
    var rest: [RadioSong] = []
    for scored in stableSortedByScore(held) + spare where !taken.contains(scored.song.id) && restSeen.insert(scored.song.id).inserted {
        rest.append(scored.song)
    }
    while picked.count < count && !rest.isEmpty {
        let last = played.last
        let at = rest.firstIndex { song in last == nil || !song.artistKeys.contains(where: last!.artistKeys.contains) } ?? 0
        let next = rest.remove(at: at)
        taken.insert(next.id)
        picked.append(next)
        played.append(next)
    }
    return picked
}

/// Whether a song would come too soon after the same album, title, artist or composer. The
/// distance is drawn fresh each time so the spacing does not feel mechanical, and never asks for
/// more variety than the pool has.
private func tooSoon(_ song: RadioSong, _ played: [RadioSong], _ spacing: (gap: Int, title: Int), _ albums: Int, _ artists: Int,
                     _ random: inout OctoRandom) -> Bool {
    let gap = spacing.gap
    let far = min(gap + random.nextInt(gap), albums - 1, played.count)
    if far > 0, let album = song.album, played.suffix(far).contains(where: { $0.album == album }) { return true }
    // The title waits the usual spacing whatever the variety; at Normal it is the album's
    // distance, drawn once.
    let titleFar = spacing.title == gap ? far : min(spacing.title + random.nextInt(spacing.title), albums - 1, played.count)
    if titleFar > 0 && !song.titleKey.isEmpty && played.suffix(titleFar).contains(where: { $0.titleKey == song.titleKey }) { return true }
    let half = gap / 2
    let near = min(half + random.nextInt(half + 1), artists - 1, played.count)
    if near <= 0 { return false }
    return played.suffix(near).contains { other in
        other.artistKeys.contains(where: song.artistKeys.contains) || other.composerKeys.contains(where: song.composerKeys.contains)
    }
}

/// How telling each genre is in this library: a rarer genre says more. Counted by album, so a
/// long album counts no more than a short one.
private func genreRarity(_ songs: [RadioSong]) -> [String: Double] {
    var albums = Set<String>()
    var withGenre: [String: Set<String>] = [:]
    for song in songs {
        let album = song.album ?? song.id
        albums.insert(album)
        for genre in song.genreKeys { withGenre[genre, default: []].insert(album) }
    }
    return withGenre.mapValues { log(1.0 + Double(albums.count) / Double($0.count)) }
}

/// A year spread over the seven either side, most on the year itself, so 1994 and 1997 count as
/// close. The spread has a length of one.
private let yearShape: [Double] = {
    let raw = (0...(2 * yearSpread)).map { cos(Double($0 - yearSpread) / (Double(yearSpread) + 1.0) * Double.pi / 2) }
    let length = raw.reduce(0) { $0 + $1 * $1 }.squareRoot()
    return raw.map { $0 / length }
}()

/// A song's features, added into `into`. Genre and genre-in-its-era are what a match must share;
/// year, artist and composer only add to one.
private func features(_ song: RadioSong, _ rarity: [String: Double], _ into: inout [String: Double]) {
    let genres = song.genreKeys
    let total = genres.reduce(0) { $0 + (rarity[$1] ?? 1.0) }
    for genre in genres {
        let share = (rarity[genre] ?? 1.0) / total
        into["g:\(genre)", default: 0] += genreWeight * share
        if let year = song.year {
            for (i, w) in yearShape.enumerated() { into["e:\(genre):\(year + i - yearSpread)", default: 0] += eraWeight * share * w }
        }
    }
    if let year = song.year {
        for (i, w) in yearShape.enumerated() { into["y:\(year + i - yearSpread)", default: 0] += yearWeight * w }
    }
    for key in song.artistKeys { into["a:\(key)", default: 0] += artistWeight / Double(song.artistKeys.count) }
    for key in song.composerKeys { into["c:\(key)", default: 0] += composerWeight / Double(song.composerKeys.count) }
}

/// How alike a song is to the seeds, 0 to 1: the cosine of their features, or 0 when they share
/// no genre.
private func likeness(_ song: [String: Double], _ seeds: [String: Double], _ seedNorm: Double) -> Double {
    var core = 0.0, extra = 0.0, norm = 0.0
    for key in song.keys.sorted() {
        let weight = song[key]!
        norm += weight * weight
        guard let other = seeds[key] else { continue }
        if key.hasPrefix("g") || key.hasPrefix("e") { core += weight * other } else { extra += weight * other }
    }
    if core <= 0 || norm <= 0 || seedNorm <= 0 { return 0 }
    return (core + extra) / (norm.squareRoot() * seedNorm)
}

private func nudged(_ song: RadioSong, _ score: Double, _ now: Int, _ disliked: Set<String>, _ favorites: Bool) -> Double {
    var result = score
    if !song.liked && song.rating < 4 { result *= nudge }
    if song.plays > manyPlays { result *= nudge }
    if let last = song.lastPlayedAt, now - last < freshDays * dayMs { result *= nudge }
    if song.artistKeys.contains(where: disliked.contains) { result *= dislikedArtist }
    if favorites && (song.liked || song.rating >= 4) { result *= favoriteBoost }
    return result
}

/// How many songs a radio plays after the one it started from.
public let radioLength = 50
