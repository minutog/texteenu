import SwiftUI

struct ReadingView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(viewModel.visibleAttributedText)
                    .font(.system(size: 30, weight: .medium, design: .rounded))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: 220, alignment: .topLeading)
                    .animation(.easeOut(duration: 0.18), value: viewModel.visibleTokens.count)

                Text(viewModel.playbackStatusText())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                HStack(spacing: 12) {
                    Button("Replay") {
                        viewModel.replay()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!viewModel.canReplay)

                    Button("New Recording") {
                        viewModel.startNewRecordingFlow()
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(24)
        }
        .navigationTitle("Reading")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    viewModel.openMenu()
                } label: {
                    Image(systemName: "line.3.horizontal")
                }
                .accessibilityLabel("Open menu")
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    viewModel.toggleAudioMuted()
                } label: {
                    Image(systemName: viewModel.audioToggleIconName)
                }
                .accessibilityLabel(viewModel.isAudioMuted ? "Unmute audio" : "Mute audio")
            }
        }
    }
}
