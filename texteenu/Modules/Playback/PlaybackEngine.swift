import Foundation

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
    func start()
    func stop()
}

@MainActor
final class TimedWordPlaybackEngine: PlaybackEngine {
    private(set) var snapshot = PlaybackSnapshot.idle
    private var loadedTokens: [WordToken] = []
    private var playbackTask: Task<Void, Never>?

    var onSnapshotChange: ((PlaybackSnapshot) -> Void)?
    var onWordReveal: ((WordToken) -> Void)?

    func load(tokens: [WordToken]) {
        cancelPlaybackTask()
        loadedTokens = tokens
        snapshot = tokens.isEmpty ? .idle : PlaybackSnapshot(state: .ready, visibleTokens: [], currentToken: nil)
        onSnapshotChange?(snapshot)
    }

    func start() {
        guard !loadedTokens.isEmpty else { return }

        cancelPlaybackTask()
        pushSnapshot(state: .playing, visibleTokens: [], currentToken: nil)

        let tokens = loadedTokens
        playbackTask = Task { @MainActor [weak self] in
            guard let self else { return }

            var visibleTokens: [WordToken] = []
            var previousStartTime: TimeInterval = 0

            for token in tokens {
                let delay = max(0, token.startTime - previousStartTime)
                if delay > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }

                guard !Task.isCancelled else { return }

                visibleTokens.append(token)
                self.pushSnapshot(state: .playing, visibleTokens: visibleTokens, currentToken: token)
                previousStartTime = token.startTime
            }

            self.pushSnapshot(state: .finished, visibleTokens: visibleTokens, currentToken: nil)
            self.playbackTask = nil
        }
    }

    func stop() {
        cancelPlaybackTask()
        let state: PlaybackState = loadedTokens.isEmpty ? .idle : .ready
        pushSnapshot(state: state, visibleTokens: [], currentToken: nil)
    }

    private func cancelPlaybackTask() {
        playbackTask?.cancel()
        playbackTask = nil
    }

    private func pushSnapshot(state: PlaybackState, visibleTokens: [WordToken], currentToken: WordToken?) {
        snapshot = PlaybackSnapshot(state: state, visibleTokens: visibleTokens, currentToken: currentToken)
        onSnapshotChange?(snapshot)

        if let currentToken {
            onWordReveal?(currentToken)
        }
    }

    deinit {
        playbackTask?.cancel()
    }
}
