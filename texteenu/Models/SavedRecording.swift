import Foundation

struct SavedRecording: Identifiable, Equatable, Sendable, Codable {
    let id: UUID
    let title: String
    let createdAt: Date
    let audioFileName: String
    let transcriptionText: String
    let tokens: [WordToken]

    init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = Date(),
        audioFileName: String,
        transcriptionText: String,
        tokens: [WordToken]
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.audioFileName = audioFileName
        self.transcriptionText = transcriptionText
        self.tokens = tokens
    }
}
