import Combine
import FirebaseCore
import FirebaseFirestore
import Foundation
import SwiftUI

#if os(iOS)
import FirebaseMessaging
import UIKit
import UserNotifications
#endif

#if os(iOS)
final class HapTextAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, MessagingDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        HapTextFirebaseBootstrap.configure()
        UNUserNotificationCenter.current().delegate = self
        Messaging.messaging().delegate = self
        print("HapText notifications: app delegate configured")
        HapTextNotificationSettings.shared.refreshAuthorizationStatus()
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Messaging.messaging().apnsToken = deviceToken
        HapTextNotificationSettings.shared.didReceiveAPNSToken()
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("HapText notifications: remote registration failed: \(error.localizedDescription)")
    }

    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        HapTextNotificationSettings.shared.updateFCMToken(fcmToken)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound, .badge])
    }
}

@MainActor
final class HapTextNotificationSettings: ObservableObject {
    static let shared = HapTextNotificationSettings()

    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var fcmToken: String?
    @Published private(set) var currentUser: ChatEndpoint?
    @Published var isEnabled: Bool {
        didSet {
            handleEnabledPreferenceChange()
        }
    }

    private static let isEnabledDefaultsKey = "haptext.notifications.enabled"
    private var registeredUser: ChatEndpoint?
    private var registeredToken: String?
    private var hasAPNSToken = false
    private var isFetchingFCMToken = false

    private init() {
        isEnabled = UserDefaults.standard.object(forKey: Self.isEnabledDefaultsKey) as? Bool ?? true
    }

    var isAuthorized: Bool {
        switch authorizationStatus {
        case .authorized, .ephemeral, .provisional:
            return true
        default:
            return false
        }
    }

    var statusLabel: String {
        if isEnabled == false {
            return "Notifications off"
        }

        switch authorizationStatus {
        case .authorized, .ephemeral, .provisional:
            return "Notifications on"
        case .denied:
            return "Notifications blocked"
        case .notDetermined:
            return "Enable notifications"
        @unknown default:
            return "Notifications"
        }
    }

    var iconName: String {
        if isEnabled == false || authorizationStatus == .denied {
            return "bell.slash.fill"
        }

        return isAuthorized ? "bell.fill" : "bell"
    }

    func setCurrentUser(_ user: ChatEndpoint?) {
        guard currentUser != user else {
            syncCurrentRegistration()
            return
        }

        let previousUser = currentUser
        currentUser = user

        if let previousUser, let registeredToken {
            deleteRegistration(user: previousUser, token: registeredToken)
            self.registeredUser = nil
            self.registeredToken = nil
        }

        syncCurrentRegistration()
    }

    func requestAuthorizationAndRegister() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        authorizationStatus = settings.authorizationStatus

        if settings.authorizationStatus == .denied {
            openSystemSettings()
            return
        }

        do {
            _ = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            refreshAuthorizationStatus()
            UIApplication.shared.registerForRemoteNotifications()

            if hasAPNSToken {
                refreshFCMToken()
            }
        } catch {
            print("HapText notifications: authorization failed: \(error.localizedDescription)")
        }
    }

    func toggleFromMenu() async {
        if isEnabled, isAuthorized {
            isEnabled = false
            return
        }

        isEnabled = true
        await requestAuthorizationAndRegister()
    }

    func refreshAuthorizationStatus() {
        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            await MainActor.run {
                self.authorizationStatus = settings.authorizationStatus

                if self.isAuthorized {
                    UIApplication.shared.registerForRemoteNotifications()

                    if self.hasAPNSToken {
                        self.refreshFCMToken()
                    }
                }
            }
        }
    }

    func didReceiveAPNSToken() {
        hasAPNSToken = true
        print("HapText notifications: APNS token received")
        refreshFCMToken()
    }

    func refreshFCMToken() {
        guard FirebaseApp.app() != nil else { return }
        guard hasAPNSToken else {
            print("HapText notifications: waiting for APNS token before requesting FCM token")
            return
        }

        guard isFetchingFCMToken == false else { return }
        isFetchingFCMToken = true

        Messaging.messaging().token { [weak self] token, error in
            Task { @MainActor in
                self?.isFetchingFCMToken = false
            }

            if let error {
                print("HapText notifications: FCM token failed: \(error.localizedDescription)")
                return
            }

            Task { @MainActor in
                self?.updateFCMToken(token)
            }
        }
    }

    func updateFCMToken(_ token: String?) {
        guard token != fcmToken else { return }

        if let registeredUser, let registeredToken {
            deleteRegistration(user: registeredUser, token: registeredToken)
            self.registeredUser = nil
            self.registeredToken = nil
        }

        fcmToken = token
        if token != nil {
            print("HapText notifications: FCM token received")
        }
        syncCurrentRegistration()
    }

    private func syncCurrentRegistration() {
        guard isEnabled, isAuthorized, let user = currentUser, let token = fcmToken else { return }
        guard registeredUser != user || registeredToken != token else { return }

        let payload: [String: Any] = [
            "token": token,
            "userID": user.rawValue,
            "platform": "ios",
            "bundleID": Bundle.main.bundleIdentifier ?? "unknown",
            "notificationsEnabled": true,
            "updatedAt": FieldValue.serverTimestamp()
        ]

        tokenDocument(user: user, token: token).setData(payload, merge: true) { [weak self] error in
            if let error {
                print("HapText notifications: token save failed: \(error.localizedDescription)")
                return
            }

            Task { @MainActor in
                self?.registeredUser = user
                self?.registeredToken = token
                print("HapText notifications: token registered for \(user.rawValue)")
            }
        }
    }

    private func handleEnabledPreferenceChange() {
        UserDefaults.standard.set(isEnabled, forKey: Self.isEnabledDefaultsKey)

        if isEnabled {
            syncCurrentRegistration()
        } else if let registeredUser, let registeredToken {
            deleteRegistration(user: registeredUser, token: registeredToken)
            self.registeredUser = nil
            self.registeredToken = nil
        }
    }

    private func deleteRegistration(user: ChatEndpoint, token: String) {
        tokenDocument(user: user, token: token).delete { error in
            if let error {
                print("HapText notifications: token delete failed: \(error.localizedDescription)")
            }
        }
    }

    private func tokenDocument(user: ChatEndpoint, token: String) -> DocumentReference {
        Firestore.firestore()
            .collection("haptext_users")
            .document(user.rawValue)
            .collection("notification_tokens")
            .document(tokenDocumentID(for: token))
    }

    private func tokenDocumentID(for token: String) -> String {
        token.data(using: .utf8)?
            .base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "") ?? UUID().uuidString
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
#else
@MainActor
final class HapTextNotificationSettings: ObservableObject {
    static let shared = HapTextNotificationSettings()

    @Published var isEnabled = false
    var fcmToken: String? { nil }
    var statusLabel: String { "iPhone notifications" }
    var iconName: String { "bell.slash.fill" }

    private init() {}

    func setCurrentUser(_ user: ChatEndpoint?) {}
    func requestAuthorizationAndRegister() async {}
    func toggleFromMenu() async {}
}
#endif
