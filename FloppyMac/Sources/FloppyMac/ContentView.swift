import AppKit
import FloppyCore
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var model: FloppyAppModel
    @State private var showsAdvancedOnboarding = false
    @State private var isDropTargeted = false

    var body: some View {
        NavigationSplitView {
            List(
                selection: Binding(
                    get: { model.selectedAccountID },
                    set: { model.selectAccount(id: $0) }
                )
            ) {
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
            await model.refreshSelectedAccountIfStale()
        }
    }

    private var connectPanel: some View {
        FloppyOnboardingFlowView(model: model, showsAdvanced: $showsAdvancedOnboarding, layout: .sidebar)
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
                model.chooseFilesForUpload()
            } label: {
                Label("Add Files", systemImage: "plus")
            }
            .disabled(!canRunNetworkAction)
            Button {
                model.openNativeFolder()
            } label: {
                Label("Open Folder", systemImage: "folder")
            }
            .disabled(!hasSelectedAccount)
            Button {
                Task { await model.refreshSelectedAccountIfStale(maxAge: 0) }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(!canRunNetworkAction)
            Button {
                Task { await model.syncSelectedAccount() }
            } label: {
                Label("Sync", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(!canRunNetworkAction)
            Button {
                Task { await model.loadHealth() }
            } label: {
                Label("Health", systemImage: "stethoscope")
            }
            .disabled(!canRunNetworkAction)
            Button(role: .destructive) {
                model.disconnectSelectedAccount()
            } label: {
                Label("Disconnect", systemImage: "xmark.circle")
            }
            .disabled(!hasSelectedAccount)
        }
        .padding()
    }

    private var fileList: some View {
        ZStack {
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

            if model.items.isEmpty {
                ContentUnavailableView("Drop files here", systemImage: "tray.and.arrow.down", description: Text("Add files to your WordPress-owned Floppy folder."))
                    .allowsHitTesting(false)
            }

            if isDropTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.tint.opacity(0.12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(.tint, style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                    }
                    .padding(18)
                    .overlay {
                        Label("Drop to add to Floppy", systemImage: "arrow.down.doc")
                            .font(.title3.bold())
                            .padding(12)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .allowsHitTesting(false)
            }
        }
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isDropTargeted) { providers in
            model.uploadDroppedProviders(providers)
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

    private var hasSelectedAccount: Bool {
        model.selectedAccount != nil
    }

    private var canStartAccountWork: Bool {
        hasSelectedAccount && !model.isWorking
    }

    private var canRunNetworkAction: Bool {
        canStartAccountWork && model.isNetworkReachable
    }
}

private extension ByteCountFormatter {
    static func string(from byteCount: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: byteCount)
    }
}
