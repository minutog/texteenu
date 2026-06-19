import AVFoundation
import Combine
#if canImport(CoreHaptics)
import CoreHaptics
#endif
import Foundation

struct HapTextWordToken: Identifiable, Equatable, Sendable {
    let id: UUID
    let text: String
    let startTime: TimeInterval
    let endTime: TimeInterval

    init(id: UUID = UUID(), text: String, startTime: TimeInterval, endTime: TimeInterval) {
        self.id = id
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
    }
}

struct HapTextTranscriptionResult: Equatable, Sendable {
    let fullText: String
    let words: [HapTextWordToken]
}

enum HapTextMessagePlaybackStatus: Equatable {
    case ready
    case preparing
    case playing
    case finished
}

struct HapTextMessagePresentation: Equatable {
    var status: HapTextMessagePlaybackStatus
    var duration: TimeInterval
    var elapsed: TimeInterval
    var fullText: String
    var tokens: [HapTextWordToken]
    var visibleTokens: [HapTextWordToken]
    var currentTokenID: UUID?

    static func initial(duration: TimeInterval) -> HapTextMessagePresentation {
        HapTextMessagePresentation(
            status: .ready,
            duration: duration,
            elapsed: 0,
            fullText: "",
            tokens: [],
            visibleTokens: [],
            currentTokenID: nil
        )
    }
}

@MainActor
final class HapTextMessagePlaybackController: ObservableObject {
    @Published private var presentations: [UUID: HapTextMessagePresentation] = [:]

    private let transcriptionService = HapTextOpenAITranscriptionService(
        apiClient: HapTextOpenAIAPIClient(configurationProvider: HapTextBundleOpenAIConfigurationProvider())
    )
    private let audioPlaybackService = HapTextAVAudioPlaybackService()
    private let hapticService = HapTextContinuousEnvelopeHapticService()

    private var preparationTasks: [UUID: Task<HapTextTranscriptionResult, Never>] = [:]
    private var activeMessageID: UUID?
    private var playbackTimer: Timer?

    func presentation(for messageID: UUID, duration: TimeInterval) -> HapTextMessagePresentation {
        presentations[messageID] ?? .initial(duration: duration)
    }

    func prepareIfNeeded(messageID: UUID, clip: AudioClip) {
        guard presentations[messageID] == nil else { return }
        presentations[messageID] = Self.presentation(duration: clip.duration, transcription: clip.transcription)
    }

    func transcribeForDelivery(fileURL: URL, duration: TimeInterval) async -> HapTextTranscriptionResult? {
        do {
            let result = try await transcriptionService.transcribeAudio(at: fileURL)
            let normalized = Self.normalizedTranscription(result, duration: duration)
            guard normalized.fullText.isEmpty == false || normalized.words.isEmpty == false else { return nil }
            return normalized
        } catch {
            return nil
        }
    }

    func togglePlayback(messageID: UUID, clip: AudioClip) {
        if activeMessageID == messageID,
           presentations[messageID]?.status == .playing {
            stopActivePlayback(resetActiveMessage: true)
            return
        }

        Task {
            await play(messageID: messageID, clip: clip)
        }
    }

    func stop() {
        stopActivePlayback(resetActiveMessage: true)
    }

    private func play(messageID: UUID, clip: AudioClip) async {
        if let activeMessageID, activeMessageID != messageID {
            stopActivePlayback(resetActiveMessage: true)
        }

        var presentation = presentations[messageID] ?? .initial(duration: clip.duration)
        presentation.duration = clip.duration
        presentation.elapsed = 0
        presentation.visibleTokens = []
        presentation.currentTokenID = nil

        if presentation.tokens.isEmpty && presentation.fullText.isEmpty {
            presentation = Self.presentation(duration: clip.duration, transcription: clip.transcription)
        }

        guard presentation.tokens.isEmpty == false else {
            presentation.status = .ready
            presentations[messageID] = presentation
            return
        }

        await hapticService.prepareSpeechHaptics(for: clip.fileURL)
        startPreparedPlayback(messageID: messageID, clip: clip, presentation: presentation)
    }

