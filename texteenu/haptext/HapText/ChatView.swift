import Combine
import SwiftUI
#if os(iOS)
import UIKit
#endif

private extension Animation {
    static var hapComposerSpring: Animation {
        .spring(response: 0.24, dampingFraction: 0.88, blendDuration: 0.02)
    }

    static var hapMessageSpring: Animation {
        .spring(response: 0.28, dampingFraction: 0.84, blendDuration: 0.02)
    }
}

struct ChatView: View {
    @EnvironmentObject private var store: ChatStore
    @Environment(\.dismiss) private var dismiss

    let route: ChatRoute

    @State private var activeViewer: ChatEndpoint
    @StateObject private var recorder = AudioCaptureController()
    @StateObject private var playback = AudioPlaybackController()
    @StateObject private var hapTextPlayback = HapTextMessagePlaybackController()
    @StateObject private var keyboard = KeyboardState()
    @State private var draftText = ""
    @State private var pendingFeedback: PendingFeedback?
    @State private var customFeedbackAnswer = ""
    @State private var chatGlobalMinY: CGFloat = 0
    @State private var fixedHeaderBaselineY: CGFloat?

    init(route: ChatRoute) {
        self.route = route
        _activeViewer = State(initialValue: route.user)
    }

    private var messages: [ChatMessage] {
        store.messages.sorted { $0.date < $1.date }
    }

    private var activeContact: ChatEndpoint {
        activeViewer == route.user ? route.contact : route.user
    }

    private var transcriptTop: CGFloat {
        0
    }

    private var transcriptBottom: CGFloat {
        874
    }

    private var textComposerTop: CGFloat {
        guard keyboardLift > 0 else {
            return textComposerDefaultTop
        }

        let liftedTop = 874 - keyboardLift - textComposerHeight - keyboardComposerClearance
        return max(164, liftedTop)
    }

    private var keyboardComposerClearance: CGFloat {
        #if os(iOS)
        keyboard.height > 380 ? 10 : 6
        #else
        0
        #endif
    }

    private var textComposerDefaultTop: CGFloat {
        isDraftExpanded ? 772 : 800
    }

    private var textComposerHeight: CGFloat {
        isDraftExpanded ? 77 : 49
    }

    private var restingComposerBottom: CGFloat {
        textComposerDefaultTop + textComposerHeight
    }

    private var recordingComposerHeight: CGFloat {
        128
    }

    private var recordingComposerTop: CGFloat {
        restingComposerBottom - recordingComposerHeight
    }

    private var isDraftExpanded: Bool {
        draftText.count > 44 || draftText.contains("\n")
    }

    private var keyboardLift: CGFloat {
        #if os(iOS)
        guard keyboard.height > 0 else { return 0 }

        let screenHeight = max(keyboard.screenHeight, 1)
        return min((keyboard.height / screenHeight) * 874, 344)
        #else
        return 0
        #endif
    }

    private var fixedHeaderCompensation: CGFloat {
        guard let fixedHeaderBaselineY else { return 0 }
        let compensation = fixedHeaderBaselineY - chatGlobalMinY
        return compensation.isFinite ? compensation : 0
    }

    private var transcriptInputClearance: CGFloat {
        12
    }

