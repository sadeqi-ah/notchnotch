import SwiftUI

struct ManagementGeneralPage: View {
    @Bindable var coordinator: ManagementCoordinator
    var body: some View {
        @Bindable var model = coordinator.model
        Form {
            Section {
                Toggle("Expand on hover", isOn: $model.expandOnHover).toggleStyle(.switch)
            } footer: {
                Text("Keep the pointer over the notch to preview an activity. Clicking always opens it.")
            }
            Section {
                LabeledContent("Local services and native helpers") {
                    Button("Disconnect All") {
                        coordinator.model.disconnectExtensions()
                        coordinator.message = "App connections closed. Reconnect from an extension’s setup page."
                    }.disabled(coordinator.busy)
                }
            } header: {
                Text("App Connections")
            } footer: {
                Text("Reconnect from each extension’s setup page.")
            }
            Section("Extension Library") {
                LabeledContent("Installed on this Mac") {
                    Button("Show in Finder", action: coordinator.showFolder)
                }
            }
            Section("About") {
                LabeledContent("NotchNotch", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0")
                LabeledContent("Release", value: "Developer Preview")
            }
        }.formStyle(.grouped)
    }
}
