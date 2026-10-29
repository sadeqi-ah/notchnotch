import SwiftUI

struct ManagementMarketplacePage: View {
    @Bindable var coordinator: ManagementCoordinator
    var body: some View {
        Form {
            Section {
                LabeledContent("Online catalog", value: "Not available in this preview")
            }
            Section {
                LabeledContent("Install a local extension") {
                    Button("Choose Folder…", action: coordinator.choosePackage).disabled(coordinator.busy)
                }
            } footer: {
                Text("You can install a built extension folder from a developer you trust.")
            }
        }.formStyle(.grouped)
    }
}