    var body: some View {
        FigmaPhoneFrame {
            ZStack(alignment: .topLeading) {
                chatInteractionLayer

                ChatHeaderFadeView()
                    .offset(y: fixedHeaderCompensation)
                    .animation(nil, value: keyboardLift)
                    .animation(nil, value: fixedHeaderCompensation)
                    .transaction { transaction in transaction.animation = nil }
                    .zIndex(1)

                ChatHeaderView(
                    contact: activeContact,
                    onBack: { dismiss() },
                    onToggleViewer: switchViewer
                )
                .offset(y: fixedHeaderCompensation)
                .animation(nil, value: keyboardLift)
                .animation(nil, value: fixedHeaderCompensation)
                .animation(nil, value: recorder.isRecording)
                .animation(nil, value: isDraftExpanded)
                .transaction { transaction in transaction.animation = nil }
                .zIndex(10)
            }
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: ChatGlobalMinYPreferenceKey.self,
                        value: proxy.frame(in: .global).minY
                    )
                }
            )
            .simultaneousGesture(backSwipeGesture)
        }
        .onPreferenceChange(ChatGlobalMinYPreferenceKey.self) { minY in
            chatGlobalMinY = minY

            if fixedHeaderBaselineY == nil {
                fixedHeaderBaselineY = minY
            }
        }
        .ignoresSafeArea()
        #if os(iOS)
        .ignoresSafeArea(.keyboard, edges: .all)
        #endif
        .navigationTitle("")
        #if os(iOS)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        #endif
        .onAppear {
            store.openConversation(between: route.user, and: route.contact)
        }
    }

    @ViewBuilder
    private var chatInteractionLayer: some View {
        TranscriptView(
            messages: messages,
            viewer: activeViewer,
            playback: playback,
            hapTextPlayback: hapTextPlayback,
            bottomContentInset: bottomTranscriptInset
        )
        .frame(width: 384, height: transcriptBottom - transcriptTop)
        .position(x: 201, y: transcriptTop + (transcriptBottom - transcriptTop) / 2)
        .zIndex(0)

        if recorder.isRecording {
            RecordingComposerView(
                recorder: recorder,
                composerTop: recordingComposerTop,
                onCancel: {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        recorder.cancel()
                    }
                },
                onSend: sendRecording
            )
            .zIndex(3)
        } else {
            TextComposerView(
                draftText: $draftText,
                composerTop: textComposerTop,
                onSendText: sendText,
                onStartRecording: {
                    Task {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            draftText = ""
                        }
                        await recorder.start()
                    }
                }
            )
            .zIndex(3)
        }

        if let pendingFeedback {
            FeedbackOverlayView(
                pendingFeedback: pendingFeedback,
                focusedMessage: feedbackMessage,
                viewer: activeViewer,
                playback: playback,
                hapTextPlayback: hapTextPlayback,
                customAnswer: $customFeedbackAnswer,
                keyboardLift: keyboardLift,
                onSelectSentiment: selectSentiment,
                onComplete: completeFeedback
            )
            .zIndex(4)
        }
    }

    private var feedbackMessage: ChatMessage? {
        guard let pendingFeedback else { return nil }
        return messages.first { $0.id == pendingFeedback.messageID }
    }

    private var bottomTranscriptInset: CGFloat {
        let composerTop = recorder.isRecording ? recordingComposerTop : textComposerTop
        return max(0, transcriptBottom - composerTop + transcriptInputClearance)
    }

    private var backSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 24, coordinateSpace: .local)
            .onEnded { value in
                let startsAtEdge = value.startLocation.x <= 38
                let movesRight = value.translation.width > 86
                let mostlyHorizontal = abs(value.translation.width) > abs(value.translation.height) * 1.4

                guard startsAtEdge, movesRight, mostlyHorizontal else { return }
                dismiss()
            }
    }

    private func switchViewer() {
        playback.stop()
        hapTextPlayback.stop()

        withAnimation(.easeInOut(duration: 0.18)) {
            activeViewer = activeContact
        }
    }

    private func sendText() {
        let text = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.isEmpty == false else { return }

        var resetTransaction = Transaction()
        resetTransaction.animation = nil
        withTransaction(resetTransaction) {
            draftText = ""
        }

        withAnimation(.hapMessageSpring) {
            store.sendText(from: activeViewer, to: activeContact, text: text)
        }
    }

    private func sendRecording() {
        do {
            let recording = try recorder.send()

            let message = withAnimation(.hapMessageSpring) {
                store.sendAudio(
                    from: activeViewer,
                    to: activeContact,
                    recording: recording,
                    isVisibleToReceiver: false
                )
            }

            withAnimation(.easeInOut(duration: 0.18)) {
                customFeedbackAnswer = ""
                pendingFeedback = PendingFeedback(messageID: message.id, step: .sentiment)
            }
        } catch {
            recorder.errorMessage = error.localizedDescription
        }
    }

    private func selectSentiment(_ sentiment: AudioSentiment) {
        guard var pendingFeedback else { return }

        withAnimation(.easeInOut(duration: 0.18)) {
            pendingFeedback.step = .detail(sentiment)
            self.pendingFeedback = pendingFeedback
        }
    }

    private func completeFeedback(_ survey: AudioSurvey) {
        guard let pendingFeedback else { return }
        let messageID = pendingFeedback.messageID
        let clip = store.audioClip(for: messageID)

        store.updateSurvey(for: messageID, survey: survey)
        withAnimation(.easeInOut(duration: 0.18)) {
            self.pendingFeedback = nil
        }

        guard let clip else { return }

        Task {
            let transcription = await hapTextPlayback.transcribeForDelivery(
                fileURL: clip.fileURL,
                duration: clip.duration
            )

            withAnimation(.hapMessageSpring) {
                store.deliverAudio(messageID: messageID, transcription: transcription)
            }
        }
    }
}

private struct ChatGlobalMinYPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct ChatHeaderFadeView: View {
    var body: some View {
        LinearGradient(
            stops: [
                .init(color: .white, location: 0),
                .init(color: .white.opacity(0.98), location: 0.42),
                .init(color: .white.opacity(0.62), location: 0.72),
                .init(color: .white.opacity(0), location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(width: 402, height: 178, alignment: .top)
        .allowsHitTesting(false)
    }
}

private struct PendingFeedback: Equatable {
    let messageID: UUID
    var step: FeedbackStep
}

private enum FeedbackStep: Equatable {
    case sentiment
    case detail(AudioSentiment)
}

private struct ChatHeaderView: View {
    let contact: ChatEndpoint
    let onBack: () -> Void
    let onToggleViewer: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            Button(action: onToggleViewer) {
                ProfileAvatarView(user: contact, size: 60)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .position(x: 201, y: 92)
            .accessibilityLabel("Switch chat")

            Button(action: onToggleViewer) {
                Text(contact.displayName)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.black)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(width: 80, height: 33)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 16.5, style: .continuous))
                    .shadow(color: Color.black.opacity(0.25), radius: 2, x: 0, y: 4)
                    .contentShape(RoundedRectangle(cornerRadius: 16.5, style: .continuous))
            }
            .buttonStyle(.plain)
            .position(x: 201, y: 132.5)
            .accessibilityLabel("Switch chat")

            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(Color.hapBlue)
                    .frame(width: 54, height: 54)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .position(x: 32, y: 64)
            .accessibilityLabel("Back")
        }
        .frame(width: 402, height: 874, alignment: .topLeading)
    }
}

