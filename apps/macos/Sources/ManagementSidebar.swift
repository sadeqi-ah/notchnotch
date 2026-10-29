import SwiftUI

struct ManagementSidebar: View {
    @Bindable var coordinator: ManagementCoordinator
    var body: some View {
        VStack(spacing: 0) {
            ManagementSearchField(text: $coordinator.query)
                .frame(height: 24).padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 4)
            List(selection: $coordinator.destination) {
                Section {
                    Label { Text("General") } icon: { ManagementSidebarIcon(symbol: "gearshape", color: .gray) }
                        .tag(ManagementDestination.general)
                    Label { Text("Extensions") } icon: { ManagementSidebarIcon(symbol: "puzzlepiece.extension.fill", color: .blue) }
                        .tag(ManagementDestination.extensions)
                    Label { Text("Marketplace") } icon: { ManagementSidebarIcon(symbol: "bag.fill", color: .purple) }
                        .tag(ManagementDestination.marketplace)
                }
                Section("Installed") {
                    ForEach(coordinator.visibleExtensions) { record in
                        HStack {
                            Label {
                                Text(record.manifest.name).lineLimit(1)
                            } icon: {
                                ExtensionIdentityView(manifest: record.manifest, size: 20)
                            }
                            Spacer(minLength: 0)
                            if !coordinator.model.isEnabled(record.id) {
                                Image(systemName: "pause.circle").foregroundStyle(.secondary).help("Disabled")
                            } else if coordinator.model.errors[record.id] != nil {
                                Image(systemName: "exclamationmark.circle").foregroundStyle(.orange).help("Needs attention")
                            }
                        }.tag(ManagementDestination.extensionDetails(record.id))
                    }
                }
            }
            .listStyle(.sidebar)
        }
    }
}
