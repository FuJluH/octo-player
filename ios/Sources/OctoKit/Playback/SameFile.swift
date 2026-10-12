import Foundation

/// How far apart two lengths may be and still be the same recording, since the phone's library
/// and the file's own tags round differently.
public let sameFileLengthMs: Int64 = 1_500

/// A phone song filed under the same name as an opened file.
public struct NamedCandidate: Sendable, Equatable {
    public let id: Int64
    public let durationMs: Int64?
    public let sizeBytes: Int64?

    public init(id: Int64, durationMs: Int64?, sizeBytes: Int64?) {
        self.id = id
        self.durationMs = durationMs
        self.sizeBytes = sizeBytes
    }
}

/// Which of the songs with the same file name is this one: the same length, or with no length to
/// go on, the same size. Among those that fit, the first of the same size wins, else the first.
/// Nil when none fits.
public func pickSameFile(_ candidates: [NamedCandidate], durationMs: Int64?, sizeBytes: Int64?) -> Int64? {
    func sameSize(_ candidate: NamedCandidate) -> Bool { sizeBytes != nil && candidate.sizeBytes == sizeBytes }
    let fits = candidates.filter { candidate in
        if let durationMs, let length = candidate.durationMs { return abs(length - durationMs) <= sameFileLengthMs }
        return sameSize(candidate)
    }
    return (fits.first(where: sameSize) ?? fits.first)?.id
}

/// The phone's songs by file name, each with its length and size when known. A length or size of
/// zero is unknown.
public func namedCandidates(_ files: [DeviceFile]) -> [String: [NamedCandidate]] {
    var named: [String: [NamedCandidate]] = [:]
    for file in files {
        named[file.fileName, default: []].append(NamedCandidate(
            id: file.id,
            durationMs: file.durationMs > 0 ? file.durationMs : nil,
            sizeBytes: file.sizeBytes > 0 ? file.sizeBytes : nil))
    }
    return named
}
