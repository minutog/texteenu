import Combine
import Foundation

@MainActor
final class ChatStore: ObservableObject {
    @Published private(set) var messages: [ChatMessage] = []

    func sendText(from sender: ChatEndpoint, text: String) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedText.isEmpty == false else { return }

        messages.append(
            ChatMessage(sender: sender, content: .text(trimmedText))
        )
    }

    @discardableResult
    func sendAudio(
        from sender: ChatEndpoint,
        recording: RecordedAudio,
        transcription: HapTextTranscriptionResult? = nil
    ) -> ChatMessage {
        let message = ChatMessage(
            sender: sender,
            content: .audio(
                AudioClip(
                    fileURL: recording.url,
                    duration: max(recording.duration, 0.2),
                    samples: recording.samples,
                    transcription: transcription
                )
            )
        )

        messages.append(message)
        return message
    }

    func updateSurvey(for messageID: UUID, survey: AudioSurvey) {
        guard let index = messages.firstIndex(where: { $0.id == messageID }) else { return }
        guard case .audio(var clip) = messages[index].content else { return }

        clip.survey = survey
        messages[index].content = .audio(clip)
    }
}
