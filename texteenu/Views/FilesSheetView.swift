import SwiftUI

struct FilesSheetView: View {
    @ObservedObject var viewModel: AppViewModel

    @State private var editingRecording: SavedRecording?
    @State private var editedTitle = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if viewModel.playerAvailableRecordings.isEmpty {
                        Text("No saved messages yet.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ForEach(viewModel.playerAvailableRecordings) { recording in
                            fileRow(for: recording)
                        }
                    }
                }
                .padding(20)
            }
            .navigationTitle("Files")
            .presentationDetents([.medium, .large])
        }
        .alert("Edit Name", isPresented: editAlertBinding) {
            TextField("Title", text: $editedTitle)
            Button("Cancel", role: .cancel) {
                editingRecording = nil
            }
            Button("Save") {
                if let editingRecording {
                    viewModel.renameRecording(id: editingRecording.id, to: editedTitle)
                }
                editingRecording = nil
            }
        } message: {
            Text("Update the selected file name.")
        }
    }

    private func fileRow(for recording: SavedRecording) -> some View {
        let isSelected = viewModel.isSelectedPlaybackRecording(recording)

        return HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 12) {
                Text(recording.title)
                    .font(.headline)

                HStack(spacing: 8) {
                    Button("Delete", role: .destructive) {
                        viewModel.deleteRecording(id: recording.id)
                    }
                    .buttonStyle(.bordered)

                    Button("Edit") {
                        editingRecording = recording
                        editedTitle = recording.title
                    }
                    .buttonStyle(.bordered)
                }
                .disabled(!viewModel.canChangePlayerMode)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.14) : Color(uiColor: .secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? Color.accentColor.opacity(0.35) : Color.clear, lineWidth: 1)
            )

            Button {
                guard !isSelected else { return }
                viewModel.selectPlaybackRecording(recording)
            } label: {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canChangePlayerMode)
        }
    }

    private var editAlertBinding: Binding<Bool> {
        Binding(
            get: { editingRecording != nil },
            set: { isPresented in
                if !isPresented {
                    editingRecording = nil
                }
            }
        )
    }
}
