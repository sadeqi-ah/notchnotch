import AppKit
import Observation
import NotchExtensions

@MainActor @Observable
final class ManagementCoordinator {
    let model: AppModel
    var destination: ManagementDestination = .extensions {
        didSet { if destination != oldValue { message = nil; error = nil } }
    }
    var query = "" {
        didSet {
            if case .extensionDetails(let id) = destination, !visibleExtensions.contains(where: { $0.id == id }) {
                destination = .extensions
            }
        }
    }
    var sheet: ManagementSheet?
    var sheetError: String?
    var error: String?
    var message: String?
    private(set) var choosingPackage = false
    private(set) var operating = false
    @ObservationIgnored weak var window: NSWindow?
    @ObservationIgnored private var picker: NSOpenPanel?
    @ObservationIgnored private var pickerGeneration = 0

    init(model: AppModel) { self.model = model }
    var busy: Bool { choosingPackage || operating }
    var visibleExtensions: [InstalledExtension] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return model.installedExtensions.filter { term.isEmpty || $0.manifest.name.localizedCaseInsensitiveContains(term) || $0.id.localizedCaseInsensitiveContains(term) }
    }
    var enabledCount: Int { model.installedExtensions.filter { model.isEnabled($0.id) }.count }

    func selectExtension(_ id: String) {
        guard model.installedExtensions.contains(where: { $0.id == id }) else { return }
        query = ""
        destination = .extensionDetails(id)
    }
    func reconcileSelection() {
        if case .extensionDetails(let id) = destination, !model.installedExtensions.contains(where: { $0.id == id }) { destination = .extensions }
    }
    func choosePackage() {
        guard !busy, sheet == nil, let window else { return }
        choosingPackage = true
        error = nil
        message = nil
        pickerGeneration += 1
        let generation = pickerGeneration
        let panel = NSOpenPanel()
        picker = panel
        panel.title = "Install Extension"
        panel.message = "Choose a built extension folder containing notchnotch.json and bundle.js."
        panel.prompt = "Review Extension"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        Task { @MainActor in
            defer { if generation == pickerGeneration { choosingPackage = false; picker = nil } }
            guard await panel.beginSheetModal(for: window) == .OK, let folder = panel.url else { return }
            do {
                let package = try await model.reviewInstall(folder)
                guard generation == pickerGeneration else { return }
                sheetError = nil
                sheet = .install(package)
            } catch { if generation == pickerGeneration { self.error = error.localizedDescription } }
        }
    }
    func confirmInstall(_ package: ExtensionPackage) {
        guard !operating else { return }
        let updating = model.installedExtensions.contains { $0.id == package.id }
        operating = true
        sheetError = nil
        Task { @MainActor in
            defer { operating = false }
            do {
                try await model.installExtension(package)
                sheet = nil
                selectExtension(package.id)
                message = "\(package.manifest.name) \(updating ? "updated" : "installed")."
            } catch { sheetError = error.localizedDescription }
        }
    }
    func requestRemoval(_ record: InstalledExtension) {
        guard !busy, model.extensionStore.isManaged(record) else { return }
        sheetError = nil
        sheet = .remove(record)
    }
    func confirmRemoval(_ record: InstalledExtension) {
        guard !operating else { return }
        operating = true
        sheetError = nil
        Task { @MainActor in
            defer { operating = false }
            do {
                try await model.removeExtension(record)
                sheet = nil
                destination = .extensions
                message = "\(record.manifest.name) moved to Trash."
            } catch { sheetError = error.localizedDescription }
        }
    }
    func dismissSheet() {
        guard !operating else { return }
        sheet = nil
        sheetError = nil
    }
    func windowClosed() {
        pickerGeneration += 1
        picker?.cancel(nil)
        picker = nil
        choosingPackage = false
        if !operating { dismissSheet() }
    }
    func showFolder() {
        do {
            try FileManager.default.createDirectory(at: model.extensionStore.directory, withIntermediateDirectories: true)
            NSWorkspace.shared.open(model.extensionStore.directory)
        } catch { self.error = error.localizedDescription }
    }
}
