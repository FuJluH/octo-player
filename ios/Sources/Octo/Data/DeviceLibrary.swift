import AVFoundation
import Foundation
import MediaPlayer
import Observation
import OctoKit
import UIKit

/// The music on this iPhone: the songs in the Music app's library (read with the media library
/// permission; only songs with a file Octo may open can be played, so protected Apple Music
/// downloads are left out and counted), and audio files put in Octo's own folder with the Files
/// app ("On My iPhone > Octo"). Scanned at start, when access is granted, when the media library
/// changes (after 2 s of quiet), when a folder is switched on or off, when Octo changed files, and
/// when the app comes back to the front and either source changed.
@MainActor
@Observable
final class DeviceLibrary {
    private(set) var access: DeviceAccess
    private(set) var scanning = false
    /// Whether a scan of this run has ended, so the phone's music is known.
    private(set) var scannedOnce = false
    /// Every folder music was found in, most songs first, switched-off ones included. Empty until
    /// the first scan of this run ends.
    private(set) var folders: [MusicFolder] = []
    /// Songs in the Music app's library Octo cannot play: protected downloads with no file.
    private(set) var protectedSongs = 0
    /// Songs found on the phone, in switched-on folders.
    private(set) var songCount = 0
    /// Each phone song's folder names and file path from the last scan, by media id.
    private(set) var paths: [Int64: [String]] = [:]
    private(set) var files: [Int64: String] = [:]
    /// Every phone song from the last scan by its file name, switched-off folders included.
    @ObservationIgnored private(set) var named: [String: [NamedCandidate]] = [:]

    @ObservationIgnored private let library: Library
    @ObservationIgnored private let settings = AppSettings.shared
    @ObservationIgnored private let lock = SerialWork()
    @ObservationIgnored private var quiet: Task<Void, Never>?
    @ObservationIgnored private var observer: NSObjectProtocol?
    @ObservationIgnored private var lastSignature: String?
    @ObservationIgnored private var waiting: Task<Void, Never>?
    @ObservationIgnored private var folderWatch: Watch<Set<String>>?

    /// The name the media library's songs are grouped under among the folders.
    nonisolated static let musicAppFolder = "Music app"
    /// The name files at the top of Octo's own folder are grouped under.
    nonisolated static let octoFolder = "Octo"

    init(library: Library) {
        self.library = library
        access = Self.systemAccess() == .granted ? .granted : .notAsked
        if case .deniedForever = Self.systemAccess() { access = .deniedForever }
    }

    /// The folders switched off, by name.
    var excluded: Set<String> { settings.excludedFolders }

