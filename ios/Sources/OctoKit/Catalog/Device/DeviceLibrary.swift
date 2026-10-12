import Foundation

/// How many files are read for tags at once.
public let deviceTagReaders = 4

/// How long the media library must stay quiet after it changes before the phone is scanned again,
/// so a big copy that fires many changes is scanned once.
public let deviceRescanQuietMs: Int64 = 2_000

/// Whether the app may read the phone's music.
public enum DeviceAccess: Sendable, Hashable {
    case granted
    case notAsked
    case denied
    /// Refused in a way the app cannot ask about again; only the system settings can change it.
    case deniedForever
}

/// Access after the answer to the request: granted, refused for now, or refused for good when the
/// question cannot be asked again. A grant calls for a scan.
public func accessAfterAsking(granted: Bool, canAskAgain: Bool) -> DeviceAccess {
    if granted { return .granted }
    return canAskAgain ? .denied : .deniedForever
}

/// Access when the app comes back, since it can change in the system settings while the app is
/// away: newly granted, or no longer granted. Anything else stays as it was. Becoming granted
/// calls for a scan.
public func accessOnReturn(_ current: DeviceAccess, grantedNow: Bool) -> DeviceAccess {
    if grantedNow, current != .granted { return .granted }
    if !grantedNow, current == .granted { return .notAsked }
    return current
}

/// What bringing the saved tags up to date takes: the files to read, being new or changed since
/// last time, and the media ids whose saved tags belong to files that are gone.
public struct TagRefreshPlan: Sendable, Equatable {
    public var toRead: [DeviceFile]
    public var forget: [Int64]

    public init(toRead: [DeviceFile], forget: [Int64]) {
        self.toRead = toRead
        self.forget = forget
    }
}

/// Plans a tags refresh. Tags are kept for every file, including those in switched-off folders,
/// so switching a folder back on needs no reading.
public func tagRefreshPlan(_ files: [DeviceFile], saved: [FileTagsRow], version: Int = deviceTagsVersion) -> TagRefreshPlan {
    var byId: [Int64: FileTagsRow] = [:]
    var savedOrder: [Int64] = []
    for row in saved {
        if byId[row.mediaId] == nil { savedOrder.append(row.mediaId) }
        byId[row.mediaId] = row
    }
    let present = Set(files.map(\.id))
    return TagRefreshPlan(
        toRead: files.filter { needsTagRead(byId[$0.id], $0, version: version) },
        forget: savedOrder.filter { !present.contains($0) }
    )
}

/// The files to read split into batches for `deviceTagReaders` readers, each batch read in order
/// by one reader.
public func tagReadBatches(_ files: [DeviceFile]) -> [[DeviceFile]] {
    let size = max(files.count / deviceTagReaders, 1) + 1
    return stride(from: 0, to: files.count, by: size).map { Array(files[$0..<Swift.min($0 + size, files.count)]) }
}

/// The tags known for each file after a refresh, by media id: the saved ones not forgotten, then
/// the fresh ones over them. Files that could not be read have none, so the media library's own
/// reading is used for them.
public func knownTags(saved: [FileTagsRow], fresh: [FileTagsRow], forget: [Int64]) -> [Int64: FileTags] {
    let gone = Set(forget)
    var rows: [Int64: FileTagsRow] = [:]
    for row in saved where !gone.contains(row.mediaId) { rows[row.mediaId] = row }
    for row in fresh { rows[row.mediaId] = row }
    return rows.filter { $0.value.readOk }.mapValues { $0.toTags() }
}

/// One scan of the phone's music, ready to keep.
public struct DeviceScan: Sendable {
    /// Every folder music was found in, including switched-off ones.
    public var folders: [MusicFolder]
    /// The phone source's rows, from the files in switched-on folders.
    public var catalog: DeviceCatalog
    /// Where each included file sits, as folder names, by media id.
    public var paths: [Int64: [String]]
    /// Each included file's path from the top of its storage, by media id.
    public var files: [Int64: String]

    public init(folders: [MusicFolder], catalog: DeviceCatalog, paths: [Int64: [String]], files: [Int64: String]) {
        self.folders = folders
        self.catalog = catalog
        self.paths = paths
        self.files = files
    }
}

/// Turns the media library's files and the tags known for them into the phone source's rows,
/// leaving out switched-off folders.
public func deviceScan(_ files: [DeviceFile], tags: [Int64: FileTags], excluded: Set<String>) -> DeviceScan {
    let included = files.withoutFolders(excluded)
    return DeviceScan(
        folders: files.folders(excluded),
        catalog: buildDeviceCatalog(included.map { $0.toRow(tags[$0.id]) }),
        paths: included.folderPaths(),
        files: included.relativeFiles()
    )
}
