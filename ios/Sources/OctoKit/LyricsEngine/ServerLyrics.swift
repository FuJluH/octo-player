import Foundation

/// The server's lyrics as one set: the main lyrics, synced ones first and word-timed ones before
/// those, with a translation into `language` beside each line when the server has one and the
/// song is in another language. Nil when the server has nothing to show.
public func serverLyrics(_ all: [StructuredLyrics], language: String?) -> Lyrics? {
    let mains = all.filter { ($0.kind == nil || $0.kind == "main") && $0.line.contains { !$0.value.isBlankText } }
    // The first of the highest score wins.
    var best: StructuredLyrics?
    var bestScore = 0
    for candidate in mains {
        let score = (candidate.synced ? 2 : 0) + (candidate.cueLine.isEmpty ? 0 : 1)
        if best == nil || score > bestScore {
            best = candidate
            bestScore = score
        }
    }
    guard let main = best else { return nil }
    if !main.synced {
        return Lyrics(synced: false, lines: main.line.map { LyricLine(text: $0.value.trimWhitespace()) }, source: .server)
    }

    var roles: [String: LyricsAgent] = [:]
    for agent in main.agents { roles[agent.id] = agent }
    var cues: [Int: [CueLine]] = [:]
    for cueLine in main.cueLine { cues[cueLine.index, default: []].append(cueLine) }
    func role(_ layer: CueLine) -> LyricsAgent? { layer.agentId.flatMap { roles[$0] } }

    let lines: [LyricLine] = main.line.enumerated().map { index, line in
        let start = line.start ?? 0
        let layers = cues[index] ?? []
        if layers.isEmpty { return LyricLine(startMs: start, text: line.value.trimWhitespace()) }
        let backing = layers.filter { role($0)?.role == "bg" }
        let leads = layers.filter { role($0)?.role != "bg" }
        let lead = joinLayers(leads)
        let back = joinLayers(backing)
        let first = leads.first.flatMap(role)
        let ends = layers.compactMap { $0.end ?? $0.cue.compactMap(\.end).max() }
        guard let lead else {
            // Only the backing voices sing this line.
            return LyricLine(
                startMs: start,
                endMs: ends.max(),
                text: back?.text ?? "",
                words: back?.words ?? [],
                background: true
            )
        }
        return LyricLine(
            startMs: start,
            endMs: ends.max(),
            text: lead.text,
            words: lead.words,
            backingText: back?.text ?? "",
            backing: back?.words ?? [],
            agent: first?.name,
            duet: first?.role == "voice"
        )
    }

    let translated = companionFor(all, main, language, "translation")
    let sounded = companionFor(all, main, language, "pronunciation", matchLanguage: false)
    let offset = main.offset
    return Lyrics(
        synced: true,
        lines: lines.enumerated().map { index, line in
            var line = line
            line.translation = translated?[index]
            line.romanization = sounded?[index]
            return line.shifted(-offset)
        },
        source: .server
    )
}

// Several cue lines for one lyric line (two voices at once) read as one text with a space
// between; each one's words keep their place in it.
private func joinLayers(_ layers: [CueLine]) -> (text: String, words: [LyricWord])? {
    if layers.isEmpty { return nil }
    var text: [UInt16] = []
    var words: [LyricWord] = []
    for layer in layers {
        if !text.isEmpty { text.append(0x20) }
        // Spaces a cue line starts with are left out, since the lyrics view trims its lines and
        // the words must keep their places.
        let value = layer.value.units
        let cut = value.count - layer.value.trimStartWhitespace().utf16.count
        let shift = text.count - cut
        text += value[cut...]
        words += cueWords(layer).filter { $0.to > cut }.map { word in
            var word = word
            word.from = max(word.from, cut) + shift
            word.to = word.to + shift
            return word
        }
    }
    return (String(units: text), words)
}

/// A cue line's timed words, placed in its text by UTF-16 unit. The server gives each cue's place
/// in UTF-8 bytes, both ends included; a cue whose bytes do not fit the text is left out.
public func cueWords(_ line: CueLine) -> [LyricWord] {
    let chars = Utf8Positions(line.value)
    let value = line.value.units
    var words: [LyricWord] = []
    for (index, cue) in line.cue.enumerated() {
        guard let range = chars.charRange(cue.byteStart, cue.byteEnd) else { continue }
        let next = index + 1 < line.cue.count ? line.cue[index + 1].start : nil
        words.append(LyricWord(
            startMs: cue.start,
            endMs: cue.end ?? next ?? line.end,
            text: String(units: value[range]),
            from: range.lowerBound,
            to: range.upperBound
        ))
    }
    return words
}

