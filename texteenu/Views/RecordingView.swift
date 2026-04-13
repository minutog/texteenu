import SwiftUI

struct RecordingView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Audio-to-Text MVP")
                    .font(.title2.weight(.semibold))

                Text(viewModel.statusText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let title = viewModel.processingState.title {
                ProgressView(title)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !viewModel.transcriptionText.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Last transcription")
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

            Spacer()

            VStack(spacing: 12) {
                Button("Record") {
                    viewModel.startRecording()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canStartRecording)

                Button("Stop") {
                    viewModel.stopRecording()
                }
                .buttonStyle(.bordered)
                .disabled(!viewModel.canStopRecording)

                Button("Process") {
                    viewModel.processRecording()
                }
                .buttonStyle(.bordered)
                .disabled(!viewModel.canProcessRecording)

                if viewModel.canCancelRecording {
                    Button("Cancel Recording", role: .destructive) {
                        viewModel.cancelRecording()
                    }
                    .buttonStyle(.bordered)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(24)
        .navigationTitle("Recording")
    }
}
