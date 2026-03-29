import MediaPlayer
import AppKit

/// Bridges MPD playback state to macOS Now Playing Info Center.
/// This makes DrPlayer appear in Control Center, respond to media keys,
/// and work with AirPods / headphone controls.
final class NowPlayingBridge {
    static let shared = NowPlayingBridge()

    private var lastFile = ""
    private var commandsRegistered = false

    private init() {}

    /// Register remote command handlers. Call once at startup.
    func setup(
        onPlayPause: @escaping () -> Void,
        onNext: @escaping () -> Void,
        onPrev: @escaping () -> Void,
        onSeek: @escaping (Double) -> Void
    ) {
        guard !commandsRegistered else { return }
        commandsRegistered = true

        let center = MPRemoteCommandCenter.shared()

        center.togglePlayPauseCommand.isEnabled = true
        center.togglePlayPauseCommand.addTarget { _ in
            onPlayPause()
            return .success
        }

        center.playCommand.isEnabled = true
        center.playCommand.addTarget { _ in
            onPlayPause()
            return .success
        }

        center.pauseCommand.isEnabled = true
        center.pauseCommand.addTarget { _ in
            onPlayPause()
            return .success
        }

        center.nextTrackCommand.isEnabled = true
        center.nextTrackCommand.addTarget { _ in
            onNext()
            return .success
        }

        center.previousTrackCommand.isEnabled = true
        center.previousTrackCommand.addTarget { _ in
            onPrev()
            return .success
        }

        center.changePlaybackPositionCommand.isEnabled = true
        center.changePlaybackPositionCommand.addTarget { event in
            guard let posEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            onSeek(posEvent.positionTime)
            return .success
        }
    }

    /// Update Now Playing info with current track state.
    func update(
        title: String,
        artist: String,
        album: String,
        duration: Double,
        elapsed: Double,
        isPlaying: Bool,
        file: String,
        coverImage: NSImage?
    ) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: artist,
            MPMediaItemPropertyAlbumTitle: album,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]

        // Set artwork if available and track changed
        if let image = coverImage {
            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            info[MPMediaItemPropertyArtwork] = artwork
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused
    }

    /// Clear Now Playing info when stopped.
    func clear() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPNowPlayingInfoCenter.default().playbackState = .stopped
    }
}
