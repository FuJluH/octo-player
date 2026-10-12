import Foundation

/// A song's file on the phone: the library song it belongs to, its address in the phone's media
/// library, and what kind of audio it is.
public struct PhoneFile: Sendable, Hashable {
    public var trackId: String
    public var uri: String
    public var mimeType: String?

    public init(trackId: String, uri: String, mimeType: String?) {
        self.trackId = trackId
        self.uri = uri
        self.mimeType = mimeType
    }
}

/// How an address in the phone's own media library starts. Only such an address can be deleted,
/// shared or made a phone sound.
public let mediaLibraryPrefixes = ["content://media/", "ipod-library://"]

/// The phone files among these copies: phone copies already merged into a song, at an address in
/// the phone's own media library, or inside the app's own music folder (`ownFolder`, a file
/// address) when it has one. One file per address.
public func phoneFiles(_ copies: [SourceTrack], ownFolder: String? = nil) -> [PhoneFile] {
    var seen = Set<String>()
    let prefixes = mediaLibraryPrefixes + [ownFolder].compactMap { $0 }.filter { !$0.isEmpty }
    return copies
        .filter { copy in
            copy.sourceId == deviceSource && !copy.mergedId.isEmpty
                && prefixes.contains { (copy.uri ?? "").hasPrefix($0) }
        }
        .map { PhoneFile(trackId: $0.mergedId, uri: $0.uri ?? "", mimeType: $0.mimeType) }
        .filter { seen.insert($0.uri).inserted }
}

/// What deleting songs from the phone takes: every phone file each one has, so the song leaves the
/// phone completely. `trackIds` are the songs that have a file to delete, in the order asked.
public struct DeletePlan: Sendable, Hashable {
    public var trackIds: [String]
    public var uris: [String]

    public init(trackIds: [String], uris: [String]) {
        self.trackIds = trackIds
        self.uris = uris
    }
}

/// Nothing to do when none of the songs has a file on the phone.
public func deletePlan(_ trackIds: [String], _ files: [PhoneFile]) -> DeletePlan? {
    let bySong = Dictionary(grouping: files, by: \.trackId)
    let songs = unique(trackIds).filter { bySong[$0] != nil }
    if songs.isEmpty { return nil }
    return DeletePlan(trackIds: songs, uris: songs.flatMap { (bySong[$0] ?? []).map(\.uri) })
}

/// One file per song for sharing, in the order asked.
public func filesToShare(_ trackIds: [String], _ files: [PhoneFile]) -> [PhoneFile] {
    let bySong = Dictionary(grouping: files, by: \.trackId)
    return unique(trackIds).compactMap { bySong[$0]?.first }
}

/// The type a share names: the files' own when they all agree, any audio when they are all audio
/// of different kinds, and anything otherwise.
public func shareType(_ mimeTypes: [String?]) -> String {
    let known: [String?] = mimeTypes.map { type in
        guard let type else { return nil }
        let clean = trimmed(type).lowercased()
        return clean.isEmpty ? nil : clean
    }
    var kinds: [String?] = []
    for kind in known where !kinds.contains(kind) { kinds.append(kind) }
    if kinds.count == 1, let one = kinds[0] { return one }
    return known.allSatisfy { $0 == nil || $0?.hasPrefix("audio/") == true } ? "audio/*" : "*/*"
}

/// The phone's sounds a song can become, in the order offered: its kind as a number (ringtone 1,
/// notification 2, alarm 4), its name, and the line that confirms it was set.
public enum PhoneSound: Int, CaseIterable, Sendable {
    case ringtone = 1
    case notification = 2
    case alarm = 4

    public var type: Int { rawValue }

    public var label: String {
        switch self {
        case .ringtone: "Ringtone"
        case .notification: "Notification sound"
        case .alarm: "Alarm"
        }
    }

    public var done: String {
        switch self {
        case .ringtone: "Set as your ringtone"
        case .notification: "Set as your notification sound"
        case .alarm: "Set as your alarm"
        }
    }
}

/// The sound picked from the sheet, by its place in the list.
public func phoneSoundAt(_ index: Int) -> PhoneSound? {
    let all = PhoneSound.allCases
    return all.indices.contains(index) ? all[index] : nil
}
