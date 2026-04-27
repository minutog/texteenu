import Dispatch
import SwiftUI

struct PlayerView: View {
    private enum ScrollTarget: Hashable {
        case playbackBottom
    }

    @ObservedObject var viewModel: AppViewModel
    @State private var isFilesSheetPresented = false
    @State private var shouldAutoScrollPlaybackText = true

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    messageCanvas

                    Color.clear
                        .frame(height: 1)
                        .id(ScrollTarget.playbackBottom)

                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }

                    Spacer(minLength: 180)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(24)
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 12)
                    .onChanged(handleManualPlaybackScroll(_:))
            )
            .onAppear {
                shouldAutoScrollPlaybackText = true
                viewModel.refreshPlayerFiles()
            }
            .onChange(of: viewModel.visibleTokens.last?.id) { _ in
                autoScrollPlaybackText(with: proxy)
            }
            .onChange(of: viewModel.playbackState) { state in
                if state == .playing {
                    shouldAutoScrollPlaybackText = true
                    autoScrollPlaybackText(with: proxy, animated: false)
                } else if state == .idle || state == .ready {
                    shouldAutoScrollPlaybackText = true
                }
            }
            .onChange(of: viewModel.selectedPlayerMode) { _ in
                shouldAutoScrollPlaybackText = true
            }
            .onChange(of: viewModel.selectedPlaybackRecording?.id) { _ in
                shouldAutoScrollPlaybackText = true
            }
            .safeAreaInset(edge: .bottom) {
                bottomControls
            }
            .navigationTitle("Message")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        viewModel.openMenu()
                    } label: {
                        Image(systemName: "line.3.horizontal")
                    }
                    .accessibilityLabel("Open menu")
                }
            }
            .sheet(isPresented: $isFilesSheetPresented) {
                FilesSheetView(viewModel: viewModel)
            }
        }
    }

    @ViewBuilder
    private var messageCanvas: some View {
        if !viewModel.hasPlayerSelection {
            Text("Select a saved message from Files.")
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 220, alignment: .topLeading)
        } else if viewModel.shouldShowPlayerPlainText {
            Text(viewModel.playerSelectedTranscriptText)
                .font(.system(size: 30, weight: .medium, design: .rounded))
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: 220, alignment: .topLeading)
        } else if viewModel.selectedPlayerMode == .audio {
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(minHeight: 220)
        } else {
            Text(viewModel.visibleAttributedText)
                .font(.system(size: 30, weight: .medium, design: .rounded))
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: 220, alignment: .topLeading)
                .animation(.easeOut(duration: 0.18), value: viewModel.visibleTokens.count)
        }
    }

    private var bottomControls: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                ForEach(viewModel.playerModes) { mode in
                    Button {
                        viewModel.selectPlayerMode(mode)
                    } label: {
                        Text(mode.rawValue)
                            .font(.footnote.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 44)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(viewModel.selectedPlayerMode == mode ? Color.accentColor : Color(uiColor: .secondarySystemBackground))
                            )
                            .foregroundStyle(viewModel.selectedPlayerMode == mode ? Color.white : Color.primary)
                    }
                    .buttonStyle(.plain)
                    .disabled(!viewModel.canChangePlayerMode)
                }
            }

            Button {
                viewModel.playSelectedMessage()
            } label: {
                Text(viewModel.playerActionTitle)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 56)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.canStartPlayerPlayback)

            Button {
                viewModel.refreshPlayerFiles()
                isFilesSheetPresented = true
            } label: {
                Text("Files")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 48)
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .background(.ultraThinMaterial)
    }

    private func handleManualPlaybackScroll(_ value: DragGesture.Value) {
        guard shouldAutoScrollPlaybackText else { return }
        guard viewModel.shouldShowPlayerAnimatedText else { return }
        guard viewModel.playbackState == .playing else { return }
        guard abs(value.translation.height) > abs(value.translation.width) else { return }

        shouldAutoScrollPlaybackText = false
    }

    private func autoScrollPlaybackText(with proxy: ScrollViewProxy, animated: Bool = true) {
        guard shouldAutoScrollPlaybackText else { return }
        guard viewModel.shouldShowPlayerAnimatedText else { return }
        guard !viewModel.visibleTokens.isEmpty else { return }

        DispatchQueue.main.async {
            let scroll = {
                proxy.scrollTo(ScrollTarget.playbackBottom, anchor: .bottom)
            }

            if animated {
                withAnimation(.easeOut(duration: 0.18)) {
                    scroll()
                }
            } else {
                scroll()
            }
        }
    }
}
