import SwiftUI

struct MainMenuView: View {
    private let buttonSpacing: CGFloat = 18
    private let buttonCornerRadius: CGFloat = 126

    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        GeometryReader { geometry in
            let buttonHeight = max(
                (geometry.size.height - buttonSpacing) / 2,
                0
            )

            VStack(spacing: buttonSpacing) {
                menuButton("Recorder") {
                    viewModel.openRecorder()
                }
                .frame(maxWidth: .infinity)
                .frame(height: buttonHeight)

                menuButton("Player") {
                    viewModel.openPlayer()
                }
                .frame(maxWidth: .infinity)
                .frame(height: buttonHeight)
            }
            .padding(.horizontal, buttonSpacing)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private func menuButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    LinearGradient(
                        colors: [
                            Color.accentColor.opacity(0.92),
                            Color.accentColor
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .buttonStyle(.plain)
        .clipShape(RoundedRectangle(cornerRadius: buttonCornerRadius, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: buttonCornerRadius, style: .continuous))
    }
}