private struct TranscriptView: View {
    let messages: [ChatMessage]
    let viewer: ChatEndpoint
    @ObservedObject var playback: AudioPlaybackController
    @ObservedObject var hapTextPlayback: HapTextMessagePlaybackController
    let bottomContentInset: CGFloat

    @GestureState private var timestampRevealOffset: CGFloat = 0
    @State private var suppressPlaybackAutoPinUntil = Date.distantPast

    private let bottomAnchorID = "TranscriptBottomAnchor"
    private let scrollSettlingDelays: [TimeInterval] = [0, 0.05, 0.18, 0.34]

    private var latestMessageLayoutKey: String {
        guard let message = messages.last else { return "empty" }

        var parts = [
            message.id.uuidString,
            message.sender.rawValue,
            message.recipient.rawValue,
            String(message.isVisibleToReceiver)
        ]

        switch message.content {
        case .text(let text):
            parts.append("text")
            parts.append(String(text.count))
            parts.append(text)
        case .audio(let clip):
            parts.append("audio")
            parts.append(String(format: "%.2f", clip.duration))
            parts.append(String(clip.samples.count))
            parts.append(clip.transcription?.fullText ?? "")
            parts.append(clip.survey?.sentiment.rawValue ?? "")
            parts.append(clip.survey?.detail ?? "")
        }

        return parts.joined(separator: "|")
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                            let showsTail = shouldShowTail(at: index)

                            if shouldShowDateDivider(at: index) {
                                MessageDateDivider(date: message.date)
                                    .padding(.bottom, 22)
                            }

                            MessageBubbleRow(
                                message: message,
                                viewer: viewer,
                                playback: playback,
                                hapTextPlayback: hapTextPlayback,
                                showsTail: showsTail,
                                timestampRevealOffset: timestampRevealOffset
                            )
                            .padding(.bottom, showsTail ? 5 : 0)
                            .transition(messageInsertionTransition(for: message))
                            .id(message.id)
                        }

                        Color.clear
                            .frame(height: bottomContentInset)
                            .id(bottomAnchorID)
                    }
                    .frame(maxWidth: .infinity, minHeight: geometry.size.height, alignment: .bottom)
                    .padding(.horizontal, 5)
                }
                .defaultScrollAnchor(.bottom)
                .scrollIndicators(.hidden)
                #if os(iOS)
                .scrollDismissesKeyboard(.interactively)
                #endif
                .simultaneousGesture(userScrollTrackingDrag)
                .simultaneousGesture(timestampRevealDrag)
                .onAppear {
                    pinLatestMessageAboveComposer(proxy)
                }
                .onChange(of: latestMessageLayoutKey) { _, _ in
                    pinLatestMessageAboveComposer(proxy)
                }
                .onChange(of: bottomContentInset) { _, _ in
                    pinLatestMessageAboveComposer(proxy)
                }
                .onChange(of: viewer) { _, _ in
                    pinLatestMessageAboveComposer(proxy)
                }
                .onReceive(hapTextPlayback.objectWillChange) { _ in
                    keepPlaybackBubbleAnchored(proxy)
                }
            }
        }
    }

    private func shouldShowDateDivider(at index: Int) -> Bool {
        guard messages.indices.contains(index) else { return false }
        guard index > 0 else { return true }

        return Calendar.current.isDate(messages[index].date, inSameDayAs: messages[index - 1].date) == false
    }

    private func shouldShowTail(at index: Int) -> Bool {
        guard messages.indices.contains(index) else { return false }
        guard messages.indices.contains(index + 1) else { return true }

        let current = messages[index]
        let next = messages[index + 1]
        let sameSender = current.sender == next.sender
        let sameDay = Calendar.current.isDate(current.date, inSameDayAs: next.date)
        return sameSender == false || sameDay == false
    }

    private func messageInsertionTransition(for message: ChatMessage) -> AnyTransition {
        let anchor: UnitPoint = message.sender == viewer ? .bottomTrailing : .bottomLeading

        return .asymmetric(
            insertion: .opacity
                .combined(with: .scale(scale: 0.96, anchor: anchor))
                .combined(with: .offset(x: 0, y: 12)),
            removal: .opacity
        )
    }

    private func pinLatestMessageAboveComposer(_ proxy: ScrollViewProxy) {
        for delay in scrollSettlingDelays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                proxy.scrollTo(bottomAnchorID, anchor: .bottom)
            }
        }
    }

    private func keepPlaybackBubbleAnchored(_ proxy: ScrollViewProxy) {
        guard suppressPlaybackAutoPinUntil <= Date() else { return }

        DispatchQueue.main.async {
            guard let activeID = hapTextPlayback.activePlaybackMessageID else { return }
            proxy.scrollTo(activeID, anchor: .bottom)
        }
    }

    private var userScrollTrackingDrag: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .local)
            .onChanged { value in
                guard isMostlyVertical(value.translation) else { return }
                suppressPlaybackAutoPinUntil = Date().addingTimeInterval(1.4)
            }
            .onEnded { value in
                guard isMostlyVertical(value.translation) else { return }
                suppressPlaybackAutoPinUntil = Date().addingTimeInterval(1.4)
            }
    }

    private var timestampRevealDrag: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .local)
            .updating($timestampRevealOffset) { value, state, _ in
                let horizontalDistance = -value.translation.width
                let isMovingLeft = horizontalDistance > 0
                let isMostlyHorizontal = horizontalDistance > abs(value.translation.height) * 1.15

                guard isMovingLeft, isMostlyHorizontal else {
                    state = 0
                    return
                }

                state = min(horizontalDistance, 78)
            }
    }

    private func isMostlyVertical(_ translation: CGSize) -> Bool {
        abs(translation.height) > abs(translation.width) * 1.2
    }
}

