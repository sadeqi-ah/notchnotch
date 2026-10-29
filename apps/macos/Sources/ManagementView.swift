import SwiftUI

struct ManagementView: View {
    @Bindable var coordinator: ManagementCoordinator
    var body: some View {
        VStack(spacing: 0) {
            if let error = coordinator.error {
                ManagementNotice(text: error, isError: true) { coordinator.error = nil }.padding()
            } else if let message = coordinator.message {
                ManagementNotice(text: message) { coordinator.message = nil }.padding()
            }
            destination
        }
        .frame(minWidth: 450, minHeight: 430)
        .sheet(item: $coordinator.sheet, onDismiss: { coordinator.sheetError = nil }) { item in
            ManagementReviewSheet(coordinator: coordinator, item: item)
        }
        .onChange(of: coordinator.model.installedExtensions.map(\.id)) { _, _ in coordinator.reconcileSelection() }
        .onChange(of: pageTitle, initial: true) { _, title in coordinator.window?.title = title }
    }
    private var pageTitle: String {
        switch coordinator.destination {
        case .extensions: "Extensions"
        case .general: "General"
        case .marketplace: "Marketplace"
        case .extensionDetails(let id): coordinator.model.installedExtensions.first(where: { $0.id == id })?.manifest.name ?? "Extension"
        }
    }
    @ViewBuilder private var destination: some View {
        switch coordinator.destination {
        case .extensions: ManagementExtensionsPage(coordinator: coordinator)
        case .extensionDetails(let id):
            if let record = coordinator.model.installedExtensions.first(where: { $0.id == id }) {
                ManagementExtensionPage(coordinator: coordinator, record: record).id(id)
            } else {
                ContentUnavailableView("Extension unavailable", systemImage: "puzzlepiece.extension",
                    description: Text("Refresh the library or choose another extension."))
            }
        case .marketplace: ManagementMarketplacePage(coordinator: coordinator)
        case .general: ManagementGeneralPage(coordinator: coordinator)
        }
    }
}
