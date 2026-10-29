import AppKit
import SwiftUI
import NotchExtensions
import NotchRenderer

struct ManagementExtensionPage: View {
    @Bindable var coordinator: ManagementCoordinator
    let record: InstalledExtension
    @State private var showAccess = false
    @State private var showPackage = false

    var body: some View {
        @Bindable var model = coordinator.model
        Form {
            Section {
                Toggle(isOn: $model[enabledFor: record.id]) {
                    Label {
                        Text("Enable \(record.manifest.name)")
                    } icon: {
                        ExtensionIdentityView(manifest: record.manifest)
                    }
                }.toggleStyle(.switch).disabled(coordinator.busy)
            } footer: {
                Text(coordinator.model.isEnabled(record.id)
                    ? record.manifest.description ?? "This extension can show activities in your notch."
                    : "This extension’s activities and app connections are stopped.")
            }
            if let error = coordinator.model.errors[record.id] {
                Section {
                    Label("This extension needs attention", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                    Text(error).textSelection(.enabled)
                    HStack {
                        Spacer()
                        Button("Try Restarting") { coordinator.model.restartExtension(record.id) }
                            .disabled(!coordinator.model.isEnabled(record.id) || coordinator.busy)
                    }
                }
            }
            if coordinator.model.isEnabled(record.id) {
                if let tree = coordinator.model.extensionSettings[record.id] {
                    Section("Setup") {
                        SettingsNodeView(node: tree) { action, value in
                            coordinator.model.sendSettings(extensionID: record.id, action: action, value: value)
                        }
                        .id(coordinator.model.extensionSessionIDs[record.id])
                        .disabled(coordinator.busy)
                    }
                } else if !coordinator.model.hasRendered(record.id), coordinator.model.errors[record.id] == nil {
                    Section {
                        HStack {
                            ProgressView().controlSize(.small)
                            Text("Starting extension…").foregroundStyle(.secondary)
                        }
                    }
                } else if coordinator.model.errors[record.id] == nil {
                    Section {
                        if coordinator.model.canRevealActivity(record.id) {
                            LabeledContent("Activity") {
                                Button("Open in Notch") { coordinator.model.revealActivity(record.id) }
                            }
                        } else {
                            LabeledContent("Status", value: "Ready")
                        }
                    } footer: {
                        Text("No additional setup is required. Activities appear in the notch when you need them.")
                    }
                }
            }
            Section {
                DisclosureGroup("App Access", isExpanded: $showAccess) {
                    ManagementAccessView(manifest: record.manifest)
                }
                DisclosureGroup("Package Details", isExpanded: $showPackage) {
                    LabeledContent("Version", value: record.manifest.version)
                    LabeledContent("Source", value: record.origin.rawValue)
                    LabeledContent("Identifier", value: record.id).textSelection(.enabled)
                    Text(record.directory.path).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                    HStack {
                        Spacer()
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([record.directory]) }
                    }
                }
            }
            Section("Maintenance") {
                LabeledContent("Extension") {
                    Button("Restart") { coordinator.model.restartExtension(record.id) }
                        .disabled(!coordinator.model.isEnabled(record.id) || coordinator.busy)
                }
                if !(record.manifest.connections ?? [:]).isEmpty {
                    LabeledContent("App connections") {
                        Button("Disconnect") { coordinator.model.disconnectExtension(record.id) }
                            .disabled(!coordinator.model.isEnabled(record.id) || coordinator.busy)
                    }
                }
                if coordinator.model.extensionStore.isManaged(record) {
                    LabeledContent("Installed package") {
                        Button("Remove Extension…", role: .destructive) { coordinator.requestRemoval(record) }
                            .disabled(coordinator.busy)
                    }
                }
            }
        }.formStyle(.grouped)
    }
}
