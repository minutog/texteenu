import Foundation

struct WordToken: Identifiable, Equatable, Sendable {
    let id: UUID
    let text: String
    let startTime: TimeInterval
    let endTime: TimeInterval
    let emotionIntensity: Double
    let importanceIntensity: Double

    init(
        id: UUID = UUID(),
        text: String,
        startTime: TimeInterval,
        endTime: TimeInterval,
        emotionIntensity: Double,
        importanceIntensity: Double
    ) {
        self.id = id
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
        self.emotionIntensity = emotionIntensity.clampedToUnitInterval
        self.importanceIntensity = importanceIntensity.clampedToUnitInterval
    }
}

struct TranscribedWord: Identifiable, Equatable, Sendable {
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

struct TranscriptionResult: Equatable, Sendable {
    let fullText: String
    let words: [TranscribedWord]
}

extension Double {
    var clampedToUnitInterval: Double {
        min(max(self, 0), 1)
    }
}
