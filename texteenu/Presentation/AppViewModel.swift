import Combine
import SwiftUI

@MainActor
final class AppViewModel: ObservableObject {
    enum Section {
        case menu
        case recorder
        case player
    }

    enum ProcessingState: Equatable {
        case idle
        case transcribing
        case saving

        var isRunning: Bool {
            self != .idle
        }

        var title: String? {
            switch self {
            case .idle:
                return nil
            case .transcribing:
                return "Transcribing audio..."
            case .saving:
                return "Saving processed audio..."
            }
        }
    }

    enum PlayerMode: String, CaseIterable, Identifiable {
        case text = "Text"
        case audio = "Audio"
        case chattern = "Chattern"
        case all = "All"

        var id: String { rawValue }

        var showsAnimatedText: Bool {
            self == .chattern || self == .all
        }

        var playsAudio: Bool {
            self == .audio || self == .all
        }

        var playsHaptics: Bool {
            self == .chattern || self == .all
        }
    }

    @Published private(set) var section: Section = .menu
    @Published private(set) var isRecording = false
    @Published private(set) var processingState: ProcessingState = .idle
    @Published private(set) var draftRecordingURL: URL?
    @Published var draftTitle = ""
    @Published private(set) var transcriptionText = ""
    @Published private(set) var visibleTokens: [WordToken] = []
    @Published private(set) var playbackState: PlaybackState = .idle
    @Published private(set) var isAudioMuted = false
    @Published private(set) var savedRecordings: [SavedRecording] = []
    @Published private(set) var lastSavedRecording: SavedRecording?
    @Published private(set) var selectedPlaybackRecording: SavedRecording?
    @Published private(set) var selectedPlayerMode: PlayerMode = .all
    @Published private(set) var playerShowsPlainText = false
    @Published private(set) var playerHasPlayedSelection = false
    @Published private(set) var isPreparingPlayerPlayback = false
    @Published private(set) var showsPostSaveActions = false
    @Published var errorMessage: String?

    private let recordingService: any AudioRecordingService
    private let transcriptionService: any AudioTranscriptionService
    private let savedRecordingStore: any SavedRecordingStore
    private let playbackEngine: any PlaybackEngine
    private let audioPlaybackService: any AudioPlaybackService
    private let timelinePlaybackService: any TimelinePlaybackService
    private let visualMapping: any VisualMappingService
    private let hapticService: any HapticService

    init(dependencies: AppDependencies) {
        recordingService = dependencies.recordingService
        transcriptionService = dependencies.transcriptionService
        savedRecordingStore = dependencies.savedRecordingStore
        playbackEngine = dependencies.playbackEngine
        audioPlaybackService = dependencies.audioPlaybackService
        timelinePlaybackService = dependencies.timelinePlaybackService
        visualMapping = dependencies.visualMapping
        hapticService = dependencies.hapticService

        playbackEngine.onSnapshotChange = { [weak self] snapshot in
            guard let self else { return }
            self.playbackState = snapshot.state
            self.visibleTokens = snapshot.visibleTokens
        }

        loadSavedRecordings()
    }

    var canStartRecording: Bool {
        !isRecording && !processingState.isRunning
    }

    var canStopRecording: Bool {
        isRecording
    }

    var canSaveAndProcess: Bool {
        hasRecordedDraft && !processingState.isRunning
    }

    var canReplay: Bool {
        canStartPlayerPlayback
    }

    var hasRecordedDraft: Bool {
        draftRecordingURL != nil && !isRecording
    }

    var shouldShowTitleField: Bool {
        hasRecordedDraft
    }

    var shouldShowPostSaveActions: Bool {
        showsPostSaveActions && !isRecording && !processingState.isRunning && lastSavedRecording != nil
    }

    var recordButtonTitle: String {
        if hasRecordedDraft {
            return "Record Again"
        }

        if lastSavedRecording != nil {
            return "Record New"
        }

        return "Record"
    }

    var audioToggleIconName: String {
        isAudioMuted ? "speaker.slash.fill" : "speaker.wave.2.fill"
    }

    var statusText: String {
        if isRecording {
            return "Recording in progress..."
        }

        if hasRecordedDraft {
            return "Add a title and save it into the app."
        }

        if let lastSavedRecording, shouldShowPostSaveActions {
            return lastSavedRecording.title
        }

        return "Capture a short audio message, add a title, and save it into the app."
    }

