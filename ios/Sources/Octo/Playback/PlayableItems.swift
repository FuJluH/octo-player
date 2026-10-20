import Foundation
import MediaPlayer
import OctoKit

/// Turns songs into songs the player can play. Each library song plays from one of its copies,
/// chosen now by the settings and by what can play: the phone's file, a download, or a stream
/// from the server. A song found online streams from the server, or plays as the library song
/// it became once downloaded. A song the library does not hold streams from the server in use.
@MainActor
struct PlayableItems {
    let session: Session
    let data: DataServices?

    /// One queue item for each song asked for, in order; nil for any that cannot be found. A song
    /// as the server lists it that the library does not know yet is taken in first, as the
    /// library song or the find it is, like every song from the server before it plays.
    func items(_ songs: [Song], source: QueueSource, streamUnknown: Bool = true) async -> [QueueItem?] {
        guard !songs.isEmpty else { return [] }
        var songs = songs
        if streamUnknown, let data { songs = await takenIn(songs, data) }
        let context = StreamContext.now(session)
        let ids = songs.map(\.id)
        var byId: [String: QueueItem] = [:]
        if let data {
            let library = data.library
            let tracks = await library.songs(ids: distinct(ids.filter { !isRadio($0) && !isOpenedFile($0) }))
            let finds = await library.finds(distinct(ids.filter(isFind)))
            var tracksById: [String: LibraryTrack] = [:]
            for track in tracks { tracksById[track.id] = track }
            for find in finds {
                if let adopted = tracksById[find.adoptedId] {
                    tracksById[find.id] = adopted
                } else {
                    byId[find.id] = findItem(find, context: context, source: source)
                }
            }
            let wanted = distinct(ids.filter { byId[$0] == nil }).compactMap { tracksById[$0] }
            let copies = await batchCopies(distinct(wanted.map(\.id)), data)
            let onServer = copies.filter { $0.value.contains(where: \.isServerCopy) }
            // Only ask about the server when some song is on one.
            let reachable = !onServer.isEmpty && OnlineWatch.shared.online && context.client != nil
            // Phone files that could be swapped for a stream, checked in case one is gone.
            let phoneFiles = onServer.values.flatMap { $0 }.filter { !$0.isServerCopy }.compactMap(\.uri)
            let missing = reachable ? await Self.missingPhoneFiles(phoneFiles) : []
            let downloads = onServer.isEmpty ? [:] : await data.offline.playableCopies(Array(onServer.keys))
            for id in distinct(ids) where byId[id] == nil {
                guard let track = tracksById[id] else { continue }
                byId[id] = libraryItem(track, copies: copies[track.id] ?? [], download: downloads[track.id], reachable: reachable,
                                       missing: missing, context: context, source: source)
            }
        }
        let orders = albumOrders(songs)
        return songs.enumerated().map { index, song in
            if let item = byId[song.id] { return item.withSource(source) }
            if isRadio(song.id) { return radioItem(song.id, mimeType: song.contentType, source: source) }
            if isOpenedFile(song.id) { return openedFileItem(song.id, source: source) }
            // Without the library (a preview), a song streams from the server in use.
            guard streamUnknown, data == nil, context.sourceId != nil else { return nil }
            return queueItem(song, sourceId: context.sourceId, quality: context.quality, source: source, albumOrder: orders[index])
        }
    }

    /// Songs as the server lists them that the library does not know become the library songs
    /// or finds they are, stored as finds are. Ids already the library's own, finds, stations and
    /// opened files stay as they are; one the library no longer knows is then dropped.
    private func takenIn(_ songs: [Song], _ data: DataServices) async -> [Song] {
        let plain = songs.filter { song in
            !isRadio(song.id) && !isOpenedFile(song.id) && !isFind(song.id)
                && !song.id.hasPrefix("server:") && !song.id.hasPrefix(deviceSource + ":")
        }
        guard !plain.isEmpty else { return songs }
        let known = Set(await data.library.tracks(ids: distinct(plain.map(\.id))).map(\.id))
        var seen = Set<String>()
        let raw = plain.filter { !known.contains($0.id) && seen.insert($0.id).inserted }
        guard !raw.isEmpty else { return songs }
        let ids = await data.discovery.idsFromServer(raw)
        var taken: [String: String] = [:]
        for (song, id) in zip(raw, ids) { taken[song.id] = id }
        return songs.map { song in
            guard let id = taken[song.id] else { return song }
            var copy = song
            copy.id = id
            return copy
        }
    }