/// Turns UTF-8 byte positions in a text into UTF-16 positions. Letters outside the basic set take
/// two to four bytes; one written with a surrogate pair (an emoji, say) takes four bytes and two
/// units.
public struct Utf8Positions: Sendable {
    private let text: [UInt16]
    // For each byte, the unit its letter starts at.
    private let charAt: [Int]

    public init(_ text: String) {
        let units = text.units
        var starts: [Int] = []
        starts.reserveCapacity(units.count * 2)
        var index = 0
        while index < units.count {
            let (point, width) = codePoint(units, index)
            let bytes: Int
            if point < 0x80 {
                bytes = 1
            } else if point < 0x800 {
                bytes = 2
            } else if point < 0x10000 {
                bytes = 3
            } else {
                bytes = 4
            }
            for _ in 0..<bytes { starts.append(index) }
            index += width
        }
        self.text = units
        charAt = starts
    }

    /// The units from the letter holding `byteStart` through the letter holding `byteEnd`. Nil
    /// when the bytes are outside the text or backwards.
    public func charRange(_ byteStart: Int, _ byteEnd: Int) -> Range<Int>? {
        if byteStart < 0 || byteEnd < byteStart || byteEnd >= charAt.count { return nil }
        let from = charAt[byteStart]
        let lastLetter = charAt[byteEnd]
        let to = lastLetter + codePoint(text, lastLetter).width
        return from..<to
    }
}

// The code point starting at `index`, and how many units it takes: two for a surrogate pair, one
// for anything else, a lone surrogate included.
private func codePoint(_ units: [UInt16], _ index: Int) -> (point: UInt32, width: Int) {
    let unit = units[index]
    if unit >= 0xD800 && unit <= 0xDBFF && index + 1 < units.count {
        let low = units[index + 1]
        if low >= 0xDC00 && low <= 0xDFFF {
            return (0x10000 + ((UInt32(unit) - 0xD800) << 10) + (UInt32(low) - 0xDC00), 2)
        }
    }
    return (UInt32(unit), 1)
}

// A translation's or pronunciation's text for each line of the main lyrics, by line number when
// both have the same lines, or else by start time. Only when the phone reads another language
// than the song is sung in. A translation must be in the phone's language; a pronunciation is in
// whatever letters the server wrote it in.
private func companionFor(
    _ all: [StructuredLyrics],
    _ main: StructuredLyrics,
    _ language: String?,
    _ kind: String,
    matchLanguage: Bool = true
) -> [Int: String]? {
    guard let language, !language.isBlankText, !sameLanguage(main.lang ?? "und", language) else { return nil }
    guard let translation = all.first(where: { $0.kind == kind && (!matchLanguage || sameLanguage($0.lang ?? "und", language)) })
    else { return nil }
    var found: [Int: String] = [:]
    if translation.line.count == main.line.count {
        for (index, line) in translation.line.enumerated() where !line.value.isBlankText {
            found[index] = line.value.trimWhitespace()
        }
    } else {
        var byStart: [Int: String] = [:]
        for line in translation.line {
            guard let start = line.start, !line.value.isBlankText else { continue }
            byStart[start] = line.value.trimWhitespace()
        }
        for (index, line) in main.line.enumerated() {
            if let start = line.start, let text = byStart[start] { found[index] = text }
        }
    }
    return found
}

/// Whether two language tags name the same language, whether written with two letters ("en") or
/// three ("eng").
func sameLanguage(_ a: String, _ b: String) -> Bool {
    func key(_ tag: String) -> String {
        let language = languageSubtag(tag.replacingUnit(0x5F, with: 0x2D))
        let short = language.isEmpty ? tag.lowercaseRoot() : language
        // A three-letter language is its own long form, and no language has none; a two-letter
        // one is looked up, and one without a long form keeps its short one.
        if language.isEmpty { return short }
        if language.utf16.count == 3 { return language }
        return iso3Languages[language] ?? short
    }
    return key(a) == key(b)
}

