import NotchExtensions

enum ManagementSheet: Identifiable {
    case install(ExtensionPackage)
    case remove(InstalledExtension)
    var id: String {
        switch self {
        case .install(let package): "install:" + package.id
        case .remove(let record): "remove:" + record.id
        }
    }
}
