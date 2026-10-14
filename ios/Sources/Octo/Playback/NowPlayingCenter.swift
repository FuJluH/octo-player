import MediaPlayer
import OctoKit
import UIKit

/// The song on the lock screen, in Control Center, on a watch and in the car: its words, picture
/// and place, and the buttons there (play, pause, previous, next, the scrub bar, and Close). The
/// heart, or the download that stands in for it, goes on the car's now playing screen: on the
/// lock screen it would take the place of Previous.
@MainActor
final class NowPlayingCenter {
    private unowned let player: Player
    private var artwork: MPMediaItemArtwork?
    private var artworkFor: String?
    /// The queue entry the picture shown belongs to.
    private var artworkEntry: String?
    /// The buttons last turned on and off, so they change only when what plays changes.
    private var shownButtons: RemoteButtons?
    /// The heart or download for the song on now.
    private(set) var heart: NotificationHeart = .none
    /// Told when the heart changes, for the car's now playing screen.
    var onHeartChange: ((NotificationHeart) -> Void)?
    /// Closed from the lock screen: nothing shows there until music plays again.
    private var closed = false

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
        if player.isPlaying { closed = false }
        guard !closed, let item = player.engine.currentItem else {
            center.nowPlayingInfo = nil
            center.playbackState = .stopped
            updateHeart(nil)
            return
        }
        // A live station shows what it has on air, with "Artist · Station" under it, and the
        // song's artwork when the station sends one.
        let live = item.isRadioStation ? LiveTitleBoard.shared.shown(item.trackId) : nil
        let picture = artworkKey(item, live)
        if artworkFor != picture { loadArtwork(item, live, key: picture) }
        let buttons = RemoteButtons.of(player.engine.queue.items.map(\.trackId), current: player.index)
        // A live station connecting counts as on, so its Stop shows while it gets going.
        let playing = live == nil ? player.isPlaying : player.liveOn
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: live?.title ?? item.title,
            MPMediaItemPropertyArtist: live?.subtitle ?? item.artist,
            MPMediaItemPropertyAlbumTitle: live == nil ? item.album : "",
            MPNowPlayingInfoPropertyElapsedPlaybackTime: player.elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: playing ? Double(live == nil ? player.engine.pace.speed : 1) : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: Double(live == nil ? player.engine.pace.speed : 1),
            MPNowPlayingInfoPropertyPlaybackQueueIndex: player.index,
            MPNowPlayingInfoPropertyPlaybackQueueCount: player.engine.queue.count,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
            MPNowPlayingInfoPropertyIsLiveStream: buttons.live,
        ]
        if buttons.showsDuration { info[MPMediaItemPropertyPlaybackDuration] = player.duration }
        if let track = item.trackNo { info[MPMediaItemPropertyAlbumTrackNumber] = track }
        if let disc = item.discNo { info[MPMediaItemPropertyDiscNumber] = disc }
        if item.explicit { info[MPMediaItemPropertyIsExplicit] = true }
        if let artwork { info[MPMediaItemPropertyArtwork] = artwork }
        center.nowPlayingInfo = info
        center.playbackState = playing ? .playing : .paused
        applyButtons(buttons)
        updateHeart(item)
    }

    /// Turns the lock screen's buttons on and off for what plays: a live station cannot be
    /// moved through, its Next and Previous stop at the ends of its list, and its transport is
    /// Stop.
    private func applyButtons(_ buttons: RemoteButtons) {
        guard buttons != shownButtons else { return }
        shownButtons = buttons
        let commands = MPRemoteCommandCenter.shared()
        commands.changePlaybackPositionCommand.isEnabled = buttons.changePosition
        commands.seekForwardCommand.isEnabled = buttons.seek
        commands.seekBackwardCommand.isEnabled = buttons.seek
        commands.skipForwardCommand.isEnabled = buttons.skipInterval
        commands.skipBackwardCommand.isEnabled = buttons.skipInterval
        commands.nextTrackCommand.isEnabled = buttons.next
        commands.previousTrackCommand.isEnabled = buttons.previous
        commands.pauseCommand.isEnabled = buttons.pause
        commands.togglePlayPauseCommand.isEnabled = buttons.togglePlayPause
        commands.stopCommand.isEnabled = buttons.stop
    }

    /// Takes everything off the lock screen, as Close does.
    func clear() {
        closed = true
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPNowPlayingInfoCenter.default().playbackState = .stopped
    }

    /// The covers a live station's lock screen picture can come from, best first.
    private func liveSources(_ item: QueueItem, _ live: LiveShown) -> [LiveCoverSource] {
        liveCoverSources(octo: LiveLookup.shared.cover(live.onAir), shown: live, serverCover: item.artwork)
    }

    /// What the picture on the lock screen is for: the entry, and for a live station the covers
    /// it can show.
    private func artworkKey(_ item: QueueItem, _ live: LiveShown?) -> String {
        let covers = live.map { liveSources(item, $0).map { "\($0)" }.joined(separator: ",") } ?? ""
        return "\(item.entryId ?? item.trackId)|\(covers)"
    }

    /// The lock screen and car pictures are drawn about 512 px wide. A live station shows the
    /// song on air's cover in Octo, else the artwork it sent, else its logo, else its server
    /// cover; the tile Octo draws for it shows at once until one of them loads.
    private func loadArtwork(_ item: QueueItem, _ live: LiveShown?, key: String) {
        let entry = item.entryId ?? item.trackId
        let session = player.session
        if let live {
            let sources = liveSources(item, live)
            // A new station shows its drawn tile at once; a new song keeps the picture it has
            // until a better one is ready.
            if artworkEntry != entry || artwork == nil { artwork = Self.artwork(drawnStationTile(live.station, pixels: 512)) }
            artworkEntry = entry
            artworkFor = key
            if let best = sources.first, let quick = cachedLiveCover(best, pixels: 512) {
                artwork = Self.artwork(quick)
                return
            }
            Task {
                let found = await loadFirstLiveCover(sources, pixels: 512, client: session.client)
                guard artworkFor == key else { return }
                artwork = Self.artwork(found?.1 ?? drawnStationTile(live.station, pixels: 512))
                publish()
            }
            return
        }
        if artworkEntry != entry { artwork = nil }
        artworkEntry = entry
        artworkFor = key
        let reference = item.artwork
        Task {
            var image: UIImage?
            if ArtworkRef.decode(reference) != nil {
                image = await ArtworkCache.shared.image(reference, px: 512, client: session.client, signedInSource: session.inUse?.sourceId)
            } else if let coverId = reference, let client = session.client {
                image = await Covers.shared.image(coverId, size: 512, client: client)
            }
            guard let image, artworkFor == key else { return }
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
        onHeartChange?(next)
    }

    private func serverIdOfFind(_ trackId: String) -> String {
        isFind(trackId) ? String(trackId.dropFirst(findPrefix.count)) : trackId
    }

    // MARK: Buttons

    private func setUpCommands() {
        let commands = MPRemoteCommandCenter.shared()
        commands.playCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated {
                guard let player = self?.player else { return .commandFailed }
                // Nothing to resume: no queue was kept, or none of it can play.
                if player.engine.queue.isEmpty && !player.restoring { return .noActionableNowPlayingItem }
                player.resume()
                return .success
            }
        }
        commands.pauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.player.pause() }
            return .success
        }
        commands.togglePlayPauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated {
                guard let player = self?.player else { return .commandFailed }
                // A headset or the lock screen brings back what was kept, never a shuffle of
                // everything: with nothing to resume, it says so.
                if player.engine.queue.isEmpty {
                    if !player.restoring { return .noActionableNowPlayingItem }
                    player.resume()
                    return .success
                }
                player.toggle()
                return .success
            }
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
            MainActor.assumeIsolated {
                guard let self else { return }
                // A live station's Stop lets go of its stream and stays on the lock screen, so
                // Play reconnects to what is on air; a song's Stop closes the player.
                switch self.shownButtons?.stopDoes ?? .close {
                case .stopStream: self.player.pause()
                case .close: self.player.close()
                }
            }
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
