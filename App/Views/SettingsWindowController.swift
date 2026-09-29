import AppKit
import SwiftUI

/// Classic toolbar-tab preferences window hosting SwiftUI panes.
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    var model: AppModel?

    convenience init() {
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        tabs.canPropagateSelectedChildViewControllerTitle = true

        func pane(_ title: String, symbol: String, _ view: some View) -> NSTabViewItem {
            let hosting = NSHostingController(rootView: view.frame(width: 480))
            hosting.sizingOptions = .preferredContentSize
            hosting.title = title
            let item = NSTabViewItem(viewController: hosting)
            item.label = title
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
            return item
        }

        tabs.addTabViewItem(pane("Server", symbol: "server.rack", ServerSettingsView()))
        tabs.addTabViewItem(pane("General", symbol: "gearshape", GeneralSettingsView()))
        tabs.addTabViewItem(pane("About", symbol: "info.circle", AboutView()))

        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        self.init(window: window)
        window.delegate = self
    }

    func show() {
        guard let window else { return }
        if !window.isVisible { window.center() }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}
