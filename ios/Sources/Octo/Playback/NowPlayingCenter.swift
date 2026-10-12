import MediaPlayer
import OctoKit
import UIKit

/// The song on the lock screen, in Control Center, on a watch and in the car: its words, picture
/// and place, and the buttons there (play, pause, previous, next, the scrub bar, the heart or the
/// download that stands in for it, and Close).
@MainActor
final class NowPlayingCenter {
    private unowned let player: Player
    private var artwork: MPMediaItemArtwork?
    private var artworkFor: String?
    private var heart: NotificationHeart = .none

    init(player: Player) {
        self.player = player
        setUpCommands()
    }

    /// The picture for the lock screen is asked for from the system's own thread.
    nonisolated private static func artwork(_ image: UIImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }

    /// Puts the song on now, where it is and whether it plays, on the lock screen.
    func publish() {
        let center = MPNowPlayingInfoCenter.default()
        guard let item = player.engine.currentItem else {
            center.nowPlayingInfo = nil
            center.playbackState = .stopped
            updateHeart(nil)
            return
        }
        if artworkFor != item.entryId { loadArtwork(item) }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: item.title,
            MPMediaItemPropertyArtist: item.artist,
            MPMediaItemPropertyAlbumTitle: item.album,
            MPMediaItemPropertyPlaybackDuration: player.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: player.elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: player.isPlaying ? Double(player.engine.pace.speed) : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: Double(player.engine.pace.speed),
            MPNowPlayingInfoPropertyPlaybackQueueIndex: player.index,
            MPNowPlayingInfoPropertyPlaybackQueueCount: player.engine.queue.count,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
            MPNowPlayingInfoPropertyIsLiveStream: item.isRadioStation,
        ]
        if let track = item.trackNo { info[MPMediaItemPropertyAlbumTrackNumber] = track }
        if let disc = item.discNo { info[MPMediaItemPropertyDiscNumber] = disc }
        if item.explicit { info[MPMediaItemPropertyIsExplicit] = true }
        if let artwork { info[MPMediaItemPropertyArtwork] = artwork }
        center.nowPlayingInfo = info
        center.playbackState = player.isPlaying ? .playing : .paused
        updateHeart(item)
    }

    /// Takes everything off the lock screen, as Close does.
    func clear() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPNowPlayingInfoCenter.default().playbackState = .stopped
    }

    /// The lock screen and car pictures are drawn about 512 px wide.
    private func loadArtwork(_ item: QueueItem) {
        artworkFor = item.entryId
        artwork = nil
        let session = player.session
        let entry = item.entryId
        let reference = item.artwork
        Task {
            var image: UIImage?
            if ArtworkRef.decode(reference) != nil {
                image = await ArtworkCache.shared.image(reference, px: 512, client: session.client, signedInSource: session.inUse?.sourceId)
            } else if let coverId = reference, let client = session.client {
                image = await Covers.shared.image(coverId, size: 512, client: client)
            }
            guard let image, artworkFor == entry else { return }
            artwork = Self.artwork(image)
            publish()
        }
    }

    // MARK: The heart

    /// The heart for a library song, the download for a song found online that was not asked
    /// for yet, nothing for no song or a station.
    func updateHeart(_ item: QueueItem?) {
        let liked = player.data?.likes.liked ?? []
        var states: [String: DownloadState] = [:]
        if let item, item.isFind, let downloads = player.data?.downloads {
            states[item.trackId] = downloads.state(serverIdOfFind(item.trackId))
        }
        let next = notificationHeart(item?.trackId, isFind: item?.isFind ?? false, liked: liked, downloads: states)
        guard next != heart else { return }
        heart = next
        let commands = MPRemoteCommandCenter.shared()
        switch next {
        case .like(let isLiked):
            commands.likeCommand.isEnabled = true
            commands.likeCommand.isActive = isLiked
            commands.likeCommand.localizedTitle = isLiked ? "Unlike" : "Like"
            commands.bookmarkCommand.isEnabled = false
        case .download:
            commands.likeCommand.isEnabled = false
            commands.bookmarkCommand.isEnabled = true
            commands.bookmarkCommand.localizedTitle = "Add to your library"
        case .none:
            commands.likeCommand.isEnabled = false
            commands.bookmarkCommand.isEnabled = false
        }
    }

    private func serverIdOfFind(_ trackId: String) -> String {
        isFind(trackId) ? String(trackId.dropFirst(findPrefix.count)) : trackId
    }

    // MARK: Buttons

    private func setUpCommands() {
        let commands = MPRemoteCommandCenter.shared()
        commands.playCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.player.resume() }
            return .success
        }
        commands.pauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.player.pause() }
            return .success
        }
        commands.togglePlayPauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.player.toggle() }
            return .success
        }
        commands.nextTrackCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.player.next() }
            return .success
        }
        commands.previousTrackCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.player.previous() }
            return .success
        }
        commands.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let position = event.positionTime
            MainActor.assumeIsolated { self?.player.seek(to: position) }
            return .success
        }
        commands.likeCommand.isEnabled = false
        commands.likeCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.player.likeFromOutside() }
            return .success
        }
        commands.bookmarkCommand.isEnabled = false
        commands.bookmarkCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.player.downloadFromOutside() }
            return .success
        }
        commands.stopCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.player.close() }
            return .success
        }
        commands.dislikeCommand.isEnabled = false
        commands.ratingCommand.isEnabled = false
        commands.changeRepeatModeCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangeRepeatModeCommandEvent else { return .commandFailed }
            let mode = event.repeatType
            MainActor.assumeIsolated {
                self?.player.setRepeat(mode == .one ? .one : mode == .all ? .all : .off)
            }
            return .success
        }
        commands.changeShuffleModeCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangeShuffleModeCommandEvent else { return .commandFailed }
            let on = event.shuffleType != .off
            MainActor.assumeIsolated {
                if self?.player.shuffled != on { self?.player.toggleShuffle() }
            }
            return .success
        }
    }
}
