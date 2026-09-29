#if DEBUG
import AppKit
import SwiftUI

/// Debug helper: `FileShuttle --snapshot <dir>` renders the main views to PNGs and quits.
/// Handy for reviewing UI changes without screen recording permission.
enum Snapshots {
    static func runIfRequested(model: AppModel) -> Bool {
        let args = CommandLine.arguments
        if let index = args.firstIndex(of: "--preview"), index + 1 < args.count {
            MarketingPreview.render(to: URL(filePath: args[index + 1]))
            return true
        }
        guard let index = args.firstIndex(of: "--snapshot"), index + 1 < args.count else { return false }
        let dir = URL(filePath: args[index + 1], directoryHint: .isDirectory)

        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            NSApp.appearance = NSAppearance(named: appearance)
            render(PopoverView(model: model, openSettings: {}), to: dir.appending(path: "popover-\(name).png"))
            render(ServerSettingsView().frame(width: 480), to: dir.appending(path: "server-\(name).png"))
            render(GeneralSettingsView().frame(width: 480), to: dir.appending(path: "general-\(name).png"))
        }
        renderIcons(to: dir.appending(path: "status-icons.png"))
        return true
    }

    /// Every menu bar icon state at 4x, on a dark and a light menu bar background.
    private static func renderIcons(to url: URL) {
        let states: [(IconState, Bool)] = [
            (.idle, false), (.idle, true), (.uploading(0), false), (.uploading(0.35), false),
            (.uploading(0.7), false), (.success, false), (.failure, false),
        ]
        let cell: CGFloat = 28, scale: CGFloat = 4
        let size = NSSize(width: cell * CGFloat(states.count), height: cell * 2)
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let rows: [(NSAppearance.Name, NSColor)] = [(.darkAqua, NSColor(white: 0.15, alpha: 1)), (.aqua, NSColor(white: 0.93, alpha: 1))]
        for (row, (name, background)) in rows.enumerated() {
            background.setFill()
            NSRect(x: 0, y: CGFloat(row) * cell, width: size.width, height: cell).fill()
            NSAppearance(named: name)!.performAsCurrentDrawingAppearance {
                for (column, (state, highlighted)) in states.enumerated() {
                    var image = StatusIcon.image(for: state, highlighted: highlighted)
                    if image.isTemplate {
                        // Mimic the menu bar rendering templates in the text color.
                        let template = image
                        image = NSImage(size: template.size, flipped: false) { rect in
                            template.draw(in: rect)
                            NSColor.labelColor.set()
                            rect.fill(using: .sourceAtop)
                            return true
                        }
                    }
                    let origin = NSPoint(x: CGFloat(column) * cell + (cell - image.size.width) / 2,
                                         y: CGFloat(row) * cell + (cell - image.size.height) / 2)
                    image.draw(in: NSRect(origin: origin, size: image.size))
                }
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }

    private static func render(_ view: some View, to url: URL) {
        let hosting = NSHostingView(rootView: view.background(Color(nsColor: .windowBackgroundColor)))
        hosting.frame.size = hosting.fittingSize
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: .now + 0.5)
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
#endif
