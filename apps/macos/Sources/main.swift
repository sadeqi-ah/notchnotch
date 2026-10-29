import AppKit
import SwiftUI
import NotchCore

final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private var panel: NotchPanel?
    private var statusItem: NSStatusItem?
    private var eventMonitors: [Any] = []
    private var pointerTimer: Timer?
    private var pagingGesture = ActivityPagingGesture()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let panel = NotchPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "NotchNotch"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.acceptsMouseMovedEvents = true
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = NSHostingView(rootView: NotchView(model: model) { [weak panel] in panel?.makeKey() })
        self.panel = panel
        model.onLayoutChange = { [weak self] in self?.layoutPanel() }
        makeMenu()
        NotificationCenter.default.addObserver(self, selector: #selector(screenChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.closeIfOutsidePanel() }
        }) { eventMonitors.append(monitor) }
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshPointerRouting() }
        }) { eventMonitors.append(monitor) }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .mouseMoved, .leftMouseDragged, .scrollWheel], handler: { [weak self] event in
            let handled = MainActor.assumeIsolated {
                guard let self else { return false }
                if event.type == .scrollWheel { return self.handlePaging(event) }
                if event.type == .keyDown, event.keyCode == 53, event.window === self.panel { self.model.close(); return true }
                if event.type == .leftMouseDown, event.window === self.panel,
                   self.model.hoverExpanded {
                    self.model.pinOpen()
                }
                if event.type == .leftMouseDown, event.window !== self.panel { self.closeIfOutsidePanel() }
                if event.type == .mouseMoved || event.type == .leftMouseDragged { self.refreshPointerRouting() }
                return false
            }
            return handled ? nil : event
        }) { eventMonitors.append(monitor) }
        layoutPanel()
        refreshPointerRouting()
        panel.orderFrontRegardless()
        model.start()
        // Pointer warps, screen/Space switches, and some input devices do not emit
        // mouseMoved. Sampling also keeps hit routing correct while the shell morphs.
        let pointerTimer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshPointerRouting() }
        }
        RunLoop.main.add(pointerTimer, forMode: .common)
        self.pointerTimer = pointerTimer
    }

    private func handlePaging(_ event: NSEvent) -> Bool {
        guard event.window === panel, model.isExpanded, model.platform.surfaces.count > 1,
              pointerIsInsideSilhouette(), event.hasPreciseScrollingDeltas else {
            pagingGesture.reset()
            return false
        }
        let phase: ActivityPagingGesture.Phase
        if !event.momentumPhase.isEmpty { phase = .momentum }
        else if event.phase.contains(.cancelled) { phase = .cancelled }
        else if event.phase.contains(.began) { phase = .began }
        else if event.phase.contains(.ended) { phase = .ended }
        else if event.phase.contains(.changed) { phase = .changed }
        else { return false }
        // Paging follows the fingers, even when Natural Scrolling is disabled.
        // AppKit's non-inverted deltas describe scrollbar travel instead.
        let fingerDirection: Double = event.isDirectionInvertedFromDevice ? 1 : -1
        let result = pagingGesture.update(deltaX: Double(event.scrollingDeltaX) * fingerDirection,
                                          deltaY: Double(event.scrollingDeltaY) * fingerDirection, phase: phase)
        if let direction = result.direction {
            panel?.makeKey()
            model.switchActivity(direction)
        }
        return result.handled
    }

    private func makeMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "circle.lefthalf.filled", accessibilityDescription: "NotchNotch")
        let menu = NSMenu()
        menu.addItem(withTitle: "NotchNotch · Developer Preview", action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        for (title, action, key) in [
            ("Show activities", #selector(showActivities), ""),
            ("Show pending question", #selector(showPrompt), ""),
            ("Preview announcement", #selector(previewAnnouncement), ""),
            ("Restart demos", #selector(restart), "r"),
            ("Disconnect extension connections", #selector(disconnectExtensions), ""),
            ("Quit NotchNotch", #selector(quit), "q"),
        ] {
            let entry = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
            entry.target = self
        }
        item.menu = menu
        statusItem = item
        // Keep commands reachable to keyboard users and accessibility clients even
        // when the notch itself is fully hidden behind the physical camera.
        let mainMenu = NSMenu()
        let appMenu = NSMenuItem(title: "NotchNotch", action: nil, keyEquivalent: "")
        appMenu.submenu = menu.copy() as? NSMenu
        mainMenu.addItem(appMenu)
        NSApp.mainMenu = mainMenu
    }

    private func layoutPanel() {
        guard let panel, let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main else { return }
        model.hasNotch = screen.safeAreaInsets.top > 0
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            model.notchWidth = max(100, right.minX - left.maxX)
        } else { model.notchWidth = 54 }
        model.topHeight = model.hasNotch ? max(32, screen.safeAreaInsets.top) : 38
        let canvas = model.geometry.canvasSize
        let frame = NSRect(x: screen.frame.midX - canvas.width / 2,
                           y: screen.frame.maxY - (model.hasNotch ? 0 : 6) - canvas.height,
                           width: canvas.width, height: canvas.height)
        if panel.frame != frame { panel.setFrame(frame, display: true) }
        refreshPointerRouting()
    }

    private func pointerIsInsideSilhouette() -> Bool {
        guard let panel else { return false }
        let mouse = NSEvent.mouseLocation
        let point = CGPoint(x: mouse.x - panel.frame.minX, y: panel.frame.maxY - mouse.y)
        let geometry = model.geometry
        let size = geometry.bodySize(presentation: model.presentation)
        let shape = NotchSilhouette(bodyWidth: size.width, bodyHeight: size.height,
                                    shoulder: geometry.shoulderRadius(presentation: model.presentation),
                                    bottomRadius: geometry.bottomRadius(presentation: model.presentation), attached: geometry.attached)
        return shape.path(in: CGRect(origin: .zero, size: geometry.canvasSize)).contains(point)
    }

    private func refreshPointerRouting() {
        guard let panel else { return }
        let mouse = NSEvent.mouseLocation
        let point = CGPoint(x: mouse.x - panel.frame.minX, y: panel.frame.maxY - mouse.y)
        let inside = model.geometry.activationFrame(presentation: model.presentation).contains(point)
        // The fixed animation canvas must never intercept clicks on transparent desktop space.
        panel.ignoresMouseEvents = !pointerIsInsideSilhouette() || model.presentation == .idle
        if !model.isExpanded, panel.isKeyWindow { panel.resignKey() }
        model.pointerChanged(inside: inside)
    }

    private func closeIfOutsidePanel() {
        guard !pointerIsInsideSilhouette() else { return }
        model.close()
    }

    @objc private func screenChanged() { layoutPanel() }
    @objc private func showActivities() { model.openFirst(); panel?.makeKey(); panel?.orderFrontRegardless() }
    @objc private func showPrompt() { model.openPrompt(); panel?.makeKey(); panel?.orderFrontRegardless() }
    @objc private func previewAnnouncement() { model.previewAnnouncement(); panel?.orderFrontRegardless() }
    @objc private func restart() { model.reloadExtensions(force: true) }
    @objc private func disconnectExtensions() { model.disconnectExtensions() }
    @objc private func quit() { NSApp.terminate(nil) }

    func applicationWillTerminate(_ notification: Notification) {
        pointerTimer?.invalidate()
        model.stop()
        for monitor in eventMonitors { NSEvent.removeMonitor(monitor) }
        NotificationCenter.default.removeObserver(self)
    }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
