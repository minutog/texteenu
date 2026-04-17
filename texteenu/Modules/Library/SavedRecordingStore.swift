import Foundation

protocol SavedRecordingStore {
    func fetchAll() throws -> [SavedRecording]
    func saveRecording(
        title: String,
        from sourceAudioURL: URL,
        transcriptionText: String,
        tokens: [WordToken]
    ) throws -> SavedRecording
    func deleteRecording(id: UUID) throws
    func updateRecordingTitle(id: UUID, title: String) throws -> SavedRecording
    func audioFileURL(for recording: SavedRecording) throws -> URL
}

enum SavedRecordingStoreError: LocalizedError {
    case storageUnavailable
    case recordingNotFound

    var errorDescription: String? {
        switch self {
        case .storageUnavailable:
            return "The app could not access local storage for saved audio."
        case .recordingNotFound:
            return "The selected saved audio could not be found."
        }
    }
}

struct LocalSavedRecordingStore: SavedRecordingStore {
    private let fileManager = FileManager.default
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func fetchAll() throws -> [SavedRecording] {
        try migrateLegacyStoreIfNeeded()

        let recordingsDirectoryURL = try recordingsDirectoryURL()
        let directoryContents = try fileManager.contentsOfDirectory(
            at: recordingsDirectoryURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        var recordings: [SavedRecording] = []

        for directoryURL in directoryContents {
            let resourceValues = try? directoryURL.resourceValues(forKeys: [.isDirectoryKey])
            guard resourceValues?.isDirectory == true else { continue }

            let metadataURL = directoryURL.appendingPathComponent("recording.json")
            guard fileManager.fileExists(atPath: metadataURL.path) else { continue }

            guard
                let data = try? Data(contentsOf: metadataURL),
                let recording = try? decoder.decode(SavedRecording.self, from: data)
            else {
                continue
            }

            recordings.append(recording)
        }

        return recordings.sorted { $0.createdAt > $1.createdAt }
    }

    func saveRecording(
        title: String,
        from sourceAudioURL: URL,
        transcriptionText: String,
        tokens: [WordToken]
    ) throws -> SavedRecording {
        let fileExtension = sourceAudioURL.pathExtension.isEmpty ? "m4a" : sourceAudioURL.pathExtension
        let audioFileName = "\(sanitizedBaseName(from: title)).\(fileExtension)"
        let recording = SavedRecording(
            title: title,
            audioFileName: audioFileName,
            transcriptionText: transcriptionText,
            tokens: tokens
        )

        let recordingDirectoryURL = try recordingDirectoryURL(for: recording.id, createIfNeeded: true)
        let destinationURL = recordingDirectoryURL.appendingPathComponent(recording.audioFileName)
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.copyItem(at: sourceAudioURL, to: destinationURL)
        try persist(recording, in: recordingDirectoryURL)
        return recording
    }

    func deleteRecording(id: UUID) throws {
        let directoryURL = try recordingDirectoryURL(for: id, createIfNeeded: false)
        guard fileManager.fileExists(atPath: directoryURL.path) else { return }
        try fileManager.removeItem(at: directoryURL)
    }

    func updateRecordingTitle(id: UUID, title: String) throws -> SavedRecording {
        let recordingDirectoryURL = try recordingDirectoryURL(for: id, createIfNeeded: false)
        let metadataURL = recordingDirectoryURL.appendingPathComponent("recording.json")
        guard fileManager.fileExists(atPath: metadataURL.path) else {
            throw SavedRecordingStoreError.recordingNotFound
        }

        let data = try Data(contentsOf: metadataURL)
        let originalRecording = try decoder.decode(SavedRecording.self, from: data)
        let updatedRecording = SavedRecording(
            id: originalRecording.id,
            title: title,
            createdAt: originalRecording.createdAt,
            audioFileName: originalRecording.audioFileName,
            transcriptionText: originalRecording.transcriptionText,
            tokens: originalRecording.tokens
        )

        try persist(updatedRecording, in: recordingDirectoryURL)
        return updatedRecording
    }

    func audioFileURL(for recording: SavedRecording) throws -> URL {
        try recordingDirectoryURL(for: recording.id, createIfNeeded: false)
            .appendingPathComponent(recording.audioFileName)
    }

    private func persist(_ recording: SavedRecording, in directoryURL: URL) throws {
        let metadataURL = directoryURL.appendingPathComponent("recording.json")
        let data = try encoder.encode(recording)
        try data.write(to: metadataURL, options: .atomic)
    }

    private func recordingsDirectoryURL() throws -> URL {
        let directoryURL = try baseDirectoryURL().appendingPathComponent("Recordings", isDirectory: true)
        if !fileManager.fileExists(atPath: directoryURL.path) {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }
        return directoryURL
    }

    private func recordingDirectoryURL(for id: UUID, createIfNeeded: Bool) throws -> URL {
        let directoryURL = try recordingsDirectoryURL().appendingPathComponent(id.uuidString, isDirectory: true)
        if createIfNeeded && !fileManager.fileExists(atPath: directoryURL.path) {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }
        return directoryURL
    }

    private func sanitizedBaseName(from title: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/:\\?%*|\"<>")
            .union(.newlines)

        let cleanedTitle = title
            .components(separatedBy: invalidCharacters)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

        return cleanedTitle.isEmpty ? "Audio" : cleanedTitle
    }

    private func baseDirectoryURL() throws -> URL {
        guard let applicationSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw SavedRecordingStoreError.storageUnavailable
        }

        let directoryURL = applicationSupportURL.appendingPathComponent("Texteenu", isDirectory: true)
        if !fileManager.fileExists(atPath: directoryURL.path) {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }
        return directoryURL
    }

    private func migrateLegacyStoreIfNeeded() throws {
        let legacyMetadataURL = try baseDirectoryURL().appendingPathComponent("recordings.json")
        guard fileManager.fileExists(atPath: legacyMetadataURL.path) else { return }

        guard
            let data = try? Data(contentsOf: legacyMetadataURL),
            let legacyRecordings = try? decoder.decode([SavedRecording].self, from: data)
        else {
            let brokenURL = try baseDirectoryURL().appendingPathComponent("recordings.broken.json")
            try? fileManager.removeItem(at: brokenURL)
            try? fileManager.moveItem(at: legacyMetadataURL, to: brokenURL)
            return
        }

        let legacyAudioDirectoryURL = try baseDirectoryURL().appendingPathComponent("Audio", isDirectory: true)

        for recording in legacyRecordings {
            let recordingDirectoryURL = try recordingDirectoryURL(for: recording.id, createIfNeeded: true)
            let migratedMetadataURL = recordingDirectoryURL.appendingPathComponent("recording.json")

            if !fileManager.fileExists(atPath: migratedMetadataURL.path) {
                try persist(recording, in: recordingDirectoryURL)
            }

            let legacyAudioURL = legacyAudioDirectoryURL.appendingPathComponent(recording.audioFileName)
            let migratedAudioURL = recordingDirectoryURL.appendingPathComponent(recording.audioFileName)

            if fileManager.fileExists(atPath: legacyAudioURL.path),
               !fileManager.fileExists(atPath: migratedAudioURL.path) {
                try fileManager.copyItem(at: legacyAudioURL, to: migratedAudioURL)
            }
        }

        try? fileManager.removeItem(at: legacyMetadataURL)
        if fileManager.fileExists(atPath: legacyAudioDirectoryURL.path) {
            try? fileManager.removeItem(at: legacyAudioDirectoryURL)
        }
    }
}
