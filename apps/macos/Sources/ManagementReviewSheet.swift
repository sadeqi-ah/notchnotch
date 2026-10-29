import SwiftUI
import NotchExtensions

struct ManagementReviewSheet: View {
    @Bindable var coordinator: ManagementCoordinator
    let item: ManagementSheet
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header.padding(24)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let error = coordinator.sheetError { ManagementNotice(text: error, isError: true) }
                    details
                }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
            }.frame(minHeight: 160, maxHeight: 320)
            Divider()
            HStack(spacing: 12) {
                if coordinator.operating {
                    ProgressView().controlSize(.small)
                    Text(progressTitle).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel", role: .cancel, action: coordinator.dismissSheet).disabled(coordinator.operating)
                    .keyboardShortcut(.cancelAction)
                confirmButton.disabled(coordinator.operating).keyboardShortcut(.defaultAction)
            }.padding(20)
        }.frame(width: 510).interactiveDismissDisabled(coordinator.operating)
    }
    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            switch item {
            case .install(let package):
                ExtensionIdentityView(manifest: package.manifest, size: 44)
                VStack(alignment: .leading, spacing: 6) {
                    Text(isUpdate ? "Update \(package.manifest.name)?" : "Install \(package.manifest.name)?").font(.title2).bold().lineLimit(2)
                    Text("Version \(package.manifest.version) · \(ByteCountFormatter.string(fromByteCount: Int64(package.byteCount), countStyle: .file))")
                        .font(.callout).foregroundStyle(.secondary).lineLimit(2)
                }
            case .remove(let record):
                Image(systemName: "trash").font(.title).foregroundStyle(.secondary).frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Remove \(record.manifest.name)?").font(.title2).bold().lineLimit(2)
                    Text("Its installed folder will move to Trash.").font(.callout).foregroundStyle(.secondary)
                }
            }
        }
    }
    @ViewBuilder private var details: some View {
        switch item {
        case .install(let package):
            if let old = coordinator.model.installedExtensions.first(where: { $0.id == package.id }) {
                Text("This replaces version \(old.manifest.version). Your enabled/disabled preference is kept.").font(.callout).foregroundStyle(.secondary)
            }
            if let description = package.manifest.description { Text(description) }
            Text(package.id).font(.callout.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
            ManagementAccessView(manifest: package.manifest)
            if package.manifest.permissions.contains("process") {
                Text("Native tools can access files and network with your account. Install only extensions you trust.").font(.callout).foregroundStyle(.secondary)
            }
            Text("App access is requested separately. Installation never runs a build script.").font(.callout).foregroundStyle(.secondary)
        case .remove(let record):
            Text("\(record.manifest.name)’s activities will close and its app connections will stop. You can recover its folder from Trash or install it again later.")
                .foregroundStyle(.secondary)
        }
    }
    private var isUpdate: Bool {
        if case .install(let package) = item { return coordinator.model.installedExtensions.contains { $0.id == package.id } }
        return false
    }
    private var progressTitle: String {
        switch item { case .install: isUpdate ? "Updating…" : "Installing…"; case .remove: "Moving to Trash…" }
    }
    @ViewBuilder private var confirmButton: some View {
        switch item {
        case .install(let package):
            Button(isUpdate ? "Update Extension" : "Install Extension") { coordinator.confirmInstall(package) }.buttonStyle(.borderedProminent)
        case .remove(let record):
            Button("Move to Trash", role: .destructive) { coordinator.confirmRemoval(record) }.buttonStyle(.borderedProminent)
        }
    }
}