    private func preparedTranscription(messageID: UUID, clip: AudioClip) async -> HapTextTranscriptionResult {
        let task: Task<HapTextTranscriptionResult, Never>

        if let existingTask = preparationTasks[messageID] {
            task = existingTask
        } else {
            let newTask = makePreparationTask(for: clip)
            preparationTasks[messageID] = newTask
            task = newTask
        }

        let result = await task.value
        preparationTasks[messageID] = nil
        return result
    }

    private func makePreparationTask(for clip: AudioClip) -> Task<HapTextTranscriptionResult, Never> {
        let transcriptionService = transcriptionService

        return Task {
            do {
                return try await transcriptionService.transcribeAudio(at: clip.fileURL)
            } catch {
                return HapTextTranscriptionResult(fullText: "", words: [])
            }
        }
    }

    private static func presentation(
        duration: TimeInterval,
        transcription: HapTextTranscriptionResult?
    ) -> HapTextMessagePresentation {
        guard let transcription else {
            return .initial(duration: duration)
        }

        let normalized = normalizedTranscription(transcription, duration: duration)
        return HapTextMessagePresentation(
            status: .ready,
            duration: duration,
            elapsed: 0,
            fullText: normalized.fullText,
            tokens: normalized.words,
            visibleTokens: [],
            currentTokenID: nil
        )
    }

    private static func normalizedTranscription(
        _ transcription: HapTextTranscriptionResult,
        duration: TimeInterval
    ) -> HapTextTranscriptionResult {
        let text = transcription.fullText.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = transcription.words.isEmpty
            ? estimatedTokens(from: text, duration: duration)
            : transcription.words

        return HapTextTranscriptionResult(fullText: text, words: words)
    }

    private func startPreparedPlayback(
        messageID: UUID,
        clip: AudioClip,
        presentation: HapTextMessagePresentation
    ) {
        stopPlaybackServices()

        do {
            let leadTime: TimeInterval = 0.08
            try audioPlaybackService.playAudio(from: clip.fileURL, muted: false, after: leadTime)
            hapticService.startSpeechHaptics(after: leadTime)

            activeMessageID = messageID
            var playingPresentation = presentation
            playingPresentation.status = .playing
            playingPresentation.elapsed = 0
            playingPresentation.visibleTokens = []
            playingPresentation.currentTokenID = nil
            presentations[messageID] = playingPresentation
            startTimer()
        } catch {
            var resetPresentation = presentation
            resetPresentation.status = .ready
            resetPresentation.elapsed = 0
            resetPresentation.visibleTokens = []
            resetPresentation.currentTokenID = nil
            presentations[messageID] = resetPresentation
        }
    }

    private func attachTranscriptionWhenReady(messageID: UUID, clip: AudioClip) {
        Task { [weak self] in
            guard let self else { return }

            let result = await self.preparedTranscription(messageID: messageID, clip: clip)
            self.applyTranscription(result, to: messageID, duration: clip.duration)
        }
    }

    private func applyTranscription(
        _ result: HapTextTranscriptionResult,
        to messageID: UUID,
        duration: TimeInterval
    ) {
        guard result.fullText.isEmpty == false || result.words.isEmpty == false else { return }

        var presentation = presentations[messageID] ?? .initial(duration: duration)
        let tokens = result.words.isEmpty
            ? Self.estimatedTokens(from: result.fullText, duration: duration)
            : result.words

        presentation.fullText = result.fullText
        presentation.tokens = tokens

        if presentation.status == .finished {
            presentation.visibleTokens = tokens
        }

        presentations[messageID] = presentation
    }