private struct MessageDateDivider: View {
    let date: Date

    var body: some View {
        Text(Self.formatter.string(from: date))
            .font(.system(size: 12.8, weight: .medium))
            .foregroundStyle(Color.hapDate)
            .frame(width: 120, height: 15)
            .frame(maxWidth: .infinity)
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, MMM d"
        return formatter
    }()
}

private struct MessageBubbleRow: View {
    let message: ChatMessage
    let viewer: ChatEndpoint
    @ObservedObject var playback: AudioPlaybackController
    @ObservedObject var hapTextPlayback: HapTextMessagePlaybackController
    let showsTail: Bool
    let timestampRevealOffset: CGFloat

    private var isOutgoing: Bool {
        message.sender == viewer
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            MessageTimestampLabel(date: message.date, revealOffset: timestampRevealOffset)

            HStack(alignment: .bottom, spacing: 0) {
                if isOutgoing {
                    Spacer(minLength: 0)
                }

                switch message.content {
                case .text(let text):
                    TextMessageBubble(text: text, isOutgoing: isOutgoing, showsTail: showsTail)
                case .audio(let clip):
                    AudioMessageBubble(
                        id: message.id,
                        clip: clip,
                        isOutgoing: isOutgoing,
                        playback: playback,
                        hapTextPlayback: hapTextPlayback,
                        showsTail: showsTail
                    )
                }

                if isOutgoing == false {
                    Spacer(minLength: 0)
                }
            }
            .offset(x: -timestampRevealOffset)
        }
        .frame(width: 374)
        .animation(.hapMessageSpring, value: timestampRevealOffset)
    }
}

private struct MessageTimestampLabel: View {
    let date: Date
    let revealOffset: CGFloat

    var body: some View {
        Text(Self.formatter.string(from: date))
            .font(.system(size: 13, weight: .regular))
            .foregroundStyle(Color.hapDate)
            .monospacedDigit()
            .lineLimit(1)
            .frame(width: 68, alignment: .trailing)
            .opacity(timestampOpacity)
            .accessibilityHidden(revealOffset == 0)
    }

    private var timestampOpacity: Double {
        Double(min(max((revealOffset - 16) / 38, 0), 1))
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "h:mm a"
        return formatter
    }()
}

private struct TextMessageBubble: View {
    let text: String
    let isOutgoing: Bool
    let showsTail: Bool

    var body: some View {
        ZStack(alignment: tailAlignment) {
            if showsTail {
                BubbleTail(isOutgoing: isOutgoing, isVisible: showsTail)
                    .zIndex(0)
            }

            Text(text)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(isOutgoing ? .white : .black)
                .lineSpacing(0)
                .fixedSize(horizontal: isCompact, vertical: true)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .frame(width: bubbleWidth, alignment: .leading)
                .background(isOutgoing ? Color.hapBubbleBlue : Color.hapGrayBubble)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .zIndex(1)
        }
    }

    private var maximumWidth: CGFloat {
        isOutgoing ? 291 : 292
    }

    private var bubbleWidth: CGFloat? {
        if isCompact {
            return nil
        }

        if text.count <= 86, text.contains("\n") == false {
            return min(maximumWidth, max(176, estimatedSingleLineWidth))
        }

        return maximumWidth
    }

    private var estimatedSingleLineWidth: CGFloat {
        let visibleCharacters = CGFloat(text.count)
        let estimatedTextWidth = visibleCharacters * 8.7
        return estimatedTextWidth + 32
    }

    private var isCompact: Bool {
        text.count <= 30 && text.contains("\n") == false
    }

    private var tailAlignment: Alignment {
        isOutgoing ? .bottomTrailing : .bottomLeading
    }
}

private struct BubbleTail: View {
    let isOutgoing: Bool
    let isVisible: Bool

    var body: some View {
        if isVisible {
            BundlePNGImage(name: isOutgoing ? "blue_tail" : "gray_tail")
                .scaledToFit()
                .frame(width: 20, height: 14)
                .offset(x: isOutgoing ? 3.2 : -3.2, y: 0.8)
                .allowsHitTesting(false)
        }
    }
}

private struct FloatingSendIcon: View {
    var size: CGFloat

