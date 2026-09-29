import AppKit
import SwiftUI

@main
enum FileShuttleMain {
    static let delegate = AppDelegate()

    static func main() {
        let app = NSApplication.shared
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel!
    private var statusItem: StatusItemController!
    private let settings = SettingsWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = Self.makeMainMenu()
        model = AppModel()
        #if DEBUG
        if Snapshots.runIfRequested(model: model) {
            NSApp.terminate(nil)
            return
        }
        #endif
        settings.model = model
        statusItem = StatusItemController(model: model) { [settings] in
            settings.show()
        }
        if !model.isConfigured {
            settings.show()
        }
    }

    /// Menu bar apps never show their main menu, but keyboard shortcuts like ⌘C / ⌘V
    /// are dispatched through it, so text fields need these items to exist.
    private static func makeMainMenu() -> NSMenu {
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        appMenu.addItem(withTitle: "Quit FileShuttle", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let mainMenu = NSMenu()
        for menu in [appMenu, editMenu] {
            let item = NSMenuItem()
            item.submenu = menu
            mainMenu.addItem(item)
        }
        return mainMenu
    }

    /// Files opened with the app (Finder "Open With", dropping on the app icon, `open -a`) get uploaded.
    func application(_ application: NSApplication, open urls: [URL]) {
        model.upload(files: urls.filter(\.isFileURL))
    }

    /// Reopening the app from Finder or Spotlight shows Settings, since there's no Dock icon.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settings.show()
        return false
    }
}
