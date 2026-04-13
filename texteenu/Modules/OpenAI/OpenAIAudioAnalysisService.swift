import Foundation

protocol AudioAnalysisService {
    func analyze(audioFileAt fileURL: URL, transcription: TranscriptionResult) async throws -> [WordToken]
}

enum AudioAnalysisError: LocalizedError {
    case emptyTranscription
    case missingStructuredOutput
    case incompleteScores(expected: Int, actual: Int)

    var errorDescription: String? {
        switch self {
        case .emptyTranscription:
            return "No transcribed words were available to analyze."
        case .missingStructuredOutput:
            return "The OpenAI analysis response did not contain structured JSON."
        case let .incompleteScores(expected, actual):
            return "OpenAI returned \(actual) analyzed word scores, but \(expected) were expected."
        }
    }
}

struct OpenAIAudioAnalysisService: AudioAnalysisService {
    let apiClient: OpenAIAPIClient
    let audioPreparer: any AnalysisAudioPreparing

    func analyze(audioFileAt fileURL: URL, transcription: TranscriptionResult) async throws -> [WordToken] {
        guard !transcription.words.isEmpty else {
            throw AudioAnalysisError.emptyTranscription
        }

        let configuration = try apiClient.loadConfiguration()
        let preparedAudio = try audioPreparer.prepareAudioForAnalysis(from: fileURL)
        let requestObject = makeRequestObject(
            model: configuration.analysisModel,
            transcription: transcription,
            audioData: preparedAudio.data.base64EncodedString(),
            audioFormat: preparedAudio.format
        )

        let responseData = try await apiClient.postJSON(path: "v1/chat/completions", jsonObject: requestObject)
        let response = try JSONDecoder().decode(ChatCompletionResponse.self, from: responseData)

        guard let content = response.choices.first?.message.content?.trimmingCharacters(in: .whitespacesAndNewlines),
              !content.isEmpty else {
            throw AudioAnalysisError.missingStructuredOutput
        }

        let jsonContent = try extractJSONObject(from: content)
        let scoresEnvelope = try JSONDecoder().decode(WordScoreEnvelope.self, from: Data(jsonContent.utf8))
        let orderedScores = try normalizeScores(scoresEnvelope.scores, expectedCount: transcription.words.count)

        return zip(transcription.words, orderedScores).map { word, score in
            WordToken(
                text: word.text,
                startTime: word.startTime,
                endTime: word.endTime,
                emotionIntensity: score.emotionIntensity,
                importanceIntensity: score.importanceIntensity
            )
        }
    }

    private func makeRequestObject(
        model: String,
        transcription: TranscriptionResult,
        audioData: String,
        audioFormat: String
    ) -> [String: Any] {
        [
            "model": model,
            "modalities": ["text"],
            "temperature": 0.0,
            "messages": [
                [
                    "role": "system",
                    "content": "You analyze spoken audio at the word level. Use the audio's prosody, timing, emphasis, and vocal delivery as the primary signal for emotionIntensity. Use the transcript context to judge importanceIntensity. Return only valid JSON with no markdown."
                ],
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "text",
                            "text": makePrompt(for: transcription)
                        ],
                        [
                            "type": "input_audio",
                            "input_audio": [
                                "data": audioData,
                                "format": audioFormat
                            ]
                        ]
                    ]
                ]
            ]
        ]
    }

    private func makePrompt(for transcription: TranscriptionResult) -> String {
        let indexedWords = transcription.words.enumerated().map { index, word in
            "\(index)|\(word.text)|\(String(format: "%.3f", word.startTime))|\(String(format: "%.3f", word.endTime))"
        }.joined(separator: "\n")

        return """
        Analyze every word in this spoken message.

        Transcript:
        \(transcription.fullText)

        Word list in exact order:
        \(indexedWords)

        Scoring rules:
        - Return one score object for every listed word.
        - Keep the same word order by using the supplied zero-based index.
        - emotionIntensity must be driven primarily by vocal delivery and prosody for that word.
        - importanceIntensity must reflect how important the word is to the overall message meaning.
        - Function words can have low importanceIntensity.
        - All values must stay between 0.0 and 1.0.
        - Respond with JSON only in this shape:
          {"scores":[{"index":0,"emotionIntensity":0.0,"importanceIntensity":0.0}]}
        """
    }

    private func normalizeScores(_ scores: [WordScore], expectedCount: Int) throws -> [WordScore] {
        var orderedScores = Array<WordScore?>(repeating: nil, count: expectedCount)

        for score in scores where orderedScores.indices.contains(score.index) {
            orderedScores[score.index] = score.clamped
        }

        let resolvedScores = orderedScores.compactMap { $0 }

        guard resolvedScores.count == expectedCount else {
            throw AudioAnalysisError.incompleteScores(expected: expectedCount, actual: resolvedScores.count)
        }

        return resolvedScores
    }

    private func extractJSONObject(from content: String) throws -> String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.hasPrefix("```"),
           let fenceStart = trimmed.range(of: "{"),
           let fenceEnd = trimmed.range(of: "}", options: .backwards),
           fenceStart.lowerBound < fenceEnd.upperBound {
            return String(trimmed[fenceStart.lowerBound..<fenceEnd.upperBound])
        }

        if let objectStart = trimmed.range(of: "{"),
           let objectEnd = trimmed.range(of: "}", options: .backwards),
           objectStart.lowerBound < objectEnd.upperBound {
            return String(trimmed[objectStart.lowerBound..<objectEnd.upperBound])
        }

        throw AudioAnalysisError.missingStructuredOutput
    }
}

private struct ChatCompletionResponse: Decodable {
    let choices: [ChatCompletionChoice]
}

private struct ChatCompletionChoice: Decodable {
    let message: ChatCompletionMessage
}

private struct ChatCompletionMessage: Decodable {
    let content: String?
}

private struct WordScoreEnvelope: Decodable {
    let scores: [WordScore]
}

private struct WordScore: Decodable {
    let index: Int
    let emotionIntensity: Double
    let importanceIntensity: Double

    var clamped: WordScore {
        WordScore(
            index: index,
            emotionIntensity: emotionIntensity.clampedToUnitInterval,
            importanceIntensity: importanceIntensity.clampedToUnitInterval
        )
    }
}
