import FloppyCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: FloppyAppModel
    @State private var selectedSection: FloppySettingsSection = .general

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    sectionContent
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 860, idealWidth: 900, minHeight: 560, idealHeight: 620)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 34, height: 34)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Floppy")
                        .font(.headline)
                    Text(model.selectedAccount?.siteURL.host ?? "Settings")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 14)
            .padding(.bottom, 8)

            ForEach(FloppySettingsSection.allCases) { section in
                Button {
                    selectedSection = section
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: section.systemImage)
                            .font(.system(size: 15, weight: .semibold))
                            .frame(width: 20)
                        Text(section.title)
                            .font(.system(size: 13, weight: .semibold))
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(RoundedRectangle(cornerRadius: 8))
                    .foregroundStyle(selectedSection == section ? .primary : .secondary)
                    .background(
                        selectedSection == section ? Color.accentColor.opacity(0.16) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 8)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityValue(selectedSection == section ? "Selected" : "")
            }

            Spacer()

            SettingsSidebarStatus(
                title: model.selectedAccount == nil ? "Not Connected" : "Connected",
                subtitle: model.nativeFolderStatusText,
                color: model.selectedAccount == nil ? .orange : (model.nativeFolderReadiness.isReady ? .green : .orange)
            )
            .padding(12)
        }
        .frame(width: 210)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.accentColor.opacity(0.14))
                Image(systemName: selectedSection.systemImage)
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(.tint)
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 4) {
                Text(selectedSection.title)
                    .font(.system(size: 28, weight: .bold))
                Text(selectedSection.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            StatusPill(
                title: model.health?.ok == true ? "Healthy" : (model.health == nil ? "Not Checked" : "Review"),
                systemImage: model.health?.ok == true ? "checkmark.seal.fill" : (model.health == nil ? "clock" : "exclamationmark.triangle.fill"),
                color: model.health?.ok == true ? .green : (model.health == nil ? .secondary : .orange)
            )
        }
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch selectedSection {
        case .general:
            generalSection
        case .account:
            accountSection
        case .sync:
            syncSection
        case .finder:
            finderSection
        case .diagnostics:
            diagnosticsSection
        case .advanced:
            advancedSection
        }
    }

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsCard("Mac Behavior", systemImage: "macwindow") {
                Toggle(isOn: Binding(
                    get: { model.launchAtLoginEnabled },
                    set: { model.setLaunchAtLoginEnabled($0) }
                )) {
                    SettingsToggleLabel(
                        title: "Launch at Login",
                        message: model.launchAtLoginStatusText,
                        systemImage: "power"
                    )
                }
                .toggleStyle(.switch)

                Toggle(isOn: Binding(
                    get: { model.backgroundSyncEnabled },
                    set: { model.setBackgroundSyncEnabled($0) }
                )) {
                    SettingsToggleLabel(
                        title: "Background Sync",
                        message: "Syncs on a timer, when the Mac wakes, when Floppy becomes active, and when the network comes back.",
                        systemImage: "arrow.triangle.2.circlepath"
                    )
                }
                .toggleStyle(.switch)

                SettingsInfoRow(
                    "Network",
                    value: model.isNetworkReachable ? "Reachable" : "Offline",
                    systemImage: model.isNetworkReachable ? "network" : "wifi.slash"
                )

                HStack(spacing: 10) {
                    SettingsActionButton("Open Login Items", systemImage: "gearshape") {
                        model.openLoginItemsSettings()
                    }

                    SettingsActionButton("Sync Now", systemImage: "arrow.triangle.2.circlepath", prominence: .primary) {
                        Task { await model.syncSelectedAccount() }
                    }
                    .disabled(model.selectedAccount == nil || model.isWorking || !model.isNetworkReachable)
                }
                .padding(.top, 4)
            }

            SettingsCard("Native Recovery", systemImage: "lifepreserver") {
                SettingsCheckRow(
                    title: "Wake and relaunch recovery",
                    message: "Floppy reconciles the File Provider domain and sync cursor after wake, activation, reconnect, and network restore.",
                    state: .pass
                )
                SettingsCheckRow(
                    title: "Finder signaling",
                    message: "Sync-affecting actions signal the working set plus active folder enumerators.",
                    state: .pass
                )
                SettingsCheckRow(
                    title: "Last automatic sync",
                    message: model.lastAutomaticSyncAt?.formatted(date: .abbreviated, time: .shortened) ?? "Not run in this app session.",
                    state: model.lastAutomaticSyncAt == nil ? .neutral : .pass
                )
            }
        }
    }

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsCard("Connected Site", systemImage: "person.crop.circle.badge.checkmark") {
                if let account = model.selectedAccount {
                    SettingsInfoRow("Site", value: account.siteURL.absoluteString, systemImage: "globe")
                    SettingsInfoRow("User", value: account.userHint, systemImage: "person")
                    SettingsInfoRow("Device", value: account.deviceUUID, systemImage: "desktopcomputer", monospaced: true)
                    SettingsInfoRow("Scope", value: account.scope, systemImage: "key.horizontal", monospaced: true)
                    SettingsInfoRow("Connected", value: account.connectedAt.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                } else {
                    EmptySettingsState(
                        title: "No WordPress site connected",
                        message: "Connect a site from the Floppy menu bar window to create a private WordPress-owned drive.",
                        systemImage: "externaldrive.badge.plus"
                    )
                }
            }

            SettingsCard("Actions", systemImage: "bolt") {
                SettingsInfoRow("Status", value: model.status, systemImage: model.isWorking ? "hourglass" : "info.circle", valueLineLimit: 2)

                HStack(spacing: 10) {
                    SettingsActionButton("Open Folder", systemImage: "folder", prominence: .primary) {
                        model.openNativeFolder()
                    }
                    .disabled(model.selectedAccount == nil)

                    SettingsActionButton("Refresh", systemImage: "arrow.clockwise") {
                        model.refreshSelectedAccountFromSettings()
                    }
                    .disabled(!canRunNetworkAction)

                    SettingsActionButton("Disconnect", systemImage: "xmark.circle", role: .destructive) {
                        model.disconnectSelectedAccount()
                    }
                    .disabled(model.selectedAccount == nil)
                }
            }
        }
    }

    private var syncSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                SettingsMetricCard(
                    title: "Local Files",
                    value: "\(model.items.count)",
                    subtitle: model.selectedAccount == nil ? "Connect a site" : "Cached locally",
                    systemImage: "doc.on.doc"
                )
                SettingsMetricCard(
                    title: "Sync Cursor",
                    value: "\(model.selectedAccount?.lastCursor ?? 0)",
                    subtitle: "Server event position",
                    systemImage: "point.3.connected.trianglepath.dotted"
                )
                SettingsMetricCard(
                    title: "Last Sync",
                    value: model.selectedAccount?.lastSyncAt?.formatted(date: .omitted, time: .shortened) ?? "-",
                    subtitle: model.selectedAccount?.lastSyncAt?.formatted(date: .abbreviated, time: .omitted) ?? "Not synced",
                    systemImage: "arrow.triangle.2.circlepath"
                )
            }

            SettingsCard("Sync Engine", systemImage: "arrow.triangle.2.circlepath.circle") {
                SettingsCheckRow(
                    title: "Scoped device token",
                    message: "Stored in Keychain and revocable from WordPress.",
                    state: model.selectedAccount == nil ? .warning : .pass
                )
                SettingsCheckRow(
                    title: "SQLite ledger",
                    message: "Tracks accounts, items, conflicts, materialized files, and sync anchors.",
                    state: .pass
                )
                SettingsCheckRow(
                    title: "Server health",
                    message: model.health == nil ? "Run diagnostics to check REST, storage, quotas, and Desktop Mode." : (model.health?.ok == true ? "Latest health check passed." : "One or more server checks need review."),
                    state: model.health == nil ? .neutral : (model.health?.ok == true ? .pass : .warning)
                )

                HStack(spacing: 10) {
                    SettingsActionButton("Sync Now", systemImage: "arrow.triangle.2.circlepath", prominence: .primary) {
                        Task { await model.syncSelectedAccount() }
                    }
                    .disabled(!canRunNetworkAction)

                    SettingsActionButton("Run Health Check", systemImage: "stethoscope") {
                        Task { await model.loadHealth() }
                    }
                    .disabled(!canRunNetworkAction)
                }
                .padding(.top, 4)
            }
        }
    }

    private var finderSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsCard("Finder Folder", systemImage: "folder.badge.gearshape") {
                SettingsCheckRow(
                    title: "File Provider extension",
                    message: model.nativeFolderReadiness.message,
                    state: model.nativeFolderReadiness.isReady ? .pass : .warning
                )
                SettingsInfoRow(
                    "App Group",
                    value: model.nativeFolderReadiness.appGroupIdentifier,
                    systemImage: "person.2.badge.gearshape",
                    monospaced: true
                )
                SettingsInfoRow(
                    "Extension",
                    value: model.nativeFolderReadiness.extensionURL?.path ?? "Not embedded in this build",
                    systemImage: "puzzlepiece.extension",
                    monospaced: true
                )

                HStack(spacing: 10) {
                    SettingsActionButton("Open Native Folder", systemImage: "folder", prominence: .primary) {
                        model.openNativeFolder()
                    }
                    .disabled(model.selectedAccount == nil)

                    SettingsActionButton("Refresh Status", systemImage: "arrow.clockwise") {
                        model.nativeFolderReadiness = FloppyNativeFolderReadiness.current()
                    }
                }
                .padding(.top, 4)
            }

            SettingsCard("What Finder Does", systemImage: "checklist") {
                SettingsCompactText("Floppy registers one File Provider domain per WordPress site.")
                SettingsCompactText("Finder materializes files on demand and sends changes through resumable Floppy upload sessions.")
                SettingsCompactText("Stale writes preserve a local conflict copy instead of overwriting server changes.")
            }
        }
    }

    private var diagnosticsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsCard("Diagnostics Bundle", systemImage: "waveform.path.ecg.rectangle") {
                Text("Exports a redacted JSON bundle with account, origin, Keychain, domain registry, ledger, cursor, queue, conflict, and onboarding state.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    SettingsActionButton("Export Bundle", systemImage: "square.and.arrow.down", prominence: .primary) {
                        model.exportDiagnostics()
                    }
                    .disabled(model.isExportingDiagnostics)

                    SettingsActionButton("Copy Support ID", systemImage: "doc.on.doc") {
                        model.copySupportID()
                    }

                    SettingsActionButton("Refresh Health", systemImage: "stethoscope") {
                        Task { await model.loadHealth() }
                    }
                    .disabled(!canRunNetworkAction)
                }
                .padding(.top, 4)
            }

            SettingsCard("Current Status", systemImage: "list.bullet.rectangle") {
                SettingsInfoRow("App Status", value: model.status, systemImage: model.isWorking ? "hourglass" : "info.circle")
                SettingsInfoRow("Accounts", value: "\(model.accounts.count)", systemImage: "person.2")
                SettingsInfoRow("Selected Items", value: "\(model.items.count)", systemImage: "doc.text")
                SettingsInfoRow("Conflicts", value: "\(model.openConflictCount)", systemImage: "exclamationmark.triangle")
                SettingsInfoRow("Pending Transfers", value: "\(model.pendingTransferCount)", systemImage: "arrow.up.arrow.down")
                SettingsInfoRow("Health Checks", value: healthSummaryText, systemImage: "checkmark.seal")
            }
        }
    }

    private var advancedSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsCard("Developer Setup", systemImage: "hammer") {
                SettingsInfoRow("Xcode", value: "/Applications/Xcode.app", systemImage: "hammer", monospaced: true)
                SettingsCommandRow(
                    title: "Signing Doctor",
                    command: "FloppyMac/Scripts/xcode-doctor.sh",
                    detail: "Checks signing, entitlements, bundle IDs, and File Provider readiness."
                )
                SettingsCommandRow(
                    title: "Plugin ZIP",
                    command: "FloppyMac/Scripts/package-wordpress-plugin.sh",
                    detail: "Builds the GitHub release ZIP used by onboarding."
                )
                SettingsCommandRow(
                    title: "Archive + Notarize",
                    command: "FloppyMac/Scripts/archive-notarize.sh",
                    detail: "Creates a Developer ID archive when the Xcode project is signed."
                )
            }

            SettingsCard("Advanced Onboarding Defaults", systemImage: "slider.horizontal.3") {
                SettingsInfoRow("GitHub ZIP", value: model.githubPluginZipURLText, systemImage: "shippingbox", monospaced: true)
                SettingsInfoRow("Plugin File", value: model.pluginMainFile, systemImage: "doc.badge.gearshape", monospaced: true)
                SettingsInfoRow("Device Name", value: model.deviceName, systemImage: "macbook", monospaced: false)

                SettingsActionButton("Reset Advanced Fields", systemImage: "arrow.counterclockwise") {
                    model.resetAdvancedOnboardingFields()
                }
            }
        }
    }

    private var healthSummaryText: String {
        guard let health = model.health else {
            return "Not run"
        }
        let failed = health.checks.values.filter { !$0.ok }.count
        return failed == 0 ? "All passed" : "\(failed) need review"
    }

    private var canRunNetworkAction: Bool {
        model.selectedAccount != nil && !model.isWorking && model.isNetworkReachable
    }
}

