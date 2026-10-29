import AppKit
import Observation
import NotchCore
import NotchProtocol
import NotchExtensions

@MainActor @Observable
final class AppModel {
    var platform = PlatformState()
    private(set) var installedExtensions: [InstalledExtension] = []
    private(set) var libraryIssues: [String: String] = [:]
    private(set) var extensionSettings: [String: UINode] = [:]
    private(set) var extensionSessionIDs: [String: UUID] = [:]
    private var snapshotRevisions: [String: Int] = [:]
    private var disabledExtensionIDs = Set(UserDefaults.standard.stringArray(forKey: "disabledExtensionIDs") ?? [])
    private var installingIDs: Set<String> = []
    var expandOnHover: Bool = UserDefaults.standard.object(forKey: "expandOnHover") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(expandOnHover, forKey: "expandOnHover")
            hoverTask?.cancel()
            hover.reset()
            onLayoutChange?()
        }
    }
    var extensionStore: ExtensionStore {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return ExtensionStore(directory: support.appendingPathComponent("NotchNotch/Extensions"))
    }
    var errors: [String: String] = [:]
    var notchWidth: CGFloat = 180
    var topHeight: CGFloat = 34
    var hasNotch = false
    private var contentSizing = ActivityContentSizing()
    var contentHeight: CGFloat { contentSizing.height }
    private(set) var pageDirection: ActivityPageDirection = .next
    private var reservedCanvasHeight: CGFloat = 0
    private var hover = HoverState()
    private var idlePinned = false
    var hoverExpanded: Bool { hover.isExpanded }
    var onLayoutChange: (() -> Void)?
    var onOpenManagement: (() -> Void)?
    var onRevealActivity: ((SurfaceKey) -> Void)?
    private var pointerInside = false
    private var suppressHover = false
    private var hoverTask: Task<Void, Never>?
    private var peekTask: Task<Void, Never>?
    private var scheduledPeek: ActivePeek?
    private(set) var lastPeekText = ""
    private var connections: [String: RunnerConnection] = [:]
    private var reloads: [String: String] = [:]
    private var reloadTimer: Timer?

    var isExpanded: Bool { platform.isExpanded || idlePinned || hoverExpanded }
    var displayedSurface: HostedSurface? {
        platform.isExpanded ? platform.selected : platform.hoverSurface
    }
    var wingSurface: HostedSurface? {
        presentation == .hovered ? platform.hoverSurface : platform.compact
    }
    var playerNode: UINode? { displayedSurface?.surface.expanded.children.first { $0.type == .player } }
    var presentation: NotchPresentation {
        if isExpanded { return .expanded }
        if platform.activePeek != nil { return .peek }
        if hover.isHighlighted { return .hovered }
        return platform.presentation
    }
    var isPeeking: Bool { presentation == .peek }
    var geometry: NotchGeometry {
        .init(cameraWidth: notchWidth, cameraHeight: topHeight, attached: hasNotch,
              contentHeight: contentHeight, hasActivity: platform.compact != nil || platform.pendingCount > 0,
              reservedCanvasHeight: reservedCanvasHeight, expandedHeaderHeight: 0)
    }
    var extensionRoot: URL {
        if let value = ProcessInfo.processInfo.environment["NOTCHNOTCH_EXTENSIONS"] { return URL(fileURLWithPath: value) }
        return Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/extensions")
    }
    var runnerURL: URL {
        if let value = ProcessInfo.processInfo.environment["NOTCHNOTCH_RUNNER"] { return URL(fileURLWithPath: value) }
        return Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/ExtensionRunner")
    }

    func start() {
        reloadExtensions()
        if ProcessInfo.processInfo.environment["NOTCHNOTCH_DEV"] == "1" {
            reloadTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.reloadExtensions() }
            }
        }
    }

    func reloadExtensions(force: Bool = false, restarting: String? = nil) {
        let scan = extensionStore.scan(included: extensionRoot, development: ProcessInfo.processInfo.environment["NOTCHNOTCH_EXTENSIONS"] != nil)
        if installedExtensions != scan.extensions { installedExtensions = scan.extensions }
        if libraryIssues != scan.issues { libraryIssues = scan.issues }
        let candidates = scan.extensions.filter { isEnabled($0.id) && !installingIDs.contains($0.id) }
        let ids = Set(candidates.map(\.id))
        for id in connections.keys.filter({ !ids.contains($0) }) { stopExtension(id) }
        for record in candidates {
            let manifest = record.manifest
            do {
                let bundle = record.directory.appendingPathComponent(manifest.entry)
                let modified = try bundle.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys]
                let revision = "\(record.directory.path):\(modified.timeIntervalSinceReferenceDate):\(try encoder.encode(manifest).base64EncodedString())"
                guard force || restarting == manifest.id || reloads[manifest.id] != revision else { continue }
                stopExtension(manifest.id)
                let sessionID = UUID()
                extensionSessionIDs[manifest.id] = sessionID
                let connection = RunnerConnection(manifest: manifest, directory: record.directory) { [weak self] snapshot in
                    guard let self, self.extensionSessionIDs[manifest.id] == sessionID else { return }
                    guard snapshot.revision > self.snapshotRevisions[manifest.id, default: 0] else { return }
                    do {
                        try self.platform.apply(snapshot, expectedExtensionID: manifest.id, allowPeek: !self.isExpanded)
                        self.snapshotRevisions[manifest.id] = snapshot.revision
                        if self.extensionSettings[manifest.id] != snapshot.settings { self.extensionSettings[manifest.id] = snapshot.settings }
                    }
                    catch { self.errors[manifest.id] = error.localizedDescription }
                    self.synchronizePeek()
                    self.onLayoutChange?()
                } onFailure: { [weak self] message in
                    guard let self, self.extensionSessionIDs[manifest.id] == sessionID else { return }
                    self.extensionSessionIDs.removeValue(forKey: manifest.id)
                    self.platform.removeExtension(manifest.id)
                    self.extensionSettings.removeValue(forKey: manifest.id)
                    self.synchronizePeek()
                    self.errors[manifest.id] = message
                    self.onLayoutChange?()
                }
                connections[manifest.id] = connection
                reloads[manifest.id] = revision
                try connection.start(executable: runnerURL, bundle: bundle)
            } catch { errors[manifest.id] = error.localizedDescription }
        }
        synchronizePeek()
        onLayoutChange?()
    }

    func isEnabled(_ id: String) -> Bool { !disabledExtensionIDs.contains(id) }
    func isRunning(_ id: String) -> Bool { connections[id] != nil && errors[id] == nil }
    func hasRendered(_ id: String) -> Bool { snapshotRevisions[id] != nil }
    subscript(enabledFor id: String) -> Bool {
        get { isEnabled(id) }
        set { setEnabled(newValue, for: id) }
    }
    func setEnabled(_ enabled: Bool, for id: String) {
        guard isEnabled(id) != enabled else { return }
        if enabled { disabledExtensionIDs.remove(id) } else { disabledExtensionIDs.insert(id) }
        UserDefaults.standard.set(disabledExtensionIDs.sorted(), forKey: "disabledExtensionIDs")
        reloadExtensions()
    }
    func canRevealActivity(_ id: String) -> Bool { platform.surfaces.contains { $0.key.extensionID == id } }
    func revealActivity(_ id: String) {
        if let key = platform.surfaces.first(where: { $0.key.extensionID == id })?.key { onRevealActivity?(key) }
    }
    func restartExtension(_ id: String) { reloadExtensions(restarting: id) }
    func disconnectExtension(_ id: String) { connections[id]?.resetConnections() }
    private func stopExtension(_ id: String) {
        extensionSessionIDs.removeValue(forKey: id)
        connections.removeValue(forKey: id)?.stop()
        platform.removeExtension(id)
        reloads.removeValue(forKey: id)
        errors.removeValue(forKey: id)
        extensionSettings.removeValue(forKey: id)
        snapshotRevisions.removeValue(forKey: id)
    }
    func reviewInstall(_ folder: URL) async throws -> ExtensionPackage {
        let store = extensionStore
        let package = try await Task.detached(priority: .userInitiated) { try store.inspect(folder) }.value
        if let existing = installedExtensions.first(where: { $0.id == package.id }), !store.isManaged(existing) {
            throw ProtocolError.invalid("\(existing.manifest.name) is included with NotchNotch and cannot be replaced. Use a different extension identifier.")
        }
        return package
    }
    func installExtension(_ package: ExtensionPackage) async throws {
        // Check again at confirmation time; included/development ids cannot be replaced.
        if let existing = installedExtensions.first(where: { $0.id == package.id }), !extensionStore.isManaged(existing) {
            throw ProtocolError.invalid("An included extension already uses this identifier.")
        }
        let replacing = installedExtensions.contains { $0.id == package.id }
        installingIDs.insert(package.id)
        stopExtension(package.id)
        defer { installingIDs.remove(package.id); reloadExtensions() }
        let store = extensionStore
        _ = try await Task.detached(priority: .userInitiated) { try store.install(package, replacing: replacing) }.value
    }
    func removeExtension(_ record: InstalledExtension) async throws {
        guard extensionStore.isManaged(record) else { throw ProtocolError.invalid("Included extensions can be disabled but not removed.") }
        installingIDs.insert(record.id)
        stopExtension(record.id)
        defer { installingIDs.remove(record.id); reloadExtensions() }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            NSWorkspace.shared.recycle([record.directory]) { _, error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
    }

    func stop() {
        hoverTask?.cancel()
        peekTask?.cancel()
        reloadTimer?.invalidate()
        for connection in connections.values { connection.stop() }
        connections.removeAll()
    }
    func disconnectExtensions() {
        for connection in connections.values { connection.resetConnections() }
    }
    func toggle() {
        if platform.isExpanded || idlePinned { close() }
        else { pinOpen() }
    }
    func close() {
        hoverTask?.cancel()
        hover.reset()
        idlePinned = false
        suppressHover = pointerInside
        platform.close()
        synchronizePeek()
        onLayoutChange?()
    }
    func open(_ key: SurfaceKey) {
        if let current = platform.surfaces.firstIndex(where: { $0.key == displayedSurface?.key }),
           let target = platform.surfaces.firstIndex(where: { $0.key == key }), current != target {
            pageDirection = target > current ? .next : .previous
        }
        hoverTask?.cancel()
        hover.reset()
        idlePinned = false
        platform.open(key)
        selectContent()
        synchronizePeek()
        onLayoutChange?()
    }
    func switchActivity(_ direction: ActivityPageDirection) {
        guard isExpanded,
              let current = platform.surfaces.firstIndex(where: { $0.key == displayedSurface?.key }) else { return }
        let target = current + direction.rawValue
        guard platform.surfaces.indices.contains(target) else { return }
        open(platform.surfaces[target].key)
    }
    func selectContent() {
        guard contentSizing.select(displayedSurface?.key) else { return }
        contentSizeChanged()
    }
    func measureContent(_ height: CGFloat, for key: SurfaceKey?) {
        let selectionChanged = contentSizing.select(displayedSurface?.key)
        let measurementChanged = contentSizing.measure(height, for: key)
        guard selectionChanged || measurementChanged else { return }
        contentSizeChanged()
    }
    private func contentSizeChanged() {
        // Reserve enough room BEFORE the shape grows. Reuse that space on
        // smaller surfaces so a closing spring cannot be clipped by the window.
        reservedCanvasHeight = geometry.canvasSize.height
        onLayoutChange?()
    }
    func pointerChanged(inside: Bool) {
        guard pointerInside != inside else { return }
        pointerInside = inside
        hoverTask?.cancel()
        if !inside { suppressHover = false }
        guard !platform.isExpanded, !idlePinned, !isPeeking, !suppressHover else { return }
        hover.pointerChanged(inside: inside)
        onLayoutChange?()
        guard expandOnHover, let deadline = hover.deadline else { return }
        hoverTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(max(0, deadline.timeIntervalSinceNow))) }
            catch { return }
            guard let self, !self.platform.isExpanded, !self.idlePinned, !self.isPeeking else { return }
            self.hover.advance(now: deadline)
            self.onLayoutChange?()
        }
    }
    func pinOpen() {
        if let key = displayedSurface?.key { open(key) }
        else {
            hoverTask?.cancel()
            hover.reset()
            idlePinned = true
            onLayoutChange?()
        }
    }
    private func synchronizePeek() {
        if let text = platform.peeking?.surface.peek?.text { lastPeekText = text }
        guard scheduledPeek != platform.activePeek else { return }
        peekTask?.cancel()
        scheduledPeek = platform.activePeek
        guard let peek = platform.activePeek else { return }
        hoverTask?.cancel()
        hover.reset()
        peekTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(max(0, peek.expiresAt.timeIntervalSinceNow))) }
            catch { return }
            guard let self, self.platform.activePeek == peek else { return }
            self.platform.expirePeek(now: peek.expiresAt)
            self.scheduledPeek = nil
            self.onLayoutChange?()
        }
    }
    func openFirst() { pinOpen() }
    func previewAnnouncement() {
        guard let item = platform.compact.flatMap({ $0.surface.peek == nil ? nil : $0 })
            ?? platform.surfaces.first(where: { $0.surface.peek != nil }) else { return }
        hoverTask?.cancel()
        hover.reset()
        idlePinned = false
        suppressHover = pointerInside
        platform.showPeek(for: item.key)
        synchronizePeek()
        onLayoutChange?()
    }
    func openPrompt() {
        if let key = platform.surfaces.first(where: { $0.surface.kind == .prompt })?.key { open(key) }
    }
    func send(extensionID: String, action: String, value: String?) {
        // Once the user interacts, leaving the hover region must not dismiss a form.
        if !platform.isExpanded { pinOpen() }
        connections[extensionID]?.send(action: action, value: value)
    }
    func sendSettings(extensionID: String, action: String, value: String?) {
        // Setup actions use the same runner but never focus or pin the notch.
        guard isEnabled(extensionID), let settings = extensionSettings[extensionID] else { return }
        func containsAction(_ node: UINode) -> Bool {
            (node.props.action == action && node.props.disabled != true) || node.children.contains(where: containsAction)
        }
        guard containsAction(settings) else { return }
        connections[extensionID]?.send(action: action, value: value)
    }
}
