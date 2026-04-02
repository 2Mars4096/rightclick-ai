import SwiftUI

@main
struct RightClickAIApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(model: AppModel.shared)
        }
    }
}
