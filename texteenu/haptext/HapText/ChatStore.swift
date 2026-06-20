import Combine
import Foundation

@MainActor
final class ChatStore: ObservableObject {
    @Published private(set) var messages: [ChatMessage] = []
    @Published private(set) var remoteErrorMessage: String?

    private var activeConversationID: String?
    private var remoteService: HapTextFirebaseChatService?
    private var remoteListener: HapTextRemoteChatListener?

    func openConversation(between user: ChatEndpoint, and contact: ChatEndpoint) {
        let conversationID = user.conversationID(with: contact)
        guard activeConversationID != conversationID else { return }

        remoteListener?.remove()
        activeConversationID = conversationID
        messages = messages.filter { message in
            message.sender.conversationID(with: message.recipient) == conversationID &&
            message.isVisibleToReceiver == false
        }

        guard let remoteService = configuredRemoteService() else { return }

        remoteListener = remoteService.listen(conversationID: conversationID) { [weak self] result in
            guard let self else { return }

            switch result {
            case .success(let remoteMessages):
                self.remoteErrorMessage = nil
                self.mergeRemoteMessages(remoteMessages)
            case .failure(let error):
                print("HapText Firebase listen error: \(error.localizedDescription)")
                self.remoteErrorMessage = error.localizedDescription
            }
        }
    }

    func clearConversation() {
        remoteListener?.remove()
        remoteListener = nil
        activeConversationID = nil
        messages = []
    }

    func sendText(from sender: ChatEndpoint, to recipient: ChatEndpoint, text: String) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedText.isEmpty == false else { return }

        let message = ChatMessage(
            sender: sender,
            recipient: recipient,
            content: .text(trimmedText)
        )

        upsertLocalMessage(message)
        publishMessageIfPossible(message)
    }

    @discardableResult
    func sendAudio(
        from sender: ChatEndpoint,
        to recipient: ChatEndpoint,
        recording: RecordedAudio,
        transcription: HapTextTranscriptionResult? = nil,
        isVisibleToReceiver: Bool = true
    ) -> ChatMessage {
        let message = ChatMessage(
            sender: sender,
            recipient: recipient,
            content: .audio(
                AudioClip(
                    fileURL: recording.url,
                    duration: max(recording.duration, 0.2),
                    samples: recording.samples,
                    transcription: transcription
                )
            ),
            isVisibleToReceiver: isVisibleToReceiver
        )

        upsertLocalMessage(message)

        if isVisibleToReceiver {
            publishMessageIfPossible(message)
        }

        return message
    }

    func audioClip(for messageID: UUID) -> AudioClip? {
        guard let message = messages.first(where: { $0.id == messageID }),
              case .audio(let clip) = message.content else { return nil }

        return clip
    }

    func deliverAudio(messageID: UUID, transcription: HapTextTranscriptionResult?) {
        guard let index = messages.firstIndex(where: { $0.id == messageID }) else { return }
        guard case .audio(var clip) = messages[index].content else { return }

        clip.transcription = transcription
        messages[index].content = .audio(clip)
        messages[index].isVisibleToReceiver = true

        publishMessageIfPossible(messages[index])
    }

    func updateSurvey(for messageID: UUID, survey: AudioSurvey) {
        guard let index = messages.firstIndex(where: { $0.id == messageID }) else { return }
        guard case .audio(var clip) = messages[index].content else { return }

        clip.survey = survey
        messages[index].content = .audio(clip)
    }

    private func configuredRemoteService() -> HapTextFirebaseChatService? {
        if let remoteService {
            return remoteService
        }

        guard let service = HapTextFirebaseChatService.makeIfConfigured() else {
            remoteErrorMessage = "Firebase is not configured for this build."
            print("HapText Firebase: Firebase is not configured for this build.")
            return nil
        }

        remoteService = service
        return service
    }

    private func publishMessageIfPossible(_ message: ChatMessage) {
        guard let remoteService = configuredRemoteService() else { return }
        let conversationID = message.sender.conversationID(with: message.recipient)

        Task { [weak self] in
            do {
                try await remoteService.send(message, conversationID: conversationID)
                await MainActor.run {
                    self?.remoteErrorMessage = nil
                }
            } catch {
                await MainActor.run {
                    print("HapText Firebase send error: \(error.localizedDescription)")
                    self?.remoteErrorMessage = error.localizedDescription
                }
            }
        }
    }

    private func mergeRemoteMessages(_ remoteMessages: [ChatMessage]) {
        var mergedMessagesByID = Dictionary(uniqueKeysWithValues: messages.map { ($0.id, $0) })

        for remoteMessage in remoteMessages {
            if let localMessage = mergedMessagesByID[remoteMessage.id] {
                mergedMessagesByID[remoteMessage.id] = merged(localMessage: localMessage, remoteMessage: remoteMessage)
            } else {
                mergedMessagesByID[remoteMessage.id] = remoteMessage
            }
        }

        messages = mergedMessagesByID.values.sorted { $0.date < $1.date }
    }

    private func upsertLocalMessage(_ message: ChatMessage) {
        if let index = messages.firstIndex(where: { $0.id == message.id }) {
            messages[index] = message
        } else {
            messages.append(message)
        }
    }

    private func merged(localMessage: ChatMessage, remoteMessage: ChatMessage) -> ChatMessage {
        guard case .audio(var remoteClip) = remoteMessage.content,
              case .audio(let localClip) = localMessage.content else {
            return remoteMessage
        }

        if remoteClip.survey == nil {
            remoteClip.survey = localClip.survey
        }

        var mergedMessage = remoteMessage
        mergedMessage.content = .audio(remoteClip)
        return mergedMessage
    }
}
