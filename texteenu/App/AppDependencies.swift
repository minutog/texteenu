import Foundation

struct AppDependencies {
    let recordingService: any AudioRecordingService
    let transcriptionService: any AudioTranscriptionService
    let savedRecordingStore: any SavedRecordingStore
    let playbackEngine: any PlaybackEngine
    let audioPlaybackService: any AudioPlaybackService
    let timelinePlaybackService: any TimelinePlaybackService
    let visualMapping: any VisualMappingService
    let hapticService: any HapticService

    static func live() -> AppDependencies {
        let configurationProvider = BundleOpenAIConfigurationProvider()
        let apiClient = OpenAIAPIClient(configurationProvider: configurationProvider)

        return AppDependencies(
            recordingService: AVAudioCaptureService(),
            transcriptionService: OpenAITranscriptionService(apiClient: apiClient),
            savedRecordingStore: LocalSavedRecordingStore(),
            playbackEngine: TimedWordPlaybackEngine(),
            audioPlaybackService: AVAudioPlaybackService(),
            timelinePlaybackService: ClockPlaybackService(),
            visualMapping: PlaybackTrailOpacityVisualMapper(),
            hapticService: ContinuousEnvelopeHapticService()
        )
    }
}
