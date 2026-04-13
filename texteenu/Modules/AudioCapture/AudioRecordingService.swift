import AVFoundation
import Foundation

@MainActor
protocol AudioRecordingService: AnyObject {
    var outputFileURL: URL? { get }
    var isRecording: Bool { get }

    func startRecording() async throws
    func stopRecording() throws -> URL
}

enum AudioRecordingError: LocalizedError {
    case microphonePermissionDenied
    case recorderUnavailable
    case missingOutputFile

    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            return "Microphone permission is required before recording."
        case .recorderUnavailable:
            return "The audio recorder could not be started."
        case .missingOutputFile:
            return "No recorded audio file was available."
        }
    }
}

@MainActor
final class AVAudioCaptureService: NSObject, AudioRecordingService {
    private let audioSession = AVAudioSession.sharedInstance()
    private var recorder: AVAudioRecorder?

    private(set) var outputFileURL: URL?

    var isRecording: Bool {
        recorder?.isRecording ?? false
    }

    func startRecording() async throws {
        let permissionGranted = await requestMicrophonePermission()
        guard permissionGranted else {
            throw AudioRecordingError.microphonePermissionDenied
        }

        let outputURL = makeOutputURL()
        outputFileURL = outputURL

        try audioSession.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        recorder = try AVAudioRecorder(url: outputURL, settings: settings)
        recorder?.prepareToRecord()

        guard recorder?.record() == true else {
            throw AudioRecordingError.recorderUnavailable
        }
    }

    func stopRecording() throws -> URL {
        guard let recorder else {
            throw AudioRecordingError.recorderUnavailable
        }

        recorder.stop()
        self.recorder = nil
        try audioSession.setActive(false, options: .notifyOthersOnDeactivation)

        guard let outputFileURL else {
            throw AudioRecordingError.missingOutputFile
        }

        return outputFileURL
    }

    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    private func makeOutputURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("texteenu-\(UUID().uuidString)")
            .appendingPathExtension("m4a")
    }
}
