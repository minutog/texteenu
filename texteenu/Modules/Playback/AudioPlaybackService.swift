import AVFoundation
import Foundation

@MainActor
protocol AudioPlaybackService: AnyObject {
    var isPlaying: Bool { get }

    func playAudio(from fileURL: URL, muted: Bool) throws
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

    var isPlaying: Bool {
        player?.isPlaying ?? false
    }

    func playAudio(from fileURL: URL, muted: Bool) throws {
        stop()

        try audioSession.setCategory(.playback, mode: .default, options: [.duckOthers])
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        let player = try AVAudioPlayer(contentsOf: fileURL)
        player.currentTime = 0
        player.volume = muted ? 0 : 1
        player.prepareToPlay()

        guard player.play() else {
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

        do {
            try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            // Ignore session teardown failures during cleanup.
        }
    }
}