private enum FloppySettingsSection: String, CaseIterable, Identifiable {
    case general
    case account
    case sync
    case finder
    case diagnostics
    case advanced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .account: "Account"
        case .sync: "Sync"
        case .finder: "Finder"
        case .diagnostics: "Diagnostics"
        case .advanced: "Advanced"
        }
    }

    var subtitle: String {
        switch self {
        case .general: "Mac launch, background sync, wake recovery, and network behavior."
        case .account: "WordPress site, scoped device token, and local account details."
        case .sync: "Cursor-based sync, SQLite ledger, and server health."
        case .finder: "Native folder availability and File Provider readiness."
        case .diagnostics: "Redacted support bundle and current runtime state."
        case .advanced: "Xcode signing scripts and GitHub-first plugin install defaults."
        }
    }

    var systemImage: String {
        switch self {
        case .general: "macwindow"
        case .account: "person.crop.circle"
        case .sync: "arrow.triangle.2.circlepath"
        case .finder: "folder"
        case .diagnostics: "waveform.path.ecg"
        case .advanced: "gearshape.2"
        }
    }
}

private struct SettingsCard<Content: View>: View {
    private let title: String
    private let systemImage: String
    @ViewBuilder private let content: Content

    init(_ title: String, systemImage: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .foregroundStyle(.tint)
                    .frame(width: 18)
                Text(title)
                    .font(.headline)
                Spacer()
            }

            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.08))
        )
    }
}

