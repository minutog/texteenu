import FirebaseCore
import FirebaseFirestore
import FirebaseStorage
import Foundation

protocol HapTextRemoteChatListener: AnyObject {
    func remove()
}

final class HapTextFirebaseChatService {
    private let database: Firestore
    private let storage: Storage
    private let maxAudioDownloadSize: Int64 = 25 * 1024 * 1024

    static func makeIfConfigured() -> HapTextFirebaseChatService? {
        guard FirebaseApp.app() != nil else { return nil }
        return HapTextFirebaseChatService()
    }

    private init(
        database: Firestore = Firestore.firestore(),
        storage: Storage = Storage.storage()
    ) {
        self.database = database
        self.storage = storage
    }

    func listen(
        conversationID: String,
        onChange: @escaping @MainActor (Result<[ChatMessage], Error>) -> Void
    ) -> HapTextRemoteChatListener {
        let query = messagesCollection(conversationID: conversationID)
            .order(by: "createdAt", descending: false)

        let registration = query.addSnapshotListener { [weak self] snapshot, error in
            guard let self else { return }

            if let error {
                Task { @MainActor in
                    onChange(.failure(error))
                }
                return
            }

            let documents = snapshot?.documents ?? []

            Task {
                do {
                    let messages = try await self.decodeMessages(
                        from: documents,
                        conversationID: conversationID
                    )

                    await MainActor.run {
                        onChange(.success(messages))
                    }
                } catch {
                    await MainActor.run {
                        onChange(.failure(error))
                    }
                }
            }
        }

        return FirestoreRemoteChatListener(registration: registration)
    }

    func send(_ message: ChatMessage, conversationID: String) async throws {
        var payload = basePayload(for: message)

        switch message.content {
        case .text(let text):
            payload["type"] = "text"
            payload["text"] = text
        case .audio(let clip):
            let audioPath = try await uploadAudioClip(
                clip,
                messageID: message.id,
                conversationID: conversationID
            )

            payload["type"] = "audio"
            payload["audioStoragePath"] = audioPath
            payload["duration"] = clip.duration
            payload["samples"] = AudioWaveformExtractor.resampled(clip.samples, targetSampleCount: 72)

            if let transcription = clip.transcription {
                payload["transcriptionText"] = transcription.fullText
                payload["transcriptionWords"] = transcription.words.map(encodedWord)
            }

            if let survey = clip.survey {
                payload["surveySentiment"] = survey.sentiment.rawValue
                payload["surveyDetail"] = survey.detail
            }
        }

        try await setData(
            payload,
            at: messagesCollection(conversationID: conversationID)
                .document(message.id.uuidString)
        )
    }

    private func messagesCollection(conversationID: String) -> CollectionReference {
        database.collection("haptext_chats")
            .document(conversationID)
            .collection("messages")
    }

    private func basePayload(for message: ChatMessage) -> [String: Any] {
        var payload: [String: Any] = [
            "id": message.id.uuidString,
            "senderID": message.sender.rawValue,
            "recipientID": message.recipient.rawValue,
            "createdAt": Timestamp(date: message.date),
            "serverCreatedAt": FieldValue.serverTimestamp(),
            "historyVersion": ChatEndpoint.chatHistoryVersion,
            "isVisibleToReceiver": message.isVisibleToReceiver
        ]

        if let senderPushToken = HapTextNotificationSettings.shared.fcmToken {
            payload["senderPushToken"] = senderPushToken
        }

        return payload
    }

    private func encodedWord(_ word: HapTextWordToken) -> [String: Any] {
        [
            "id": word.id.uuidString,
            "text": word.text,
            "startTime": word.startTime,
            "endTime": word.endTime
        ]
    }

    private func decodeMessages(
        from documents: [QueryDocumentSnapshot],
        conversationID: String
    ) async throws -> [ChatMessage] {
        var messages: [ChatMessage] = []

        for document in documents {
            do {
                guard let message = try await decodeMessage(document, conversationID: conversationID) else {
                    continue
                }

                messages.append(message)
            } catch {
                print("HapText Firebase: failed to decode message \(document.documentID): \(error.localizedDescription)")
            }
        }

        return messages.sorted { $0.date < $1.date }
    }

