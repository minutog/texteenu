import Foundation

enum ChatEndpoint: String, CaseIterable, Identifiable, Hashable {
    case chatA
    case chatB

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .chatA:
            return "Chat A"
        case .chatB:
            return "Chat B"
        }
    }

    var peer: ChatEndpoint {
        switch self {
        case .chatA:
            return .chatB
        case .chatB:
            return .chatA
        }
    }
}

enum AudioSentiment: String, CaseIterable, Identifiable, Equatable {
    case positive
    case negative

    var id: String { rawValue }

    var title: String {
        switch self {
        case .positive:
            return "Positive"
        case .negative:
            return "Negative"
        }
    }

    var detailOptions: [String] {
        switch self {
        case .positive:
            return ["Happiness", "Excitement", "Relax"]
        case .negative:
            return ["Sadness", "Frustration", "Anxiety"]
        }
    }
}

struct AudioSurvey: Equatable {
    var sentiment: AudioSentiment
    var detail: String
}

struct AudioClip: Identifiable, Equatable {
    let id: UUID
    var fileURL: URL
    var duration: TimeInterval
    var samples: [Double]
    var transcription: HapTextTranscriptionResult?
    var survey: AudioSurvey?

    init(
        id: UUID = UUID(),
        fileURL: URL,
        duration: TimeInterval,
        samples: [Double],
        transcription: HapTextTranscriptionResult? = nil,
        survey: AudioSurvey? = nil
    ) {
        self.id = id
        self.fileURL = fileURL
        self.duration = duration
        self.samples = samples
        self.transcription = transcription
        self.survey = survey
    }
}

enum MessageContent: Equatable {
    case text(String)
    case audio(AudioClip)
}

struct ChatMessage: Identifiable, Equatable {
    let id: UUID
    let sender: ChatEndpoint
    let date: Date
    var content: MessageContent
    var isVisibleToReceiver: Bool

    init(
        id: UUID = UUID(),
        sender: ChatEndpoint,
        date: Date = Date(),
        content: MessageContent,
        isVisibleToReceiver: Bool = true
    ) {
        self.id = id
        self.sender = sender
        self.date = date
        self.content = content
        self.isVisibleToReceiver = isVisibleToReceiver
    }
}
