import Foundation

enum OpenAIAPIError: LocalizedError {
    case invalidResponse
    case invalidJSONObject
    case requestFailed(statusCode: Int, message: String)
    case unsupportedAudioFormat(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "OpenAI returned an invalid response."
        case .invalidJSONObject:
            return "The OpenAI request body could not be encoded."
        case let .requestFailed(statusCode, message):
            return "OpenAI request failed (\(statusCode)): \(message)"
        case let .unsupportedAudioFormat(extensionName):
            return "Unsupported audio format: \(extensionName)"
        }
    }
}

final class OpenAIAPIClient {
    private let configurationProvider: any OpenAIConfigurationProviding
    private let session: URLSession

    init(configurationProvider: any OpenAIConfigurationProviding, session: URLSession = .shared) {
        self.configurationProvider = configurationProvider
        self.session = session
    }

    func loadConfiguration() throws -> OpenAIConfiguration {
        try configurationProvider.loadConfiguration()
    }

    func postJSON(path: String, jsonObject: [String: Any]) async throws -> Data {
        guard JSONSerialization.isValidJSONObject(jsonObject) else {
            throw OpenAIAPIError.invalidJSONObject
        }

        var request = try makeRequest(path: path, contentType: "application/json")
        request.httpBody = try JSONSerialization.data(withJSONObject: jsonObject, options: [])
        return try await execute(request)
    }

    func postMultipart(path: String, body: MultipartFormDataBuilder) async throws -> Data {
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
            throw OpenAIAPIError.invalidResponse
        }

        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            let errorEnvelope = try? JSONDecoder().decode(OpenAIErrorEnvelope.self, from: data)
            let message = errorEnvelope?.error.message ?? String(data: data, encoding: .utf8) ?? "Unknown error"
            throw OpenAIAPIError.requestFailed(statusCode: httpResponse.statusCode, message: message)
        }

        return data
    }
}

struct MultipartFormDataBuilder {
    let boundary = "Boundary-\(UUID().uuidString)"
    private var body = Data()

    mutating func addTextField(named name: String, value: String) {
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        body.append("\(value)\r\n")
    }

    mutating func addFileField(named name: String, filename: String, mimeType: String, data: Data) {
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n")
        body.append("Content-Type: \(mimeType)\r\n\r\n")
        body.append(data)
        body.append("\r\n")
    }

    func build() -> Data {
        var output = body
        output.append("--\(boundary)--\r\n")
        return output
    }
}

struct OpenAIAudioFormat {
    let apiValue: String
    let mimeType: String

    init(fileURL: URL) throws {
        switch fileURL.pathExtension.lowercased() {
        case "m4a":
            apiValue = "m4a"
            mimeType = "audio/m4a"
        case "mp3":
            apiValue = "mp3"
            mimeType = "audio/mpeg"
        case "wav":
            apiValue = "wav"
            mimeType = "audio/wav"
        case "mp4":
            apiValue = "mp4"
            mimeType = "audio/mp4"
        case "mpeg", "mpga":
            apiValue = "mpeg"
            mimeType = "audio/mpeg"
        case "webm":
            apiValue = "webm"
            mimeType = "audio/webm"
        default:
            throw OpenAIAPIError.unsupportedAudioFormat(fileURL.pathExtension)
        }
    }
}

private struct OpenAIErrorEnvelope: Decodable {
    let error: OpenAIErrorPayload
}

private struct OpenAIErrorPayload: Decodable {
    let message: String
}

private extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}
