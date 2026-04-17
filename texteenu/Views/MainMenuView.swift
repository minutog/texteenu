import SwiftUI

struct MainMenuView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack {
            Spacer()

            VStack(spacing: 18) {
                Button {
                    viewModel.openRecorder()
                } label: {
                    menuButtonLabel("Recorder")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    viewModel.openPlayer()
                } label: {
                    menuButtonLabel("Player")
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity)

            Spacer()
        }
        .padding(24)
        .navigationTitle("Menu")
    }

    private func menuButtonLabel(_ title: String) -> some View {
        Text(title)
            .font(.title2.weight(.semibold))
            .frame(maxWidth: .infinity)
            .frame(minHeight: 168)
    }
}