    var body: some View {
        Circle()
            .fill(Color.white)
            .frame(width: size, height: size)
            .shadow(color: Color.hapShadow, radius: 4.8, x: 0, y: 0)
            .overlay {
                AssetIcon(name: "send", size: size)
            }
    }
}

private struct AudioMessageBubble: View {
    let id: UUID
    let clip: AudioClip
    let isOutgoing: Bool
    @ObservedObject var playback: AudioPlaybackController
    @ObservedObject var hapTextPlayback: HapTextMessagePlaybackController
    let showsTail: Bool

    private var isPlaying: Bool {
        playback.playingMessageID == id
    }

    var body: some View {
        if isOutgoing == false, clip.transcription != nil {
            ReceivedHapTextAudioBubble(
                id: id,
                clip: clip,
                controller: hapTextPlayback,
                onStartPlayback: {
                    playback.stop()
                },
                showsTail: showsTail
            )
        } else {
            waveformBubble
        }
    }

    private var waveformBubble: some View {
        ZStack(alignment: isOutgoing ? .bottomTrailing : .bottomLeading) {
            if showsTail {
                BubbleTail(isOutgoing: isOutgoing, isVisible: showsTail)
                    .zIndex(0)
            }

            Button {
                hapTextPlayback.stop()
                playback.toggle(messageID: id, url: clip.fileURL)
            } label: {
                HStack(spacing: 11) {
                    AssetIcon(name: playbackIconName, size: 31)
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())

                    AudioProgressWaveform(
                        samples: AudioWaveformExtractor.resampled(clip.samples, targetSampleCount: 42),
                        color: isOutgoing ? Color.white.opacity(0.9) : Color.hapBubbleBlue,
                        indicatorColor: isOutgoing ? .white : Color.hapBubbleBlue,
                        progress: playback.progress(for: id, duration: clip.duration),
                        isScrubbable: isPlaying,
                        onSeek: { progress in
                            playback.seek(messageID: id, duration: clip.duration, to: progress)
                        }
                    )
                    .frame(width: 166, height: 42)

                    Text(durationString)
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(isOutgoing ? .white : .black)
                        .frame(width: 46, height: 42, alignment: .center)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .frame(width: 291, height: 60)
                .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isPlaying ? "Pause audio" : "Play audio")
            .background(isOutgoing ? Color.hapBubbleBlue : Color.hapGrayBubble)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .zIndex(1)
        }
    }

    private var durationString: String {
        let seconds = max(Int(clip.duration.rounded()), 1)
        return "0:\(String(format: "%02d", seconds))"
    }

    private var playbackIconName: String {
        if isPlaying {
            return isOutgoing ? "pause_white" : "pause"
        }

        return isOutgoing ? "white_play" : "play"
    }
}

private struct AudioProgressWaveform: View {
    let samples: [Double]
    let color: Color
    let indicatorColor: Color
    let progress: Double
    let isScrubbable: Bool
    let onSeek: (Double) -> Void

    var body: some View {
        GeometryReader { proxy in
            let markerSize: CGFloat = 11
            let width = max(proxy.size.width, markerSize)
            let markerX = min(max(CGFloat(progress) * width, markerSize / 2), width - markerSize / 2)

            applyScrubbing(
                to: ZStack(alignment: .leading) {
                    WaveformView(samples: samples, color: color)

                    if isScrubbable {
                        Circle()
                            .fill(indicatorColor)
                            .frame(width: markerSize, height: markerSize)
                            .overlay {
                                Circle()
                                    .stroke(Color.white.opacity(0.72), lineWidth: 1.2)
                            }
                            .shadow(color: Color.black.opacity(0.18), radius: 1.4, x: 0, y: 0.6)
                            .position(x: markerX, y: proxy.size.height / 2)
                    }
                }
                .contentShape(Rectangle()),
                width: width
            )
        }
    }

    @ViewBuilder
    private func applyScrubbing<Content: View>(to content: Content, width: CGFloat) -> some View {
        if isScrubbable {
            content.highPriorityGesture(scrubGesture(width: width))
        } else {
            content
        }
    }

    private func scrubGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                onSeek(Double(min(max(value.location.x / max(width, 1), 0), 1)))
            }
    }
}

private struct ReceivedHapTextAudioBubble: View {
    let id: UUID
    let clip: AudioClip
    @ObservedObject var controller: HapTextMessagePlaybackController
    let onStartPlayback: () -> Void
    let showsTail: Bool

    private var presentation: HapTextMessagePresentation {
        controller.presentation(for: id, duration: clip.duration)
    }

