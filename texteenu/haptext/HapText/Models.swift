import Foundation

enum ChatEndpoint: String, CaseIterable, Identifiable, Hashable {
    case ameena
    case gonzalo

    static let chatHistoryVersion = 2

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ameena:
            return "Ameena"
        case .gonzalo:
            return "Gonzalo"
        }
    }

    var peer: ChatEndpoint {
        switch self {
        case .ameena:
            return .gonzalo
        case .gonzalo:
            return .ameena
        }
    }

    static func contacts(excluding user: ChatEndpoint) -> [ChatEndpoint] {
        allCases.filter { $0 != user }
    }

    func conversationID(with contact: ChatEndpoint) -> String {
        [rawValue, contact.rawValue].sorted().joined(separator: "_")
    }

    var avatarImageName: String {
        switch self {
        case .ameena:
            return "ameena_profile"
        case .gonzalo:
            return "profile"
        }
    }
}

struct ChatRoute: Identifiable, Hashable {
    let user: ChatEndpoint
    let contact: ChatEndpoint

    var id: String {
        "\(user.rawValue)-\(contact.rawValue)"
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
    let recipient: ChatEndpoint
    let date: Date
    var content: MessageContent
    var isVisibleToReceiver: Bool

    init(
        id: UUID = UUID(),
        sender: ChatEndpoint,
        recipient: ChatEndpoint,
        date: Date = Date(),
        content: MessageContent,
        isVisibleToReceiver: Bool = true
    ) {
        self.id = id
        self.sender = sender
        self.recipient = recipient
        self.date = date
        self.content = content
        self.isVisibleToReceiver = isVisibleToReceiver
    }
}