    /// The folder Files puts music in for Octo.
    nonisolated static var filesFolder: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }

    /// Starts watching the media library, and scans once.
    func start() {
        if access == .granted { watchMediaLibrary() }
        folderWatch = Watch({ [weak self] in self?.excluded ?? [] }) { [weak self] _ in
            Task { await self?.rescan() }
        }
        foreground = NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil,
                                                            queue: .main) { [weak self] _ in
            Task { @MainActor in self?.returned() }
        }
        Task {
            // The count the library keeps shows at once; the scan brings it up to date.
            if let kept = try? await library.store.trackCount(sourceId: deviceSource) { songCount = kept }
            await rescan()
        }
    }

    @ObservationIgnored private var foreground: NSObjectProtocol?

    /// Asks for the media library. A grant scans at once.
    func requestAccess() {
        MPMediaLibrary.requestAuthorization { [weak self] status in
            Task { @MainActor in
                guard let self else { return }
                self.access = accessAfterAsking(granted: status == .authorized, canAskAgain: false)
                if self.access == .granted {
                    self.watchMediaLibrary()
                    await self.rescan()
                }
            }
        }
    }

    /// Opens the app's page in the system settings, where a refused access can be given.
    func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
    }

    /// The app came back to the front: access may have changed in the settings, and either source
    /// may have changed meanwhile.
    func returned() {
        let before = access
        access = accessOnReturn(access, grantedNow: Self.systemAccess() == .granted)
        if access == .granted && before != .granted { watchMediaLibrary() }
        Task {
            if access != before || signature() != lastSignature { await rescan() }
        }
    }

    /// Switches a folder on or off; the scan follows the setting.
    func setFolder(_ name: String, included: Bool) {
        settings.setFolderIncluded(name, included)
    }

    /// Puts back the switched-off folders from a backup, replacing them whole; the scan follows.
    func restoreExcluded(_ names: Set<String>) {
        settings.setExcludedFolders(names)
    }

    /// Scans the phone's music once. Scans never overlap, and asking again while one waits to
    /// start joins that one.
    func rescan() async {
        if let waiting { return await waiting.value }
        let next = Task { @MainActor [weak self] in
            guard let lock = self?.lock else { return }
            await lock.run { [weak self] in
                self?.waiting = nil
                await self?.scan()
            }
        }
        waiting = next
        await next.value
    }

    private func scan() async {
        scanning = true
        defer {
            scanning = false
            scannedOnce = true
        }
        let granted = access == .granted
        let nowSeconds = Int64(Date().timeIntervalSince1970)
        var found = await Task.detached(priority: .utility) {
            Self.listFiles(mediaLibrary: granted, nowSeconds: nowSeconds)
        }.value
        found.files = await Self.withLengths(found.files)
        protectedSongs = found.protected
        lastSignature = signature()
        let store = library.store
        let saved = (try? await store.fileTags()) ?? []
        let plan = tagRefreshPlan(found.files, saved: saved)
        let fresh = await Self.readTags(plan.toRead)
        try? await store.upsertFileTags(fresh)
        if !plan.forget.isEmpty { try? await store.deleteFileTags(plan.forget) }
        let tags = knownTags(saved: saved, fresh: fresh, forget: plan.forget)
        let excluded = excluded
        let result = await Task.detached(priority: .utility) { deviceScan(found.files, tags: tags, excluded: excluded) }.value
        folders = result.folders
        paths = result.paths
        files = result.files
        let listed = found.files
        named = await Task.detached(priority: .utility) { namedCandidates(listed) }.value
        songCount = result.catalog.tracks.count
        try? await store.replaceSource(deviceSource, tracks: result.catalog.tracks, albums: result.catalog.albums,
                                       artists: result.catalog.artists)
        _ = try? await store.rebuild(serverInUse: library.serverInUse)
    }

    // MARK: Reading the phone

    private struct Found: Sendable {
        var files: [DeviceFile]
        var protected: Int
    }

    /// What both sources hold now, cheap to read, to tell whether they changed while the app was away.
    private func signature() -> String {
        let media = access == .granted ? "\(MPMediaLibrary.default().lastModifiedDate.timeIntervalSince1970)" : "-"
        let folder = Self.filesFolder
        let stamp = (try? folder.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)?
            .timeIntervalSince1970 ?? 0
        let count = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)?.allObjects.count ?? 0
        return "\(media)|\(stamp)|\(count)"
    }

    nonisolated private static func listFiles(mediaLibrary: Bool, nowSeconds: Int64) -> Found {
        var files: [DeviceFile] = []
        var protected = 0
        if mediaLibrary {
            for item in MPMediaQuery.songs().items ?? [] {
                guard let url = item.assetURL, !item.hasProtectedAsset else {
                    protected += 1
                    continue
                }
                let ext = url.pathExtension.lowercased()
                let title = item.title ?? ""
                let added = Int64(item.dateAdded.timeIntervalSince1970)
                let year = (item.value(forProperty: MPMediaItemPropertyReleaseDate) as? Date).map { Calendar(identifier: .gregorian).component(.year, from: $0) }
                var file = DeviceFile.scanned(
                    id: Int64(bitPattern: item.persistentID), uri: url.absoluteString,
                    fileName: title.isEmpty ? url.lastPathComponent : "\(title).\(ext)", folder: musicAppFolder + "/",
                    modifiedSeconds: added, sizeBytes: 0, durationMs: Int64((item.playbackDuration * 1000).rounded()),
                    addedSeconds: added, nowSeconds: nowSeconds, mimeType: mimeFor(ext),
                    title: item.title, artist: item.artist, albumArtist: item.albumArtist, album: item.albumTitle,
                    track: item.albumTrackNumber > 0 ? item.albumTrackNumber : nil, disc: item.discNumber > 0 ? item.discNumber : nil,
                    year: year, genre: item.genre)
                // The Music app gives no time a song last changed, so what it says of the song
                // stands in: a song tagged anew and synced again has its own tags read again.
                file.modifiedAt = changeMark(item)
                files.append(file)
            }
        }
        let root = filesFolder
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey, .creationDateKey]
        if let walk = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) {
            for case let url as URL in walk {
                guard playableExtensions.contains(url.pathExtension.lowercased()),
                      let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true
                else { continue }
                let relative = String(url.standardizedFileURL.path.dropFirst(root.standardizedFileURL.path.count))
                    .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                let parent = (relative as NSString).deletingLastPathComponent
                let folder = parent.isEmpty ? octoFolder + "/" : parent + "/"
                let modified = Int64(values.contentModificationDate?.timeIntervalSince1970 ?? 0)
                let created = Int64(values.creationDate?.timeIntervalSince1970 ?? 0)
                files.append(DeviceFile.scanned(
                    id: fileId(relative), uri: url.absoluteString, fileName: url.lastPathComponent, folder: folder,
                    modifiedSeconds: modified, sizeBytes: Int64(values.fileSize ?? 0), durationMs: 0, addedSeconds: created,
                    nowSeconds: nowSeconds, mimeType: mimeFor(url.pathExtension)))
            }
        }
        return Found(files: files, protected: protected)
    }

    /// A mark that changes whenever the Music app's reading of a song does.
    nonisolated private static func changeMark(_ item: MPMediaItem) -> Int64 {
        let reading = [item.title, item.artist, item.albumArtist, item.albumTitle, item.genre, item.composer].map { $0 ?? "" }
            + ["\(item.albumTrackNumber)", "\(item.discNumber)", "\(Int(item.playbackDuration * 1000))",
               "\((item.value(forProperty: MPMediaItemPropertyReleaseDate) as? Date)?.timeIntervalSince1970 ?? 0)"]
        let bytes = Hashes.sha1(Array(reading.joined(separator: "\u{1F}").utf8))
        var value: UInt64 = 0
        for byte in bytes.prefix(8) { value = value << 8 | UInt64(byte) }
        return Int64(bitPattern: value)
    }

    /// Kinds of file Apple's player opens.
    nonisolated private static let playableExtensions: Set<String> = ["mp3", "m4a", "m4b", "mp4", "aac", "flac", "wav", "aif", "aiff", "caf", "alac"]

    /// A stable id for a file in Octo's folder, from its path there.
    nonisolated static func fileId(_ relativePath: String) -> Int64 {
        let bytes = Hashes.sha1(Array(relativePath.utf8))
        var value: UInt64 = 0
        for byte in bytes.prefix(8) { value = value << 8 | UInt64(byte) }
        return Int64(bitPattern: value)
    }

    /// The id of a file in Octo's folder, or nil for a file anywhere else.
    nonisolated static func ownFileId(_ url: URL) -> Int64? {
        guard url.isFileURL else { return nil }
        let root = filesFolder.resolvingSymlinksInPath().standardizedFileURL.path
        let path = url.resolvingSymlinksInPath().standardizedFileURL.path
        guard path.hasPrefix(root + "/") else { return nil }
        let relative = String(path.dropFirst(root.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return relative.isEmpty ? nil : fileId(relative)
    }

    /// Files in Octo's own folder with their lengths, read from each file, 4 at a time.
    nonisolated private static func withLengths(_ files: [DeviceFile]) async -> [DeviceFile] {
        let missing = files.indices.filter { files[$0].durationMs == 0 }
        guard !missing.isEmpty else { return files }
        var out = files
        for start in stride(from: 0, to: missing.count, by: deviceTagReaders) {
            let batch = missing[start..<min(start + deviceTagReaders, missing.count)].map { ($0, files[$0].uri) }
            let lengths = await withTaskGroup(of: (Int, Int64).self) { group in
                for (index, uri) in batch {
                    group.addTask {
                        guard let url = URL(string: uri), let time = try? await AVURLAsset(url: url).load(.duration), time.seconds.isFinite
                        else { return (index, 0) }
                        return (index, Int64((time.seconds * 1000).rounded()))
                    }
                }
                var found: [(Int, Int64)] = []
                for await item in group { found.append(item) }
                return found
            }
            for (index, ms) in lengths { out[index].durationMs = ms }
        }
        return out
    }

    /// Reads the tags of new or changed files, 4 at a time. A file that cannot be read keeps the
    /// media library's own reading.
    nonisolated private static func readTags(_ files: [DeviceFile]) async -> [FileTagsRow] {
        await withTaskGroup(of: [FileTagsRow].self) { group in
            for batch in tagReadBatches(files) {
                group.addTask {
                    var rows: [FileTagsRow] = []
                    for file in batch { rows.append(file.toSaved(await tags(of: file))) }
                    return rows
                }
            }
            var all: [FileTagsRow] = []
            for await rows in group { all += rows }
            return all
        }
    }

    /// A file's own tags, by every name its format writes them under.
    nonisolated private static func tags(of file: DeviceFile) async -> FileTags? {
        guard let url = URL(string: file.uri) else { return nil }
        let asset = AVURLAsset(url: url)
        guard let items = try? await asset.load(.metadata) else { return nil }
        var pairs: [(String, [String])] = []
        for item in items {
            guard let name = await tagKey(item), let value = await tagValue(item, name: name) else { continue }
            pairs.append((name, [value]))
        }
        let common = (try? await asset.load(.commonMetadata)) ?? []
        for item in common {
            guard let key = item.commonKey, let name = commonNames[key], let value = try? await item.load(.stringValue) else { continue }
            pairs.append((name, [value]))
        }
        return parseTags(pairs)
    }

    /// The names the common keys go by among the tag names.
    nonisolated private static let commonNames: [AVMetadataKey: String] = [
        .commonKeyTitle: "TITLE", .commonKeyArtist: "ARTIST", .commonKeyAlbumName: "ALBUM", .commonKeyCreationDate: "DATE",
    ]

    /// An item's tag name: its key as text, a four-character code read as letters (© kept). A
    /// user-defined ID3 frame goes by its description, and an iTunes free-form tag by its name,
    /// in the forms the tag reader knows ("TXXX:NAME", "----:com.apple.iTunes:NAME").
    nonisolated private static func tagKey(_ item: AVMetadataItem) async -> String? {
        if let text = item.key as? String {
            if text == "TXXX", let extra = try? await item.load(.extraAttributes), let description = extra[.info] as? String,
               !description.isEmpty {
                return "TXXX:" + description
            }
            for form in ["com.apple.iTunes:", "com.apple.iTunes."] where text.hasPrefix(form) {
                return "----:com.apple.iTunes:" + text.dropFirst(form.count)
            }
            return text
        }
        if let number = item.key as? NSNumber {
            let code = number.uint32Value
            let bytes = [UInt8(code >> 24 & 0xFF), UInt8(code >> 16 & 0xFF), UInt8(code >> 8 & 0xFF), UInt8(code & 0xFF)]
            return String(bytes: bytes, encoding: .isoLatin1)
        }
        return nil
    }

    /// An item's value as text. Track and disc numbers in MP4 files come as data: the number and
    /// the total, read as "3/12".
    nonisolated private static func tagValue(_ item: AVMetadataItem, name: String) async -> String? {
        if let text = try? await item.load(.stringValue), !text.isEmpty { return text }
        if let number = try? await item.load(.numberValue) { return number.stringValue }
        if ["trkn", "disk"].contains(name), let data = try? await item.load(.dataValue), data.count >= 6 {
            let bytes = [UInt8](data)
            let number = Int(bytes[2]) << 8 | Int(bytes[3])
            let total = Int(bytes[4]) << 8 | Int(bytes[5])
            return total > 0 ? "\(number)/\(total)" : "\(number)"
        }
        return nil
    }

    // MARK: Watching

    private func watchMediaLibrary() {
        guard observer == nil else { return }
        MPMediaLibrary.default().beginGeneratingLibraryChangeNotifications()
        observer = NotificationCenter.default.addObserver(forName: .MPMediaLibraryDidChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.changedSoon() }
        }
    }

    /// The media library changed: scanned once it has been quiet for 2 s.
    private func changedSoon() {
        quiet?.cancel()
        quiet = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(deviceRescanQuietMs))
            if Task.isCancelled { return }
            await self?.rescan()
        }
    }

    nonisolated private static func systemAccess() -> DeviceAccess {
        switch MPMediaLibrary.authorizationStatus() {
        case .authorized: .granted
        case .denied, .restricted: .deniedForever
        default: .notAsked
        }
    }

    // MARK: Phone files

    /// Deletes the phone files of these songs: files in Octo's own folder go; songs in the Music
    /// app's library can only be removed in the Music app. Answers how many files went and the
    /// words to show, if any. Once any went, the phone is scanned again.
    func delete(_ trackIds: [String]) async -> (removed: Int, words: String?) {
        let copies = (try? await library.store.copies(of: trackIds)) ?? []
        guard let plan = deletePlan(trackIds, phoneFiles(copies, ownFolder: Self.filesFolder.absoluteString)) else { return (0, nil) }
        var kept = 0
        var removed = 0
        var failed = 0
        for uri in plan.uris {
            guard let url = URL(string: uri), url.isFileURL else {
                kept += 1
                continue
            }
            do {
                try FileManager.default.removeItem(at: url)
                removed += 1
            } catch {
                failed += 1
            }
        }
        if removed > 0 { await rescan() }
        if failed > 0 { return (removed, "Could not delete from the phone") }
        if kept == 0 { return (removed, nil) }
        return (removed, kept == 1 ? "1 song is in the Music app's library. Remove it in the Music app."
            : "\(kept) songs are in the Music app's library. Remove them in the Music app.")
    }

    /// Files to hand to the share sheet for these songs: Octo's own files as they are, and songs
    /// from the Music app's library copied out first.
    func shareFiles(_ trackIds: [String]) async -> [URL] {
        let copies = (try? await library.store.copies(of: trackIds)) ?? []
        var urls: [URL] = []
        for file in filesToShare(trackIds, phoneFiles(copies, ownFolder: Self.filesFolder.absoluteString)) {
            guard let url = URL(string: file.uri) else { continue }
            if url.isFileURL {
                urls.append(url)
            } else if let copy = await Self.exportFromLibrary(url) {
                urls.append(copy)
            }
        }
        return urls
    }

    /// Copies a media library song to a temporary file, for sharing.
    nonisolated private static func exportFromLibrary(_ url: URL) async -> URL? {
        let asset = AVURLAsset(url: url)
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else { return nil }
        let target = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).m4a")
        do {
            try await export.export(to: target, as: .m4a)
            return target
        } catch {
            return nil
        }
    }
}