    /// Every copy of these library songs, by song, read in batches.
    private func batchCopies(_ trackIds: [String], _ data: DataServices) async -> [String: [SongCopy]] {
        guard !trackIds.isEmpty else { return [:] }
        let rows = (try? await data.library.store.copies(of: trackIds)) ?? []
        var byTrack: [String: [SongCopy]] = [:]
        for row in rows { byTrack[row.mergedId, default: []].append(songCopy(row)) }
        return byTrack
    }

    /// Songs by their ids, as the library holds them.
    func items(ids: [String], source: QueueSource) async -> [QueueItem?] {
        await items(ids.map { Song(id: $0, title: "") }, source: source, streamUnknown: false)
    }

    // MARK: Each kind

    private func libraryItem(_ track: LibraryTrack, copies: [SongCopy], download: KeptDownload?, reachable: Bool, missing: Set<String>,
                             context: StreamContext, source: QueueSource) -> QueueItem {
        let downloadCopy = download.flatMap { kept -> SongCopy? in
            let server = copies.first { $0.sourceId == kept.sourceId && $0.nativeId == kept.serverId } ?? copies.first(where: \.isServerCopy)
            guard let server else { return nil }
            return downloadedCopy(server, uri: URL(fileURLWithPath: kept.path).absoluteString, format: kept.format, sizeBytes: Int(kept.sizeBytes))
        }
        let online = OnlineWatch.shared.online
        let prefs = AppSettings.shared
        // Downloads play first, unless streaming on Wi-Fi is preferred and the phone is on it.
        let streamInstead = prefs.offline.streamOnWifi && online && !OnlineWatch.shared.onMobileData
        let chosen = chooseCopy(copies, download: downloadCopy, streamInstead: streamInstead, prefs.stream.copies,
                                serverReachable: reachable, phoneFileMissing: { copy in missing.contains(copy.uri ?? "") })
        var uri = track.uri ?? ""
        var mime = track.mimeType
        let fileMime = chosen?.mimeType ?? track.mimeType
        if let chosen {
            if chosen.isServerCopy {
                let ref = StreamRef(sourceId: chosen.sourceId, serverId: chosen.nativeId, mimeType: chosen.mimeType, bitrate: bitrateOf(chosen),
                                    size: chosen.sizeBytes.map(Int64.init))
                uri = streamUri(ref)
                mime = phoneRequest(chosen.mimeType, bitrateOf(chosen), context.quality).mimeType(chosen.mimeType)
            } else {
                uri = chosen.uri ?? uri
                mime = chosen.mimeType
            }
        }
        var item = QueueItem(
            trackId: track.id, uri: uri, title: track.title, artist: track.artist, album: track.album,
            durationMs: Int(track.durationMs), mimeType: mime, fileMime: fileMime, trackNo: track.trackNo, discNo: track.discNo,
            year: track.year, artwork: track.artwork, albumId: track.albumId, artistId: track.artistId,
            albumOrder: track.albumOrder >= 0 ? track.albumOrder : nil, explicit: track.explicit ?? false,
            bpm: songBpm(chosen, copies), genre: track.genre.isEmpty ? nil : track.genre, loudness: storedLoudness(chosen, copies),
            source: source, isFind: false)
        item.song = songOf(track, id: track.id)
        return item
    }

    private func findItem(_ find: OnlineSong, context: StreamContext, source: QueueSource) -> QueueItem {
        let ref = findStreamRef(sourceId: find.sourceId, serverId: find.nativeId, mimeType: find.mimeType)
        var item = QueueItem(
            trackId: find.id, uri: streamUri(ref), title: find.title, artist: find.artist, album: find.album,
            durationMs: Int(find.durationMs), mimeType: ref.request(context.quality).mimeType(find.mimeType),
            // A find has no album or artist in the library to open.
            fileMime: find.mimeType, artwork: onlineArtwork(find.sourceId, find.coverId), albumId: "",
            artistId: "", explicit: find.explicit ?? false, source: source, isFind: true)
        let song = Song(id: find.id, title: find.title, artist: find.artist, album: find.album, albumId: nil,
                        duration: Int((find.durationMs + 500) / 1_000), coverArt: find.coverId, isExternal: true)
        item.song = song
        return item
    }

