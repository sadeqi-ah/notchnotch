import AppKit
import SwiftUI

struct ManagementExtensionsPage: View {
    @Bindable var coordinator: ManagementCoordinator
    var body: some View {
        Form {
            Section {
                if coordinator.visibleExtensions.isEmpty {
                    ContentUnavailableView {
                        Label(coordinator.query.isEmpty ? "No extensions installed" : "No matching extensions", systemImage: "puzzlepiece.extension")
                    } description: {
                        Text(coordinator.query.isEmpty ? "Install an extension to add activities to your notch." : "Try another name or extension identifier.")
                    } actions: {
                        if !coordinator.query.isEmpty { Button("Clear Search") { coordinator.query = "" } }
                    }
                } else {
                    ForEach(coordinator.visibleExtensions) { record in
                        Button {
                            coordinator.selectExtension(record.id)
                        } label: {
                            HStack(spacing: 10) {
                                ExtensionIdentityView(manifest: record.manifest)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(record.manifest.name)
                                    Text(record.manifest.description ?? record.origin.rawValue)
                                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 8)
                                Text(coordinator.model.isEnabled(record.id) ? "On" : "Off").foregroundStyle(.secondary)
                                Image(systemName: "chevron.right").font(.callout).foregroundStyle(.tertiary)
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
            } header: {
                Text("Installed Extensions")
            } footer: {
                Text("\(coordinator.model.installedExtensions.count) installed. \(coordinator.enabledCount) enabled.")
            }
            Section {
                LabeledContent("Add an extension") {
                    Button("Install from Folder…", action: coordinator.choosePackage)
                        .disabled(coordinator.busy).keyboardShortcut("i", modifiers: [.command, .shift])
                }
            } footer: {
                Text("Choose a built extension folder from a developer you trust.")
            }
            if !coordinator.model.libraryIssues.isEmpty {
                Section("Folders That Couldn’t Load") {
                    ForEach(coordinator.model.libraryIssues.keys.sorted(), id: \.self) { path in
                        LabeledContent {
                            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }
                        } label: {
                            Text(URL(fileURLWithPath: path).lastPathComponent)
                            Text(coordinator.model.libraryIssues[path] ?? "").font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                    }
                }
            }
        }.formStyle(.grouped)
    }
}
