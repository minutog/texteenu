import AVFoundation
import Foundation

@MainActor
protocol PlaybackTimeSource: AnyObject {
    var currentPlaybackTime: TimeInterval { get }
    var hasStartedPlayback: Bool { get }
    var isPlaybackRunning: Bool { get }
}

@MainActor
protocol AudioPlaybackService: PlaybackTimeSource {
    var isPlaying: Bool { get }

    func playAudio(from fileURL: URL, muted: Bool, after delay: TimeInterval) throws
    func setMuted(_ muted: Bool)
    func stop()
}

enum AudioPlaybackError: LocalizedError {
    case playerUnavailable

    var errorDescription: String? {
        switch self {
        case .playerUnavailable:
            return "The recorded audio could not be played back."
        }
    }
}

@MainActor
final class AVAudioPlaybackService: NSObject, AudioPlaybackService {
    private let audioSession = AVAudioSession.sharedInstance()
    private var player: AVAudioPlayer?
    private var scheduledStartDeviceTime: TimeInterval?

    var isPlaying: Bool {
        player?.isPlaying ?? false
    }

    var currentPlaybackTime: TimeInterval {
        player?.currentTime ?? 0
    }

    var hasStartedPlayback: Bool {
        guard let player else { return false }
        guard let scheduledStartDeviceTime else { return player.isPlaying }
        return player.deviceCurrentTime >= scheduledStartDeviceTime
    }

    var isPlaybackRunning: Bool {
        player?.isPlaying ?? false
    }

    func playAudio(from fileURL: URL, muted: Bool, after delay: TimeInterval) throws {
        stop()

        try audioSession.setCategory(.playback, mode: .default, options: [.duckOthers])
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        let player = try AVAudioPlayer(contentsOf: fileURL)
        player.currentTime = 0
        player.volume = muted ? 0 : 1
        player.prepareToPlay()

        let scheduledDelay = max(delay, 0)
        let startDeviceTime = player.deviceCurrentTime + scheduledDelay
        scheduledStartDeviceTime = startDeviceTime

        let didStart = scheduledDelay > 0
            ? player.play(atTime: startDeviceTime)
            : player.play()

        guard didStart else {
            scheduledStartDeviceTime = nil
            throw AudioPlaybackError.playerUnavailable
        }

        self.player = player
    }

    func setMuted(_ muted: Bool) {
        player?.volume = muted ? 0 : 1
    }

    func stop() {
        player?.stop()
        player = nil
        scheduledStartDeviceTime = nil

        do {
            try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            // Ignore session teardown failures during cleanup.
        }
    }
}