    /// A station; `mimeType`, or the id's HLS mark, names an HLS one whose address does not say
    /// so. A server station carries its server cover.
    private func radioItem(_ id: String, mimeType: String? = nil, source: QueueSource) -> QueueItem? {
        guard let station = radioOf(id) else { return nil }
        let cover = radioDetailsOf(id).coverArt
        return QueueItem(trackId: id, uri: station.stream, title: radioTitle(id) ?? station.stream, artist: radioArtist,
                         mimeType: mimeType ?? (radioIsHls(id) ? hlsPlaylistTypes[0] : nil), artwork: cover.isEmpty ? nil : cover,
                         source: source)
    }

    private func openedFileItem(_ id: String, source: QueueSource) -> QueueItem? {
        guard let file = openedFileOf(id), let url = URL(string: file.uri), OpenedFileAccess.canRead(url) else { return nil }
        return QueueItem(trackId: id, uri: file.uri, title: file.shownTitle, artist: file.artist, source: source)
    }

    private func songCopy(_ copy: SourceTrack) -> SongCopy {
        SongCopy(id: copy.id, sourceId: copy.sourceId, nativeId: copy.nativeId, uri: copy.uri, mimeType: copy.mimeType,
                 sizeBytes: copy.sizeBytes.map(Int.init), bitrate: copy.bitrate, sampleRate: copy.sampleRate, bitDepth: copy.bitDepth,
                 durationMs: Int(copy.durationMs), bpm: copy.bpm, trackGain: copy.trackGain.map(Double.init),
                 trackPeak: copy.trackPeak.map(Double.init), albumGain: copy.albumGain.map(Double.init),
                 albumPeak: copy.albumPeak.map(Double.init))
    }

    /// The phone files among these that are gone: files in Octo's folder no longer there, and
    /// songs the Music app's library no longer has. Without access to the Music app's library,
    /// none of its songs can play.
    nonisolated private static func missingPhoneFiles(_ uris: [String]) async -> Set<String> {
        guard !uris.isEmpty else { return [] }
        return await Task.detached(priority: .userInitiated) {
            let allowed = MPMediaLibrary.authorizationStatus() == .authorized
            var missing = Set<String>()
            for uri in Set(uris) {
                guard let url = URL(string: uri) else {
                    missing.insert(uri)
                    continue
                }
                if url.isFileURL {
                    if !FileManager.default.fileExists(atPath: url.path) { missing.insert(uri) }
                } else if url.scheme == "ipod-library" {
                    guard allowed, let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
                        .first(where: { $0.name == "id" })?.value.flatMap(UInt64.init) else {
                        missing.insert(uri)
                        continue
                    }
                    let query = MPMediaQuery.songs()
                    query.addFilterPredicate(MPMediaPropertyPredicate(value: NSNumber(value: id), forProperty: MPMediaItemPropertyPersistentID))
                    if (query.items ?? []).isEmpty { missing.insert(uri) }
                }
            }
            return missing
        }.value
    }

    /// A library song as the screens show it.
    func songOf(_ track: LibraryTrack, id: String) -> Song {
        var song = Song(id: id, title: track.title, artist: track.artist, album: track.album, albumId: track.albumId,
                        duration: Int((track.durationMs + 500) / 1_000), coverArt: Self.coverId(track.artwork),
                        isExternal: isFind(id))
        song.artistId = track.artistId
        song.track = track.trackNo
        song.discNumber = track.discNo
        song.year = track.year
        song.genre = track.genre.isEmpty ? nil : track.genre
        song.contentType = track.mimeType
        if track.explicit == true { song.explicitStatus = "explicit" }
        return song
    }

    /// The server's cover id inside a stored artwork reference; a picture from the phone keeps
    /// its reference, which covers draw as it is.
    static func coverId(_ artwork: String?) -> String? {
        guard ArtworkRef.decode(artwork) != nil else { return artwork }
        return Octo.coverId(of: artwork)
    }
}