private struct SettingsMetricCard: View {
    let title: String
    let value: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: systemImage)
                    .foregroundStyle(.tint)
                Spacer()
            }
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.08))
        )
    }
}

private struct SettingsInfoRow: View {
    let title: String
    let value: String
    let systemImage: String
    let monospaced: Bool
    let valueLineLimit: Int

    init(_ title: String, value: String, systemImage: String, monospaced: Bool = false, valueLineLimit: Int = 1) {
        self.title = title
        self.value = value
        self.systemImage = systemImage
        self.monospaced = monospaced
        self.valueLineLimit = valueLineLimit
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            Text(title)
                .font(.callout.weight(.medium))
            Spacer(minLength: 18)
            Text(value)
                .font(monospaced ? .system(.callout, design: .monospaced) : .callout)
                .foregroundStyle(.secondary)
                .lineLimit(valueLineLimit)
                .truncationMode(.middle)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 2)
    }
}

private struct SettingsCheckRow: View {
    enum State {
        case pass
        case warning
        case neutral

        var color: Color {
            switch self {
            case .pass: .green
            case .warning: .orange
            case .neutral: .secondary
            }
        }

        var systemImage: String {
            switch self {
            case .pass: "checkmark.circle.fill"
            case .warning: "exclamationmark.triangle.fill"
            case .neutral: "circle.dashed"
            }
        }
    }

