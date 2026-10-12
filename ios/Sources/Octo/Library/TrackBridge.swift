import OctoKit
import SwiftUI

// Between the library's rows and what the player and the routes take.

extension LibraryTrack {
    /// The server's own id for this song, when its row is the server's copy.
    var serverSongId: String? {
        if isFind(id) { return nativeId }
        return isServerSource(sourceId) ? nativeId : nil
    }

    /// The cover's id on the server, when the artwork is the server's.
    var coverId: String? {
        if case .server(_, let coverId, _, _) = ArtworkRef.decode(artwork) { return coverId }
        return nil
    }

    /// The song as the player takes it: the server's copy, by the server's id.
    var asSong: Song {
        var song = Song(id: serverSongId ?? nativeId, title: title, artist: artist, album: album,
                        albumId: serverAlbumId, duration: Int(durationMs / 1_000), coverArt: coverId,
                        suffix: mimeType.flatMap { $0.split(separator: "/").last.map(String.init) }, isExternal: isFind(id))
        song.track = trackNo
        song.discNumber = discNo
        song.year = year
        song.contentType = mimeType
        song.genre = genre.isEmpty ? nil : genre
        song.explicitStatus = explicit == true ? "explicit" : (explicit == false ? "clean" : nil)
        song.artistId = serverArtistId
        return song
    }

    /// The album's id on the server, from the library's "<source>:<id>".
    var serverAlbumId: String? { serverPart(albumId) }
    var serverArtistId: String? { serverPart(artistId) }

    private func serverPart(_ libraryId: String) -> String? {
        guard isServerSource(sourceId), libraryId.hasPrefix(sourceId + ":") else { return nil }
        let rest = String(libraryId.dropFirst(sourceId.count + 1))
        return rest.isEmpty || rest.hasPrefix("album:") ? nil : rest
    }

    /// Whether a song row offers the song as found online, not in the library.
    var isFound: Bool { isFind(id) }
}

extension LibraryAlbum {
    var coverId: String? {
        if case .server(_, let coverId, _, _) = ArtworkRef.decode(artwork) { return coverId }
        return nil
    }

    /// The album as routes and cards take it.
    var asAlbum: Album {
        var album = Album(id: id, name: title, artist: artist, coverArt: coverId)
        album.artistId = artistId
        album.year = year
        album.songCount = songCount
        album.duration = Int(durationMs / 1_000)
        return album
    }

    /// The release types, one a line as kept.
    var types: [String] { releaseTypes.split(separator: "\n").map(String.init).filter { !$0.isEmpty } }
}

extension LibraryArtist {
    var coverId: String? {
        if case .server(_, let coverId, _, _) = ArtworkRef.decode(artwork) { return coverId }
        return nil
    }
}

/// A picture from the library's artwork: a server's cover, or the stand-in tile while it loads
/// or when there is none.
struct ArtCover: View {
    let artwork: String?
    var size: CGFloat
    var radius: CGFloat = OctoRadius.artS

    var body: some View {
        switch ArtworkRef.decode(artwork) {
        case .server(_, let coverId, _, _):
            Cover(id: coverId, size: size, radius: radius)
        default:
            Cover(id: nil, size: size, radius: radius)
        }
    }
}

extension Library {
    /// The library album a route names: by the library's id, or by the server's own id.
    func resolveAlbum(_ id: String) async -> LibraryAlbum? {
        if let album = await album(id) { return album }
        if let server = serverInUse { return await album("\(server):\(id)") }
        return nil
    }

    /// The library artist a route names: by the library's id, the server's own id, or the name.
    func resolveArtist(_ id: String, name: String) async -> LibraryArtist? {
        if let artist = await artist(id) { return artist }
        if let server = serverInUse, let artist = await artist("\(server):\(id)") { return artist }
        return await artistsWithKeys([searchKey(name)]).first
    }

    /// Library songs for plain songs the server listed, where the library has them.
    func libraryTracks(for songs: [Song]) async -> [LibraryTrack] {
        guard let server = serverInUse else { return [] }
        return await tracks(ids: songs.map { "\(server):\($0.id)" })
    }

    /// The library song a plain song from the server is, when the library has it.
    func libraryTrack(for song: Song) async -> LibraryTrack? {
        if song.isExternal { return nil }
        if let track = await track(song.id) { return track }
        guard let server = serverInUse else { return nil }
        return await track("\(server):\(song.id)")
    }
}