    private var hasTranscript: Bool {
        guard presentation.status == .playing || presentation.status == .finished else {
            return false
        }

        return presentation.tokens.isEmpty == false || presentation.fullText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    private var topIconName: String {
        presentation.status == .playing ? "pause" : "play"
    }

    private var topLabel: String? {
        switch presentation.status {
        case .ready:
            return "Play message"
        case .preparing:
            return "Preparing..."
        case .playing:
            return nil
        case .finished:
            return "Replay message"
        }
    }

    private var displayedDuration: TimeInterval {
        presentation.status == .playing ? presentation.elapsed : clip.duration
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if showsTail {
                BubbleTail(isOutgoing: false, isVisible: showsTail)
                    .zIndex(0)
            }

            Button {
                guard presentation.status != .preparing else { return }
                if presentation.status != .playing {
                    onStartPlayback()
                }
                controller.togglePlayback(messageID: id, clip: clip)
            } label: {
                VStack(alignment: .leading, spacing: hasTranscript ? 7 : 0) {
                    playbackControls

                    if hasTranscript {
                        transcriptContent
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, hasTranscript ? 10 : 9)
                .frame(width: 291, alignment: .leading)
                .background(Color.hapGrayBubble)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(presentation.status == .preparing)
            .zIndex(1)
        }
        .onAppear {
            controller.prepareIfNeeded(messageID: id, clip: clip)
        }
        .animation(.hapMessageSpring, value: presentation.status)
        .animation(.hapMessageSpring, value: presentation.visibleTokens.count)
        .animation(.easeOut(duration: 0.14), value: presentation.currentTokenID)
    }

    private var playbackControls: some View {
        HStack(spacing: 11) {
            TintedAssetIcon(name: topIconName, color: Color.hapDate, size: 31)
                .frame(width: 44, height: 44)

            if let topLabel {
                Text(topLabel)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.hapDate)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }

            Spacer(minLength: 8)

            Text(durationString(displayedDuration))
                .font(.system(size: 17, weight: .regular))
                .monospacedDigit()
                .foregroundStyle(Color.hapDate)
                .frame(width: 46, height: 42, alignment: .center)
        }
        .frame(width: 263, height: 42, alignment: .center)
    }

    @ViewBuilder
    private var transcriptContent: some View {
        if presentation.status == .playing {
            VStack(alignment: .leading, spacing: 0) {
                if previousPlaybackText.isEmpty == false {
                    Text(previousPlaybackText)
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(Color.hapDate)
                        .lineLimit(nil)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(width: 263, alignment: .leading)
                }

                Text(currentPlaybackText.isEmpty ? " " : currentPlaybackText)
                    .font(.system(size: 32, weight: .regular))
                    .foregroundStyle(.black)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .frame(width: 263, alignment: .leading)
                    .frame(minHeight: 34, alignment: .leading)
                    .opacity(currentPlaybackText.isEmpty ? 0 : 1)
            }
            .frame(width: 263, alignment: .bottomLeading)
            .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .bottomLeading)))
        } else {
            Text(finishedTranscriptText)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(.black)
                .multilineTextAlignment(.leading)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 263, alignment: .leading)
                .frame(minHeight: 34, alignment: .leading)
                .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .bottomLeading)))
        }
    }

    private var previousPlaybackText: String {
        let tokens = presentation.visibleTokens.dropLast()
        return tokens.map(\.text).joined(separator: " ")
    }

    private var currentPlaybackText: String {
        presentation.visibleTokens.last?.text ?? ""
    }

    private var finishedTranscriptText: String {
        let fullText = presentation.fullText.trimmingCharacters(in: .whitespacesAndNewlines)
        if fullText.isEmpty == false {
            return fullText
        }

        return presentation.tokens.map(\.text).joined(separator: " ")
    }

    private func durationString(_ duration: TimeInterval) -> String {
        let seconds = max(Int(duration.rounded(.down)), 0)
        return "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }
}

private struct TextComposerView: View {
    @Binding var draftText: String
    let composerTop: CGFloat
    let onSendText: () -> Void
    let onStartRecording: () -> Void

    private var hasText: Bool {
        draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    private var isExpanded: Bool {
        draftText.count > 44 || draftText.contains("\n")
    }

    private var composerHeight: CGFloat {
        isExpanded ? 77 : 49
    }

    private var composerCornerRadius: CGFloat {
        isExpanded ? 27 : 42
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            TextField("Message", text: $draftText, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(.black)
                .lineLimit(isExpanded ? 1...3 : 1...1)
                .padding(.horizontal, 13)
                .padding(.vertical, isExpanded ? 10 : 0)
                .frame(width: 309, height: composerHeight, alignment: isExpanded ? .topLeading : .center)
                .background(Color.white, in: RoundedRectangle(cornerRadius: composerCornerRadius, style: .continuous))
                .shadow(color: Color.hapShadow, radius: 4.8, x: 0, y: 0)
                .submitLabel(.send)
                .onSubmit {
                    guard hasText else { return }
                    onSendText()
                }

            if hasText {
                Button(action: onSendText) {
                    FloatingSendIcon(size: 49)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .position(x: 343.5, y: composerHeight - 24.5)
                .transition(.scale(scale: 0.82, anchor: .center).combined(with: .opacity))
                .accessibilityLabel("Send message")
            } else {
                Button(action: onStartRecording) {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 49, height: 49)
                        .shadow(color: Color.hapShadow, radius: 4.8, x: 0, y: 0)
                        .overlay {
                            AssetIcon(name: "microphone", size: 39.2)
                        }
                }
                .buttonStyle(.plain)
                .position(x: 343.5, y: 24.5)
                .transition(.scale(scale: 0.82, anchor: .center).combined(with: .opacity))
                .accessibilityLabel("Record audio")
            }
        }
        .frame(width: 368, height: composerHeight, alignment: .topLeading)
        .position(x: 201, y: composerTop + composerHeight / 2)
        .animation(.hapComposerSpring, value: isExpanded)
        .animation(.hapComposerSpring, value: hasText)
    }
}

private struct RecordingComposerView: View {
    @ObservedObject var recorder: AudioCaptureController
    let composerTop: CGFloat
    let onCancel: () -> Void
    let onSend: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 41, style: .continuous)
                .fill(Color.white)
                .shadow(color: Color.hapShadow, radius: 4.8, x: 0, y: 0)
                .frame(width: 384, height: 128)

