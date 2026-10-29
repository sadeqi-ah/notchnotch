import SwiftUI
import NotchProtocol

struct ManagementAccessView: View {
    let manifest: ExtensionManifest
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if manifest.permissions.isEmpty {
                Label("This extension doesn’t request access to other apps.", systemImage: "checkmark.shield").foregroundStyle(.secondary)
            }
            if manifest.permissions.contains("process") {
                Label("Run native tools", systemImage: "terminal").font(.headline)
                Text("Declared tools run with your account. Permission is requested before the connection starts.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if manifest.permissions.contains("local-network") {
                Label("Connect to local apps", systemImage: "network").font(.headline)
                Text("Only the local destinations listed below can be contacted.").font(.callout).foregroundStyle(.secondary)
            }
            ForEach((manifest.connections ?? [:]).keys.sorted(), id: \.self) { id in
                if let connection = manifest.connections?[id] {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(id).font(.headline)
                        Text(connection.endpoint ?? connection.executable ?? "").font(.callout.monospaced()).textSelection(.enabled)
                        if let arguments = connection.arguments, !arguments.isEmpty {
                            Text(arguments.joined(separator: " ")).font(.callout.monospaced()).textSelection(.enabled).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
