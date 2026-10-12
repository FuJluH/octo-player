import Foundation

// The tag names lyrics are kept under, as tag libraries name them: MP3 USLT frames read as
// LYRICS (or LYRICS:<description>), MP4 and FLAC LYRICS, and some taggers write UNSYNCEDLYRICS.
// Synced SYLT frames are seldom read by tag libraries at all, but most taggers also write LRC text
// into USLT, which is.
private let lyricsTags = ["LYRICS", "UNSYNCEDLYRICS", "UNSYNCED LYRICS", "SYNCEDLYRICS"]

/// The best lyrics text among a file's tags, in the order the tag reader gave them: timed (LRC)
/// text before plain, then in the order above. Nil when the file has none.
public func songFileLyrics(_ tags: [(key: String, value: [String])]) -> String? {
    func rank(_ key: String) -> Int {
        let name = key.uppercaseRoot()
        let head = name.units.firstIndex(of: 0x3A).map { name.utf16Slice(0, $0) } ?? name
        return lyricsTags.firstIndex { $0.utf16Equals(head) } ?? lyricsTags.count
    }
    let found = tags
        .filter { entry in
            let name = entry.key.uppercaseRoot()
            return lyricsTags.contains { $0.utf16Equals(name) } || name.startsWith("LYRICS:", ignoreCase: false)
        }
        .stableSorted { rank($0.key) < rank($1.key) }
        .flatMap(\.value)
        .filter { !$0.isBlankText }
    return found.first(where: looksTimed) ?? found.first
}

/// The same for tags without an order of their own; they are taken by name.
public func songFileLyrics(_ tags: [String: [String]]) -> String? {
    songFileLyrics(tags.sorted { $0.key.utf16.lexicographicallyPrecedes($1.key.utf16) }.map { (key: $0.key, value: $0.value) })
}

// An LRC line stamp at the start of any line, after any spaces.
private let timedStamp = TextPattern(#"(?:\A|(?<=[\n\r\u0085  ]))[ \t\n\u000B\f\r]*\[[0-9]{1,3}:[0-9]{1,2}"#)

/// Whether text has LRC line stamps.
public func looksTimed(_ text: String) -> Bool { timedStamp.containsMatch(in: text) }
