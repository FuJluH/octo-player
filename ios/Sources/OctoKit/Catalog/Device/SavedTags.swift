import Foundation

/// The way of reading tags that saved rows must match. Raised whenever reading tags learns
/// something new, so every file is read again once. Rows saved before genres were read are
/// version 0. Version 2 reads original years, credits, MusicBrainz ids, sort names, loudness and
/// the other details, and more spellings of every tag.
public let deviceTagsVersion = 2

/// A file's tags as they are kept between scans. Lists are kept one value per line. Nil tags mean
/// the file could not be read.
public func savedTags(mediaId: Int64, modifiedAt: Int64, size: Int64, tags: FileTags?, version: Int) -> FileTagsRow {
    FileTagsRow(
        mediaId: mediaId,
        modifiedAt: modifiedAt,
        size: size,
        readOk: tags != nil,
        title: tags?.title,
        artist: tags?.artist,
        albumArtist: tags?.albumArtist,
        album: tags?.album,
        trackNo: tags?.trackNo,
        discNo: tags?.discNo,
        year: tags?.year,
        compilation: tags?.compilation ?? false,
        mbAlbumId: tags?.mbAlbumId,
        genres: joinLines(tags?.genres),
        tagsVersion: version,
        originalYear: tags?.originalYear,
        artists: joinLines(tags?.artists),
        composer: tags?.composer,
        bpm: tags?.bpm,
        comment: tags?.comment,
        explicit: tags?.explicit,
        discTitle: tags?.discTitle,
        mbRecordingId: tags?.mbRecordingId,
        mbReleaseGroupId: tags?.mbReleaseGroupId,
        mbArtistIds: joinLines(tags?.mbArtistIds),
        sortTitle: tags?.sortTitle,
        sortAlbum: tags?.sortAlbum,
        sortAlbumArtist: tags?.sortAlbumArtist,
        trackGain: tags?.trackGain,
        albumGain: tags?.albumGain,
        trackPeak: tags?.trackPeak,
        albumPeak: tags?.albumPeak
    )
}

extension FileTagsRow {
    /// The kept tags as a file's tags again.
    public func toTags() -> FileTags {
        FileTags(
            title: title,
            artist: artist,
            albumArtist: albumArtist,
            album: album,
            trackNo: trackNo,
            discNo: discNo,
            year: year,
            compilation: compilation,
            mbAlbumId: mbAlbumId,
            genres: splitLines(genres),
            originalYear: originalYear,
            artists: splitLines(artists),
            composer: composer,
            bpm: bpm,
            comment: comment,
            explicit: explicit,
            discTitle: discTitle,
            mbRecordingId: mbRecordingId,
            mbReleaseGroupId: mbReleaseGroupId,
            mbArtistIds: splitLines(mbArtistIds),
            sortTitle: sortTitle,
            sortAlbum: sortAlbum,
            sortAlbumArtist: sortAlbumArtist,
            trackGain: trackGain,
            albumGain: albumGain,
            trackPeak: trackPeak,
            albumPeak: albumPeak
        )
    }
}

/// Whether a file's tags must be read again: a file never read, one whose modified time or size
/// changed since, or one read by another way of reading tags.
public func needsTagRead(_ saved: FileTagsRow?, _ file: DeviceFile, version: Int = deviceTagsVersion) -> Bool {
    guard let saved else { return true }
    return saved.modifiedAt != file.modifiedAt || saved.size != file.sizeBytes || saved.tagsVersion != version
}

extension DeviceFile {
    /// The file's tags as they are kept, with this file's modified time and size.
    public func toSaved(_ tags: FileTags?, version: Int = deviceTagsVersion) -> FileTagsRow {
        savedTags(mediaId: id, modifiedAt: modifiedAt, size: sizeBytes, tags: tags, version: version)
    }
}
