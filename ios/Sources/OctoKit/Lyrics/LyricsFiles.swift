import Foundation

/// A lyrics file bigger than this is not a lyrics file.
public let MAX_LYRICS_FILE_BYTES = 1 << 20

/// The names a song's lyrics file can have: the song's name with .lrc, in either case.
public func lyricsFileNames(_ songFileName: String) -> [String] {
    guard let dot = songFileName.lastIndex(of: ".") else { return [] }
    let base = String(songFileName[..<dot])
    if base.isEmpty { return [] }
    return ["\(base).lrc", "\(base).LRC"]
}

/// A lyrics file's text. Most are UTF-8; older ones are often Windows Latin-1, so a file that is
/// not valid UTF-8 is read that way.
public func decodeText(_ bytes: [UInt8]) -> String {
    if let text = String(validating: bytes, as: UTF8.self) { return text }
    var scalars = String.UnicodeScalarView()
    for byte in bytes {
        if (0x80...0x9F).contains(byte) {
            scalars.append(windows1252[byte] ?? "\u{FFFD}")
        } else {
            scalars.append(Unicode.Scalar(byte))
        }
    }
    return String(scalars)
}

/// Reads a lyrics file beside a song file on the phone: same folder, same name with .lrc. Nil
/// when there is none, it cannot be read, or it is too big.
public func lyricsFileBeside(_ songFile: URL) -> String? {
    let folder = songFile.deletingLastPathComponent()
    for name in lyricsFileNames(songFile.lastPathComponent) {
        let file = folder.appendingPathComponent(name)
        guard let size = (try? FileManager.default.attributesOfItem(atPath: file.path))?[.size] as? NSNumber,
              size.intValue <= MAX_LYRICS_FILE_BYTES,
              let data = try? Data(contentsOf: file)
        else { continue }
        return decodeText(Array(data))
    }
    return nil
}

// Windows-1252's letters where Latin-1 has control codes.
private let windows1252: [UInt8: Unicode.Scalar] = [
    0x80: "\u{20AC}", 0x82: "\u{201A}", 0x83: "\u{0192}", 0x84: "\u{201E}", 0x85: "\u{2026}", 0x86: "\u{2020}",
    0x87: "\u{2021}", 0x88: "\u{02C6}", 0x89: "\u{2030}", 0x8A: "\u{0160}", 0x8B: "\u{2039}", 0x8C: "\u{0152}",
    0x8E: "\u{017D}", 0x91: "\u{2018}", 0x92: "\u{2019}", 0x93: "\u{201C}", 0x94: "\u{201D}", 0x95: "\u{2022}",
    0x96: "\u{2013}", 0x97: "\u{2014}", 0x98: "\u{02DC}", 0x99: "\u{2122}", 0x9A: "\u{0161}", 0x9B: "\u{203A}",
    0x9C: "\u{0153}", 0x9E: "\u{017E}", 0x9F: "\u{0178}",
]