    private func startTimer() {
        playbackTimer?.invalidate()

        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.syncPlayback()
            }
        }

        RunLoop.main.add(timer, forMode: .common)
        playbackTimer = timer
    }

    private func syncPlayback() {
        guard let activeMessageID,
              var presentation = presentations[activeMessageID] else {
            stopPlaybackServices()
            return
        }

        let playbackTime = max(0, audioPlaybackService.currentPlaybackTime)
        presentation.elapsed = playbackTime

        let visibleTokens = presentation.tokens.filter { $0.startTime <= playbackTime }
        presentation.visibleTokens = visibleTokens
        presentation.currentTokenID = visibleTokens.last?.id

        let didFinish = audioPlaybackService.hasStartedPlayback && audioPlaybackService.isPlaybackRunning == false
        if didFinish || playbackTime >= max(presentation.duration - 0.02, 0) {
            finishPlayback(messageID: activeMessageID, presentation: presentation)
        } else {
            presentations[activeMessageID] = presentation
        }
    }

    private func finishPlayback(messageID: UUID, presentation: HapTextMessagePresentation) {
        var finishedPresentation = presentation
        finishedPresentation.status = .finished
        finishedPresentation.elapsed = presentation.duration
        finishedPresentation.visibleTokens = presentation.tokens
        finishedPresentation.currentTokenID = nil
        presentations[messageID] = finishedPresentation

        stopPlaybackServices()
        activeMessageID = nil
    }

    private func stopActivePlayback(resetActiveMessage: Bool) {
        let stoppedMessageID = activeMessageID
        stopPlaybackServices()
        activeMessageID = nil

        guard resetActiveMessage,
              let stoppedMessageID,
              var presentation = presentations[stoppedMessageID] else { return }

        presentation.status = presentation.tokens.isEmpty ? .ready : .ready
        presentation.elapsed = 0
        presentation.visibleTokens = []
        presentation.currentTokenID = nil
        presentations[stoppedMessageID] = presentation
    }

    private func stopPlaybackServices() {
        playbackTimer?.invalidate()
        playbackTimer = nil
        audioPlaybackService.stop()
        hapticService.stop()
    }

    private static func estimatedTokens(from text: String, duration: TimeInterval) -> [HapTextWordToken] {
        let words = text
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { $0.isEmpty == false }

        guard words.isEmpty == false else { return [] }

        let clampedDuration = max(duration, Double(words.count) * 0.18)
        let step = clampedDuration / Double(words.count)

        return words.enumerated().map { index, word in
            let start = Double(index) * step
            return HapTextWordToken(
                text: word,
                startTime: start,
                endTime: min(start + step, clampedDuration)
            )
        }
    }

}

private struct HapTextOpenAIConfiguration {
    static let defaultBaseURL = URL(string: "https://api.openai.com/")!
    static let placeholderAPIKey = "YOUR_OPENAI_API_KEY_HERE"
    static let defaultTranscriptionModel = "whisper-1"

    let apiKey: String
    let baseURL: URL
    let transcriptionModel: String
}

private protocol HapTextOpenAIConfigurationProviding: Sendable {
    func loadConfiguration() throws -> HapTextOpenAIConfiguration
}

private struct HapTextBundleOpenAIConfigurationProvider: HapTextOpenAIConfigurationProviding {
    func loadConfiguration() throws -> HapTextOpenAIConfiguration {
        let environmentKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"]?.trimmedNonEmpty
        let infoDictionaryKey = (Bundle.main.object(forInfoDictionaryKey: "OPENAI_API_KEY") as? String)?.trimmedNonEmpty
        let baseURLString = (Bundle.main.object(forInfoDictionaryKey: "OPENAI_BASE_URL") as? String)?.trimmedNonEmpty
        let transcriptionModel = (Bundle.main.object(forInfoDictionaryKey: "OPENAI_TRANSCRIPTION_MODEL") as? String)?.trimmedNonEmpty
            ?? HapTextOpenAIConfiguration.defaultTranscriptionModel

        let candidateKey = infoDictionaryKey ?? environmentKey
        guard let apiKey = candidateKey,
              apiKey != HapTextOpenAIConfiguration.placeholderAPIKey,
              apiKey.contains("$(") == false else {
            throw HapTextOpenAIConfigurationError.missingAPIKey
        }

        return HapTextOpenAIConfiguration(
            apiKey: apiKey,
            baseURL: baseURLString.flatMap(URL.init(string:)) ?? HapTextOpenAIConfiguration.defaultBaseURL,
            transcriptionModel: transcriptionModel
        )
    }
}

