import AppKit
import Observation
import NotchCore
import NotchProtocol

@MainActor @Observable
final class AppModel {
    var platform = PlatformState()
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
    let music = MusicProvider()
    var hoverExpanded: Bool { hover.isExpanded }
    var onLayoutChange: (() -> Void)?
    private var pointerInside = false
    private var suppressHover = false
    private var hoverTask: Task<Void, Never>?
    private var peekTask: Task<Void, Never>?
    private var scheduledPeek: ActivePeek?
    private(set) var lastPeekText = ""
    private var connections: [String: RunnerConnection] = [:]
    private var reloads: [String: Date] = [:]
    private var reloadTimer: Timer?

    var isExpanded: Bool { platform.isExpanded || idlePinned || hoverExpanded }
    var displayedSurface: HostedSurface? {
        platform.isExpanded ? platform.selected : platform.hoverSurface
    }
    var wingSurface: HostedSurface? {
        presentation == .hovered ? platform.hoverSurface : platform.compact
    }
    var musicNode: UINode? { displayedSurface?.surface.expanded.children.first { $0.type == .player } }
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
        music.onChange = { [weak self] state in
            guard let self else { return }
            for connection in self.connections.values { connection.sendMedia(state) }
        }
        music.start()
        reloadExtensions()
        if ProcessInfo.processInfo.environment["NOTCHNOTCH_DEV"] == "1" {
            reloadTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.reloadExtensions() }
            }
        }
    }

    func reloadExtensions(force: Bool = false) {
        do {
            let folders = try FileManager.default.contentsOfDirectory(at: extensionRoot, includingPropertiesForKeys: [.isDirectoryKey])
                .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            var candidates: [(URL, ExtensionManifest)] = []
            for folder in folders {
                do {
                    let manifest = try JSONDecoder().decode(ExtensionManifest.self, from: Data(contentsOf: folder.appendingPathComponent("notchnotch.json")))
                    try manifest.validate()
                    guard !candidates.contains(where: { $0.1.id == manifest.id }) else {
                        throw ProtocolError.invalid("Duplicate extension identifier")
                    }
                    candidates.append((folder, manifest))
                    errors.removeValue(forKey: folder.lastPathComponent)
                } catch { errors[folder.lastPathComponent] = error.localizedDescription }
            }
            let ids = Set(candidates.map { $0.1.id })
            for id in connections.keys.filter({ !ids.contains($0) }) {
                connections.removeValue(forKey: id)?.stop()
                platform.removeExtension(id)
                reloads.removeValue(forKey: id)
                errors.removeValue(forKey: id)
            }
            for (folder, manifest) in candidates.sorted(by: { $0.1.name < $1.1.name }) {
                do {
                    let bundle = folder.appendingPathComponent(manifest.entry)
                    let modified = try bundle.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast
                    guard force || reloads[manifest.id] != modified else { continue }
                    connections[manifest.id]?.stop()
                    platform.removeExtension(manifest.id)
                    errors.removeValue(forKey: manifest.id)
                    let connection = RunnerConnection(manifest: manifest) { [weak self] snapshot in
                        guard let self else { return }
                        do { try self.platform.apply(snapshot, expectedExtensionID: manifest.id, allowPeek: !self.isExpanded) }
                        catch { self.errors[manifest.id] = error.localizedDescription }
                        self.synchronizePeek()
                        self.onLayoutChange?()
                    } onMediaCommand: { [weak self] request in
                        self?.music.perform(request)
                    } onFailure: { [weak self] message in
                        guard let self else { return }
                        self.platform.removeExtension(manifest.id)
                        self.synchronizePeek()
                        self.errors[manifest.id] = message
                        self.onLayoutChange?()
                    }
                    connections[manifest.id] = connection
                    reloads[manifest.id] = modified
                    try connection.start(executable: runnerURL, bundle: bundle)
                    connection.sendMedia(music.state)
                } catch { errors[manifest.id] = error.localizedDescription }
            }
            errors.removeValue(forKey: "host")
        } catch { errors["host"] = error.localizedDescription }
        synchronizePeek()
        onLayoutChange?()
    }

    func stop() {
        hoverTask?.cancel()
        peekTask?.cancel()
        reloadTimer?.invalidate()
        music.stop()
        for connection in connections.values { connection.stop() }
        connections.removeAll()
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
        guard let deadline = hover.deadline else { return }
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
}
