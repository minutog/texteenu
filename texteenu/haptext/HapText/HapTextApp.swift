import SwiftUI

@main
struct HapTextApp: App {
    var body: some Scene {
        WindowGroup {
            HapTextRootView()
                .frame(minWidth: 360, minHeight: 640)
        }
    }
}
