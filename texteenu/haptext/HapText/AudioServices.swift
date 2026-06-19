import AVFoundation
import Combine
import Foundation

struct RecordedAudio {
    let url: URL
    let duration: TimeInterval
    let samples: [Double]
}

enum AudioCaptureError: LocalizedError {
    case permissionDenied
    case recorderUnavailable
    case recordingDidNotStart

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Microphone permission was denied."
        case .recorderUnavailable:
            return "Audio recorder is not available."
        case .recordingDidNotStart:
            return "The recording could not be started."
        }
    }
}

@MainActor
final class AudioCaptureController: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var currentSamples: [Double] = AudioWaveformExtractor.silentSamples()
    @Published var errorMessage: String?

    private var recorder: AVAudioRecorder?
    private var meterTimer: Timer?
    private var meterSamples: [Double] = []
    private var outputURL: URL?

    func start() async {
        guard isRecording == false else { return }

        elapsed = 0
        meterSamples = []
        currentSamples = AudioWaveformExtractor.silentSamples()
        errorMessage = nil
        isRecording = true

        do {
            let hasPermission = await requestPermission()
            guard isRecording else { return }
            guard hasPermission else { throw AudioCaptureError.permissionDenied }

            try configureSessionForRecording()
            guard isRecording else { return }

            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("HapText-\(UUID().uuidString)")
                .appendingPathExtension("m4a")

            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]

            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.isMeteringEnabled = true
            recorder.prepareToRecord()
            guard recorder.record() else { throw AudioCaptureError.recordingDidNotStart }

            self.recorder = recorder
            outputURL = url
            isRecording = true
            startMetering()
        } catch {
            cancel()
            errorMessage = error.localizedDescription
        }
    }

    func send() throws -> RecordedAudio {
        guard let recorder, let outputURL else { throw AudioCaptureError.recorderUnavailable }

        recorder.updateMeters()
        let duration = recorder.currentTime
        recorder.stop()
        stopMetering()

        self.recorder = nil
        self.outputURL = nil
        isRecording = false

        let extractedSamples = (try? AudioWaveformExtractor.samples(from: outputURL)) ?? AudioWaveformExtractor.resampled(meterSamples)
        currentSamples = AudioWaveformExtractor.silentSamples()
        meterSamples = []

        return RecordedAudio(
            url: outputURL,
            duration: max(duration, 0.2),
            samples: extractedSamples
        )
    }

    func cancel() {
        let url = outputURL
        recorder?.stop()
        recorder = nil
        outputURL = nil
        stopMetering()
        isRecording = false
        elapsed = 0
        meterSamples = []
        currentSamples = AudioWaveformExtractor.silentSamples()

        if let url {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func startMetering() {
        stopMetering()

        let timer = Timer(timeInterval: 0.045, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.captureMeterSample()
            }
        }

        RunLoop.main.add(timer, forMode: .common)
        meterTimer = timer
    }

    private func stopMetering() {
        meterTimer?.invalidate()
        meterTimer = nil
    }

    private func captureMeterSample() {
        guard let recorder, isRecording else { return }

        recorder.updateMeters()
        elapsed = recorder.currentTime

        let sample = normalizedPower(recorder.averagePower(forChannel: 0))
        meterSamples.append(sample)
        if meterSamples.count > 120 {
            meterSamples.removeFirst(meterSamples.count - 120)
        }

        currentSamples = AudioWaveformExtractor.resampled(meterSamples, targetSampleCount: 72)
    }

    private func normalizedPower(_ power: Float) -> Double {
        let minimumDb: Float = -55
        guard power > minimumDb else { return 0.08 }

        let normalized = (power - minimumDb) / abs(minimumDb)
        return min(max(Double(pow(normalized, 1.6)), 0.08), 1.0)
    }

    private func requestPermission() async -> Bool {
        #if os(iOS)
        return await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
        #else
        return await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
        #endif
    }

    private func configureSessionForRecording() throws {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setActive(true)
        #endif
    }
}

