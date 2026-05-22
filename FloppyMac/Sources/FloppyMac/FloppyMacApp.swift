import SwiftUI

@main
struct FloppyMacApp: App {
    @StateObject private var model = FloppyAppModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .frame(minWidth: 760, minHeight: 520)
                .onOpenURL { url in
                    model.handleCallback(url)
                }
        }

        Settings {
            SettingsView(model: model)
        }
    }
}