private enum HapTextOpenAIConfigurationError: LocalizedError {
    case missingAPIKey
}

private enum HapTextOpenAIAPIError: LocalizedError {
    case invalidResponse
    case invalidJSONObject
    case requestFailed(statusCode: Int, message: String)
    case unsupportedAudioFormat(String)
}

private final class HapTextOpenAIAPIClient: @unchecked Sendable {
    private let configurationProvider: any HapTextOpenAIConfigurationProviding
    private let session: URLSession

    init(configurationProvider: any HapTextOpenAIConfigurationProviding, session: URLSession = .shared) {
        self.configurationProvider = configurationProvider
        self.session = session
    }

    func loadConfiguration() throws -> HapTextOpenAIConfiguration {
        try configurationProvider.loadConfiguration()
    }

    func postMultipart(path: String, body: HapTextMultipartFormDataBuilder) async throws -> Data {
        var request = try makeRequest(path: path, contentType: "multipart/form-data; boundary=\(body.boundary)")
        request.httpBody = body.build()
        return try await execute(request)
    }

    private func makeRequest(path: String, contentType: String) throws -> URLRequest {
        let configuration = try configurationProvider.loadConfiguration()
        let url = configuration.baseURL.appendingPathComponent(path)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120
        return request
    }

    private func execute(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw HapTextOpenAIAPIError.invalidResponse
        }

        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            let errorEnvelope = try? JSONDecoder().decode(HapTextOpenAIErrorEnvelope.self, from: data)
            let message = errorEnvelope?.error.message ?? String(data: data, encoding: .utf8) ?? "Unknown error"
            throw HapTextOpenAIAPIError.requestFailed(statusCode: httpResponse.statusCode, message: message)
        }

        return data
    }
}

private struct HapTextOpenAIErrorEnvelope: Decodable {
    let error: HapTextOpenAIErrorPayload
}

private struct HapTextOpenAIErrorPayload: Decodable {
    let message: String
}

private struct HapTextMultipartFormDataBuilder: Sendable {
    let boundary = "Boundary-\(UUID().uuidString)"
    private var body = Data()

    mutating func addTextField(named name: String, value: String) {
        body.appendString("--\(boundary)\r\n")
        body.appendString("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        body.appendString("\(value)\r\n")
    }

    mutating func addFileField(named name: String, filename: String, mimeType: String, data: Data) {
        body.appendString("--\(boundary)\r\n")
        body.appendString("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n")
        body.appendString("Content-Type: \(mimeType)\r\n\r\n")
        body.append(data)
        body.appendString("\r\n")
    }

    func build() -> Data {
        var output = body
        output.appendString("--\(boundary)--\r\n")
        return output
    }
}

private struct HapTextOpenAIAudioFormat {
    let mimeType: String

    init(fileURL: URL) throws {
        switch fileURL.pathExtension.lowercased() {
        case "m4a":
            mimeType = "audio/m4a"
        case "mp3", "mpeg", "mpga":
            mimeType = "audio/mpeg"
        case "wav":
            mimeType = "audio/wav"
        case "mp4":
            mimeType = "audio/mp4"
        case "webm":
            mimeType = "audio/webm"
        default:
            throw HapTextOpenAIAPIError.unsupportedAudioFormat(fileURL.pathExtension)
        }
    }
}

private struct HapTextOpenAITranscriptionService: Sendable {
    private static let defaultTranscriptionPrompt = """
    Transcribe the audio strictly in English. Always output in English, regardless of the input language.
    Preserve the exact spoken words verbatim. Do not paraphrase, summarize, translate meaning, or rewrite in any way.
    Include all disfluencies and fillers such as "um", "uh", repetitions, and self-corrections exactly as spoken.
    Add punctuation only when clearly supported by the audio.
    Return only the transcript.
    """

