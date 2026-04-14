import AVFoundation
import CoreHaptics
import Foundation

@MainActor
protocol HapticService: AnyObject {
    func prepareSpeechHaptics(for audioFileURL: URL) async
    func startSpeechHaptics(after delay: TimeInterval)
    func stop()
}

@MainActor
final class ContinuousEnvelopeHapticService: HapticService {
    private enum Constants {
        static let frameDuration: TimeInterval = 0.02
        static let smoothingAlpha: Float = 0.55
        static let silenceThreshold: Float = 0.045
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

    private let supportsHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics

    private var engine: CHHapticEngine?
    private var player: (any CHHapticAdvancedPatternPlayer)?
    private var preparedAudioFileURL: URL?
    private var preparedPattern: CHHapticPattern?

    func prepareSpeechHaptics(for audioFileURL: URL) async {
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
    }

    func startSpeechHaptics(after delay: TimeInterval) {
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
    }

    func stop() {
        stopCurrentPlayer()
    }

    private func stopCurrentPlayer() {
        do {
            try player?.stop(atTime: CHHapticTimeImmediate)
        } catch {
            // Ignore teardown failures during playback resets.
        }

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

        let controlPoints = makeControlPoints(from: profile)
        let curve = CHHapticParameterCurve(
            parameterID: .hapticIntensityControl,
            controlPoints: controlPoints,
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
                CHHapticParameterCurve.ControlPoint(
                    relativeTime: point.time,
                    value: point.intensity
                )
            )
            previousIntensity = point.intensity
        }

        if controlPoints.isEmpty {
            controlPoints = [
                CHHapticParameterCurve.ControlPoint(relativeTime: 0, value: 0),
                CHHapticParameterCurve.ControlPoint(relativeTime: max(profile.duration, 0.01), value: 0)
            ]
        } else if controlPoints.last?.relativeTime ?? 0 < profile.duration {
            controlPoints.append(
                CHHapticParameterCurve.ControlPoint(relativeTime: profile.duration, value: 0)
            )
        }

        return controlPoints
    }

    nonisolated private static func buildEnvelopeProfile(from audioFileURL: URL) throws -> EnvelopeProfile {
        let frameDuration = 0.02
        let smoothingAlpha: Float = 0.55
        let silenceThreshold: Float = 0.045

        let audioFile = try AVAudioFile(forReading: audioFileURL)
        let audioFormat = audioFile.processingFormat
        let frameCount = AVAudioFrameCount(audioFile.length)

        guard let buffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: frameCount) else {
            return EnvelopeProfile(duration: 0, points: [])
        }

        try audioFile.read(into: buffer)

        let monoSamples = monoSamples(from: buffer)
        guard !monoSamples.isEmpty else {
            return EnvelopeProfile(duration: 0, points: [])
        }

        let sampleRate = audioFormat.sampleRate
        let samplesPerFrame = max(Int(sampleRate * frameDuration), 1)

        var rmsValues: [Float] = []
        var sampleIndex = 0

        while sampleIndex < monoSamples.count {
            let windowEnd = min(sampleIndex + samplesPerFrame, monoSamples.count)
            let window = monoSamples[sampleIndex..<windowEnd]

            var squareSum: Float = 0
            for sample in window {
                squareSum += sample * sample
            }

            let rms = sqrt(squareSum / Float(window.count))
            rmsValues.append(rms)
            sampleIndex = windowEnd
        }

        guard !rmsValues.isEmpty else {
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
            let shapedIntensity = Float(pow(Double(max(smoothed, 0)), 0.85))
            let finalIntensity = shapedIntensity < silenceThreshold ? 0 : shapedIntensity

            smoothedIntensity = finalIntensity == 0 ? 0 : smoothed
            points.append(
                EnvelopePoint(
                    time: TimeInterval(index) * frameDuration,
                    intensity: clampToUnitInterval(finalIntensity)
                )
            )
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
        guard !values.isEmpty else { return 0 }

        let sortedValues = values.sorted()
        let index = Int(Float(sortedValues.count - 1) * clampToUnitInterval(percentile))
        return sortedValues[index]
    }

    nonisolated private static func clampToUnitInterval(_ value: Float) -> Float {
        min(max(value, 0), 1)
    }
}
