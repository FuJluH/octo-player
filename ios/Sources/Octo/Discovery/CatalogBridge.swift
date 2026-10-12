import Foundation
import OctoKit

// The library's rows as the player, the rows and the pages take songs, albums and artists today:
// by their ids on the server in use.

/// The server's id for a library row id made from it ("<source>:<native id>"), or nil for a row the
/// library made itself or one from another source.
func serverId(of catalogId: String, sourceId: String?) -> String? {
    guard let sourceId, catalogId.hasPrefix(sourceId + ":") else { return nil }
    let native = String(catalogId.dropFirst(sourceId.count + 1))
    if native.isEmpty || native.hasPrefix("artist:") || native.hasPrefix("album:") { return nil }
    return native
}

/// The server cover a library picture names, or nil for a picture from the phone.
func coverId(of artwork: String?) -> String? {
    if case .server(_, let coverId, _, _) = ArtworkRef.decode(artwork) { return coverId }
    return nil
}

extension LibraryTrack {
    /// The song as the player plays it: a find by its id on the server, a server song by its own.
    var asSong: Song {
        let find = isFind(id)
        var song = Song(id: find || isServerSource(sourceId) ? nativeId : id, title: title, artist: artist, album: album,
                        albumId: serverId(of: albumId, sourceId: sourceId), duration: Int(durationMs / 1_000),
                        coverArt: coverId(of: artwork), isExternal: find)
        song.artistId = serverId(of: artistId, sourceId: sourceId)
        song.year = year
        song.track = trackNo
        song.discNumber = discNo
        song.genre = genre.isEmpty ? nil : genre
        if let explicit { song.explicitStatus = explicit ? "explicit" : "clean" }
        return song
    }
}

extension LibraryAlbum {
    /// The album as its page opens it.
    var asAlbum: Album {
        var album = Album(id: isServerSource(sourceId) ? nativeId : id, name: title, artist: artist, coverArt: coverId(of: artwork))
        album.artistId = serverId(of: artistId, sourceId: sourceId)
        album.songCount = songCount
        album.duration = Int(durationMs / 1_000)
        album.year = year
        return album
    }
}

extension LibraryArtist {
    /// The artist's id on the server, for its page.
    func pageId(_ sourceInUse: String?) -> String { serverId(of: id, sourceId: sourceInUse ?? sourceId) ?? id }
}

extension PlaylistSummary {
    /// The playlist as its page opens it.
    func asPlaylist(_ sourceInUse: String?) -> Playlist? {
        let data = try? JSONSerialization.data(withJSONObject: [
            "id": serverId(of: id, sourceId: sourceInUse) ?? id, "name": name, "songCount": songCount,
            "duration": Int(durationMs / 1_000), "coverArt": coverId(of: covers.first) ?? "", "octoNotice": octoNotice ?? "",
        ])
        return data.flatMap { try? JSONDecoder().decode(Playlist.self, from: $0) }
    }
}