    let apiClient: HapTextOpenAIAPIClient

    func transcribeAudio(at fileURL: URL) async throws -> HapTextTranscriptionResult {
        let configuration = try apiClient.loadConfiguration()
        let fileData = try Data(contentsOf: fileURL)
        let audioFormat = try HapTextOpenAIAudioFormat(fileURL: fileURL)

        var multipartBody = HapTextMultipartFormDataBuilder()
        multipartBody.addTextField(named: "model", value: configuration.transcriptionModel)
        multipartBody.addTextField(named: "response_format", value: "verbose_json")
        multipartBody.addTextField(named: "timestamp_granularities[]", value: "word")
        multipartBody.addTextField(named: "prompt", value: Self.defaultTranscriptionPrompt)
        multipartBody.addFileField(
            named: "file",
            filename: fileURL.lastPathComponent,
            mimeType: audioFormat.mimeType,
            data: fileData
        )

        let responseData = try await apiClient.postMultipart(path: "v1/audio/transcriptions", body: multipartBody)
        let response = try JSONDecoder().decode(HapTextVerboseTranscriptionResponse.self, from: responseData)
        let words = response.words ?? []
        let fullText = response.text.trimmingCharacters(in: .whitespacesAndNewlines)

        return HapTextTranscriptionResult(
            fullText: fullText,
            words: Self.makeWordTokens(from: words)
        )
    }

    private static func makeWordTokens(from words: [HapTextVerboseTranscriptionWord]) -> [HapTextWordToken] {
        words.compactMap { word -> HapTextWordToken? in
            let text = word.word.trimmingCharacters(in: .whitespacesAndNewlines)
            guard text.isEmpty == false else { return nil }

            return HapTextWordToken(
                text: text,
                startTime: word.start,
                endTime: word.end
            )
        }
    }
}

private struct HapTextVerboseTranscriptionResponse: Decodable {
    let text: String
    let words: [HapTextVerboseTranscriptionWord]?
}

private struct HapTextVerboseTranscriptionWord: Decodable {
    let word: String
    let start: Double
    let end: Double
}

@MainActor
private protocol HapTextPlaybackTimeSource: AnyObject {
    var currentPlaybackTime: TimeInterval { get }
    var hasStartedPlayback: Bool { get }
    var isPlaybackRunning: Bool { get }
}

@MainActor
private final class HapTextAVAudioPlaybackService: NSObject, HapTextPlaybackTimeSource {
    #if os(iOS)
    private let audioSession = AVAudioSession.sharedInstance()
    #endif

    private var player: AVAudioPlayer?
    private var scheduledStartDeviceTime: TimeInterval?

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

        #if os(iOS)
        try audioSession.setCategory(.playback, mode: .default, options: [.duckOthers])
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        #endif

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
            throw HapTextAudioPlaybackError.playerUnavailable
        }

        self.player = player
    }

    func stop() {
        player?.stop()
        player = nil
        scheduledStartDeviceTime = nil

        #if os(iOS)
        try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }
}

private enum HapTextAudioPlaybackError: LocalizedError {
    case playerUnavailable
}

@MainActor
private final class HapTextContinuousEnvelopeHapticService {
    private enum Constants {
        static let durationPadding: TimeInterval = 0.15
        static let sharpness: Float = 0.32
    }

    private struct EnvelopePoint: Sendable {
        let time: TimeInterval
        let intensity: Float
    }

    private struct EnvelopeProfile: Sendable {
        let duration: TimeInterval
        let points: [EnvelopePoint]
    }

    #if canImport(CoreHaptics)
    private let supportsHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics
    private var engine: CHHapticEngine?
    private var player: (any CHHapticAdvancedPatternPlayer)?
    private var preparedAudioFileURL: URL?
    private var preparedPattern: CHHapticPattern?
    #else
    private let supportsHaptics = false
    #endif