    var visibleAttributedText: AttributedString {
        var output = AttributedString()

        for index in visibleTokens.indices {
            let token = visibleTokens[index]
            let distanceFromCurrent = (visibleTokens.count - 1) - index
            let style = visualMapping.style(forDistanceFromCurrent: distanceFromCurrent)

            var fragment = AttributedString(token.text)
            fragment.foregroundColor = .primary.opacity(style.opacity)
            output.append(fragment)

            if index < visibleTokens.count - 1 {
                output.append(AttributedString(" "))
            }
        }

        return output
    }

    var lastSavedTitle: String? {
        shouldShowPostSaveActions ? lastSavedRecording?.title : nil
    }

    var playerModes: [PlayerMode] {
        PlayerMode.allCases
    }

    var hasPlayerSelection: Bool {
        selectedPlaybackRecording != nil
    }

    var playerAvailableRecordings: [SavedRecording] {
        if !savedRecordings.isEmpty {
            if let selectedPlaybackRecording,
               !savedRecordings.contains(where: { $0.id == selectedPlaybackRecording.id }) {
                return [selectedPlaybackRecording] + savedRecordings
            }
            return savedRecordings
        }

        if let selectedPlaybackRecording {
            return [selectedPlaybackRecording]
        }

        return []
    }

    var playerSelectedTitle: String? {
        selectedPlaybackRecording?.title
    }

    var playerSelectedTranscriptText: String {
        selectedPlaybackRecording?.transcriptionText ?? ""
    }

    var canStartPlayerPlayback: Bool {
        selectedPlaybackRecording != nil && !processingState.isRunning && !isPreparingPlayerPlayback && playbackState != .playing
    }

    var canChangePlayerMode: Bool {
        !isPreparingPlayerPlayback && playbackState != .playing
    }

    var playerActionTitle: String {
        if isPreparingPlayerPlayback {
            return "Loading..."
        }

        if playbackState == .playing {
            return "Playing..."
        }

        return playerHasPlayedSelection ? "Replay" : "Play"
    }

    var playerStatusText: String {
        guard selectedPlaybackRecording != nil else {
            return savedRecordings.isEmpty
                ? "No saved messages yet."
                : "Select a saved message from Files."
        }

        if isPreparingPlayerPlayback {
            return "Preparing playback..."
        }

        switch selectedPlayerMode {
        case .text:
            return playerShowsPlainText ? "Showing the full message text." : "Press Play to show the full message."
        case .audio:
            return playbackState == .playing ? "Playing audio only." : "Press Play to hear the message."
        case .chattern:
            return playbackState == .playing
                ? "Playing animated text with haptics."
                : "Press Play for text animation and haptics."
        case .all:
            return playbackState == .playing
                ? "Playing text, haptics, and audio."
                : "Press Play for the full message."
        }
    }

    var shouldShowPlayerPlainText: Bool {
        selectedPlayerMode == .text && playerShowsPlainText
    }

    var shouldShowPlayerAnimatedText: Bool {
        selectedPlayerMode.showsAnimatedText
    }

    func isSelectedPlaybackRecording(_ recording: SavedRecording) -> Bool {
        selectedPlaybackRecording?.id == recording.id
    }

    func openMenu() {
        if isRecording {
            stopRecording()
        }
        stopPlayback()
        section = .menu
    }

    func openRecorder() {
        section = .recorder
    }

    func openPlayer() {
        if isRecording {
            stopRecording()
        }

        stopPlayback()
        refreshPlayerFiles()
        if selectedPlaybackRecording == nil {
            selectedPlaybackRecording = playerAvailableRecordings.first
        }
        section = .player
    }

    func refreshPlayerFiles() {
        loadSavedRecordings()
        if selectedPlaybackRecording == nil {
            selectedPlaybackRecording = playerAvailableRecordings.first
        }
    }

    func startRecording() {
        errorMessage = nil
        processingState = .idle
        showsPostSaveActions = false
        clearCurrentDraft(deleteAudioFile: true)
        clearProcessedPreview()
        stopPlayback()
        section = .recorder

        Task {
            do {
                try await self.recordingService.startRecording()
                self.draftRecordingURL = self.recordingService.outputFileURL
                self.isRecording = true
            } catch {
                self.present(error)
            }
        }
    }

    func stopRecording() {
        do {
            draftRecordingURL = try recordingService.stopRecording()
            draftTitle = makeDefaultRecordingTitle()
            isRecording = false
            errorMessage = nil
        } catch {
            present(error)
        }
    }

