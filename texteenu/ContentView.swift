import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel: AppViewModel

    init(viewModel: @autoclosure @escaping () -> AppViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel())
    }

    var body: some View {
        NavigationStack {
            switch viewModel.screen {
            case .recording:
                RecordingView(viewModel: viewModel)
            case .reading:
                ReadingView(viewModel: viewModel)
            }
        }
    }
}