    func prepareSpeechHaptics(for audioFileURL: URL) async {
        #if canImport(CoreHaptics)
        guard supportsHaptics else { return }

        if preparedAudioFileURL == audioFileURL, preparedPattern != nil {
            return
        }

        stop()

        do {
            let profile = try await Task.detached(priority: .userInitiated) {
                try Self.buildEnvelopeProfile(from: audioFileURL)
            }.value

            preparedAudioFileURL = audioFileURL
            try ensureEngineStarted()
            preparedPattern = try makePattern(from: profile)
        } catch {
            preparedAudioFileURL = nil
            preparedPattern = nil
        }
        #endif
    }

    func startSpeechHaptics(after delay: TimeInterval) {
        #if canImport(CoreHaptics)
        guard supportsHaptics, let preparedPattern else { return }

        stopCurrentPlayer()

        do {
            try ensureEngineStarted()

            let player = try engine?.makeAdvancedPlayer(with: preparedPattern)
            guard let player else { return }

            let scheduledStartTime = (engine?.currentTime ?? 0) + max(delay, 0)
            try player.start(atTime: scheduledStartTime)
            self.player = player
        } catch {
            stop()
        }
        #endif
    }

    func stop() {
        #if canImport(CoreHaptics)
        stopCurrentPlayer()
        #endif
    }

    #if canImport(CoreHaptics)
    private func stopCurrentPlayer() {
        try? player?.stop(atTime: CHHapticTimeImmediate)
        player = nil
    }

    private func ensureEngineStarted() throws {
        if engine == nil {
            engine = try makeEngine()
        }

        try engine?.start()
    }

    private func makeEngine() throws -> CHHapticEngine {
        let engine = try CHHapticEngine()
        engine.playsHapticsOnly = true
        engine.isAutoShutdownEnabled = false
        engine.resetHandler = { [weak self] in
            Task { @MainActor in
                do {
                    try self?.ensureEngineStarted()
                } catch {
                    self?.engine = nil
                }
            }
        }
        return engine
    }