    func saveAndProcessRecording() {
        guard let draftRecordingURL else { return }

        errorMessage = nil
        processingState = .transcribing

        let proposedTitle = resolvedDraftTitle()

        Task {
            do {
                let transcription = try await self.transcriptionService.transcribeAudio(at: draftRecordingURL)
                self.transcriptionText = transcription.fullText

                let tokens = transcription.words.map {
                    WordToken(
                        text: $0.text,
                        startTime: $0.startTime,
                        endTime: $0.endTime
                    )
                }

                self.processingState = .saving
                let savedRecording = try self.savedRecordingStore.saveRecording(
                    title: proposedTitle,
                    from: draftRecordingURL,
                    transcriptionText: transcription.fullText,
                    tokens: tokens
                )
                let savedAudioURL = try self.savedRecordingStore.audioFileURL(for: savedRecording)
                await self.hapticService.prepareSpeechHaptics(for: savedAudioURL)

                self.deleteFileIfNeeded(at: draftRecordingURL)
                let fetchedRecordings = (try? self.savedRecordingStore.fetchAll()) ?? []
                self.savedRecordings = self.mergedRecordings(including: savedRecording, preferredOrder: fetchedRecordings)
                self.lastSavedRecording = savedRecording
                self.selectedPlaybackRecording = savedRecording
                self.draftRecordingURL = nil
                self.draftTitle = ""
                self.processingState = .idle
                self.showsPostSaveActions = true
                self.playerHasPlayedSelection = false
                self.playerShowsPlainText = false
                self.section = .recorder
            } catch {
                self.processingState = .idle
                self.present(error)
            }
        }
    }

    func deleteLastSavedAudio() {
        let recordingToDelete = savedRecordings.first ?? lastSavedRecording
        guard let recordingToDelete else {
            savedRecordings = []
            lastSavedRecording = nil
            clearProcessedPreview()
            showsPostSaveActions = false
            errorMessage = nil
            return
        }

        deleteRecording(id: recordingToDelete.id)
        clearProcessedPreview()
        showsPostSaveActions = false
    }

    func deleteRecording(id: UUID) {
        do {
            let deletedWasSelected = selectedPlaybackRecording?.id == id
            let deletedWasLastSaved = lastSavedRecording?.id == id

            if deletedWasSelected {
                stopPlayback()
                resetPlayerPresentation()
                playerHasPlayedSelection = false
            }

            try savedRecordingStore.deleteRecording(id: id)
            savedRecordings = try savedRecordingStore.fetchAll()

            if deletedWasLastSaved {
                lastSavedRecording = savedRecordings.first
            } else if let currentLastSaved = lastSavedRecording {
                lastSavedRecording = savedRecordings.first(where: { $0.id == currentLastSaved.id }) ?? savedRecordings.first
            }

            if deletedWasSelected {
                selectedPlaybackRecording = savedRecordings.first
            } else if let selectedPlaybackRecording {
                self.selectedPlaybackRecording = savedRecordings.first(where: { $0.id == selectedPlaybackRecording.id }) ?? savedRecordings.first
            } else {
                selectedPlaybackRecording = savedRecordings.first
            }

            if savedRecordings.isEmpty {
                selectedPlaybackRecording = nil
                if showsPostSaveActions {
                    clearProcessedPreview()
                    showsPostSaveActions = false
                }
            }

            errorMessage = nil
        } catch {
            present(error)
        }
    }

    func renameRecording(id: UUID, to newTitle: String) {
        let trimmedTitle = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

        do {
            let updatedRecording = try savedRecordingStore.updateRecordingTitle(id: id, title: trimmedTitle)
            savedRecordings = try savedRecordingStore.fetchAll()

            if lastSavedRecording?.id == id {
                lastSavedRecording = updatedRecording
            } else if let currentLastSaved = lastSavedRecording {
                lastSavedRecording = savedRecordings.first(where: { $0.id == currentLastSaved.id }) ?? savedRecordings.first
            }

            if selectedPlaybackRecording?.id == id {
                selectedPlaybackRecording = updatedRecording
            } else if let selectedPlaybackRecording {
                self.selectedPlaybackRecording = savedRecordings.first(where: { $0.id == selectedPlaybackRecording.id }) ?? savedRecordings.first
            }

            errorMessage = nil
        } catch {
            present(error)
        }
    }

    func selectPlaybackRecording(_ recording: SavedRecording) {
        stopPlayback()
        resetPlayerPresentation()
        selectedPlaybackRecording = recording
        errorMessage = nil
    }

    func selectPlayerMode(_ mode: PlayerMode) {
        guard canChangePlayerMode else { return }
        guard selectedPlayerMode != mode else { return }

        stopPlayback()
        resetPlayerPresentation()
        selectedPlayerMode = mode
        playerHasPlayedSelection = false
        errorMessage = nil
    }