            WaveformView(
                samples: recorder.currentSamples,
                color: Color.hapBlue
            )
            .frame(width: 339, height: 42.751)
            .position(x: 192, y: 39)

            Button(action: onCancel) {
                AssetIcon(name: "trash", size: 35)
                    .frame(width: 35, height: 35)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .position(x: 48.5, y: 90.375)
            .accessibilityLabel("Cancel recording")

            Text(durationString)
                .font(.system(size: 17, weight: .regular))
                .monospacedDigit()
                .foregroundStyle(.black)
                .frame(width: 80, height: 24)
                .position(x: 192, y: 90.375)

            Button(action: onSend) {
                AssetIcon(name: "send", size: 40)
                    .frame(width: 40, height: 40)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .position(x: 333, y: 90.375)
            .accessibilityLabel("Send recording")
        }
        .frame(width: 384, height: 128, alignment: .topLeading)
        .position(x: 201, y: composerTop + 64)
        .transition(.scale(scale: 0.84, anchor: .bottom).combined(with: .opacity))
    }

    private var durationString: String {
        let seconds = max(Int(recorder.elapsed.rounded(.down)), 0)
        return "0:\(String(format: "%02d", seconds))"
    }
}

private struct FeedbackOverlayView: View {
    let pendingFeedback: PendingFeedback
    let focusedMessage: ChatMessage?
    let viewer: ChatEndpoint
    @ObservedObject var playback: AudioPlaybackController
    @ObservedObject var hapTextPlayback: HapTextMessagePlaybackController
    @Binding var customAnswer: String
    let keyboardLift: CGFloat
    let onSelectSentiment: (AudioSentiment) -> Void
    let onComplete: (AudioSurvey) -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color.white.opacity(0.5))
                .background(.ultraThinMaterial)
                .frame(width: 402, height: 874)
                .allowsHitTesting(false)

            if let focusedMessage {
                MessageBubbleRow(
                    message: focusedMessage,
                    viewer: viewer,
                    playback: playback,
                    hapTextPlayback: hapTextPlayback,
                    showsTail: true,
                    timestampRevealOffset: 0
                )
                .position(x: 201, y: focusedMessageY)
                .zIndex(1)
            }

            switch pendingFeedback.step {
            case .sentiment:
                SentimentCard(onSelectSentiment: onSelectSentiment)
                    .position(x: 201, y: sentimentCardY)
                    .zIndex(2)
            case .detail(let sentiment):
                DetailCard(
                    sentiment: sentiment,
                    customAnswer: $customAnswer,
                    onComplete: onComplete
                )
                .position(x: 201, y: detailCardY)
                .zIndex(2)
            }
        }
        .frame(width: 402, height: 874, alignment: .topLeading)
        .animation(.hapComposerSpring, value: keyboardLift)
    }

    private var restingBottom: CGFloat {
        849
    }

    private var sentimentCardHeight: CGFloat {
        232
    }

    private var detailCardHeight: CGFloat {
        346
    }

    private var sentimentCardY: CGFloat {
        restingBottom - sentimentCardHeight / 2
    }

    private var detailCardY: CGFloat {
        restingBottom - detailCardHeight / 2 - detailKeyboardOffset
    }

    private var detailKeyboardOffset: CGFloat {
        guard keyboardLift > 0 else { return 0 }
        return min(max(keyboardLift + 14, 0), 350)
    }

    private var focusedMessageY: CGFloat {
        let cardTop: CGFloat

        switch pendingFeedback.step {
        case .sentiment:
            cardTop = sentimentCardY - sentimentCardHeight / 2
        case .detail:
            cardTop = detailCardY - detailCardHeight / 2
        }

        return max(220, cardTop - 42)
    }
}

private struct SentimentCard: View {
    let onSelectSentiment: (AudioSentiment) -> Void

    var body: some View {
        VStack(spacing: 10) {
            Text("What emotion where you trying to communicate in this last message?")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.black)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 350)
                .frame(minHeight: 42)

            Text("Choose one option")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(Color.hapPlaceholder)
                .frame(width: 350, height: 19)

            FeedbackOptionButton(title: "Positive") {
                onSelectSentiment(.positive)
            }

            FeedbackOptionButton(title: "Negative") {
                onSelectSentiment(.negative)
            }
        }
        .padding(.horizontal, 17)
        .padding(.vertical, 17)
        .frame(width: 384, height: 232)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 41, style: .continuous))
        .shadow(color: Color.hapShadow, radius: 4.8, x: 0, y: 0)
    }
}

