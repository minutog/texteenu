import Foundation

struct AppDependencies {
    let recordingService: any AudioRecordingService
    let transcriptionService: any AudioTranscriptionService
    let analysisService: any AudioAnalysisService
    let playbackEngine: any PlaybackEngine
    let audioPlaybackService: any AudioPlaybackService
    let visualMapping: any VisualMappingService
    let hapticMapping: any HapticMappingService
    let hapticService: any HapticService

    static func live() -> AppDependencies {
        let configurationProvider = BundleOpenAIConfigurationProvider()
        let apiClient = OpenAIAPIClient(configurationProvider: configurationProvider)
        let analysisAudioPreparer = OpenAIAudioInputPreparer()

        return AppDependencies(
            recordingService: AVAudioCaptureService(),
            transcriptionService: OpenAITranscriptionService(apiClient: apiClient),
            analysisService: OpenAIAudioAnalysisService(
                apiClient: apiClient,
                audioPreparer: analysisAudioPreparer
            ),
            playbackEngine: TimedWordPlaybackEngine(),
            audioPlaybackService: AVAudioPlaybackService(),
            visualMapping: EmotionOpacityVisualMapper(),
            hapticMapping: ImportancePulseHapticMapper(minimumIntensity: 0.45),
            hapticService: ImpactHapticService()
        )
    }
}
