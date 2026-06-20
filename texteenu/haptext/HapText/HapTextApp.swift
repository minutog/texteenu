import FirebaseCore
import SwiftUI

@main
struct HapTextApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(HapTextAppDelegate.self) private var appDelegate
    #endif

    init() {
        #if !os(iOS)
        HapTextFirebaseBootstrap.configure()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            HapTextRootView()
                .frame(minWidth: 360, minHeight: 640)
        }
    }
}

enum HapTextFirebaseBootstrap {
    private static var isConfigured = false

    static func configure() {
        guard isConfigured == false else { return }
        FirebaseApp.configure()
        isConfigured = true
    }
}
