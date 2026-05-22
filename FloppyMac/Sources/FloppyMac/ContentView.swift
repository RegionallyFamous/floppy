import AppKit
import FloppyCore
import SwiftUI

struct ContentView: View {
    @ObservedObject var model: FloppyAppModel

    var body: some View {
        NavigationSplitView {
            List(selection: $model.selectedAccountID) {
                Section("Accounts") {
                    ForEach(model.accounts) { account in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(account.siteURL.host ?? account.siteURL.absoluteString)
                                .font(.headline)
                            Text("Cursor \(account.lastCursor)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(account.id as String?)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                connectPanel
                    .padding()
            }
        } detail: {
            VStack(spacing: 0) {
                toolbar
                Divider()
                if model.selectedAccount == nil {
                    ContentUnavailableView("Connect a WordPress site", systemImage: "externaldrive.connected.to.line.below", description: Text("Floppy for Mac syncs private WordPress files through a browser-approved device token."))
                } else {
                    fileList
                }
                Divider()
                statusBar
            }
        }
        .task {
            await model.refreshSelectedAccount()
        }
    }

    private var connectPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                Text("Connect Site")
                    .font(.headline)
            }
            TextField("https://example.com", text: $model.siteURLText)
                .textFieldStyle(.roundedBorder)
            TextField("https://github.com/owner/repo/releases/latest/download/floppy.zip", text: $model.githubPluginZipURLText)
                .textFieldStyle(.roundedBorder)
            TextField("Plugin file", text: $model.pluginMainFile)
                .textFieldStyle(.roundedBorder)
            TextField("Device name", text: $model.deviceName)
                .textFieldStyle(.roundedBorder)
            Button {
                model.startBrowserApproval()
            } label: {
                Label(connectButtonTitle, systemImage: "safari")
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isOnboarding)
            onboardingProgress
        }
    }

    private var connectButtonTitle: String {
        switch model.onboardingStep {
        case .waitingForWordPressAuthorization:
            "Waiting for WordPress"
        case .installingPlugin:
            "Preparing GitHub ZIP"
        case .waitingForManualGitHubInstall:
            "Waiting for Install"
        case .activatingPlugin:
            "Activating Plugin"
        case .creatingDeviceToken:
            "Securing Device"
        default:
            "Install & Connect"
        }
    }

    @ViewBuilder
    private var onboardingProgress: some View {
        if model.isOnboarding {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text(connectButtonTitle)
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
        }
    }

    private var toolbar: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(model.selectedAccount?.siteURL.host ?? "Floppy")
                    .font(.title2.bold())
                Text("Private WordPress Drive")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Task { await model.refreshSelectedAccount() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            Button {
                Task { await model.syncSelectedAccount() }
            } label: {
                Label("Sync", systemImage: "arrow.triangle.2.circlepath")
            }
            Button {
                Task { await model.loadHealth() }
            } label: {
                Label("Health", systemImage: "stethoscope")
            }
            Button(role: .destructive) {
                model.disconnectSelectedAccount()
            } label: {
                Label("Disconnect", systemImage: "xmark.circle")
            }
            .disabled(model.selectedAccount == nil)
        }
        .padding()
    }

    private var fileList: some View {
        Table(model.items) {
            TableColumn("Name") { item in
                Label(item.name, systemImage: item.kind == .folder ? "folder" : "doc")
            }
            TableColumn("Kind") { item in
                Text(item.kind.rawValue)
            }
            TableColumn("Size") { item in
                Text(item.sizeBytes.map(ByteCountFormatter.string) ?? "-")
            }
            TableColumn("Updated") { item in
                Text(item.updatedAtGMT)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var statusBar: some View {
        HStack {
            if model.isWorking {
                ProgressView()
                    .controlSize(.small)
            }
            Text(model.status)
                .lineLimit(1)
            Spacer()
            if let health = model.health {
                Label(health.ok ? "Healthy" : "Needs attention", systemImage: health.ok ? "checkmark.seal" : "exclamationmark.triangle")
                    .foregroundStyle(health.ok ? .green : .orange)
            }
        }
        .font(.caption)
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

private extension FloppyAppModel {
    var isOnboarding: Bool {
        switch onboardingStep {
        case .waitingForWordPressAuthorization, .installingPlugin, .waitingForManualGitHubInstall, .activatingPlugin, .creatingDeviceToken:
            true
        default:
            false
        }
    }
}

private extension ByteCountFormatter {
    static func string(from byteCount: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: byteCount)
    }
}
