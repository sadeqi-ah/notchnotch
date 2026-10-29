import AppKit
import SwiftUI

@MainActor
final class ManagementWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate {
    let coordinator: ManagementCoordinator
    init(model: AppModel) {
        coordinator = ManagementCoordinator(model: model)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 620),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "NotchNotch"
        window.contentMinSize = NSSize(width: 690, height: 500)
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.toolbarStyle = .unified
        window.titlebarSeparatorStyle = .none
        coordinator.window = window
        let split = NSSplitViewController()
        let sidebar = NSSplitViewItem(sidebarWithViewController: NSHostingController(rootView: ManagementSidebar(coordinator: coordinator)))
        sidebar.canCollapse = false
        sidebar.minimumThickness = 215
        sidebar.maximumThickness = 215
        sidebar.titlebarSeparatorStyle = .none
        split.addSplitViewItem(sidebar)
        let detail = NSSplitViewItem(viewController: NSHostingController(rootView: ManagementView(coordinator: coordinator)))
        detail.titlebarSeparatorStyle = .none
        split.addSplitViewItem(detail)
        window.contentViewController = split
        let toolbar = NSToolbar(identifier: "NotchNotchSettingsToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar
        window.setContentSize(NSSize(width: 760, height: 620))
        window.center()
        window.setFrameAutosaveName("NotchNotchSettings")
        window.delegate = self
    }
    required init?(coder: NSCoder) { return nil }
    func reveal(extensionID: String? = nil) {
        coordinator.model.reloadExtensions()
        if let extensionID { coordinator.selectExtension(extensionID) }
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
    func windowWillClose(_ notification: Notification) { coordinator.windowClosed() }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.sidebarTrackingSeparator, .flexibleSpace]
    }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.sidebarTrackingSeparator, .flexibleSpace]
    }
}
