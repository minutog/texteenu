import SwiftUI

struct HapTextRootView: View {
    @StateObject private var store = ChatStore()
    @State private var showsLoader = true

    var body: some View {
        NavigationStack {
            Group {
                if showsLoader {
                    LoaderView()
                        .transition(.opacity)
                } else {
                    ChatMenuView()
                        .transition(.opacity)
                }
            }
            .navigationDestination(for: ChatEndpoint.self) { endpoint in
                ChatView(viewer: endpoint)
            }
        }
        .environmentObject(store)
        #if os(iOS)
        .ignoresSafeArea(.keyboard, edges: .all)
        #endif
        .task {
            try? await Task.sleep(for: .seconds(1.15))
            withAnimation(.easeInOut(duration: 0.35)) {
                showsLoader = false
            }
        }
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
    }
}

private struct LoaderView: View {
    var body: some View {
        FigmaPhoneFrame {
            ZStack(alignment: .topLeading) {
                BundlePNGImage(name: "loader")
                    .scaledToFit()
                    .frame(width: 322.031, height: 107.915)
                    .rotationEffect(.degrees(1.58))
                    .position(x: 201.016, y: 361.958)
            }
        }
        .ignoresSafeArea()
    }
}

private struct ChatMenuView: View {
    var body: some View {
        FigmaPhoneFrame {
            ZStack(alignment: .topLeading) {
                MenuButton(endpoint: .chatA)
                    .position(x: 201.5, y: 366.5)

                MenuButton(endpoint: .chatB)
                    .position(x: 201, y: 507.5)
            }
        }
        .ignoresSafeArea()
        .navigationTitle("")
        #if os(iOS)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        #endif
    }
}

private struct MenuButton: View {
    let endpoint: ChatEndpoint

    var body: some View {
        NavigationLink(value: endpoint) {
            Text(endpoint.displayName)
                .font(.system(size: 64, weight: .regular))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: endpoint == .chatA ? 245 : 244, height: 117)
                .background(Color.hapBlue, in: RoundedRectangle(cornerRadius: 58.5, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