@MainActor
final class AudioPlaybackController: ObservableObject {
    @Published private(set) var playingMessageID: UUID?

    private var player: AVAudioPlayer?
    private var playbackTimer: Timer?

    func toggle(messageID: UUID, url: URL) {
        if playingMessageID == messageID {
            stop()
        } else {
            play(messageID: messageID, url: url)
        }
    }

    func stop() {
        player?.stop()
        player = nil
        playingMessageID = nil
        stopTimer()
    }

    private func play(messageID: UUID, url: URL) {
        do {
            try configureSessionForPlayback()
            let player = try AVAudioPlayer(contentsOf: url)
            player.prepareToPlay()
            player.play()

            self.player = player
            playingMessageID = messageID
            startTimer()
        } catch {
            stop()
        }
    }

    private func startTimer() {
        stopTimer()

        let timer = Timer(timeInterval: 0.08, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.player?.isPlaying != true {
                    self.stop()
                }
            }
        }

        RunLoop.main.add(timer, forMode: .common)
        playbackTimer = timer
    }

    private func stopTimer() {
        playbackTimer?.invalidate()
        playbackTimer = nil
    }

    private func configureSessionForPlayback() throws {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default)
        try session.setActive(true)
        #endif
    }
}

enum AudioWaveformExtractor {
    static func samples(from url: URL, targetSampleCount: Int = 72) throws -> [Double] {
        let file = try AVAudioFile(forReading: url)
        let maximumFrames = AVAudioFramePosition(44_100 * 180)
        let requestedFrames = min(file.length, maximumFrames)
        let frameCount = AVAudioFrameCount(max(requestedFrames, 1))

        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frameCount) else {
            return silentSamples(count: targetSampleCount)
        }

        try file.read(into: buffer, frameCount: frameCount)

        guard let channelData = buffer.floatChannelData else {
            return silentSamples(count: targetSampleCount)
        }

        let channelCount = max(Int(buffer.format.channelCount), 1)
        let totalFrames = Int(buffer.frameLength)
        guard totalFrames > 0 else { return silentSamples(count: targetSampleCount) }

        let bucketSize = max(totalFrames / targetSampleCount, 1)
        var output: [Double] = []

        for bucketIndex in 0..<targetSampleCount {
            let startFrame = bucketIndex * bucketSize
            guard startFrame < totalFrames else { break }

            let endFrame = min(startFrame + bucketSize, totalFrames)
            var sum: Double = 0
            var count = 0

            for frame in startFrame..<endFrame {
                var monoSample: Double = 0
                for channel in 0..<channelCount {
                    monoSample += abs(Double(channelData[channel][frame]))
                }

                monoSample /= Double(channelCount)
                sum += monoSample * monoSample
                count += 1
            }

            let rms = sqrt(sum / Double(max(count, 1)))
            output.append(min(max(rms * 7.0, 0.08), 1.0))
        }

        return resampled(output, targetSampleCount: targetSampleCount)
    }

    static func resampled(_ samples: [Double], targetSampleCount: Int = 72) -> [Double] {
        guard samples.isEmpty == false else { return silentSamples(count: targetSampleCount) }
        guard samples.count != targetSampleCount else { return samples.map(clamped) }

        return (0..<targetSampleCount).map { index in
            let sourceIndex = Double(index) * Double(samples.count - 1) / Double(max(targetSampleCount - 1, 1))
            let lowerIndex = Int(floor(sourceIndex))
            let upperIndex = min(lowerIndex + 1, samples.count - 1)
            let fraction = sourceIndex - Double(lowerIndex)
            let value = samples[lowerIndex] * (1 - fraction) + samples[upperIndex] * fraction
            return clamped(value)
        }
    }

    static func silentSamples(count: Int = 72) -> [Double] {
        Array(repeating: 0.08, count: count)
    }

    private static func clamped(_ value: Double) -> Double {
        min(max(value, 0.08), 1.0)
    }
}
