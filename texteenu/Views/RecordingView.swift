import SwiftUI

struct RecordingView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                headerContent

                if viewModel.shouldShowTitleField {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Title")
                            .font(.headline)

                        TextField("Audio title", text: $viewModel.draftTitle)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled(true)
                            .textContentType(.none)
                            .submitLabel(.done)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color(uiColor: .secondarySystemBackground))
                            )
                    }
                }

                if let title = viewModel.processingState.title {
                    ProgressView(title)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if !viewModel.transcriptionText.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Transcript")
                            .font(.headline)
                        Text(viewModel.transcriptionText)
                            .foregroundStyle(.secondary)
                    }
                }

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
                Spacer(minLength: 140)
            }
            .frame(maxWidth: .infinity, minHeight: 0, alignment: .topLeading)
            .padding(24)
        }
        .safeAreaInset(edge: .bottom) {
            bottomActionBar
        }
        .navigationTitle("Recorder")
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
    }

    private var bottomActionBar: some View {
        VStack(spacing: 14) {
            Button {
                viewModel.startRecording()
            } label: {
                buttonLabel(viewModel.recordButtonTitle, minHeight: 56)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.canStartRecording)

            if viewModel.canStopRecording {
                Button {
                    viewModel.stopRecording()
                } label: {
                    buttonLabel("Stop", minHeight: 56)
                }
                .buttonStyle(.borderedProminent)
            }

            if viewModel.canSaveAndProcess {
                Button {
                    viewModel.saveAndProcessRecording()
                } label: {
                    buttonLabel("Save and Process", minHeight: 60)
                }
                .buttonStyle(.borderedProminent)
            }

            if viewModel.shouldShowPostSaveActions {
                Button(role: .destructive) {
                    viewModel.deleteLastSavedAudio()
                } label: {
                    buttonLabel("Delete last audio", minHeight: 56)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)

                Button {
                    viewModel.openPlayer()
                } label: {
                    buttonLabel("Go to Player", minHeight: 60)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private var headerContent: some View {
        if let lastSavedTitle = viewModel.lastSavedTitle {
            Text(lastSavedTitle)
                .font(.title2.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if viewModel.isRecording {
            Text("Recording in progress...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text(viewModel.hasRecordedDraft ? "Add a title and save it into the app." : "Capture a short audio message, add a title, and save it into the app.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func buttonLabel(_ title: String, minHeight: CGFloat) -> some View {
        Text(title)
            .font(.headline)
            .frame(maxWidth: .infinity)
            .frame(minHeight: minHeight)
    }
}
