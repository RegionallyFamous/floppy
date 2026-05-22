import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: FloppyAppModel

    var body: some View {
        Form {
            Section("Sync") {
                Text("Finder-native sync requires the File Provider extension target from this source tree to be built in Xcode with the included entitlements.")
                Text("The SwiftPM app stores device tokens in Keychain and keeps its SQLite metadata ledger in Application Support.")
                    .foregroundStyle(.secondary)
            }

            Section("Developer Setup") {
                LabeledContent("Xcode") {
                    Text("/Applications/Xcode.app")
                        .monospaced()
                }
                Text("Run `FloppyMac/Scripts/xcode-doctor.sh` before signing the app or wiring the File Provider extension.")
                    .foregroundStyle(.secondary)
                Text("Run `FloppyMac/Scripts/package-wordpress-plugin.sh` to create the GitHub release ZIP used by onboarding.")
                    .foregroundStyle(.secondary)
                Text("Run `FloppyMac/Scripts/archive-notarize.sh` from an Xcode project or workspace when you are ready for Developer ID signing and notarization.")
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(width: 520)
    }
}
