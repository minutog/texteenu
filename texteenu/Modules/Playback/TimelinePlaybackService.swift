import Foundation
import QuartzCore

@MainActor
protocol TimelinePlaybackService: PlaybackTimeSource {
    func start(duration: TimeInterval, after delay: TimeInterval)
    func stop()
}

@MainActor
final class ClockPlaybackService: TimelinePlaybackService {
    private var scheduledStartTime: CFTimeInterval?
    private var playbackDuration: TimeInterval = 0

    var currentPlaybackTime: TimeInterval {
        guard let scheduledStartTime else { return 0 }
        let elapsed = CACurrentMediaTime() - scheduledStartTime
        return min(max(elapsed, 0), playbackDuration)
    }

    var hasStartedPlayback: Bool {
        guard let scheduledStartTime else { return false }
        return CACurrentMediaTime() >= scheduledStartTime
    }

    var isPlaybackRunning: Bool {
        guard scheduledStartTime != nil else { return false }
        return hasStartedPlayback && currentPlaybackTime < playbackDuration
    }

    func start(duration: TimeInterval, after delay: TimeInterval) {
        playbackDuration = max(duration, 0)
        scheduledStartTime = CACurrentMediaTime() + max(delay, 0)
    }

    func stop() {
        scheduledStartTime = nil
        playbackDuration = 0
    }
}
