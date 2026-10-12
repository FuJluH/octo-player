import Foundation

// The lyrics as the flowing view draws them: one flat list of lines, each holding its timed
// words. Times are in seconds on the lyrics' own clock.

/// A timed word, or one syllable of a word. Syllables of one word sit flush; only the last has
/// `trailingSpace`, so the word wraps as one.
public struct SyncWord: Equatable, Sendable {
    public var text: String
    public var start: Double
    public var end: Double
    public var trailingSpace: Bool

    public init(text: String, start: Double, end: Double, trailingSpace: Bool) {
        self.text = text
        self.start = start
        self.end = end
        self.trailingSpace = trailingSpace
    }
}

public struct SyncLine: Equatable, Sendable {
    /// Its place in the list.
    public var index: Int
    /// The whole line, for reading aloud.
    public var text: String
    /// Empty for an interlude.
    public var words: [SyncWord]
    public var start: Double
    public var end: Double
    /// Read right to left, as Arabic or Hebrew are.
    public var rtl: Bool
    public var translation: String?
    public var romanization: String?
    /// A gap where nobody sings: it shows dots.
    public var isInterlude: Bool
    /// Sung by the backing voices.
    public var isBackground: Bool
    /// Sung by a second lead voice, set on the other side.
    public var isDuet: Bool
    /// Timed by line only: no fill word by word, no bloom.
    public var isLineTimed: Bool
    /// The closing "Written by" line, which never ends.
    public var isCredit: Bool

    public init(
        index: Int,
        text: String,
        words: [SyncWord],
        start: Double,
        end: Double,
        rtl: Bool = false,
        translation: String? = nil,
        romanization: String? = nil,
        isInterlude: Bool = false,
        isBackground: Bool = false,
        isDuet: Bool = false,
        isLineTimed: Bool = false,
        isCredit: Bool = false
    ) {
        self.index = index
        self.text = text
        self.words = words
        self.start = start
        self.end = end
        self.rtl = rtl
        self.translation = translation
        self.romanization = romanization
        self.isInterlude = isInterlude
        self.isBackground = isBackground
        self.isDuet = isDuet
        self.isLineTimed = isLineTimed
        self.isCredit = isCredit
    }

    /// Set against the right edge: right-to-left lines, and duet lines on the side away from the
    /// lead, which flips for right-to-left songs.
    public var alignRight: Bool { rtl != isDuet }
}
