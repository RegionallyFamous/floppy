import AppKit
import FloppyCore
import SwiftUI

struct FloppyOnboardingFlowView: View {
    enum Layout {
        case compact
        case sidebar
    }

    @ObservedObject var model: FloppyAppModel
    @Binding var showsAdvanced: Bool
    var layout: Layout = .compact

    var body: some View {
        VStack(alignment: .leading, spacing: layout == .compact ? 11 : 14) {
            header
            siteField
            actionRow
            verificationList
            statusPanel
            advancedFields
            recoveryActions
            privacyFooter
        }
        .padding(layout == .compact ? 12 : 14)
        .background(.quaternary.opacity(layout == .compact ? 0.36 : 0.28), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Floppy connection setup")
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: layout == .compact ? 30 : 36, height: layout == .compact ? 30 : 36)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text("Connect Floppy")
                    .font(.system(size: layout == .compact ? 15 : 18, weight: .semibold))
                Text("WordPress-owned storage")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var siteField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("WordPress site")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            TextField("https://example.com", text: $model.siteURLText)
                .textFieldStyle(.roundedBorder)
                .disabled(model.isOnboarding)
                .accessibilityLabel("WordPress site URL")
                .accessibilityHint("Enter the WordPress site to connect with Floppy.")
        }
    }

    private var actionRow: some View {
        HStack(spacing: 8) {
            Button {
                performPrimaryAction()
            } label: {
                Label(primaryActionTitle, systemImage: primaryActionImage)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!primaryActionEnabled)
            .accessibilityHint(primaryActionHint)

            if model.isOnboarding {
                Button {
                    model.cancelOnboarding()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .help("Cancel")
                .accessibilityLabel("Cancel setup")
            }
        }
    }

    private var verificationList: some View {
        VStack(spacing: 7) {
            ForEach(checks) { check in
                FloppyOnboardingCheckRow(check: check)
            }
        }
        .padding(.top, 1)
    }

    private var statusPanel: some View {
        HStack(alignment: .top, spacing: 8) {
            if model.isOnboarding {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.72)
                    .frame(width: 18, height: 18)
                    .accessibilityLabel("Setup in progress")
            } else {
                Image(systemName: model.onboardingStep.systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(statusColor)
                    .frame(width: 18, height: 18)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(model.onboardingStep.detail)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if !model.status.isEmpty {
                    Text(model.status)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(statusColor)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var advancedFields: some View {
        DisclosureGroup(isExpanded: $showsAdvanced) {
            VStack(alignment: .leading, spacing: 8) {
                TextField("GitHub release ZIP", text: $model.githubPluginZipURLText)
                    .textFieldStyle(.roundedBorder)
                    .disabled(model.isOnboarding)
                    .accessibilityLabel("GitHub release ZIP URL")
                TextField("Plugin file", text: $model.pluginMainFile)
                    .textFieldStyle(.roundedBorder)
                    .disabled(model.isOnboarding)
                    .accessibilityLabel("Plugin main file")
                TextField("Device name", text: $model.deviceName)
                    .textFieldStyle(.roundedBorder)
                    .disabled(model.isOnboarding)
                    .accessibilityLabel("Device name")
                HStack {
                    Spacer()
                    Button {
                        model.resetAdvancedOnboardingFields()
                    } label: {
                        Label("Reset", systemImage: "arrow.counterclockwise")
                    }
                    .controlSize(.small)
                    .disabled(model.isOnboarding)
                }
            }
            .padding(.top, 6)
        } label: {
            Label("Advanced", systemImage: "slider.horizontal.3")
                .font(.system(size: 12, weight: .medium))
        }
    }

    @ViewBuilder
    private var recoveryActions: some View {
        if model.lastDownloadedPluginZipURL != nil || model.pendingPluginUploadURL != nil {
            HStack(spacing: 8) {
                Button {
                    model.revealDownloadedPluginZip()
                } label: {
                    Label("Reveal ZIP", systemImage: "folder")
                }
                .disabled(model.lastDownloadedPluginZipURL == nil)

                Button {
                    model.openPluginUploadPage()
                } label: {
                    Label("Open Upload", systemImage: "safari")
                }
                .disabled(model.pendingPluginUploadURL == nil)
            }
            .controlSize(.small)
        }
    }

    private var privacyFooter: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.shield")
                .font(.system(size: 11, weight: .semibold))
            Text("No external service")
                .font(.system(size: 11, weight: .medium))
            Spacer(minLength: 6)
            Text(model.onboardingStep.title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .foregroundStyle(.secondary)
        .padding(.top, 1)
    }

    private var checks: [FloppyOnboardingCheck] {
        [
            siteCheck,
            githubCheck,
            approvalCheck,
            tokenCheck,
            finderCheck
        ]
    }

    private var siteCheck: FloppyOnboardingCheck {
        guard !model.siteURLText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return FloppyOnboardingCheck(title: "WordPress site", detail: "Enter your site", systemImage: "globe", state: .pending)
        }

        guard let url = URL.floppySiteURL(from: model.siteURLText), url.host != nil else {
            return FloppyOnboardingCheck(title: "WordPress site", detail: "Check the URL", systemImage: "globe", state: .warning)
        }

        if url.usesSecureSchemeForOnboarding {
            return FloppyOnboardingCheck(title: "WordPress site", detail: url.host ?? "Ready", systemImage: "globe", state: model.isOnboarding ? .complete : .ready)
        }

        return FloppyOnboardingCheck(title: "WordPress site", detail: "Use HTTPS or localhost", systemImage: "globe", state: .warning)
    }

    private var githubCheck: FloppyOnboardingCheck {
        guard let url = URL.floppySiteURL(from: model.githubPluginZipURLText) else {
            return FloppyOnboardingCheck(title: "GitHub plugin", detail: "ZIP required", systemImage: "shippingbox", state: .warning)
        }

        do {
            try FloppyGitHubZipValidator.validateReleaseAssetURL(url)
        } catch {
            return FloppyOnboardingCheck(title: "GitHub plugin", detail: "Use a GitHub release ZIP", systemImage: "shippingbox", state: .warning)
        }

        let state: FloppyOnboardingCheck.State
        switch model.onboardingStep {
        case .installingPlugin, .waitingForManualGitHubInstall:
            state = .active
        case .activatingPlugin, .creatingDeviceToken, .connected:
            state = .complete
        default:
            state = .ready
        }
        return FloppyOnboardingCheck(title: "GitHub plugin", detail: url.lastPathComponent, systemImage: "shippingbox", state: state)
    }

    private var approvalCheck: FloppyOnboardingCheck {
        switch model.onboardingStep {
        case .waitingForWordPressAuthorization:
            return FloppyOnboardingCheck(title: "Approve", detail: "Waiting in browser", systemImage: "safari", state: .active)
        case .installingPlugin, .waitingForManualGitHubInstall, .activatingPlugin, .creatingDeviceToken, .connected:
            return FloppyOnboardingCheck(title: "Approve", detail: "WordPress approved", systemImage: "checkmark.seal", state: .complete)
        case .failed:
            return FloppyOnboardingCheck(title: "Approve", detail: "Needs retry", systemImage: "safari", state: .warning)
        default:
            return FloppyOnboardingCheck(title: "Approve", detail: "Browser approval", systemImage: "safari", state: .pending)
        }
    }

    private var tokenCheck: FloppyOnboardingCheck {
        switch model.onboardingStep {
        case .creatingDeviceToken:
            return FloppyOnboardingCheck(title: "Device token", detail: "Securing Mac", systemImage: "key", state: .active)
        case .connected:
            return FloppyOnboardingCheck(title: "Device token", detail: "Stored in Keychain", systemImage: "key", state: .complete)
        case .failed:
            return FloppyOnboardingCheck(title: "Device token", detail: "Not connected", systemImage: "key", state: .warning)
        default:
            return FloppyOnboardingCheck(title: "Device token", detail: "Scoped access", systemImage: "key", state: .pending)
        }
    }

    private var finderCheck: FloppyOnboardingCheck {
        if model.selectedAccount != nil {
            return FloppyOnboardingCheck(
                title: "Finder folder",
                detail: model.nativeFolderReadiness.isReady ? "Ready" : "Needs signed app",
                systemImage: "folder",
                state: model.nativeFolderReadiness.isReady ? .complete : .warning
            )
        }

        if model.onboardingStep == .creatingDeviceToken {
            return FloppyOnboardingCheck(title: "Finder folder", detail: "Registering", systemImage: "folder", state: .active)
        }

        return FloppyOnboardingCheck(title: "Finder folder", detail: "Final step", systemImage: "folder", state: .pending)
    }

    private var primaryActionTitle: String {
        switch model.onboardingStep {
        case .waitingForManualGitHubInstall:
            "Open Upload"
        case .connected:
            "Open Floppy Folder"
        case .waitingForWordPressAuthorization:
            "Reopen Approval"
        case .installingPlugin:
            "Preparing"
        case .activatingPlugin:
            "Activating"
        case .creatingDeviceToken:
            "Securing"
        default:
            "Connect"
        }
    }

    private var primaryActionImage: String {
        switch model.onboardingStep {
        case .waitingForManualGitHubInstall:
            "safari"
        case .connected:
            "folder"
        default:
            model.onboardingStep.systemImage
        }
    }

    private var primaryActionEnabled: Bool {
        switch model.onboardingStep {
        case .waitingForManualGitHubInstall:
            model.pendingPluginUploadURL != nil
        case .connected:
            model.selectedAccount != nil
        case .idle, .failed, .waitingForWordPressAuthorization:
            canAttemptConnection
        default:
            false
        }
    }

    private var primaryActionHint: String {
        switch model.onboardingStep {
        case .waitingForManualGitHubInstall:
            "Opens the WordPress upload screen."
        case .connected:
            "Opens the native Floppy folder in Finder."
        default:
            "Opens WordPress in your browser to approve this Mac."
        }
    }

    private var canAttemptConnection: Bool {
        guard let siteURL = URL.floppySiteURL(from: model.siteURLText), siteURL.host != nil, siteURL.usesSecureSchemeForOnboarding else {
            return false
        }

        guard let zipURL = URL.floppySiteURL(from: model.githubPluginZipURLText), (try? FloppyGitHubZipValidator.validateReleaseAssetURL(zipURL)) != nil else {
            return false
        }

        let pluginFile = FloppyGitHubZipValidator.normalizePluginPath(model.pluginMainFile)
        return !pluginFile.isEmpty && pluginFile.hasSuffix(".php") && pluginFile.contains("/")
    }

    private var statusColor: Color {
        switch model.onboardingStep {
        case .connected:
            .green
        case .failed:
            .orange
        default:
            .accentColor
        }
    }

    private func performPrimaryAction() {
        switch model.onboardingStep {
        case .waitingForManualGitHubInstall:
            model.openPluginUploadPage()
        case .connected:
            model.openNativeFolder()
        default:
            model.startBrowserApproval()
        }
    }
}

private struct FloppyOnboardingCheck: Identifiable {
    enum State {
        case pending
        case ready
        case active
        case complete
        case warning
    }

    var id: String { title }
    let title: String
    let detail: String
    let systemImage: String
    let state: State
}

private struct FloppyOnboardingCheckRow: View {
    let check: FloppyOnboardingCheck

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(stateColor.opacity(check.state == .pending ? 0.10 : 0.16))
                Image(systemName: stateImage)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(stateColor)
            }
            .frame(width: 22, height: 22)

            Text(check.title)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)

            Spacer(minLength: 8)

            Text(check.detail)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(height: 28)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(check.title), \(check.detail)")
    }

    private var stateImage: String {
        switch check.state {
        case .pending:
            check.systemImage
        case .ready:
            "checkmark"
        case .active:
            "arrow.triangle.2.circlepath"
        case .complete:
            "checkmark"
        case .warning:
            "exclamationmark"
        }
    }

    private var stateColor: Color {
        switch check.state {
        case .pending:
            .secondary
        case .ready:
            .accentColor
        case .active:
            .blue
        case .complete:
            .green
        case .warning:
            .orange
        }
    }
}