    private func decodeMessage(
        _ document: QueryDocumentSnapshot,
        conversationID: String
    ) async throws -> ChatMessage? {
        let data = document.data()

        guard let id = UUID(uuidString: data["id"] as? String ?? document.documentID),
              let sender = endpoint(from: data["senderID"]),
              let recipient = endpoint(from: data["recipientID"]),
              let type = data["type"] as? String else {
            return nil
        }

        guard int(from: data["historyVersion"]) == ChatEndpoint.chatHistoryVersion else {
            return nil
        }

        let date = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
        let isVisibleToReceiver = data["isVisibleToReceiver"] as? Bool ?? true
        let content: MessageContent

        switch type {
        case "text":
            guard let text = data["text"] as? String else { return nil }
            content = .text(text)
        case "audio":
            guard let storagePath = data["audioStoragePath"] as? String else { return nil }
            let localURL = try await cachedAudioURL(
                storagePath: storagePath,
                messageID: id,
                conversationID: conversationID
            )

            let clip = AudioClip(
                fileURL: localURL,
                duration: double(from: data["duration"]) ?? 0.2,
                samples: doubleArray(from: data["samples"]),
                transcription: transcription(from: data),
                survey: survey(from: data)
            )

            content = .audio(clip)
        default:
            return nil
        }

        return ChatMessage(
            id: id,
            sender: sender,
            recipient: recipient,
            date: date,
            content: content,
            isVisibleToReceiver: isVisibleToReceiver
        )
    }

    private func endpoint(from value: Any?) -> ChatEndpoint? {
        guard let rawValue = value as? String else { return nil }
        return ChatEndpoint(rawValue: rawValue)
    }

    private func transcription(from data: [String: Any]) -> HapTextTranscriptionResult? {
        let text = (data["transcriptionText"] as? String) ?? ""
        let words = ((data["transcriptionWords"] as? [[String: Any]]) ?? []).compactMap { rawWord in
            word(from: rawWord)
        }

        guard text.isEmpty == false || words.isEmpty == false else { return nil }
        return HapTextTranscriptionResult(fullText: text, words: words)
    }

    private func word(from data: [String: Any]) -> HapTextWordToken? {
        guard let text = data["text"] as? String,
              let startTime = double(from: data["startTime"]),
              let endTime = double(from: data["endTime"]) else {
            return nil
        }

        let id = UUID(uuidString: data["id"] as? String ?? "") ?? UUID()
        return HapTextWordToken(id: id, text: text, startTime: startTime, endTime: endTime)
    }

    private func survey(from data: [String: Any]) -> AudioSurvey? {
        guard let rawSentiment = data["surveySentiment"] as? String,
              let sentiment = AudioSentiment(rawValue: rawSentiment),
              let detail = data["surveyDetail"] as? String else {
            return nil
        }

        return AudioSurvey(sentiment: sentiment, detail: detail)
    }

    private func doubleArray(from value: Any?) -> [Double] {
        if let values = value as? [Double], values.isEmpty == false {
            return values
        }

        if let values = value as? [NSNumber], values.isEmpty == false {
            return values.map(\.doubleValue)
        }

        return AudioWaveformExtractor.silentSamples()
    }

    private func double(from value: Any?) -> Double? {
        if let value = value as? Double {
            return value
        }

        if let value = value as? NSNumber {
            return value.doubleValue
        }

        return nil
    }

    private func int(from value: Any?) -> Int? {
        if let value = value as? Int {
            return value
        }

        if let value = value as? NSNumber {
            return value.intValue
        }

        return nil
    }

    private func uploadAudioClip(
        _ clip: AudioClip,
        messageID: UUID,
        conversationID: String
    ) async throws -> String {
        let path = audioStoragePath(messageID: messageID, conversationID: conversationID)
        let reference = storage.reference(withPath: path)
        let metadata = StorageMetadata()
        metadata.contentType = "audio/mp4"

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            reference.putFile(from: clip.fileURL, metadata: metadata) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }

        return path
    }

    private func cachedAudioURL(
        storagePath: String,
        messageID: UUID,
        conversationID: String
    ) async throws -> URL {
        let localURL = audioCacheDirectory(conversationID: conversationID)
            .appendingPathComponent("\(messageID.uuidString).m4a")

        if FileManager.default.fileExists(atPath: localURL.path) {
            return localURL
        }

        try FileManager.default.createDirectory(
            at: localURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let data = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            storage.reference(withPath: storagePath).getData(maxSize: maxAudioDownloadSize) { data, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: HapTextFirebaseChatError.missingAudioData)
                }
            }
        }

        try data.write(to: localURL, options: [.atomic])
        return localURL
    }

    private func audioStoragePath(messageID: UUID, conversationID: String) -> String {
        "haptext_chats/\(conversationID)/messages/\(messageID.uuidString).m4a"
    }

    private func audioCacheDirectory(conversationID: String) -> URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HapTextAudioMessages", isDirectory: true)
            .appendingPathComponent(conversationID, isDirectory: true)
    }

    private func setData(_ data: [String: Any], at document: DocumentReference) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            document.setData(data) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}

private final class FirestoreRemoteChatListener: HapTextRemoteChatListener {
    private let registration: ListenerRegistration

    init(registration: ListenerRegistration) {
        self.registration = registration
    }

    func remove() {
        registration.remove()
    }
}

private enum HapTextFirebaseChatError: LocalizedError {
    case missingAudioData

    var errorDescription: String? {
        switch self {
        case .missingAudioData:
            return "The audio message could not be downloaded."
        }
    }
}