    private func makePattern(from profile: EnvelopeProfile) throws -> CHHapticPattern {
        let event = CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 1),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: Constants.sharpness)
            ],
            relativeTime: 0,
            duration: max(profile.duration + Constants.durationPadding, 0.25)
        )

        let curve = CHHapticParameterCurve(
            parameterID: .hapticIntensityControl,
            controlPoints: makeControlPoints(from: profile),
            relativeTime: 0
        )

        return try CHHapticPattern(events: [event], parameterCurves: [curve])
    }

    private func makeControlPoints(from profile: EnvelopeProfile) -> [CHHapticParameterCurve.ControlPoint] {
        let epsilon: Float = 0.015
        var controlPoints: [CHHapticParameterCurve.ControlPoint] = []
        var previousIntensity: Float?

        for point in profile.points {
            guard previousIntensity == nil || abs(point.intensity - previousIntensity!) >= epsilon else {
                continue
            }

            controlPoints.append(
                CHHapticParameterCurve.ControlPoint(relativeTime: point.time, value: point.intensity)
            )
            previousIntensity = point.intensity
        }

        if controlPoints.isEmpty {
            return [
                CHHapticParameterCurve.ControlPoint(relativeTime: 0, value: 0),
                CHHapticParameterCurve.ControlPoint(relativeTime: max(profile.duration, 0.01), value: 0)
            ]
        }

        if controlPoints.last?.relativeTime ?? 0 < profile.duration {
            controlPoints.append(CHHapticParameterCurve.ControlPoint(relativeTime: profile.duration, value: 0))
        }

        return controlPoints
    }

    nonisolated private static func buildEnvelopeProfile(from audioFileURL: URL) throws -> EnvelopeProfile {
        let frameDuration = 0.02
        let smoothingAlpha: Float = 0.3
        let silenceThreshold: Float = 0.01
        let dynamicRangeBoost: Float = 1.2

        let audioFile = try AVAudioFile(forReading: audioFileURL)
        let audioFormat = audioFile.processingFormat
        let frameCount = AVAudioFrameCount(audioFile.length)

        guard let buffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: frameCount) else {
            return EnvelopeProfile(duration: 0, points: [])
        }

        try audioFile.read(into: buffer)

        let monoSamples = monoSamples(from: buffer)
        guard monoSamples.isEmpty == false else {
            return EnvelopeProfile(duration: 0, points: [])
        }

        let sampleRate = audioFormat.sampleRate
        let samplesPerFrame = max(Int(sampleRate * frameDuration), 1)
        var rmsValues: [Float] = []
        var sampleIndex = 0

        while sampleIndex < monoSamples.count {
            let windowEnd = min(sampleIndex + samplesPerFrame, monoSamples.count)
            let window = monoSamples[sampleIndex..<windowEnd]
            let squareSum = window.reduce(Float.zero) { $0 + ($1 * $1) }
            rmsValues.append(sqrt(squareSum / Float(window.count)))
            sampleIndex = windowEnd
        }

        guard rmsValues.isEmpty == false else {
            return EnvelopeProfile(duration: 0, points: [])
        }

        let noiseFloor = percentile(of: rmsValues, percentile: 0.2)
        let peak = max(percentile(of: rmsValues, percentile: 0.98), noiseFloor + 0.0001)
        let speechGate = max(noiseFloor * 2.2, peak * 0.05)
        let normalizationRange = max(peak - noiseFloor, 0.0001)

        var smoothedIntensity: Float = 0
        var points: [EnvelopePoint] = []

        for (index, rms) in rmsValues.enumerated() {
            let gatedIntensity: Float

            if rms < speechGate {
                gatedIntensity = 0
            } else {
                let denoised = max(0, rms - noiseFloor)
                gatedIntensity = clampToUnitInterval(denoised / normalizationRange)
            }

            let smoothed = smoothedIntensity + (smoothingAlpha * (gatedIntensity - smoothedIntensity))
            let shapedIntensity = Float(pow(Double(max(smoothed, 0)), 0.6))
            let finalIntensity = shapedIntensity < silenceThreshold ? 0 : shapedIntensity
            let clampedIntensity = clampToUnitInterval(finalIntensity)
            let boostedIntensity = clampToUnitInterval(clampedIntensity * dynamicRangeBoost)

            smoothedIntensity = finalIntensity == 0 ? 0 : smoothed
            points.append(EnvelopePoint(time: TimeInterval(index) * frameDuration, intensity: boostedIntensity))
        }

        let audioDuration = Double(monoSamples.count) / sampleRate
        return EnvelopeProfile(duration: audioDuration, points: points)
    }

    nonisolated private static func monoSamples(from buffer: AVAudioPCMBuffer) -> [Float] {
        guard let channelData = buffer.floatChannelData else { return [] }

        let channelCount = Int(buffer.format.channelCount)
        let frameLength = Int(buffer.frameLength)

        guard frameLength > 0 else { return [] }

        if channelCount == 1 {
            return Array(UnsafeBufferPointer(start: channelData[0], count: frameLength)).map { abs($0) }
        }

        var monoSamples = Array(repeating: Float.zero, count: frameLength)
        let scale = 1 / Float(channelCount)

        for channelIndex in 0..<channelCount {
            let samples = UnsafeBufferPointer(start: channelData[channelIndex], count: frameLength)
            for frameIndex in 0..<frameLength {
                monoSamples[frameIndex] += abs(samples[frameIndex]) * scale
            }
        }

        return monoSamples
    }

    nonisolated private static func percentile(of values: [Float], percentile: Float) -> Float {
        guard values.isEmpty == false else { return 0 }

        let sortedValues = values.sorted()
        let index = Int(Float(sortedValues.count - 1) * clampToUnitInterval(percentile))
        return sortedValues[index]
    }

    nonisolated private static func clampToUnitInterval(_ value: Float) -> Float {
        min(max(value, 0), 1)
    }
    #endif
}

private extension Data {
    mutating func appendString(_ string: String) {
        guard let data = string.data(using: .utf8) else { return }
        append(data)
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
