import FloppyCore
import SwiftUI
import UniformTypeIdentifiers

struct MenuBarView: View {
    @ObservedObject var model: FloppyAppModel
    @State private var showsAdvanced = false
    @State private var isDropTargeted = false

    private var recentItems: [FloppyItem] {
        Array(model.items.prefix(2))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if model.selectedAccount == nil {
                connectPanel
            } else {
                connectedPanel
            }

            footer
        }
        .padding(14)
        .frame(width: 380)
        .background(.ultraThinMaterial)
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isDropTargeted) { providers in
            model.uploadDroppedProviders(providers)
        }
        .task {
            await model.refreshSelectedAccountIfStale()
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            FloppyMenuBarIcon()
                .frame(width: 19, height: 19)
                .padding(6)
                .background(.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text("Floppy")
                    .font(.system(size: 17, weight: .semibold))
                Text(accountSubtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                    .accessibilityLabel(statusAccessibilityLabel)

                Button {
                    Task { await model.syncSelectedAccount() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(FloppyIconButtonStyle())
                .help("Sync now")
                .accessibilityLabel("Sync now")
                .disabled(model.selectedAccount == nil || model.isWorking)

                Button {
                    model.openSettingsWindow()
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(FloppyIconButtonStyle())
                .help("Settings")
                .accessibilityLabel("Open Floppy Settings")
            }
        }
    }

    private var connectPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Connect WordPress")
                .font(.system(size: 15, weight: .semibold))

            TextField("https://example.com", text: $model.siteURLText)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 8) {
                Button {
                    model.startBrowserApproval()
                } label: {
                    Label(model.isOnboarding ? "Connecting" : "Install & Connect", systemImage: model.onboardingStep.systemImage)
                }
                .buttonStyle(FloppyPrimaryButtonStyle())
                .disabled(model.isOnboarding)

                if model.isOnboarding {
                    Button {
                        model.cancelOnboarding()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(FloppyIconButtonStyle())
                    .help("Cancel")
                    .accessibilityLabel("Cancel setup")
                }
            }

            DisclosureGroup(isExpanded: $showsAdvanced) {
                VStack(alignment: .leading, spacing: 7) {
                    TextField("GitHub release ZIP", text: $model.githubPluginZipURLText)
                        .textFieldStyle(.roundedBorder)
                    TextField("Plugin file", text: $model.pluginMainFile)
                        .textFieldStyle(.roundedBorder)
                    TextField("Device name", text: $model.deviceName)
                        .textFieldStyle(.roundedBorder)
                }
                .padding(.top, 6)
            } label: {
                Label("Advanced", systemImage: "slider.horizontal.3")
                    .font(.system(size: 12, weight: .medium))
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.36), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private var connectedPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button {
                    model.openNativeFolder()
                } label: {
                    Label("Open Folder", systemImage: "folder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(FloppyPrimaryButtonStyle())

                Button {
                    model.chooseFilesForUpload()
                } label: {
                    Label("Add Files", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(FloppySecondaryButtonStyle())
                .disabled(model.isWorking)
            }

            dropStrip

            recentPanel
        }
    }

    private var dropStrip: some View {
        HStack(spacing: 8) {
            Image(systemName: isDropTargeted ? "arrow.down.doc.fill" : "arrow.down.doc")
                .font(.system(size: 15, weight: .semibold))
            Text("Drop files to upload")
                .font(.system(size: 13, weight: .medium))
            Spacer()
        }
        .foregroundStyle(isDropTargeted ? Color.accentColor : Color.secondary)
        .padding(.horizontal, 12)
        .frame(height: 42)
        .background(
            isDropTargeted ? Color.accentColor.opacity(0.13) : Color.secondary.opacity(0.08),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(
                    isDropTargeted ? Color.accentColor.opacity(0.82) : Color.secondary.opacity(0.18),
                    style: StrokeStyle(lineWidth: 1, dash: isDropTargeted ? [6, 5] : [])
                )
        }
    }

    private var recentPanel: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("Recent")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if model.isWorking {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.72)
                }
            }

            if recentItems.isEmpty {
                Text("No recent files")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                ForEach(recentItems) { item in
                    recentRow(item)
                }
            }
        }
        .padding(10)
        .background(.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func recentRow(_ item: FloppyItem) -> some View {
        HStack(spacing: 8) {
            Image(systemName: item.kind == .folder ? "folder.fill" : "doc.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(item.kind == .folder ? Color.accentColor : Color.secondary)
                .frame(width: 17)

            Text(shortenedName(item.name))
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)

            Spacer(minLength: 8)

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.green)
        }
        .frame(height: 22)
    }

    private var footer: some View {
        VStack(spacing: 10) {
            Divider()
                .opacity(0.5)

            HStack(spacing: 8) {
                Text(footerStatus)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Button {
                    model.openSettingsWindow()
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                .buttonStyle(FloppyFooterButtonStyle())
                .accessibilityLabel("Open Floppy Settings")

                Button {
                    NSApp.terminate(nil)
                } label: {
                    Label("Quit", systemImage: "power")
                }
                .buttonStyle(FloppyFooterButtonStyle())
                .accessibilityLabel("Quit Floppy")
            }
        }
    }

    private var accountSubtitle: String {
        guard let account = model.selectedAccount else {
            return "Freedom for your files"
        }

        let host = account.siteURL.host ?? "Connected"
        if model.isWorking {
            return "\(host) · Syncing..."
        }
        guard model.isNetworkReachable else {
            return "\(host) · Offline"
        }
        if let lastSyncAt = account.lastSyncAt {
            return "\(host) · Synced \(lastSyncAt.formatted(date: .omitted, time: .shortened))"
        }
        return "\(host) · Ready"
    }

    private var footerStatus: String {
        if model.selectedAccount == nil {
            return model.onboardingStep.title
        }

        if model.openConflictCount > 0 {
            return "\(model.openConflictCount) conflict\(model.openConflictCount == 1 ? "" : "s") need attention"
        }

        if model.pendingTransferCount > 0 {
            return "\(model.pendingTransferCount) interrupted transfer\(model.pendingTransferCount == 1 ? "" : "s") preserved"
        }

        if model.status.isEmpty {
            return model.nativeFolderStatusText
        }

        return model.status
    }

    private var statusColor: Color {
        if model.selectedAccount == nil {
            return .orange
        }
        if model.hasLocalAttentionItems {
            return .orange
        }
        if !model.isNetworkReachable {
            return .secondary
        }
        return .green
    }

    private var statusAccessibilityLabel: String {
        if model.selectedAccount == nil {
            return "Not connected"
        }
        if model.hasLocalAttentionItems {
            return "Needs attention"
        }
        if !model.isNetworkReachable {
            return "Offline"
        }
        return "Connected"
    }

    private func shortenedName(_ name: String) -> String {
        guard name.count > 32 else {
            return name
        }

        let prefix = name.prefix(24)
        let suffix = name.suffix(5)
        return "\(prefix)...\(suffix)"
    }
}

private struct FloppyPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.13, green: 0.48, blue: 0.96),
                        Color(red: 0.09, green: 0.36, blue: 0.84)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .opacity(configuration.isPressed ? 0.82 : 1)
    }
}

private struct FloppySecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(.secondary.opacity(configuration.isPressed ? 0.22 : 0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.white.opacity(0.08), lineWidth: 1)
            }
    }
}

private struct FloppyIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(width: 30, height: 30)
            .background(.secondary.opacity(configuration.isPressed ? 0.24 : 0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct FloppyFooterButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background(.secondary.opacity(configuration.isPressed ? 0.20 : 0.10), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}
