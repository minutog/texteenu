import SwiftUI

struct HapTextRootView: View {
    @StateObject private var store = ChatStore()
    @StateObject private var notificationSettings = HapTextNotificationSettings.shared
    @State private var showsLoader = true
    @State private var selectedUser: ChatEndpoint?

    var body: some View {
        NavigationStack {
            Group {
                if showsLoader {
                    LoaderView()
                        .transition(.opacity)
                } else if let selectedUser {
                    ChatMenuView(
                        currentUser: selectedUser,
                        notificationSettings: notificationSettings,
                        onChangeUser: {
                            store.clearConversation()
                            notificationSettings.setCurrentUser(nil)
                            withAnimation(.easeInOut(duration: 0.2)) {
                                self.selectedUser = nil
                            }
                        }
                    )
                    .transition(.opacity)
                } else {
                    UserPickerView { user in
                        notificationSettings.setCurrentUser(user)
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedUser = user
                        }
                    }
                        .transition(.opacity)
                }
            }
            .navigationDestination(for: ChatRoute.self) { route in
                ChatView(route: route)
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
        .onChange(of: selectedUser) { _, newValue in
            notificationSettings.setCurrentUser(newValue)
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
    let currentUser: ChatEndpoint
    @ObservedObject var notificationSettings: HapTextNotificationSettings
    let onChangeUser: () -> Void

    var body: some View {
        FigmaPhoneFrame {
            ZStack(alignment: .topLeading) {
                Button(action: onChangeUser) {
                    Text(currentUser.displayName)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.black)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(width: 104, height: 33)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 16.5, style: .continuous))
                        .shadow(color: Color.black.opacity(0.2), radius: 2, x: 0, y: 4)
                }
                .buttonStyle(.plain)
                .position(x: 201, y: 132.5)

                NotificationMenuButton(settings: notificationSettings)
                    .position(x: 201, y: 203)

                ForEach(Array(ChatEndpoint.contacts(excluding: currentUser).enumerated()), id: \.element.id) { index, contact in
                    MenuButton(
                        title: contact.displayName,
                        route: ChatRoute(user: currentUser, contact: contact)
                    )
                    .position(x: 201.5, y: CGFloat(366.5 + Double(index) * 141))
                }
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

private struct NotificationMenuButton: View {
    @ObservedObject var settings: HapTextNotificationSettings

    var body: some View {
        Button {
            Task {
                await settings.toggleFromMenu()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: settings.iconName)
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 18, height: 18)

                Text(settings.statusLabel)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .foregroundStyle(.black)
            .frame(width: 210, height: 40)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: Color.black.opacity(0.16), radius: 2, x: 0, y: 3)
        }
        .buttonStyle(.plain)
    }
}

private struct UserPickerView: View {
    let onSelectUser: (ChatEndpoint) -> Void

    var body: some View {
        FigmaPhoneFrame {
            ZStack(alignment: .topLeading) {
                Text("Select your name")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.black)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(width: 144, height: 33)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 16.5, style: .continuous))
                    .shadow(color: Color.black.opacity(0.2), radius: 2, x: 0, y: 4)
                    .position(x: 201, y: 132.5)

                ForEach(Array(ChatEndpoint.allCases.enumerated()), id: \.element.id) { index, user in
                    UserButton(title: user.displayName) {
                        onSelectUser(user)
                    }
                    .position(x: 201.5, y: CGFloat(366.5 + Double(index) * 141))
                }
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

private struct UserButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 58, weight: .regular))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.62)
                .frame(width: 275, height: 117)
                .background(Color.hapBlue, in: RoundedRectangle(cornerRadius: 58.5, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct MenuButton: View {
    let title: String
    let route: ChatRoute

    var body: some View {
        NavigationLink(value: route) {
            Text(title)
                .font(.system(size: 58, weight: .regular))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.62)
                .frame(width: 275, height: 117)
                .background(Color.hapBlue, in: RoundedRectangle(cornerRadius: 58.5, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
