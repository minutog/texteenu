import Combine
import SwiftUI

@MainActor
final class AppViewModel: ObservableObject {
    private enum PlaybackSynchronization {
        static let leadTime: TimeInterval = 0.1
    }

    enum Screen {
        case recording
        case reading
    }

    enum ProcessingState: Equatable {
        case idle
        case transcribing
        case analyzing

        var isRunning: Bool {
            self != .idle
        }

        var title: String? {
            switch self {
            case .idle:
                return nil
            case .transcribing:
                return "Transcribing audio..."
            case .analyzing:
                return "Analyzing prosody and word importance..."
            }
        }
    }

    @Published private(set) var screen: Screen = .recording
    @Published private(set) var isRecording = false
    @Published private(set) var processingState: ProcessingState = .idle
    @Published private(set) var recordedFileURL: URL?
    @Published private(set) var transcriptionText = ""
    @Published private(set) var analyzedTokens: [WordToken] = []
    @Published private(set) var visibleTokens: [WordToken] = []
    @Published private(set) var playbackState: PlaybackState = .idle
    @Published private(set) var isAudioMuted = false
    @Published var errorMessage: String?

    private let recordingService: any AudioRecordingService
    private let transcriptionService: any AudioTranscriptionService
    private let analysisService: any AudioAnalysisService
    private let playbackEngine: any PlaybackEngine
    private let audioPlaybackService: any AudioPlaybackService
    private let visualMapping: any VisualMappingService
    private let hapticService: any HapticService

    init(dependencies: AppDependencies) {
        recordingService = dependencies.recordingService
        transcriptionService = dependencies.transcriptionService
        analysisService = dependencies.analysisService
        playbackEngine = dependencies.playbackEngine
        audioPlaybackService = dependencies.audioPlaybackService
        visualMapping = dependencies.visualMapping
        hapticService = dependencies.hapticService

        playbackEngine.onSnapshotChange = { [weak self] snapshot in
            guard let self else { return }
            self.playbackState = snapshot.state
            self.visibleTokens = snapshot.visibleTokens
        }
    }

    var canStartRecording: Bool {
        !isRecording && !processingState.isRunning
    }

    var canStopRecording: Bool {
        isRecording
    }

    var canProcessRecording: Bool {
        recordedFileURL != nil && !isRecording && !processingState.isRunning
    }

    var canCancelRecording: Bool {
        recordedFileURL != nil && !isRecording && !processingState.isRunning
    }

    var canReplay: Bool {
        !analyzedTokens.isEmpty && !processingState.isRunning
    }

    var audioToggleIconName: String {
        isAudioMuted ? "speaker.slash.fill" : "speaker.wave.2.fill"
    }

    var statusText: String {
        if isRecording {
            return "Recording in progress..."
        }

        if let recordedFileURL {
            return "Recorded file ready: \(recordedFileURL.lastPathComponent)"
        }

        return "Capture a short audio message, then process it."
    }

    var visibleAttributedText: AttributedString {
        var output = AttributedString()

        for index in visibleTokens.indices {
            let token = visibleTokens[index]
            let style = visualMapping.style(for: token.emotionIntensity)

            var fragment = AttributedString(token.text)
            fragment.foregroundColor = .primary.opacity(style.opacity)
            output.append(fragment)

            if index < visibleTokens.count - 1 {
                output.append(AttributedString(" "))
            }
        }

        return output
    }

    func startRecording() {
        processingState = .idle
        discardCurrentRecording(deleteAudioFile: true)

        Task {
            do {
                try await self.recordingService.startRecording()
                self.recordedFileURL = self.recordingService.outputFileURL
                self.isRecording = true
            } catch {
                self.present(error)
            }
        }
    }

    func stopRecording() {
        do {
            recordedFileURL = try recordingService.stopRecording()
            isRecording = false
        } catch {
            present(error)
        }
    }

    func cancelRecording() {
        guard canCancelRecording else { return }
        discardCurrentRecording(deleteAudioFile: true)
    }

    func processRecording() {
        guard let recordedFileURL else { return }

        errorMessage = nil
        processingState = .transcribing

        Task {
            do {
                let transcription = try await self.transcriptionService.transcribeAudio(at: recordedFileURL)
                self.transcriptionText = transcription.fullText

                self.processingState = .analyzing
                let analyzedTokens = try await self.analysisService.analyze(audioFileAt: recordedFileURL, transcription: transcription)
                await self.hapticService.prepareSpeechHaptics(for: recordedFileURL)

                self.analyzedTokens = analyzedTokens
                self.processingState = .idle
                self.screen = .reading
                self.startPlayback()
            } catch {
                self.processingState = .idle
                self.present(error)
            }
        }
    }

    func replay() {
        guard !analyzedTokens.isEmpty else { return }
        startPlayback()
    }

    func toggleAudioMuted() {
        isAudioMuted.toggle()
        audioPlaybackService.setMuted(isAudioMuted)
    }

    func startNewRecordingFlow() {
        discardCurrentRecording(deleteAudioFile: true)
    }

    func playbackStatusText() -> String {
        switch playbackState {
        case .idle:
            return "Ready to play."
        case .ready:
            return "Playback prepared."
        case .playing:
            return "Revealing words with original speech timing."
        case .finished:
            return "Playback finished."
        }
    }

    private func resetPlayback() {
        hapticService.stop()
        audioPlaybackService.stop()
        playbackEngine.stop()
        visibleTokens = []
        playbackState = .idle
        screen = .recording
    }

    private func discardCurrentRecording(deleteAudioFile: Bool) {
        resetPlayback()

        if deleteAudioFile, let recordedFileURL {
            deleteFileIfNeeded(at: recordedFileURL)
        }

        isRecording = false
        recordedFileURL = nil
        transcriptionText = ""
        analyzedTokens = []
        errorMessage = nil
        screen = .recording
    }

    private func startPlayback() {
        playbackEngine.load(tokens: analyzedTokens)

        if let recordedFileURL {
            do {
                let leadTime = PlaybackSynchronization.leadTime
                let hapticDelay = leadTime - 0.5 // 200ms after audio
                try audioPlaybackService.playAudio(from: recordedFileURL, muted: isAudioMuted, after: leadTime)
                hapticService.startSpeechHaptics(after: hapticDelay)
            } catch {
                hapticService.stop()
                present(error)
                return
            }
        }

        playbackEngine.start(synchronizedTo: audioPlaybackService)
    }

    private func present(_ error: Error) {
        errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        isRecording = false
    }

    private func deleteFileIfNeeded(at url: URL) {
        guard FileManager.default.fileExists(atPath: url.path()) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
