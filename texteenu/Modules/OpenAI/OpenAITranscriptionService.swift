import Foundation

protocol AudioTranscriptionService {
    func transcribeAudio(at fileURL: URL) async throws -> TranscriptionResult
}

enum AudioTranscriptionError: LocalizedError {
    case missingWordTimestamps

    var errorDescription: String? {
        switch self {
        case .missingWordTimestamps:
            return "The transcription response did not include word-level timestamps."
        }
    }
}

struct OpenAITranscriptionService: AudioTranscriptionService {
    let apiClient: OpenAIAPIClient

    func transcribeAudio(at fileURL: URL) async throws -> TranscriptionResult {
        let configuration = try apiClient.loadConfiguration()
        let fileData = try Data(contentsOf: fileURL)
        let audioFormat = try OpenAIAudioFormat(fileURL: fileURL)

        var multipartBody = MultipartFormDataBuilder()
        multipartBody.addTextField(named: "model", value: configuration.transcriptionModel)
        multipartBody.addTextField(named: "response_format", value: "verbose_json")
        multipartBody.addTextField(named: "timestamp_granularities[]", value: "word")
        multipartBody.addFileField(
            named: "file",
            filename: fileURL.lastPathComponent,
            mimeType: audioFormat.mimeType,
            data: fileData
        )

        let responseData = try await apiClient.postMultipart(path: "v1/audio/transcriptions", body: multipartBody)
        let response = try JSONDecoder().decode(VerboseTranscriptionResponse.self, from: responseData)

        guard let words = response.words, !words.isEmpty else {
            throw AudioTranscriptionError.missingWordTimestamps
        }

        return TranscriptionResult(
            fullText: response.text.trimmingCharacters(in: .whitespacesAndNewlines),
            words: words.map {
                TranscribedWord(
                    text: $0.word.trimmingCharacters(in: .whitespacesAndNewlines),
                    startTime: $0.start,
                    endTime: $0.end
                )
            }
        )
    }
}

private struct VerboseTranscriptionResponse: Decodable {
    let text: String
    let words: [VerboseTranscriptionWord]?
}

private struct VerboseTranscriptionWord: Decodable {
    let word: String
    let start: Double
    let end: Double
}
