import Foundation
import QuartzCore

enum PlaybackState: Equatable {
    case idle
    case ready
    case playing
    case finished
}

struct PlaybackSnapshot: Equatable {
    let state: PlaybackState
    let visibleTokens: [WordToken]
    let currentToken: WordToken?

    static let idle = PlaybackSnapshot(state: .idle, visibleTokens: [], currentToken: nil)
}

@MainActor
protocol PlaybackEngine: AnyObject {
    var snapshot: PlaybackSnapshot { get }
    var onSnapshotChange: ((PlaybackSnapshot) -> Void)? { get set }
    var onWordReveal: ((WordToken) -> Void)? { get set }

    func load(tokens: [WordToken])
    func start(synchronizedTo timeSource: any PlaybackTimeSource)
    func stop()
}

@MainActor
final class TimedWordPlaybackEngine: PlaybackEngine {
    private enum Synchronization {
        static let textRevealDelay: TimeInterval = 0.08
    }
    private(set) var snapshot = PlaybackSnapshot.idle
    private var loadedTokens: [WordToken] = []
    private weak var timeSource: (any PlaybackTimeSource)?
    private var displayLink: CADisplayLink?
    private var nextTokenIndex = 0
    private var visibleTokens: [WordToken] = []

    var onSnapshotChange: ((PlaybackSnapshot) -> Void)?
    var onWordReveal: ((WordToken) -> Void)?

    func load(tokens: [WordToken]) {
        invalidateDisplayLink()
        loadedTokens = tokens
        nextTokenIndex = 0
        visibleTokens = []
        snapshot = tokens.isEmpty ? .idle : PlaybackSnapshot(state: .ready, visibleTokens: [], currentToken: nil)
        onSnapshotChange?(snapshot)
    }

    func start(synchronizedTo timeSource: any PlaybackTimeSource) {
        guard !loadedTokens.isEmpty else { return }

        invalidateDisplayLink()
        self.timeSource = timeSource
        nextTokenIndex = 0
        visibleTokens = []
        pushSnapshot(state: .playing, visibleTokens: [], currentToken: nil)

        let displayLink = CADisplayLink(target: self, selector: #selector(handleDisplayLink))
        displayLink.add(to: .main, forMode: .common)
        self.displayLink = displayLink
    }

    func stop() {
        invalidateDisplayLink()
        timeSource = nil
        nextTokenIndex = 0
        visibleTokens = []
        let state: PlaybackState = loadedTokens.isEmpty ? .idle : .ready
        pushSnapshot(state: state, visibleTokens: [], currentToken: nil)
    }

    @objc
    private func handleDisplayLink(_ displayLink: CADisplayLink) {
        guard let timeSource else {
            finishPlayback()
            return
        }

        guard timeSource.hasStartedPlayback else { return }

        let adjustedPlaybackTime = max(0, timeSource.currentPlaybackTime - Synchronization.textRevealDelay)
        revealTokens(upTo: adjustedPlaybackTime)

        if nextTokenIndex >= loadedTokens.count {
            finishPlayback()
            return
        }

        if !timeSource.isPlaybackRunning && adjustedPlaybackTime >= loadedTokens[nextTokenIndex].startTime {
            revealTokens(upTo: adjustedPlaybackTime)
        }
    }

    private func revealTokens(upTo playbackTime: TimeInterval) {
        while nextTokenIndex < loadedTokens.count {
            let token = loadedTokens[nextTokenIndex]
            guard token.startTime <= playbackTime else { break }

            visibleTokens.append(token)
            nextTokenIndex += 1
            pushSnapshot(state: .playing, visibleTokens: visibleTokens, currentToken: token)
        }
    }

    private func finishPlayback() {
        invalidateDisplayLink()
        let finalVisibleTokens = visibleTokens
        timeSource = nil
        pushSnapshot(state: .finished, visibleTokens: finalVisibleTokens, currentToken: nil)
    }

    private func invalidateDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    private func pushSnapshot(state: PlaybackState, visibleTokens: [WordToken], currentToken: WordToken?) {
        snapshot = PlaybackSnapshot(state: state, visibleTokens: visibleTokens, currentToken: currentToken)
        onSnapshotChange?(snapshot)

        if let currentToken {
            onWordReveal?(currentToken)
        }
    }

    deinit {
        displayLink?.invalidate()
    }
}