private struct DetailCard: View {
    let sentiment: AudioSentiment
    @Binding var customAnswer: String
    let onComplete: (AudioSurvey) -> Void

    @State private var isWritingCustom = false
    @FocusState private var isCustomAnswerFocused: Bool

    var body: some View {
        VStack(spacing: 10) {
            Text("More specifically, what type of emotion?")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.black)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 350)
                .frame(minHeight: 40)

            Text("Choose one option or write another")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(Color.hapPlaceholder)
                .frame(width: 350, height: 19)

            ForEach(sentiment.detailOptions, id: \.self) { option in
                FeedbackOptionButton(title: option) {
                    onComplete(AudioSurvey(sentiment: sentiment, detail: option))
                }
            }

            if isWritingCustom || customAnswer.isEmpty == false {
                HStack(spacing: 10) {
                    TextField("Personalized answer", text: $customAnswer)
                        .textFieldStyle(.plain)
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(.black)
                        .lineLimit(1)
                        .padding(.horizontal, 13)
                        .frame(width: 291, height: 49, alignment: .leading)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 42, style: .continuous))
                        .shadow(color: Color.hapShadow, radius: 4.8, x: 0, y: 0)
                        .submitLabel(.send)
                        .focused($isCustomAnswerFocused)
                        .onChange(of: customAnswer) { _, newValue in
                            let limited = limitedCustomAnswer(newValue)
                            guard limited != newValue else { return }
                            customAnswer = limited
                        }
                        .onSubmit(sendCustom)

                    Button(action: sendCustom) {
                        FloatingSendIcon(size: 49)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(customAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel("Send custom emotion")
                }
                .frame(width: 350, height: 49)
            } else {
                FeedbackOptionButton(title: "Personalized answer", fill: .white) {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isWritingCustom = true
                    }
                    focusCustomAnswer()
                }
            }
        }
        .padding(.horizontal, 17)
        .padding(.vertical, 17)
        .frame(width: 384, height: 346)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 41, style: .continuous))
        .shadow(color: Color.hapShadow, radius: 4.8, x: 0, y: 0)
        .onChange(of: isWritingCustom) { _, isWriting in
            guard isWriting else { return }
            focusCustomAnswer()
        }
    }

    private func sendCustom() {
        let trimmed = limitedCustomAnswer(customAnswer).trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }

        onComplete(AudioSurvey(sentiment: sentiment, detail: trimmed))
    }

    private func limitedCustomAnswer(_ value: String) -> String {
        let withoutLineBreaks = value.replacingOccurrences(of: "\n", with: " ")
        let words = withoutLineBreaks.split(whereSeparator: \.isWhitespace)

        guard words.count > 2 else {
            return withoutLineBreaks
        }

        return words.prefix(2).joined(separator: " ")
    }

    private func focusCustomAnswer() {
        DispatchQueue.main.async {
            isCustomAnswerFocused = true
        }
    }
}

private struct FeedbackOptionButton: View {
    let title: String
    var fill: Color = Color.hapOptionFill
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(.black)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: 350, height: 49)
                .background(fill, in: RoundedRectangle(cornerRadius: 42, style: .continuous))
                .shadow(color: Color.hapShadow, radius: 9.6, x: 0, y: 0)
        }
        .buttonStyle(.plain)
    }
}

@MainActor
private final class KeyboardState: ObservableObject {
    @Published var height: CGFloat = 0
    @Published var screenHeight: CGFloat = 874

    #if os(iOS)
    private var observers: [NSObjectProtocol] = []

    init() {
        let center = NotificationCenter.default

        observers.append(
            center.addObserver(
                forName: UIResponder.keyboardWillChangeFrameNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
                    return
                }

                let screenHeight = max(UIScreen.main.bounds.height, 1)
                let overlap = max(0, screenHeight - frame.minY)
                Task { @MainActor [weak self] in
                    self?.apply(height: overlap, screenHeight: screenHeight, from: notification)
                }
            }
        )

        observers.append(
            center.addObserver(
                forName: UIResponder.keyboardWillHideNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                Task { @MainActor [weak self] in
                    self?.apply(height: 0, screenHeight: max(UIScreen.main.bounds.height, 1), from: notification)
                }
            }
        )
    }

    private func apply(height: CGFloat, screenHeight: CGFloat, from notification: Notification) {
        let duration = (notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber)?.doubleValue ?? 0.22
        let animation = Self.keyboardAnimation(from: notification, duration: duration)

        if duration <= 0.02 {
            self.screenHeight = screenHeight
            self.height = height
        } else {
            withAnimation(animation) {
                self.screenHeight = screenHeight
                self.height = height
            }
        }
    }

    private static func keyboardAnimation(from notification: Notification, duration: Double) -> Animation {
        let rawCurve = (notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? NSNumber)?.intValue
        let curve = rawCurve.flatMap(UIView.AnimationCurve.init(rawValue:))

        switch curve {
        case .easeIn:
            return .easeIn(duration: duration)
        case .easeOut:
            return .easeOut(duration: duration)
        case .linear:
            return .linear(duration: duration)
        default:
            return .easeInOut(duration: duration)
        }
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }
    #else
    init() {}
    #endif
}