    func playSelectedMessage() {
        guard let recording = selectedPlaybackRecording else { return }

        stopPlayback()
        resetPlayerPresentation()
        errorMessage = nil
        playerHasPlayedSelection = true

        let mode = selectedPlayerMode

        if mode == .text {
            playerShowsPlainText = true
            playbackState = .finished
            return
        }

        isPreparingPlayerPlayback = true

        Task {
            do {
                let audioFileURL = try self.savedRecordingStore.audioFileURL(for: recording)
                if mode.playsHaptics {
                    await self.hapticService.prepareSpeechHaptics(for: audioFileURL)
                }

                await MainActor.run {
                    self.beginPlayback(for: recording, audioFileURL: audioFileURL, mode: mode)
                }
            } catch {
                await MainActor.run {
                    self.isPreparingPlayerPlayback = false
                    self.present(error)
                }
            }
        }
    }

    func replay() {
        playSelectedMessage()
    }

    func toggleAudioMuted() {
        isAudioMuted.toggle()
        audioPlaybackService.setMuted(isAudioMuted)
    }

    func startNewRecordingFlow() {
        clearCurrentDraft(deleteAudioFile: true)
        clearProcessedPreview()
        showsPostSaveActions = false
        stopPlayback()
        section = .recorder
    }

    func playbackStatusText() -> String {
        switch playbackState {
        case .idle:
            return "Ready to play."
        case .ready:
            return "Playback prepared."
        case .playing:
            return "Revealing words with original speech timing."
        case .finished:
            return "Playback finished."
        }
    }

    private func beginPlayback(for recording: SavedRecording, audioFileURL: URL, mode: PlayerMode) {
        let tokens = recording.tokens
        playbackEngine.load(tokens: tokens)

        let leadTime = 0.1

        do {
            if mode.playsAudio {
                try audioPlaybackService.playAudio(from: audioFileURL, muted: false, after: leadTime)
            }

            if mode.playsHaptics {
                hapticService.startSpeechHaptics(after: leadTime)
            }

            if mode.playsAudio {
                playbackEngine.start(synchronizedTo: audioPlaybackService)
            } else {
                let duration = max(tokens.last?.endTime ?? 0, 0.01)
                timelinePlaybackService.start(duration: duration, after: leadTime)
                playbackEngine.start(synchronizedTo: timelinePlaybackService)
            }

            isPreparingPlayerPlayback = false
        } catch {
            isPreparingPlayerPlayback = false
            hapticService.stop()
            present(error)
        }
    }

    private func stopPlayback() {
        isPreparingPlayerPlayback = false
        hapticService.stop()
        audioPlaybackService.stop()
        timelinePlaybackService.stop()
        playbackEngine.stop()
        visibleTokens = []
        playbackState = .idle
    }

    private func resetPlayerPresentation() {
        playerShowsPlainText = false
        visibleTokens = []
    }

    private func clearCurrentDraft(deleteAudioFile: Bool) {
        guard let draftRecordingURL else { return }

        if deleteAudioFile {
            deleteFileIfNeeded(at: draftRecordingURL)
        }

        self.draftRecordingURL = nil
        draftTitle = ""
        isRecording = false
    }

    private func clearProcessedPreview() {
        transcriptionText = ""
    }

    private func resolvedDraftTitle() -> String {
        let trimmedTitle = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedTitle.isEmpty ? makeDefaultRecordingTitle() : trimmedTitle
    }

    private func makeDefaultRecordingTitle() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "audio-\(formatter.string(from: Date()))-\(UUID().uuidString.prefix(4))"
    }

    private func loadSavedRecordings() {
        do {
            savedRecordings = try savedRecordingStore.fetchAll()
            lastSavedRecording = savedRecordings.first

            if let selectedPlaybackRecording {
                self.selectedPlaybackRecording = savedRecordings.first(where: { $0.id == selectedPlaybackRecording.id }) ?? savedRecordings.first
            } else {
                selectedPlaybackRecording = savedRecordings.first
            }
        } catch {
            if savedRecordings.isEmpty, let lastSavedRecording {
                savedRecordings = [lastSavedRecording]
            }

            if selectedPlaybackRecording == nil {
                selectedPlaybackRecording = lastSavedRecording
            }
        }
    }

    private func mergedRecordings(including savedRecording: SavedRecording, preferredOrder fetchedRecordings: [SavedRecording]) -> [SavedRecording] {
        var merged = fetchedRecordings.filter { $0.id != savedRecording.id }
        merged.insert(savedRecording, at: 0)
        return merged.sorted { $0.createdAt > $1.createdAt }
    }

    private func present(_ error: Error) {
        errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        isRecording = false
        isPreparingPlayerPlayback = false
    }

    private func deleteFileIfNeeded(at url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
