import AVFoundation
import Foundation

struct PreparedAudioInput {
    let data: Data
    let format: String
}

protocol AnalysisAudioPreparing {
    func prepareAudioForAnalysis(from fileURL: URL) throws -> PreparedAudioInput
}

enum AudioPreparationError: LocalizedError {
    case invalidAudioFile

    var errorDescription: String? {
        switch self {
        case .invalidAudioFile:
            return "The recorded audio file could not be prepared for analysis."
        }
    }
}

struct OpenAIAudioInputPreparer: AnalysisAudioPreparing {
    func prepareAudioForAnalysis(from fileURL: URL) throws -> PreparedAudioInput {
        let extensionName = fileURL.pathExtension.lowercased()

        if extensionName == "wav" || extensionName == "mp3" {
            let audioFormat = try OpenAIAudioFormat(fileURL: fileURL)
            return PreparedAudioInput(data: try Data(contentsOf: fileURL), format: audioFormat.apiValue)
        }

        let convertedURL = try convertAudioToWAV(sourceURL: fileURL)
        return PreparedAudioInput(data: try Data(contentsOf: convertedURL), format: "wav")
    }

    private func convertAudioToWAV(sourceURL: URL) throws -> URL {
        let inputFile = try AVAudioFile(forReading: sourceURL)
        let processingFormat = inputFile.processingFormat
        let frameCount = AVAudioFrameCount(inputFile.length)

        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: processingFormat, frameCapacity: frameCount) else {
            throw AudioPreparationError.invalidAudioFile
        }

        try inputFile.read(into: buffer)

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("texteenu-analysis-\(UUID().uuidString)")
            .appendingPathExtension("wav")

        let outputFile = try AVAudioFile(
            forWriting: outputURL,
            settings: processingFormat.settings,
            commonFormat: processingFormat.commonFormat,
            interleaved: processingFormat.isInterleaved
        )

        try outputFile.write(from: buffer)
        return outputURL
    }
}
