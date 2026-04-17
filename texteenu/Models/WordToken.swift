import Foundation

struct WordToken: Identifiable, Equatable, Sendable, Codable {
    let id: UUID
    let text: String
    let startTime: TimeInterval
    let endTime: TimeInterval

    init(
        id: UUID = UUID(),
        text: String,
        startTime: TimeInterval,
        endTime: TimeInterval
    ) {
        self.id = id
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
    }
}

struct TranscribedWord: Identifiable, Equatable, Sendable, Codable {
    let id: UUID
    let text: String
    let startTime: TimeInterval
    let endTime: TimeInterval

    init(id: UUID = UUID(), text: String, startTime: TimeInterval, endTime: TimeInterval) {
        self.id = id
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
    }
}

struct TranscriptionResult: Equatable, Sendable, Codable {
    let fullText: String
    let words: [TranscribedWord]
}

extension Double {
    var clampedToUnitInterval: Double {
        min(max(self, 0), 1)
    }
}
