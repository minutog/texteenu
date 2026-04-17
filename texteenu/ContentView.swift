import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel: AppViewModel

    init(viewModel: @autoclosure @escaping () -> AppViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel())
    }

    var body: some View {
        NavigationStack {
            switch viewModel.section {
            case .menu:
                MainMenuView(viewModel: viewModel)
            case .recorder:
                RecordingView(viewModel: viewModel)
            case .player:
                PlayerView(viewModel: viewModel)
            }
        }
    }
}
