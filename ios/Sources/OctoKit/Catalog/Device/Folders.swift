import Foundation

/// Folders are grouped by their top level, like "Music" or "Download", so a big library of artist
/// and album folders still shows as a short list.
public func topFolder(_ relativePath: String?) -> String {
    guard let relativePath else { return "" }
    let inner = trimmedSlashes(relativePath)
    return inner.firstIndex(of: "/").map { String(inner[..<$0]) } ?? String(inner)
}

/// A file's path from the top of its storage, like "Music/Kavinsky/01.mp3".
public func relativeFile(_ folder: String?, _ fileName: String) -> String {
    let inner = folder.map(trimmedSlashes) ?? ""
    return inner.isEmpty ? fileName : "\(inner)/\(fileName)"
}

/// The main storage, as the media library names it.
public let mainStorageVolume = "external_primary"

/// What to call a storage: the phone's own, or a memory card, told apart by its id when there is
/// more than one card.
public func storageName(_ volume: String?, cardCount: Int) -> String {
    guard let volume, volume != mainStorageVolume else { return "Internal storage" }
    return cardCount <= 1 ? "SD card" : "SD card \(volume.uppercased())"
}

/// The folder names in a path, from the top: "Music/Kavinsky/" is "Music" and "Kavinsky".
private func pathFolderNames(_ folder: String?) -> [String] {
    (folder ?? "").split(separator: "/", omittingEmptySubsequences: true).map(String.init).filter { !trimmed($0).isEmpty }
}

/// The stored setting that holds the switched-off folders. New folders are always in.
public let excludedFoldersKey = "excluded_folders"

/// The switched-off folders after switching one folder on or off.
public func excludedFolders(_ now: Set<String>, switching folder: String, included: Bool) -> Set<String> {
    included ? now.subtracting([folder]) : now.union([folder])
}

/// Text without slashes at either end.
private func trimmedSlashes(_ text: String) -> Substring {
    var inner = Substring(text)
    while inner.first == "/" { inner = inner.dropFirst() }
    while inner.last == "/" { inner = inner.dropLast() }
    return inner
}

extension Array where Element == DeviceFile {
    /// Leaves out files in folders someone switched off.
    public func withoutFolders(_ excluded: Set<String>) -> [DeviceFile] {
        excluded.isEmpty ? self : filter { !excluded.contains(topFolder($0.folder)) }
    }

    /// Lists every folder music was found in, including switched-off ones, so they can be switched
    /// back on. Most songs first.
    public func folders(_ excluded: Set<String>) -> [MusicFolder] {
        groupInOrder(self) { topFolder($0.folder) }
            .map { name, files in MusicFolder(name, songs: files.count, included: !excluded.contains(name)) }
            .enumerated()
            .sorted { $0.element.songs != $1.element.songs ? $0.element.songs > $1.element.songs : $0.offset < $1.offset }
            .map(\.element)
    }

    /// Where each file sits, as folder names, by media id. The storage it is on leads the path only
    /// when music is on more than one, so a phone with one storage starts at "Music" rather than
    /// "Internal storage".
    public func folderPaths() -> [Int64: [String]] {
        let volumes = Set(map { $0.volume ?? mainStorageVolume })
        let cards = volumes.subtracting([mainStorageVolume])
        var paths: [Int64: [String]] = [:]
        for file in self {
            let names = pathFolderNames(file.folder)
            paths[file.id] = volumes.count > 1 ? [storageName(file.volume, cardCount: cards.count)] + names : names
        }
        return paths
    }

    /// Each file's path from the top of its storage, by media id, for reading and writing playlist
    /// files.
    public func relativeFiles() -> [Int64: String] {
        var files: [Int64: String] = [:]
        for file in self { files[file.id] = relativeFile(file.folder, file.fileName) }
        return files
    }
}