// The language of a BCP 47 tag, lowercased: its first subtag when that is two to eight ASCII
// letters, and none for "und" or a tag that does not start with a language.
private func languageSubtag(_ tag: String) -> String {
    let first = tag.units.split(separator: 0x2D, maxSplits: 1, omittingEmptySubsequences: false).first ?? []
    guard (2...8).contains(first.count),
          first.allSatisfy({ ($0 >= 0x41 && $0 <= 0x5A) || ($0 >= 0x61 && $0 <= 0x7A) }) else { return "" }
    let language = String(units: first.map(simpleLower))
    return language == "und" ? "" : language
}

// ISO 639-1 languages and their ISO 639-2 three-letter forms, the old two-letter codes ("iw",
// "in", "ji") included.
private let iso3Languages: [String: String] = [
    "aa": "aar", "ab": "abk", "ae": "ave", "af": "afr", "ak": "aka", "am": "amh", "an": "arg",
    "ar": "ara", "as": "asm", "av": "ava", "ay": "aym", "az": "aze", "ba": "bak", "be": "bel",
    "bg": "bul", "bi": "bis", "bm": "bam", "bn": "ben", "bo": "bod", "br": "bre", "bs": "bos",
    "ca": "cat", "ce": "che", "ch": "cha", "co": "cos", "cr": "cre", "cs": "ces", "cu": "chu",
    "cv": "chv", "cy": "cym", "da": "dan", "de": "deu", "dv": "div", "dz": "dzo", "ee": "ewe",
    "el": "ell", "en": "eng", "eo": "epo", "es": "spa", "et": "est", "eu": "eus", "fa": "fas",
    "ff": "ful", "fi": "fin", "fj": "fij", "fo": "fao", "fr": "fra", "fy": "fry", "ga": "gle",
    "gd": "gla", "gl": "glg", "gn": "grn", "gu": "guj", "gv": "glv", "ha": "hau", "he": "heb",
    "hi": "hin", "ho": "hmo", "hr": "hrv", "ht": "hat", "hu": "hun", "hy": "hye", "hz": "her",
    "ia": "ina", "id": "ind", "ie": "ile", "ig": "ibo", "ii": "iii", "ik": "ipk", "in": "ind",
    "io": "ido", "is": "isl", "it": "ita", "iu": "iku", "iw": "heb", "ja": "jpn", "ji": "yid",
    "jv": "jav", "jw": "jaw", "ka": "kat", "kg": "kon", "ki": "kik", "kj": "kua", "kk": "kaz",
    "kl": "kal", "km": "khm", "kn": "kan", "ko": "kor", "kr": "kau", "ks": "kas", "ku": "kur",
    "kv": "kom", "kw": "cor", "ky": "kir", "la": "lat", "lb": "ltz", "lg": "lug", "li": "lim",
    "ln": "lin", "lo": "lao", "lt": "lit", "lu": "lub", "lv": "lav", "mg": "mlg", "mh": "mah",
    "mi": "mri", "mk": "mkd", "ml": "mal", "mn": "mon", "mo": "mol", "mr": "mar", "ms": "msa",
    "mt": "mlt", "my": "mya", "na": "nau", "nb": "nob", "nd": "nde", "ne": "nep", "ng": "ndo",
    "nl": "nld", "nn": "nno", "no": "nor", "nr": "nbl", "nv": "nav", "ny": "nya", "oc": "oci",
    "oj": "oji", "om": "orm", "or": "ori", "os": "oss", "pa": "pan", "pi": "pli", "pl": "pol",
    "ps": "pus", "pt": "por", "qu": "que", "rm": "roh", "rn": "run", "ro": "ron", "ru": "rus",
    "rw": "kin", "sa": "san", "sc": "srd", "sd": "snd", "se": "sme", "sg": "sag", "sh": "srp",
    "si": "sin", "sk": "slk", "sl": "slv", "sm": "smo", "sn": "sna", "so": "som", "sq": "sqi",
    "sr": "srp", "ss": "ssw", "st": "sot", "su": "sun", "sv": "swe", "sw": "swa", "ta": "tam",
    "te": "tel", "tg": "tgk", "th": "tha", "ti": "tir", "tk": "tuk", "tl": "tgl", "tn": "tsn",
    "to": "ton", "tr": "tur", "ts": "tso", "tt": "tat", "tw": "twi", "ty": "tah", "ug": "uig",
    "uk": "ukr", "ur": "urd", "uz": "uzb", "ve": "ven", "vi": "vie", "vo": "vol", "wa": "wln",
    "wo": "wol", "xh": "xho", "yi": "yid", "yo": "yor", "za": "zha", "zh": "zho", "zu": "zul",
]