    let title: String
    let message: String
    let state: State

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: state.systemImage)
                .foregroundStyle(state.color)
                .frame(width: 18)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

private struct SettingsCommandRow: View {
    let title: String
    let command: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Image(systemName: "terminal")
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                Text(title)
                    .font(.callout.weight(.semibold))
                Spacer()
                Text(command)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 28)
        }
        .padding(.vertical, 2)
    }
}

private struct SettingsCompactText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark")
                .font(.caption.bold())
                .foregroundStyle(.green)
                .frame(width: 18)
                .padding(.top, 2)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct SettingsToggleLabel: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 18)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .contentShape(Rectangle())
    }
}

private struct SettingsActionButton: View {
    enum Prominence {
        case standard
        case primary
    }

    let title: String
    let systemImage: String
    let prominence: Prominence
    let role: ButtonRole?
    let action: () -> Void

    init(
        _ title: String,
        systemImage: String,
        prominence: Prominence = .standard,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.prominence = prominence
        self.role = role
        self.action = action
    }

    @ViewBuilder
    var body: some View {
        if prominence == .primary {
            button
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
        } else {
            button
                .buttonStyle(.bordered)
                .controlSize(.regular)
        }
    }

    private var button: some View {
        Button(role: role, action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.titleAndIcon)
                .frame(minWidth: 82)
                .contentShape(Rectangle())
        }
    }
}

private struct StatusPill: View {
    let title: String
    let systemImage: String
    let color: Color

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(color)
            .background(color.opacity(0.12), in: Capsule())
    }
}

private struct SettingsSidebarStatus: View {
    let title: String
    let subtitle: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                Text(title)
                    .font(.caption.weight(.semibold))
            }
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct EmptySettingsState: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 24))
                .foregroundStyle(.secondary)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }
}
