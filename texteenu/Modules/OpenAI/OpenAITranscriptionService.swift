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
    private static let defaultTranscriptionPrompt = """
    Transcribe the audio strictly in English. Always output in English, regardless of the input language.
    Preserve the exact spoken words verbatim. Do not paraphrase, summarize, translate meaning, or rewrite in any way.
    Include all disfluencies and fillers such as "um", "uh", repetitions, and self-corrections exactly as spoken.
    Add punctuation only when clearly supported by the audio:
    - Use periods to separate sentences
    - Use commas for natural pauses within sentences
    - Use ellipses (...) to represent noticeable pauses
    - Use extra letters inside of a word if a word is exagerated or elongated more than usual
    Preserve the original wording exactly while improving readability only through punctuation and paragraph breaks. Do not remove or alter any words.
    Return only the transcript.
    """

    let apiClient: OpenAIAPIClient

    func transcribeAudio(at fileURL: URL) async throws -> TranscriptionResult {
        let configuration = try apiClient.loadConfiguration()
        let fileData = try Data(contentsOf: fileURL)
        let audioFormat = try OpenAIAudioFormat(fileURL: fileURL)

        var multipartBody = MultipartFormDataBuilder()
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
