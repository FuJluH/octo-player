import Foundation
import OctoKit

/// Turns songs into songs the player can play. Each library song plays from one of its copies,
/// chosen now by the settings and by what can play: the phone's file, a download, or a stream
/// from the server. A song found online streams from the server, or plays as the library song
/// it became once downloaded. A song the library does not hold streams from the server in use.
@MainActor
struct PlayableItems {
    let session: Session
    let data: DataServices?

    /// One queue item for each song asked for, in order; nil for any that cannot be found.
    func items(_ songs: [Song], source: QueueSource, streamUnknown: Bool = true) async -> [QueueItem?] {
        guard !songs.isEmpty else { return [] }
        let context = StreamContext.now(session)
        let ids = songs.map(\.id)
        var byId: [String: QueueItem] = [:]
        if let data {
            let library = data.library
            let tracks = await library.songs(ids: ids.filter { !isRadio($0) && !isOpenedFile($0) })
            let finds = await library.finds(ids.filter(isFind))
            let downloads = await data.offline.playableCopies(tracks.map(\.id))
            var tracksById: [String: LibraryTrack] = [:]
            for track in tracks { tracksById[track.id] = track }
            for find in finds {
                if let adopted = tracksById[find.adoptedId] {
                    tracksById[find.id] = adopted
                } else {
                    byId[find.id] = findItem(find, context: context, source: source)
                }
            }
            for id in Set(ids) where byId[id] == nil {
                guard let track = tracksById[id] else { continue }
                byId[id] = await libraryItem(track, download: downloads[track.id], context: context, source: source)
            }
            // A song the server lists as found online that has since joined the library plays as
            // the library song it became.
            let outside = Set(songs.filter { $0.isExternal && !isFind($0.id) }.map(\.id))
            if !outside.isEmpty {
                let joined = await library.finds(outside.map(findId)).filter { !$0.adoptedId.isEmpty }
                let became = await library.songs(ids: joined.map(\.adoptedId))
                let keptCopies = await data.offline.playableCopies(became.map(\.id))
                for find in joined where byId[find.nativeId] == nil {
                    guard let track = became.first(where: { $0.id == find.adoptedId }) else { continue }
                    byId[find.nativeId] = await libraryItem(track, download: keptCopies[track.id], context: context, source: source)
                }
            }
        }
        let orders = albumOrders(songs)
        return songs.enumerated().map { index, song in
            if let item = byId[song.id] { return item.withSource(source) }
            if isRadio(song.id) { return radioItem(song.id, source: source) }
            if isOpenedFile(song.id) { return openedFileItem(song.id, source: source) }
            // A song the library does not hold: the server in use streams it.
            guard streamUnknown, context.sourceId != nil else { return nil }
            return queueItem(song, sourceId: context.sourceId, quality: context.quality, source: source, albumOrder: orders[index])
        }
    }

    /// Songs by their ids, as the library holds them.
    func items(ids: [String], source: QueueSource) async -> [QueueItem?] {
        await items(ids.map { Song(id: $0, title: "") }, source: source, streamUnknown: false)
    }

    // MARK: Each kind

    private func libraryItem(_ track: LibraryTrack, download: KeptDownload?, context: StreamContext, source: QueueSource) async -> QueueItem {
        let copies = (await data?.library.copies(track.id) ?? []).map(songCopy)
        let downloadCopy = download.flatMap { kept -> SongCopy? in
            let server = copies.first { $0.sourceId == kept.sourceId && $0.nativeId == kept.serverId } ?? copies.first(where: \.isServerCopy)
            guard let server else { return nil }
            return downloadedCopy(server, uri: URL(fileURLWithPath: kept.path).absoluteString, format: kept.format, sizeBytes: Int(kept.sizeBytes))
        }
        let online = OnlineWatch.shared.online
        let reachable = copies.contains(where: \.isServerCopy) && online && context.client != nil
        let prefs = AppSettings.shared
        let streamInstead = prefs.offline.streamOnWifi && online && !OnlineWatch.shared.onMobileData
        let chosen = chooseCopy(copies, download: downloadCopy, streamInstead: streamInstead, prefs.stream.copies,
                                serverReachable: reachable, phoneFileMissing: { copy in Self.fileMissing(copy.uri) })
        var uri = track.uri ?? ""
        var mime = track.mimeType
        let fileMime = chosen?.mimeType ?? track.mimeType
        if let chosen {
            if chosen.isServerCopy {
                let ref = StreamRef(sourceId: chosen.sourceId, serverId: chosen.nativeId, mimeType: chosen.mimeType, bitrate: bitrateOf(chosen))
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
        let bitrate = find.bitrate.map { $0 * 1_000 }
        let ref = StreamRef(sourceId: find.sourceId, serverId: find.nativeId, mimeType: find.mimeType, bitrate: bitrate)
        var item = QueueItem(
            trackId: find.id, uri: streamUri(ref), title: find.title, artist: find.artist, album: find.album,
            durationMs: Int(find.durationMs), mimeType: phoneRequest(find.mimeType, bitrate, context.quality).mimeType(find.mimeType),
            fileMime: find.mimeType, artwork: onlineArtwork(find.sourceId, find.coverId), albumId: find.albumId,
            artistId: find.artistId, explicit: find.explicit ?? false, source: source, isFind: true)
        var song = Song(id: find.id, title: find.title, artist: find.artist, album: find.album, albumId: find.albumId,
                        duration: Int((find.durationMs + 500) / 1_000), coverArt: find.coverId, isExternal: true)
        song.artistId = find.artistId
        item.song = song
        return item
    }

    private func radioItem(_ id: String, source: QueueSource) -> QueueItem? {
        guard let station = radioOf(id) else { return nil }
        return QueueItem(trackId: id, uri: station.stream, title: radioTitle(id) ?? station.stream, artist: radioArtist, source: source)
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

    /// Whether a phone file has gone. Songs of the media library are taken to be there.
    private static func fileMissing(_ uri: String?) -> Bool {
        guard let uri, let url = URL(string: uri) else { return true }
        guard url.isFileURL else { return false }
        return !FileManager.default.fileExists(atPath: url.path)
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

    /// The server's cover id inside a stored artwork reference.
    static func coverId(_ artwork: String?) -> String? {
        guard let ref = ArtworkRef.decode(artwork) else { return artwork }
        if case .server(_, let coverId, _, _) = ref { return coverId }
        return nil
    }
}
