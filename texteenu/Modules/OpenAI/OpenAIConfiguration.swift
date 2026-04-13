import Foundation

struct OpenAIConfiguration {
    static let defaultBaseURL = URL(string: "https://api.openai.com/")!
    static let placeholderAPIKey = "YOUR_OPENAI_API_KEY_HERE"
    static let defaultTranscriptionModel = "whisper-1"
    static let defaultAnalysisModel = "gpt-audio-mini"

    let apiKey: String
    let baseURL: URL
    let transcriptionModel: String
    let analysisModel: String
}

protocol OpenAIConfigurationProviding {
    func loadConfiguration() throws -> OpenAIConfiguration
}

struct BundleOpenAIConfigurationProvider: OpenAIConfigurationProviding {
    func loadConfiguration() throws -> OpenAIConfiguration {
        let environmentKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"]?.trimmedNonEmpty
        let infoDictionaryKey = (Bundle.main.object(forInfoDictionaryKey: "OPENAI_API_KEY") as? String)?.trimmedNonEmpty
        let baseURLString = (Bundle.main.object(forInfoDictionaryKey: "OPENAI_BASE_URL") as? String)?.trimmedNonEmpty
        let transcriptionModel = (Bundle.main.object(forInfoDictionaryKey: "OPENAI_TRANSCRIPTION_MODEL") as? String)?.trimmedNonEmpty
            ?? OpenAIConfiguration.defaultTranscriptionModel
        let analysisModel = (Bundle.main.object(forInfoDictionaryKey: "OPENAI_ANALYSIS_MODEL") as? String)?.trimmedNonEmpty
            ?? OpenAIConfiguration.defaultAnalysisModel

        let candidateKey = environmentKey ?? infoDictionaryKey

        guard let apiKey = candidateKey, apiKey != OpenAIConfiguration.placeholderAPIKey, !apiKey.contains("$(") else {
            throw OpenAIConfigurationError.missingAPIKey
        }

        let baseURL = baseURLString.flatMap(URL.init(string:)) ?? OpenAIConfiguration.defaultBaseURL

        return OpenAIConfiguration(
            apiKey: apiKey,
            baseURL: baseURL,
            transcriptionModel: transcriptionModel,
            analysisModel: analysisModel
        )
    }
}

enum OpenAIConfigurationError: LocalizedError {
    case missingAPIKey

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Set OPENAI_API_KEY in the app target settings or in your Xcode scheme environment variables before processing audio."
        }
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
